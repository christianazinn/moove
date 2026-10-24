import type { Identity } from 'spacetimedb';
import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Approval, Deal, ShoppingItem } from '../module_bindings/types.js';
import { logEvent } from '../events.js';
import { visaCheckout } from '../checkout.js';
import { CARD_CHECKOUT_SOURCES, rankDeals, sanitizeText, sellerInfo, type DealSource, type RankedDeal } from '../integrations/deals.js';
import { approvalGate, dollars } from '../integrations/visa.js';
import { createDealSource } from '../integrations/deals-apify.js';

// Buy agent (#15). For each open shopping_item:
//   1. search deals (live Apify, else labeled sample data), rank them by
//      price, condition and distance, and write the top ones as `deal` rows
//   2. recommend the best one with choose_deal (the user can pick another in the app)
//   3. for the chosen deal: skip it if fraud screening (#18) flagged it; marketplace sellers get a
//      drafted message; card merchants go through Visa checkout. Above the owner's
//      approval_threshold_cents (or -1 = always ask) it calls request_approval and waits for
//      decide_approval; the approval must match the deal price, and is re-checked right before capture.
// Every step is an agent_event. Scraped text is only ever treated as data.

const AGENT = 'buy';
const DEFAULT_THRESHOLD_CENTS = BigInt(process.env.APPROVAL_THRESHOLD_CENTS_DEFAULT || '10000');
const MAX_DEALS = 5;
const FRAUD_BLOCK = Number(process.env.BUY_FRAUD_BLOCK ?? '0.7');
// Default 0: the agent ranks and recommends, and nothing is bought until the user chooses a deal
// in the app. 1 = the agent also chooses its recommendation (purchases at or under the threshold then
// happen without the user touching anything).
const AUTO_CHOOSE = process.env.BUY_AUTO_CHOOSE === '1';
// 1 = wait for the fraud screen (#18) to score a deal before buying it. Off until a fraud agent runs.
const REQUIRE_FRAUD_SCORE = process.env.BUY_REQUIRE_FRAUD_SCORE === '1';

// The one place the deal source is chosen: live Apify search (DEALS_SOURCE / APIFY_TOKEN), else
// the labeled sample data. See integrations/deals-apify.ts.
const dealSource: DealSource = createDealSource(process.env);

const searching = new Set<bigint>(); // shopping item ids searched this session
const busyItems = new Set<bigint>(); // shopping item ids in checkout
const settled = new Set<string>(); // keys that reached a final outcome this session
const approvalRequested = new Set<string>();
const ignoredChoice = new Set<string>();
const retries = new Map<string, number>(); // key -> transient failures so far
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = Number(process.env.BUY_RETRY_DELAY_MS ?? '60000');

// Transient failures (network, 5xx, a reducer call failing mid-reconnect) don't end a purchase: nothing
// was charged, the budget was released, and the item is tried again later, a few times at most.
function retryLater(conn: Conn, s: ShoppingItem, key: string, why: string): void {
  const n = retries.get(key) ?? 0;
  const ref = { owner: s.owner, agent: AGENT, refTable: 'deal', refId: s.chosenDealId };
  if (n >= MAX_RETRIES) {
    settled.add(key);
    logEvent(conn, { ...ref, kind: 'error', message: `Giving up on checkout after ${n + 1} tries: ${why}` });
    return;
  }
  retries.set(key, n + 1);
  const delay = RETRY_DELAY_MS * (n + 1);
  logEvent(conn, { ...ref, kind: 'error', message: `Checkout hit a temporary problem (${why}); will try again in ${Math.round(delay / 1000)}s`, data: { retry: n + 1, of: MAX_RETRIES } });
  setTimeout(() => {
    const cur = conn.db.shoppingItem.id.find(s.id);
    if (cur && keyOf(cur) === key) step(conn, cur);
  }, delay).unref?.();
}

const keyOf = (s: ShoppingItem) => `${s.id}:${s.chosenDealId}`;

function dealsFor(conn: Conn, itemId: bigint): Deal[] {
  return [...conn.db.deal.iter()].filter(d => d.shoppingItemId === itemId);
}

function thresholdFor(conn: Conn, owner: Identity): bigint {
  return conn.db.user.identity.find(owner)?.approvalThresholdCents ?? DEFAULT_THRESHOLD_CENTS;
}

function latestApproval(conn: Conn, dealId: bigint): Approval | undefined {
  let latest: Approval | undefined;
  for (const a of conn.db.approval.iter()) {
    if (a.kind === 'purchase' && a.refId === dealId && (!latest || a.id > latest.id)) latest = a;
  }
  return latest;
}

function paymentState(conn: Conn, dealId: bigint): 'settled' | 'pending' | 'failed' | undefined {
  let state: 'settled' | 'pending' | 'failed' | undefined;
  for (const p of conn.db.payment.iter()) {
    if (p.rail !== 'visa' || p.refTable !== 'deal' || p.refId !== dealId) continue;
    if (p.status === 'settled') return 'settled';
    if (p.status === 'pending') state = 'pending';
    else if (!state) state = 'failed';
  }
  return state;
}

async function search(conn: Conn, s: ShoppingItem): Promise<void> {
  searching.add(s.id);
  const ref = { owner: s.owner, agent: AGENT, refTable: 'shopping_item', refId: s.id };
  try {
    await conn.reducers.setShoppingStatus({ shoppingItemId: s.id, status: 'searching' });
    logEvent(conn, { ...ref, kind: 'plan', message: `Looking for deals on "${s.name}"` });
    logEvent(conn, { ...ref, kind: 'tool_call', message: `Searching ${dealSource.name}${dealSource.replay ? ' (not live)' : ''} for "${s.name}"`, data: { source: dealSource.name, replay: dealSource.replay, query: { name: s.name, category: s.category } } });
    const ranked = rankDeals(await dealSource.search({ name: s.name, category: s.category })).slice(0, MAX_DEALS);
    if (!ranked.length) {
      await conn.reducers.setShoppingStatus({ shoppingItemId: s.id, status: 'open' });
      logEvent(conn, { ...ref, kind: 'result', message: `No deals found for "${s.name}"` });
      return;
    }
    for (const d of ranked) {
      await conn.reducers.addDeal({ shoppingItemId: s.id, source: d.source, title: d.title, priceCents: d.priceCents, url: d.url, sellerInfo: sellerInfo(d) });
    }
    logEvent(conn, {
      ...ref,
      kind: 'result',
      message: `Found ${ranked.length} deals for "${s.name}", best: ${ranked[0].title} at ${dollars(ranked[0].priceCents)} (${ranked[0].source})${ranked[0].sample ? ' [sample data]' : ranked[0].replay ? ' [cached replay]' : ''}`,
      data: { replay: ranked[0].replay, sample: !!ranked[0].sample, ranking: ranked.map(d => ({ source: d.source, title: d.title, priceCents: d.priceCents, score: d.score, why: d.why })) },
    });
    await recommend(conn, s, ranked);
  } catch (err) {
    logEvent(conn, { ...ref, kind: 'error', message: `Deal search failed: ${String(err)}` });
  }
}

// Best card-checkout deal if there is one (the agent can complete it), else the best overall.
export function pickRecommendation(ranked: RankedDeal[]): RankedDeal | undefined {
  return ranked.find(d => d.checkout === 'visa') ?? ranked[0];
}

async function recommend(conn: Conn, s: ShoppingItem, ranked: RankedDeal[]): Promise<void> {
  const pick = pickRecommendation(ranked);
  const row = pick && dealsFor(conn, s.id).find(d => d.url === pick.url && d.title === pick.title && d.priceCents === pick.priceCents);
  if (!pick || !row) return;
  const cur = conn.db.shoppingItem.id.find(s.id);
  if (!cur || cur.chosenDealId !== 0n) return; // the user already chose
  if (AUTO_CHOOSE) await conn.reducers.chooseDeal({ shoppingItemId: s.id, dealId: row.id });
  logEvent(conn, { owner: s.owner, agent: AGENT, kind: 'result', refTable: 'deal', refId: row.id, message: `Recommended ${row.title} at ${dollars(row.priceCents)}: ${pick.why}${AUTO_CHOOSE ? ' (chosen automatically)' : '. Choose it in the app to buy'}` });
}

function draftSellerMessage(d: Deal): string {
  return `Hi! Is your "${sanitizeText(d.title, 80)}" (${dollars(d.priceCents)}) still available? I'm moving nearby and could pick it up this week. Thanks!`;
}

async function checkout(conn: Conn, s: ShoppingItem): Promise<void> {
  const key = keyOf(s);
  // One checkout per shopping item at a time, whichever deal is chosen.
  if (busyItems.has(s.id) || settled.has(key)) return;
  busyItems.add(s.id);
  try {
    await checkoutChosen(conn, s, key);
  } catch (err) {
    retryLater(conn, s, key, String(err));
  } finally {
    busyItems.delete(s.id);
  }
  // The user may have picked another deal while this one was in flight.
  const cur = conn.db.shoppingItem.id.find(s.id);
  if (cur && keyOf(cur) !== key) step(conn, cur);
}

async function checkoutChosen(conn: Conn, s: ShoppingItem, key: string): Promise<void> {
  const d = conn.db.deal.id.find(s.chosenDealId);
  if (!d || d.shoppingItemId !== s.id) return;
  const ref = { owner: s.owner, agent: AGENT, refTable: 'deal', refId: d.id };

  // Never buy twice for one need: any settled or pending card payment on any of this item's deals stops here.
  for (const other of dealsFor(conn, s.id)) {
    const st = paymentState(conn, other.id);
    if (st === 'settled') {
      settled.add(key);
      if (s.status !== 'bought') await conn.reducers.setShoppingStatus({ shoppingItemId: s.id, status: 'bought' });
      return;
    }
    if (st === 'pending') {
      // A hold in flight or from an earlier run; never double-charge. Say so if the user picked another deal.
      if (other.id !== d.id && !ignoredChoice.has(key)) {
        ignoredChoice.add(key);
        logEvent(conn, { ...ref, kind: 'result', message: `Not switching to "${d.title}" yet: a Visa hold on "${other.title}" is still in progress` });
      }
      return;
    }
  }
  if (paymentState(conn, d.id) === 'failed') {
    settled.add(key);
    logEvent(conn, { ...ref, kind: 'result', message: `An earlier checkout of "${d.title}" failed, not retrying it automatically` });
    return;
  }

  if (d.fraudScore >= FRAUD_BLOCK) {
    settled.add(key);
    logEvent(conn, { ...ref, kind: 'error', message: `Not buying "${d.title}": fraud screen scored it ${d.fraudScore.toFixed(2)} (${d.fraudReasons.join('; ') || 'no reasons given'})` });
    return;
  }
  if (d.fraudScore < 0 && REQUIRE_FRAUD_SCORE) return; // wait for the fraud screen (#18)

  if (!CARD_CHECKOUT_SOURCES.has(d.source)) {
    settled.add(key);
    const msg = draftSellerMessage(d);
    logEvent(conn, { ...ref, kind: 'result', message: `${d.source} sellers can't be paid through an API, so I drafted a message to the seller`, data: { draft: msg, url: d.url } });
    return;
  }

  // Never ask the user to approve something the card caps would refuse anyway.
  const visa = visaCheckout(conn);
  const blocked = visa.spendBlocker(AGENT, d.priceCents);
  if (blocked) {
    settled.add(key);
    logEvent(conn, { ...ref, kind: 'error', message: `Not buying "${d.title}": ${blocked}`, data: { refused: true, remainingCents: visa.remaining(AGENT) } });
    return;
  }

  const threshold = thresholdFor(conn, s.owner);
  const gate = approvalGate(d.priceCents, threshold, latestApproval(conn, d.id));
  if (!gate.ok) {
    if (gate.needsApproval) {
      if (approvalRequested.has(key)) return;
      approvalRequested.add(key);
      // Amount first, and no quotes or $ from scraped text, so a title can't fake the price.
      const title = sanitizeText(d.title, 80).replace(/["$]/g, '');
      await conn.reducers.requestApproval({ owner: s.owner, kind: 'purchase', refId: d.id, amountCents: d.priceCents, summary: `Pay ${dollars(d.priceCents)} to ${d.source} for: ${title}` });
      logEvent(conn, { ...ref, kind: 'approval', message: `${gate.reason}, asking for approval` });
    } else if (gate.reason !== 'waiting for approval') {
      settled.add(key);
      logEvent(conn, { ...ref, kind: 'approval', message: `Not buying "${d.title}": ${gate.reason}` });
    }
    return;
  }

  const unscreened = d.fraudScore < 0 ? ' Not fraud-screened yet.' : '';
  logEvent(conn, { ...ref, kind: 'plan', message: `Checking out "${d.title}" for ${dollars(d.priceCents)} via Visa${gate.approvalId ? ', approved by the user' : `, under the ${dollars(threshold)} approval threshold`}.${unscreened}` });
  const r = await visa.purchase({
    owner: s.owner,
    agent: AGENT,
    purpose: `${s.name}: ${sanitizeText(d.title, 80)}`,
    merchant: d.source,
    refTable: 'deal',
    refId: d.id,
    amountCents: d.priceCents,
    // Read fresh at every re-check, so lowering the threshold mid-flight is respected.
    thresholdCents: () => thresholdFor(conn, s.owner),
    currentApproval: () => latestApproval(conn, d.id),
    stillValid: () => {
      const cur = conn.db.shoppingItem.id.find(s.id);
      if (!cur) return 'shopping item was removed';
      if (cur.chosenDealId !== d.id) return 'the user picked a different deal';
      const deal = conn.db.deal.id.find(d.id);
      if (!deal) return 'deal was removed';
      if (deal.fraudScore >= FRAUD_BLOCK) return `fraud screen scored it ${deal.fraudScore.toFixed(2)}`;
      return undefined;
    },
    consumerPrompt: `Buy ${s.name} (${s.reason}) for no more than ${dollars(d.priceCents)} from ${d.source}`,
  });
  const label = r.simulated ? ' (simulated)' : ' (Visa sandbox, test card)';
  if (r.status === 'captured') {
    settled.add(key);
    await conn.reducers.setShoppingStatus({ shoppingItemId: s.id, status: 'bought' });
    logEvent(conn, { ...ref, kind: 'result', message: `Bought "${d.title}" for ${dollars(d.priceCents)}${label}`, data: { provider: r.provider, simulated: r.simulated, authId: r.hold?.authId, captureId: r.captureId } });
  } else if (r.status === 'unknown') {
    settled.add(key);
    logEvent(conn, { ...ref, kind: 'error', message: `Capture of "${d.title}" may or may not have gone through${label}; the payment stays pending until someone checks the processor`, data: { authId: r.hold?.authId, reconcile: true } });
  } else if (r.retryable) {
    retryLater(conn, s, key, r.reason ?? r.status);
  } else if (r.status !== 'waiting' && r.status !== 'needs_approval') {
    settled.add(key);
    logEvent(conn, { ...ref, kind: 'result', message: `Did not buy "${d.title}": ${r.status}${r.reason ? ` (${r.reason})` : ''}`, data: { provider: r.provider, simulated: r.simulated } });
  }
}

function step(conn: Conn, s: ShoppingItem): void {
  if (s.status === 'open' && !searching.has(s.id) && dealsFor(conn, s.id).length === 0) {
    void search(conn, s);
  } else if (s.status === 'found' && s.chosenDealId !== 0n) {
    void checkout(conn, s);
  }
}

export const buyAgent: Agent = {
  name: 'buy',
  start(conn) {
    const forDeal = (dealId: bigint) => {
      const d = conn.db.deal.id.find(dealId);
      const s = d && conn.db.shoppingItem.id.find(d.shoppingItemId);
      if (s) step(conn, s);
    };
    for (const s of conn.db.shoppingItem.iter()) step(conn, s);
    conn.db.shoppingItem.onInsert((_ctx, s) => step(conn, s));
    conn.db.shoppingItem.onUpdate((_ctx, _old, s) => step(conn, s));
    conn.db.approval.onInsert((_ctx, a) => a.kind === 'purchase' && forDeal(a.refId));
    conn.db.approval.onUpdate((_ctx, _old, a) => a.kind === 'purchase' && forDeal(a.refId));
    conn.db.deal.onUpdate((_ctx, _old, d) => forDeal(d.id));
  },
};
