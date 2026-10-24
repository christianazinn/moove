import { z } from 'zod';
import type { Agent } from './types.js';
import { findUser, type Conn } from '../spacetime.js';
import type { Approval, Item, Listing } from '../module_bindings/types.js';
import { config } from '../config.js';
import { logEvent } from '../events.js';
import { structuredCall } from '../integrations/anthropic.js';
import { chooseEbay, dollars, simulatedEbay, type EbayPoster } from '../integrations/ebay.js';
import { buildDraftPrompt, clampPrice, finalizeCopy, LISTING_SYSTEM } from './listingPrompt.js';

// Real eBay (sandbox) once scripts/ebay-setup.ts has filled in the EBAY_* keys, otherwise the
// labeled simulation (#11, #32). Fixed at startup so a draft's `simulated` flag matches how it posts.
const ebay: EbayPoster = chooseEbay();

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
    it.disposition === 'sell' &&
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
  try {
    // Comps are scraped (untrusted): cleaned and fenced in the prompt, and the output is checked in code (#17).
    const d = await structuredCall({ model: config.models.agent, system: LISTING_SYSTEM, text: buildDraftPrompt(it, comps), schema: ListingDraft });
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
    await conn.reducers.requestApproval({ owner: l.owner, kind: 'listing', refId: l.id, amountCents: l.priceCents, summary: `Sell "${l.title}" for ${dollars(l.priceCents)}` });
    return true;
  } catch (err) {
    approvalRequested.delete(l.id);
    logEvent(conn, { owner: l.owner, agent: 'listing', kind: 'error', message: `Could not ask for approval: ${String(err)}`, refTable: 'listing', refId: l.id });
    return false;
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
  const it = conn.db.item.id.find(l.itemId);
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  // A listing posts the way it was drafted, so its `simulated` flag stays true to what happened.
  if (!l.simulated && ebay.simulated) {
    await setStatus(conn, l, 'failed');
    logEvent(conn, { ...ref, kind: 'error', message: 'Drafted for real eBay, but the eBay keys are no longer configured' });
    return;
  }
  const poster = l.simulated ? simulatedEbay : ebay;
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
    await setStatus(conn, l, 'posted', r.externalId, r.url);
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

// Moves one listing forward: draft -> (awaiting_approval ->) posted, or rejected.
async function advance(conn: Conn, l: Listing): Promise<void> {
  if (advancing.has(l.id)) return;
  const ref = { owner: l.owner, agent: 'listing', refTable: 'listing', refId: l.id };
  if (l.status === 'draft') {
    const threshold = thresholdFor(conn, l);
    if (threshold < 0n || l.priceCents > threshold) {
      if (approvalRequested.has(l.id)) return;
      // A restart between request_approval and the status update leaves a draft that was already
      // asked about: reuse that approval rather than asking twice.
      const prior = approvalFor(conn, l);
      if (prior?.amountCents === l.priceCents) approvalRequested.add(l.id);
      else if (!(await askApproval(conn, l))) return;
      await setStatus(conn, l, 'awaiting_approval');
      logEvent(conn, { ...ref, kind: 'approval', message: `${dollars(l.priceCents)} is over the ${threshold < 0n ? 'always-ask' : dollars(threshold)} threshold, asking for approval` });
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
    for (const l of conn.db.listing.iter()) maybeAdvance(l);
    conn.db.item.onInsert((_ctx, it) => maybeDraft(it));
    conn.db.item.onUpdate((_ctx, _old, it) => maybeDraft(it));
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
