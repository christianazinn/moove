import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Deal } from '../module_bindings/types.js';
import { logEvent } from '../events.js';
import { cachedComps } from '../integrations/apify.js';
import { chooseAiTextDetector, type AiTextDetector } from '../integrations/aitext.js';
import { fixtureDescription } from '../integrations/deals.js';

// Fraud screening (#18). Every deal with fraud_score = -1 gets five rule-based signals, each 0..1,
// combined into one fraud_score with set_deal_fraud. No Claude calls: it's cheap, deterministic
// and every point of score comes with a reason the app can show.
//
// Combination is a weighted noisy-OR: score = 1 - prod(1 - weight * signal). A weight is the most
// one signal can contribute on its own, so a single strong off-platform payment ask (0.85) is
// enough to cross the buy agent's block line (BUY_FRAUD_BLOCK, 0.7), while a cheap price alone
// (0.55) only reaches "some risk" and needs a second signal to block.
export const WEIGHTS = {
  offPlatform: 0.85, // pay by Zelle / gift card / wire, contact outside the platform, deposits
  price: 0.55, // too good to be true vs. the other deals and cached comps
  newSeller: 0.45, // brand-new or empty seller account
  duplicate: 0.5, // same link or same listing reused across deals/sources
  aiText: 0.4, // listing copy scored as AI-generated (Pangram replication)
} as const;
export type SignalKey = keyof typeof WEIGHTS;
export type Signal = { score: number; reasons: string[] };

export type DealLike = Pick<Deal, 'source' | 'title' | 'url' | 'sellerInfo'> & {
  id: bigint;
  shoppingItemId: bigint;
  priceCents: number | bigint;
};

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const dollars = (cents: number) => `$${Math.round(cents / 100)}`;
const NONE: Signal = { score: 0, reasons: [] };

export function median(xs: number[]): number | null {
  const s = xs.filter(x => x > 0).sort((a, b) => a - b);
  if (s.length === 0) return null;
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

// Several hits within one signal: the strongest counts fully, each extra adds a little.
function stack(hits: { score: number; reason: string }[]): Signal {
  if (hits.length === 0) return NONE;
  const sorted = [...hits].sort((a, b) => b.score - a.score);
  return { score: clamp01(sorted[0].score + 0.1 * (sorted.length - 1)), reasons: sorted.map(h => h.reason) };
}

// (1) Too good to be true. Comps (#6, used sold prices) are the best reference; other deals for
// the same shopping item mix new retail with used, so a used listing at 30% of the retail median
// is normal there and the bar is lower. Linear from `start` (0) down to `full` (1).
export const PRICE_BANDS = { comps: { start: 0.4, full: 0.15, min: 3 }, peers: { start: 0.25, full: 0.08, min: 2 } };

export function priceSignal(priceCents: number, peerPrices: number[], compPrices: number[]): Signal & { ref?: number; basis?: 'comps' | 'peers' } {
  if (!(priceCents > 0)) return NONE;
  const pick = (basis: 'comps' | 'peers', prices: number[]) => {
    const band = PRICE_BANDS[basis];
    const ref = prices.filter(p => p > 0).length >= band.min ? median(prices) : null;
    if (!ref) return null;
    const ratio = priceCents / ref;
    return { basis, ref, ratio, score: clamp01((band.start - ratio) / (band.start - band.full)) };
  };
  const options = [pick('comps', compPrices), pick('peers', peerPrices)].filter(o => o !== null);
  if (options.length === 0) return NONE;
  const best = options.sort((a, b) => b.score - a.score)[0];
  // Below 0.25 the gap is plausible for a used item: no score, so every point of score has a reason.
  if (best.score < 0.25) return { score: 0, reasons: [], ref: best.ref, basis: best.basis };
  const pct = Math.round((1 - best.ratio) * 100);
  const vs = best.basis === 'comps' ? 'recent sold prices' : 'the other deals';
  return { score: best.score, reasons: [`price ${dollars(priceCents)} is ${pct}% below ${vs} (median ${dollars(best.ref)})`], ref: best.ref, basis: best.basis };
}

// (2) Off-platform payment or contact, the classic marketplace scam script.
const OFF_PLATFORM: { re: RegExp; score: number; reason: string }[] = [
  { re: /\bzelle\b/i, score: 1, reason: 'asks for payment by Zelle' },
  { re: /\bcash\s?app\b/i, score: 1, reason: 'asks for payment by Cash App' },
  { re: /\bvenmo\s+only\b|\bonly\s+(?:accept\s+)?venmo\b/i, score: 0.9, reason: 'Venmo only' },
  { re: /\bpaypal\s+(?:friends|f&f|ff)\b|\bfriends\s*(?:and|&)\s*family\b/i, score: 0.9, reason: 'asks for PayPal friends & family (no buyer protection)' },
  { re: /\bwire\s+(?:transfer|the\s+money|payment|me)\b|\bbank\s+transfer\b|\bwestern\s+union\b|\bmoneygram\b/i, score: 1, reason: 'asks for a wire / money transfer' },
  { re: /\bgift\s?cards?\b|\b(?:itunes|steam|google\s+play)\s+cards?\b/i, score: 1, reason: 'asks for gift cards' },
  { re: /\bcrypto\b|\bbitcoin\b|\bbtc\b|\busdt\b|\bethereum\b/i, score: 0.9, reason: 'asks for crypto payment' },
  { re: /\bdeposit\s+to\s+hold\b|\b(?:send|pay)\s+(?:a\s+)?deposit\b|\bholding\s+(?:fee|deposit)\b/i, score: 0.9, reason: 'wants a deposit to hold the item' },
  { re: /\bshipping\s+only\b|\bship\s+only\b|\bno\s+(?:local\s+)?pick\s?up\b|\bcan'?t\s+meet\b/i, score: 0.5, reason: 'shipping only, no meetup' },
  { re: /\bemail\s+me\b|\btext\s+me\s+at\b|\bcall\s+me\s+at\b|\bcontact\s+me\s+(?:at|on)\b|\bwhats\s?app\b|\btelegram\b/i, score: 0.6, reason: 'asks to be contacted off-platform' },
  { re: /(?<![\d.x×])\(?\b\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/, score: 0.6, reason: 'phone number in the listing' },
  { re: /[\w.+-]+@[\w-]+\.[a-z]{2,}/i, score: 0.6, reason: 'email address in the listing' },
];

export function offPlatformSignal(text: string): Signal {
  return stack(OFF_PLATFORM.filter(p => p.re.test(text)).map(p => ({ score: p.score, reason: p.reason })));
}

// (3) New or empty seller account, parsed from whatever seller_info the deal source exposes
// (e.g. "Marketplace seller, Oakland (4.8 stars) · good · 6 mi · message seller").
export function newSellerSignal(sellerInfo: string, now: Date = new Date()): Signal {
  const s = sellerInfo.trim();
  if (!s) return { score: 0.4, reasons: ['no seller info'] };
  const hits: { score: number; reason: string }[] = [];
  const joined = s.match(/\b(?:joined|member\s+since|on\s+\w+\s+since)\b[^·|\d]{0,25}?(20\d\d)\b/i);
  if (joined) {
    const age = now.getUTCFullYear() - Number(joined[1]);
    if (age <= 0) hits.push({ score: 0.8, reason: `seller account is new (joined ${joined[1]})` });
    else if (age === 1) hits.push({ score: 0.3, reason: `seller account is recent (joined ${joined[1]})` });
  }
  const ago = s.match(/\b(?:joined|created|account\s+(?:is\s+)?)\s*(\d+)\s+(hour|day|week)s?\s+(?:ago|old)\b/i);
  if (ago) hits.push({ score: 0.8, reason: `seller account is ${ago[1]} ${ago[2]}${ago[1] === '1' ? '' : 's'} old` });
  if (/\bnew\s+(?:account|seller|member|profile|user)\b/i.test(s)) hits.push({ score: 0.7, reason: 'new seller account' });
  if (/\b(?:0|no|zero)\s+(?:ratings?|reviews?|feedback|sales|transactions)\b/i.test(s)) hits.push({ score: 0.7, reason: 'seller has no ratings' });
  else {
    const few = s.match(/\b([12])\s+(?:ratings?|reviews?|feedback)\b/i);
    if (few) hits.push({ score: 0.3, reason: `seller has only ${few[1]} rating${few[1] === '1' ? '' : 's'}` });
  }
  return stack(hits);
}

// (4) Reused listings. Deals carry no photos, so this works on what they do carry: the same link
// reused by a listing with a different title, or the same title + price posted under different
// links (copy-pasted scam listings, or one listing cross-posted to several sources).
// Retail catalog deals are exempt: the same product page (or search page) legitimately shows up
// under several shopping items, users and URLs. Same list as the buy agent's card-checkout sources.
export const RETAIL_SOURCES = new Set(['ikea', 'target', 'amazon', 'wayfair']);
const normTitle = (t: string) => t.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

export function duplicateSignal(deal: DealLike, others: DealLike[]): Signal {
  if (RETAIL_SOURCES.has(deal.source.toLowerCase())) return NONE;
  const hits: { score: number; reason: string }[] = [];
  const title = normTitle(deal.title);
  const url = deal.url.trim();
  const price = Number(deal.priceCents);
  const rest = others.filter(o => o.id !== deal.id);
  if (url && rest.some(o => o.url.trim() === url && normTitle(o.title) !== title)) {
    hits.push({ score: 0.7, reason: 'same link is used by a different listing' });
  }
  if (title.length >= 12) {
    const copies = rest.filter(o => normTitle(o.title) === title && Number(o.priceCents) === price && o.url.trim() !== url);
    if (copies.length) {
      const sources = [...new Set([deal.source, ...copies.map(c => c.source)])];
      hits.push({
        score: sources.length > 1 ? 0.5 : 0.6,
        reason: sources.length > 1 ? `identical listing posted on ${sources.join(' and ')}` : `identical listing posted ${copies.length + 1} times`,
      });
    }
  }
  return stack(hits);
}

// (5) AI-written listing copy. Below 0.5 is treated as human.
export function aiTextSignal(aiTextScore: number): Signal {
  if (!(aiTextScore >= 0.5)) return NONE;
  const how = aiTextScore >= 0.7 ? 'likely' : 'may be';
  return { score: aiTextScore, reasons: [`listing text ${how} AI-generated (${aiTextScore.toFixed(2)})`] };
}

export function combine(signals: Record<SignalKey, Signal>): { fraudScore: number; reasons: string[] } {
  let clean = 1;
  const reasons: string[] = [];
  // Strongest contributions first, so the app's first line is the main reason.
  const keys = (Object.keys(WEIGHTS) as SignalKey[]).sort((a, b) => WEIGHTS[b] * signals[b].score - WEIGHTS[a] * signals[a].score);
  for (const k of keys) {
    clean *= 1 - WEIGHTS[k] * clamp01(signals[k].score);
    reasons.push(...signals[k].reasons);
  }
  return { fraudScore: Math.round((1 - clean) * 1000) / 1000, reasons };
}

export type Screen = { fraudScore: number; aiTextScore: number; reasons: string[]; signals: Record<SignalKey, Signal> };

// Everything a deal is judged against. `allDeals` is every deal the worker can see (for duplicates);
// peers are the other deals for the same shopping item.
export function screenDeal(
  deal: DealLike,
  ctx: { allDeals: DealLike[]; compPrices?: number[]; aiTextScore?: number; now?: Date }
): Screen {
  const peers = ctx.allDeals.filter(o => o.id !== deal.id && o.shoppingItemId === deal.shoppingItemId).map(o => Number(o.priceCents));
  const aiTextScore = ctx.aiTextScore ?? -1;
  const signals: Record<SignalKey, Signal> = {
    offPlatform: offPlatformSignal(`${deal.title}\n${deal.sellerInfo}`),
    price: priceSignal(Number(deal.priceCents), peers, ctx.compPrices ?? []),
    newSeller: newSellerSignal(deal.sellerInfo, ctx.now),
    duplicate: duplicateSignal(deal, ctx.allDeals),
    aiText: aiTextSignal(aiTextScore),
  };
  return { ...combine(signals), aiTextScore, signals };
}

// Cached comps for the shopping item's name, if pricing (#6) or a demo fixture already saved them.
// Cache-only on purpose: screening a deal must never start a paid Apify run.
export function cachedCompPrices(query: string): number[] {
  try {
    return (cachedComps(query) ?? []).map(c => c.priceCents);
  } catch {
    return [];
  }
}

// Listing copy sent to the detector: the title, plus the listing's description when a fixture row
// has one (deal rows don't store descriptions). Too-short text is skipped (detectors are unreliable
// on a few words) and stays -1.
export const AI_TEXT_MIN_CHARS = Number(process.env.FRAUD_AI_TEXT_MIN_CHARS ?? '20');

let detector: AiTextDetector | null | undefined;
export function setAiTextDetector(d: AiTextDetector | null): void {
  detector = d;
}

// Deals for one shopping item usually arrive in a burst (the buy agent adds them one by one), so
// wait for the burst to settle before screening: the price check needs the other deals.
const SETTLE_MS = Number(process.env.FRAUD_SETTLE_MS ?? '1500');
const timers = new Map<bigint, NodeJS.Timeout>();
const inFlight = new Set<bigint>();

async function aiScore(conn: Conn, d: Deal): Promise<number> {
  const text = [d.title.trim(), fixtureDescription(d.url).trim()].filter(Boolean).join('\n\n');
  if (!detector || text.length < AI_TEXT_MIN_CHARS) return -1;
  try {
    return await detector.score(text);
  } catch (err) {
    logEvent(conn, { owner: d.owner, agent: 'fraud', kind: 'error', message: `AI-text check failed for "${d.title}": ${String(err)}`, refTable: 'deal', refId: d.id });
    return -1;
  }
}

// A failed set_deal_fraud would leave the deal at -1 (and its purchase waiting) until a restart, so
// retry a few times with backoff (FRAUD_RETRY_DELAY_MS, then 2x, 4x...). The last error is rethrown
// and logged by screen() as an `error` event.
export const SET_FRAUD_TRIES = 3;
const RETRY_DELAY_MS = Number(process.env.FRAUD_RETRY_DELAY_MS ?? '500');

async function setDealFraudWithRetry(conn: Conn, args: Parameters<Conn['reducers']['setDealFraud']>[0]): Promise<void> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await conn.reducers.setDealFraud(args);
    } catch (err) {
      if (attempt >= SET_FRAUD_TRIES) throw new Error(`set_deal_fraud failed after ${attempt} tries: ${String(err)}`);
      console.warn(`[fraud] set_deal_fraud for deal ${args.dealId} failed (try ${attempt}/${SET_FRAUD_TRIES}), retrying: ${String(err)}`);
      await new Promise(r => setTimeout(r, RETRY_DELAY_MS * 2 ** (attempt - 1)));
    }
  }
}

async function screen(conn: Conn, d: Deal): Promise<void> {
  inFlight.add(d.id);
  try {
    const item = conn.db.shoppingItem.id.find(d.shoppingItemId);
    const compPrices = item ? cachedCompPrices(item.name) : [];
    const aiTextScore = await aiScore(conn, d);
    const s = screenDeal(d, { allDeals: [...conn.db.deal.iter()], compPrices, aiTextScore });
    await setDealFraudWithRetry(conn, { dealId: d.id, fraudScore: s.fraudScore, aiTextScore: s.aiTextScore, reasons: s.reasons });
    logEvent(conn, {
      owner: d.owner,
      agent: 'fraud',
      kind: 'result',
      message: `Fraud screen "${d.title}" (${d.source}): ${s.fraudScore.toFixed(2)}${s.reasons.length ? ` - ${s.reasons.join('; ')}` : ', no red flags'}`,
      refTable: 'deal',
      refId: d.id,
      data: {
        fraudScore: s.fraudScore,
        aiTextScore: s.aiTextScore,
        aiTextDetector: detector?.name ?? null,
        compsCached: compPrices.length,
        weights: WEIGHTS,
        signals: Object.fromEntries(Object.entries(s.signals).map(([k, v]) => [k, Math.round(v.score * 100) / 100])),
      },
    });
  } catch (err) {
    logEvent(conn, { owner: d.owner, agent: 'fraud', kind: 'error', message: `Fraud screen failed for "${d.title}": ${String(err)}`, refTable: 'deal', refId: d.id });
  } finally {
    inFlight.delete(d.id);
  }
}

// Re-screen (after #143's retry): a deal whose set_deal_fraud failed every try stays at -1 and its
// purchase waits at "Waiting for the fraud screen" until a restart. So every FRAUD_RESCREEN_MS (60 s)
// a low-frequency sweep re-screens deals this worker has seen unscored for at least
// FRAUD_RESCREEN_AGE_MS (30 s), at most RESCREEN_MAX_ATTEMPTS times per deal, then gives up with one
// error event (a restart starts the count again). Age is measured from when this worker first saw the
// deal unscored, not created_at, so DB/worker clock skew doesn't matter. The timer is unref()'d.
export const RESCREEN_MAX_ATTEMPTS = 3;
const RESCREEN_EVERY_MS = Number(process.env.FRAUD_RESCREEN_MS ?? '60000');
const RESCREEN_AGE_MS = Number(process.env.FRAUD_RESCREEN_AGE_MS ?? '30000');
const firstSeenUnscored = new Map<bigint, number>();
const rescreens = new Map<bigint, number>();
let rescreenTimer: NodeJS.Timeout | undefined;

/** One re-screen pass (exported for tests). Returns the ids it re-screened. */
export function rescreenStale(conn: Conn, now = Date.now()): bigint[] {
  const pendingItems = new Set(timers.keys()); // a settle timer will screen these anyway
  const started: bigint[] = [];
  for (const d of conn.db.deal.iter()) {
    if (d.fraudScore !== -1 || inFlight.has(d.id) || pendingItems.has(d.shoppingItemId)) continue;
    const seen = firstSeenUnscored.get(d.id);
    if (seen === undefined) {
      firstSeenUnscored.set(d.id, now);
      continue;
    }
    if (now - seen < RESCREEN_AGE_MS) continue;
    const n = rescreens.get(d.id) ?? 0;
    if (n > RESCREEN_MAX_ATTEMPTS) continue; // already gave up
    if (n === RESCREEN_MAX_ATTEMPTS) {
      rescreens.set(d.id, n + 1);
      logEvent(conn, { owner: d.owner, agent: 'fraud', kind: 'error', message: `Fraud screen gave up on "${d.title}" after ${n} re-screens; it stays unscored until the worker restarts.`, refTable: 'deal', refId: d.id });
      continue;
    }
    rescreens.set(d.id, n + 1);
    console.warn(`[fraud] deal ${d.id} still unscored after ${Math.round((now - seen) / 1000)} s, re-screening (${n + 1}/${RESCREEN_MAX_ATTEMPTS})`);
    started.push(d.id);
    void screen(conn, d);
  }
  return started;
}

/** Stops the re-screen timer and pending settle timers (tests; the worker just exits). */
export function stopFraudAgent(): void {
  clearInterval(rescreenTimer);
  rescreenTimer = undefined;
  for (const t of timers.values()) clearTimeout(t);
  timers.clear();
  firstSeenUnscored.clear();
  rescreens.clear();
}

function screenPending(conn: Conn, shoppingItemId: bigint): void {
  timers.delete(shoppingItemId);
  for (const d of conn.db.deal.iter()) {
    if (d.shoppingItemId === shoppingItemId && d.fraudScore === -1 && !inFlight.has(d.id)) void screen(conn, d);
  }
}

// Scores every unscored deal (#18) so the buy agent and the shopping UI can act on it.
export const fraudAgent: Agent = {
  name: 'fraud',
  start(conn) {
    if (detector === undefined) detector = chooseAiTextDetector();
    console.log(`[fraud] AI-text detector: ${detector ? detector.name : 'off (PANGRAM_URL unset)'}`);
    stopFraudAgent(); // a second start() (tests) replaces the first one's timer
    const maybe = (d: Deal) => {
      if (d.fraudScore !== -1) {
        firstSeenUnscored.delete(d.id);
        rescreens.delete(d.id);
        return;
      }
      if (!firstSeenUnscored.has(d.id)) firstSeenUnscored.set(d.id, Date.now());
      if (inFlight.has(d.id)) return;
      clearTimeout(timers.get(d.shoppingItemId));
      timers.set(d.shoppingItemId, setTimeout(() => screenPending(conn, d.shoppingItemId), SETTLE_MS));
    };
    for (const d of conn.db.deal.iter()) maybe(d);
    conn.db.deal.onInsert((_ctx, d) => maybe(d));
    conn.db.deal.onUpdate((_ctx, _old, d) => maybe(d));
    if (RESCREEN_EVERY_MS > 0) {
      rescreenTimer = setInterval(() => rescreenStale(conn), RESCREEN_EVERY_MS);
      rescreenTimer.unref?.(); // never keeps the worker alive on its own
    }
  },
};
