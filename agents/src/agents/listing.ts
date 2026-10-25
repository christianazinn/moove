import { z } from 'zod';
import type { Agent } from './types.js';
import { findUser, type Conn } from '../spacetime.js';
import type { Approval, Item, Listing } from '../module_bindings/types.js';
import { config } from '../config.js';
import { logEvent } from '../events.js';
import { isBuiltInFixture } from '../builtins.js';
import { structuredCall } from '../integrations/anthropic.js';
import { chooseEbay, dollars, simulatedEbay, type EbayPoster, type PublishResult } from '../integrations/ebay.js';
import { buildDraftPrompt, clampPrice, finalizeCopy, LISTING_SYSTEM } from './listingPrompt.js';
import { afterExpiry, approvalExpiry } from './approval-expiry.js';
import { paymentRail } from '../payments.js';
import { createRecallChecker, describeMatch, recallCheckEnabled, type Recall, type RecallChecker } from '../integrations/recalls.js';

// Real eBay (sandbox) once scripts/ebay-setup.ts has filled in the EBAY_* keys, otherwise the
// labeled simulation (#11, #32). Fixed at startup so a draft's `simulated` flag matches how it posts.
let ebay: EbayPoster = chooseEbay();
let simulated: EbayPoster = simulatedEbay;

// Tests swap in fake posters (the real one, and the simulated one simulated listings use).
export function setListingDeps(d: { ebay?: EbayPoster; simulated?: EbayPoster; recalls?: RecallChecker }): void {
  if (d.ebay) ebay = d.ebay;
  if (d.simulated) simulated = d.simulated;
  if (d.recalls) recalls = d.recalls;
}

// CPSC recall check before listing (RECALL_CHECK_X402=1, off by default): the safety agent pays a
// third-party x402 service once per query (integrations/recalls.ts). A probable recall makes the
// listing ask for approval whatever its price, with the recall in the summary. Never blocks a draft.
let recalls: RecallChecker | undefined;
function recallChecker(conn: Conn): RecallChecker {
  return (recalls ??= createRecallChecker({ rail: paymentRail(conn), log: e => logEvent(conn, e) }));
}
async function checkRecalls(conn: Conn, it: Item): Promise<void> {
  if (!recallCheckEnabled()) return;
  try {
    await recallChecker(conn).check(it);
  } catch (err) {
    // check() already turns failures into events; this is only a backstop.
    console.warn(`[safety] recall check threw: ${String(err)}`);
  }
}
/** The recall already found for this listing's item (from the paid report's cache), if any. */
function recallFor(conn: Conn, l: Listing): Recall | undefined {
  if (!recallCheckEnabled()) return undefined;
  const it = conn.db.item.id.find(l.itemId);
  return it ? recallChecker(conn).cached(it)?.[0] : undefined;
}
function approvalSummary(conn: Conn, l: Listing): string {
  const recall = recallFor(conn, l);
  return `Sell "${l.title}" for ${dollars(l.priceCents)}${recall ? `. Possible CPSC recall: ${describeMatch(recall)}` : ''}`;
}

// Fallback when the owner has no user row; the user's approval_threshold_cents wins (#12).
const DEFAULT_THRESHOLD_CENTS = BigInt(process.env.APPROVAL_THRESHOLD_CENTS_DEFAULT || '10000');
// Demo nicety: flip posted simulated listings to `sold` after this many seconds (0 = never).
const SOLD_AFTER_SEC = Number(process.env.LISTING_SIM_SOLD_AFTER_SEC ?? '0');

export const ListingDraft = z.object({
  title: z.string().describe('eBay title, max 80 chars: brand, item, key spec, condition. No emoji, no ALL CAPS.'),
  description: z
    .string()
    .describe('2-4 short paragraphs separated by blank lines: what it is, condition and flaws, dimensions, pickup/shipping note'),
  priceCents: z.number().int().describe('Asking price in US cents'),
  priceReason: z.string().describe('One sentence tying the price to the comps'),
});

const drafting = new Set<bigint>(); // item ids
const advancing = new Set<bigint>(); // listing ids
const approvalRequested = new Set<bigint>(); // listing ids; the approval row can arrive before the status update
const reasked = new Set<bigint>(); // expired approval ids already re-asked this run (#186)
const claimRetries = new Map<bigint, number>(); // listing id -> failed `posting` claims in a row
const CLAIM_RETRY_MS = 5000;
const CLAIM_MAX_RETRIES = 5;

// A listing only goes ahead while its item is still sorted to sell: the user (or a re-sort) can
// move it to keep/donate at any point between drafting and posting.
function stillSelling(conn: Conn, l: Pick<Listing, 'itemId'>): boolean {
  const it = conn.db.item.id.find(l.itemId);
  return it != null && listable(it);
}

// Sorted to sell, and not part of the building: a toilet or sink swiped to "sell" in Review
// stays with the house (Rio's hotel bathroom had two of each listed).
export function listable(it: Pick<Item, 'disposition' | 'name' | 'category'>): boolean {
  return it.disposition === 'sell' && !isBuiltInFixture(it);
}

function hasListing(conn: Conn, itemId: bigint): boolean {
  for (const l of conn.db.listing.iter()) if (l.itemId === itemId) return true;
  return false;
}

// Vision has had its chance: done, failed, or no photo to look at (scanned items without photos
// would otherwise never be listed). Same rule as pricing.
export function visionSettled(it: Pick<Item, 'detailsStatus' | 'photoUrls'>): boolean {
  return it.detailsStatus === 'done' || it.detailsStatus === 'failed' || it.photoUrls.length === 0;
}

function needsDraft(conn: Conn, it: Item): boolean {
  return (
    listable(it) &&
    visionSettled(it) &&
    (it.pricingStatus === 'done' || it.pricingStatus === 'failed') &&
    !drafting.has(it.id) &&
    !hasListing(conn, it.id)
  );
}

async function draft(conn: Conn, it: Item): Promise<void> {
  drafting.add(it.id);
  const comps = [...conn.db.comp.iter()].filter(c => c.itemId === it.id);
  logEvent(conn, { owner: it.owner, agent: 'listing', kind: 'plan', message: `Drafting a listing for "${it.name}" from ${comps.length} comp(s)`, refTable: 'item', refId: it.id });
  // Runs alongside the Claude draft; awaited before the listing row exists so advance() sees a recall.
  const recallCheck = checkRecalls(conn, it);
  try {
    // Comps are scraped (untrusted): cleaned and fenced in the prompt, and the output is checked in code (#17).
    const d = await structuredCall({ model: config.models.agent, system: LISTING_SYSTEM, text: buildDraftPrompt(it, comps), schema: ListingDraft });
    await recallCheck;
    if (!stillSelling(conn, { itemId: it.id })) {
      // Re-sorted while Claude wrote it. Dropped from `drafting` so a flip back to sell drafts again.
      drafting.delete(it.id);
      logEvent(conn, { owner: it.owner, agent: 'listing', kind: 'plan', message: `Not listing "${it.name}": it is no longer sorted to sell`, refTable: 'item', refId: it.id });
      return;
    }
    const price = clampPrice(it, d.priceCents, comps);
    const copy = finalizeCopy(d);
    await conn.reducers.createListingDraft({ itemId: it.id, title: copy.title, description: copy.description, priceCents: price, simulated: ebay.simulated });
    const clamped = BigInt(Math.round(d.priceCents)) !== price ? ` (model said ${dollars(BigInt(Math.round(d.priceCents)))}, clamped)` : '';
    logEvent(conn, { owner: it.owner, agent: 'listing', kind: 'result', message: `Drafted "${copy.title}" at ${dollars(price)}${clamped}: ${d.priceReason}`, refTable: 'item', refId: it.id, data: { ...d, ...copy, modelPriceCents: d.priceCents, priceCents: price } });
  } catch (err) {
    // Stays in `drafting`, so it isn't retried in a loop; a worker restart retries it.
    logEvent(conn, { owner: it.owner, agent: 'listing', kind: 'error', message: `Drafting failed: ${String(err)}`, refTable: 'item', refId: it.id });
  }
}

function thresholdFor(conn: Conn, l: Listing): bigint {
  return findUser(conn, l.owner)?.approvalThresholdCents ?? DEFAULT_THRESHOLD_CENTS;
}

// Status writes are awaited so a failed one (e.g. while reconnecting) shows up as an error event
// instead of an unhandled rejection with the listing silently stuck.
async function setStatus(conn: Conn, l: Listing, status: string, externalId = '', url = ''): Promise<boolean> {
  try {
    await conn.reducers.updateListing({ listingId: l.id, status, externalId, url, priceCents: -1n });
    return true;
  } catch (err) {
    logEvent(conn, { owner: l.owner, agent: 'listing', kind: 'error', message: `Could not set the listing to ${status}: ${String(err)}`, refTable: 'listing', refId: l.id });
    return false;
  }
}

// Asks once per listing per worker run. On failure it logs and forgets, so a later pass retries.
async function askApproval(conn: Conn, l: Listing): Promise<boolean> {
  if (approvalRequested.has(l.id)) return false;
  approvalRequested.add(l.id);
  try {
    await conn.reducers.requestApproval({ owner: l.owner, kind: 'listing', refId: l.id, amountCents: l.priceCents, summary: approvalSummary(conn, l) });
    return true;
  } catch (err) {
    approvalRequested.delete(l.id);
    logEvent(conn, { owner: l.owner, agent: 'listing', kind: 'error', message: `Could not ask for approval: ${String(err)}`, refTable: 'listing', refId: l.id });
    return false;
  }
}

async function rejectUnsold(conn: Conn, l: Listing): Promise<void> {
  if (await setStatus(conn, l, 'rejected')) {
    logEvent(conn, { owner: l.owner, agent: 'listing', kind: 'approval', message: 'Not posting: the item is no longer sorted to sell', refTable: 'listing', refId: l.id });
  }
}

function approvalFor(conn: Conn, l: Listing): Approval | undefined {
  let latest: Approval | undefined;
  for (const a of conn.db.approval.iter()) {
    if (a.kind === 'listing' && a.refId === l.id && (!latest || a.id > latest.id)) latest = a;
  }
  return latest;
}

async function post(conn: Conn, l: Listing): Promise<void> {
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  if (!stillSelling(conn, l)) {
    await rejectUnsold(conn, l);
    return;
  }
  // A listing posts the way it was drafted, so its `simulated` flag stays true to what happened.
  if (!l.simulated && ebay.simulated) {
    await setStatus(conn, l, 'failed');
    logEvent(conn, { ...ref, kind: 'error', message: 'Drafted for real eBay, but the eBay keys are no longer configured' });
    return;
  }
  const poster = l.simulated ? simulated : ebay;
  // Claim the post first (#144): the module allows `posting` only from draft/awaiting_approval, so
  // if it's refused, another post already owns this listing and publishing here would post it twice.
  try {
    await conn.reducers.updateListing({ listingId: l.id, status: 'posting', externalId: '', url: '', priceCents: -1n });
  } catch (err) {
    const cur = conn.db.listing.id.find(l.id);
    if (!cur || (cur.status !== 'draft' && cur.status !== 'awaiting_approval')) {
      logEvent(conn, { ...ref, kind: 'plan', message: `Not posting: this listing is already being posted (${String(err)})` });
      return;
    }
    // Still unposted, so the claim failed for another reason (e.g. reconnecting): try again shortly.
    const tries = (claimRetries.get(l.id) ?? 0) + 1;
    claimRetries.set(l.id, tries);
    if (tries > CLAIM_MAX_RETRIES) {
      logEvent(conn, { ...ref, kind: 'error', message: `Could not start posting after ${CLAIM_MAX_RETRIES} retries: ${String(err)}. A worker restart retries it.` });
      return;
    }
    logEvent(conn, { ...ref, kind: 'error', message: `Could not start posting, retrying in ${CLAIM_RETRY_MS / 1000}s: ${String(err)}` });
    setTimeout(() => {
      const next = conn.db.listing.id.find(l.id);
      if (next) void advance(conn, next);
    }, CLAIM_RETRY_MS);
    return;
  }
  claimRetries.delete(l.id);
  await publish(conn, l, poster);
}

// Publishes a listing this worker holds the `posting` claim on, then marks it posted or failed.
async function publish(conn: Conn, l: Listing, poster: EbayPoster): Promise<void> {
  const it = conn.db.item.id.find(l.itemId);
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  logEvent(conn, { ...ref, kind: 'plan', message: `Posting "${l.title}" to eBay at ${dollars(l.priceCents)}${poster.simulated ? ' (simulated)' : ''}` });
  try {
    const r = await poster.publish(
      {
        listingId: l.id,
        title: l.title,
        description: l.description,
        priceCents: l.priceCents,
        condition: it?.condition ?? '',
        category: it?.category ?? '',
        photoUrls: it?.photoUrls ?? [],
        itemName: it?.name ?? l.title,
        brand: it?.brand ?? '',
        material: it?.material ?? '',
      },
      s => logEvent(conn, { ...ref, kind: 'tool_call', message: `eBay ${s.call}${poster.simulated ? ' (simulated)' : ''}: ${s.detail}`, data: { ...s, simulated: poster.simulated } })
    );
    // It's live now, so a failed write is retried once rather than left `posting` for a restart to mark failed.
    if (!(await setStatus(conn, l, 'posted', r.externalId, r.url)) && !(await setStatus(conn, l, 'posted', r.externalId, r.url))) {
      logEvent(conn, { ...ref, kind: 'error', message: `Posted as item #${r.externalId}${r.simulated ? ' (simulated)' : ''} (${r.url}), but the listing couldn't be marked posted`, data: r });
      return;
    }
    logEvent(conn, { ...ref, kind: 'result', message: `Live as item #${r.externalId}${r.simulated ? ' (simulated)' : ''}`, data: r });
    if (r.simulated && SOLD_AFTER_SEC > 0) {
      setTimeout(() => {
        const cur = conn.db.listing.id.find(l.id);
        if (cur?.status !== 'posted') return;
        void setStatus(conn, l, 'sold');
        logEvent(conn, { ...ref, kind: 'result', message: `Sold "${l.title}" for ${dollars(l.priceCents)} (simulated)` });
      }, SOLD_AFTER_SEC * 1000);
    }
  } catch (err) {
    await setStatus(conn, l, 'failed');
    logEvent(conn, { ...ref, kind: 'error', message: `Posting failed: ${String(err)}` });
  }
}

// #186: nobody answered and the worker expired the approval. Ask again while the item is still
// sorted to sell, at most APPROVAL_MAX_REASKS times. Decided from the approval rows (the latest one
// is pending again once the re-ask lands), so a restart doesn't ask twice; `reasked` covers the gap
// before the new row reaches the cache.
async function reaskAfterExpiry(conn: Conn, l: Listing): Promise<void> {
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  const next = afterExpiry(conn.db.approval.iter(), 'listing', l.id, approvalExpiry.maxReasks);
  if (next.action === 'none') return;
  const it = conn.db.item.id.find(l.itemId);
  if (next.action === 'give_up' || it?.disposition !== 'sell') {
    if (advancing.has(l.id)) return;
    advancing.add(l.id);
    const why =
      next.action === 'give_up'
        ? `the approval expired ${next.expiredCount} times without an answer`
        : 'the approval expired and the item is no longer sorted to sell';
    if (await setStatus(conn, l, 'rejected')) logEvent(conn, { ...ref, kind: 'approval', message: `Not posting: ${why}` });
    advancing.delete(l.id);
    return;
  }
  if (reasked.has(next.expired)) return;
  reasked.add(next.expired);
  try {
    await conn.reducers.requestApproval({ owner: l.owner, kind: 'listing', refId: l.id, amountCents: l.priceCents, summary: approvalSummary(conn, l) });
    logEvent(conn, { ...ref, kind: 'approval', message: `The approval expired without an answer, asking again (${next.attempt} of ${approvalExpiry.maxReasks})`, data: { expiredApprovalId: next.expired } });
  } catch (err) {
    reasked.delete(next.expired); // a later update retries
    logEvent(conn, { ...ref, kind: 'error', message: `Could not ask for approval again: ${String(err)}` });
  }
}


// A listing found in `posting` when the worker starts: the last worker died mid-post (#144), so
// it may or may not be live. Never publish it blindly.
// - Real eBay: look the SKU up. Already live -> mark it posted. Not live -> finish the post, which
//   is idempotent by SKU (the inventory item is replaced, the SKU's offer reused).
// - Simulated: mark it failed. Nothing external can be checked, and re-running it would make up
//   a second item number and listing page for the same listing (and the sold timer could then
//   "sell" it), so failing it loudly is the safer choice. The text can still be cross-posted.
async function recover(conn: Conn, l: Listing): Promise<void> {
  if (advancing.has(l.id)) return;
  advancing.add(l.id);
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  try {
    if (l.simulated) {
      if (await setStatus(conn, l, 'failed')) {
        logEvent(conn, { ...ref, kind: 'error', message: 'A post was interrupted by a restart; nothing was posted twice. Marked failed (simulated listing).' });
      }
      return;
    }
    if (!ebay.findLive) {
      if (await setStatus(conn, l, 'failed')) {
        logEvent(conn, { ...ref, kind: 'error', message: `A post to real eBay was interrupted by a restart and the eBay keys are no longer configured, so it can't be checked. Marked failed; check eBay for SKU MOOVE-${l.id}.` });
      }
      return;
    }
    let found: PublishResult | null;
    try {
      found = await ebay.findLive(l.id);
    } catch (err) {
      // Left in `posting`: the next restart checks again. Better stuck than posted twice.
      logEvent(conn, { ...ref, kind: 'error', message: `A post was interrupted by a restart, and checking eBay for SKU MOOVE-${l.id} failed: ${String(err)}. Not posting again.` });
      return;
    }
    if (found) {
      logEvent(conn, { ...ref, kind: 'tool_call', message: `eBay getOffers: a post interrupted by a restart is already live as #${found.externalId}, not posting again`, data: found });
      if (await setStatus(conn, l, 'posted', found.externalId, found.url)) {
        logEvent(conn, { ...ref, kind: 'result', message: `Live as item #${found.externalId}`, data: found });
      }
      return;
    }
    logEvent(conn, { ...ref, kind: 'plan', message: `A post was interrupted by a restart and SKU MOOVE-${l.id} isn't live on eBay yet, so finishing it (same SKU and offer, never a second listing)` });
    await publish(conn, l, ebay);
  } finally {
    advancing.delete(l.id);
  }
}

// Moves one listing forward: draft -> (awaiting_approval ->) posting -> posted, or rejected.
async function advance(conn: Conn, l: Listing): Promise<void> {
  if (advancing.has(l.id)) return;
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  // Re-sorted to keep/donate/... before it posted: withdraw it instead of asking or posting.
  // (A pending approval card can't be closed by the worker; deciding it later does nothing.)
  if ((l.status === 'draft' || l.status === 'awaiting_approval') && !stillSelling(conn, l)) {
    advancing.add(l.id);
    await rejectUnsold(conn, l);
    advancing.delete(l.id);
    return;
  }
  if (l.status === 'draft') {
    const threshold = thresholdFor(conn, l);
    const recall = recallFor(conn, l);
    if (recall || threshold < 0n || l.priceCents > threshold) {
      if (approvalRequested.has(l.id)) return;
      // A restart between request_approval and the status update leaves a draft that was already
      // asked about: reuse that approval rather than asking twice.
      const prior = approvalFor(conn, l);
      if (prior?.amountCents === l.priceCents) approvalRequested.add(l.id);
      else if (!(await askApproval(conn, l))) return;
      if (!(await setStatus(conn, l, 'awaiting_approval'))) {
        // Forget the ask, so the next advance (e.g. the approval being decided) reuses it and retries.
        approvalRequested.delete(l.id);
        return;
      }
      const why = recall
        ? `Possible CPSC recall (${describeMatch(recall)}), asking for approval before posting`
        : `${dollars(l.priceCents)} is over the ${threshold < 0n ? 'always-ask' : dollars(threshold)} threshold, asking for approval`;
      logEvent(conn, { ...ref, kind: 'approval', message: why, ...(recall ? { data: { possibleRecall: true, recallNumber: recall.recallNumber, title: recall.title } } : {}) });
      return;
    }
    advancing.add(l.id);
    await post(conn, l);
    advancing.delete(l.id);
    return;
  }
  if (l.status === 'awaiting_approval') {
    const a = approvalFor(conn, l);
    if (!a) {
      // The status update landed but the approval request didn't (worker died or disconnected).
      if (await askApproval(conn, l)) logEvent(conn, { ...ref, kind: 'approval', message: `Waiting for approval but none was on file, asking again` });
      return;
    }
    if (a.status === 'pending') return;
    if (a.status === 'expired') {
      await reaskAfterExpiry(conn, l);
      return;
    }
    advancing.add(l.id);
    if (a.status === 'approved' && a.amountCents === l.priceCents) {
      logEvent(conn, { ...ref, kind: 'approval', message: `Approved by the user, posting` });
      await post(conn, l);
    } else {
      const why = a.status === 'approved' ? 'price changed after approval' : a.status;
      await setStatus(conn, l, 'rejected');
      logEvent(conn, { ...ref, kind: 'approval', message: `Not posting: ${why}` });
    }
    advancing.delete(l.id);
  }
}

// Writes and posts listings for items sorted to `sell` (#11). Listings above the user's
// approval threshold wait for an `approval` row to be decided (in-app or Auth0 CIBA, #12).
export const listingAgent: Agent = {
  name: 'listing',
  start(conn) {
    const maybeDraft = (it: Item) => {
      if (needsDraft(conn, it)) void draft(conn, it);
    };
    const maybeAdvance = (l: Listing) => void advance(conn, l);
    for (const it of conn.db.item.iter()) maybeDraft(it);
    // `posting` rows at start were left by a worker that died mid-post. Only these are recovered:
    // later `posting` updates are this worker's own claims, already in `advancing`.
    for (const l of conn.db.listing.iter()) {
      if (l.status === 'posting') void recover(conn, l);
      else maybeAdvance(l);
    }
    conn.db.item.onInsert((_ctx, it) => maybeDraft(it));
    conn.db.item.onUpdate((_ctx, _old, it) => {
      maybeDraft(it);
      // Moved off sell: withdraw its unposted listing right away, not only once someone approves it.
      if (it.disposition !== 'sell') {
        for (const l of conn.db.listing.iter()) {
          if (l.itemId === it.id && (l.status === 'draft' || l.status === 'awaiting_approval')) maybeAdvance(l);
        }
      }
    });
    conn.db.listing.onInsert((_ctx, l) => maybeAdvance(l));
    conn.db.listing.onUpdate((_ctx, _old, l) => maybeAdvance(l));
    conn.db.approval.onInsert((_ctx, a) => {
      if (a.kind === 'listing') {
        const l = conn.db.listing.id.find(a.refId);
        if (l) maybeAdvance(l);
      }
    });
    conn.db.approval.onUpdate((_ctx, _old, a) => {
      if (a.kind !== 'listing') return;
      const l = conn.db.listing.id.find(a.refId);
      if (l) maybeAdvance(l);
    });
  },
};
