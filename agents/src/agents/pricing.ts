import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import { logEvent } from '../events.js';
import { isBuiltInFixture } from '../builtins.js';
import { filterCacheFile, isApifyUnavailable, lookupComps, similarCachedComps, type Comp, type CompsResult } from '../integrations/apify.js';
import { filterComps, type FilterResult } from './comp-filter.js';
import { pricePrior, priorCacheFile, type PriorResult } from './price-prior.js';
import type { ImageInput } from '../integrations/photos.js';

// Where comps come from. Defaults to calling Apify directly; once the x402 rail (#7) is wired,
// swap in a source that buys them from the paywalled /x402/comps endpoint so every lookup is a
// logged agent payment.
export type CompsSource = (query: string, item: Item) => Promise<CompsResult>;
let compsSource: CompsSource = q => lookupComps(q);
export function setCompsSource(src: CompsSource): void {
  compsSource = src;
}

// The price guess sees the item's latest photo (1.13 -> 0.95 RMSLE on real listing photos). Swappable in tests.
let loadPriorPhoto = async (url: string): Promise<ImageInput> => (await import('../integrations/anthropic.js')).loadImage(url);
export function setPriorPhotoLoader(f: typeof loadPriorPhoto): void {
  loadPriorPhoto = f;
}

// Comps are mostly used listings in "good" shape; scale for the item's condition.
const CONDITION_FACTOR: Record<string, number> = { new: 1.15, like_new: 1.05, good: 1, fair: 0.8, poor: 0.55 };

// Linear interpolation between neighbors, so the median of 2 comps is their midpoint, not the higher one.
const quantile = (sorted: number[], q: number) => {
  const i = Math.min(sorted.length - 1, Math.max(0, q * (sorted.length - 1)));
  const lo = Math.floor(i);
  return sorted[lo] + (sorted[Math.min(lo + 1, sorted.length - 1)] - sorted[lo]) * (i - lo);
};

// How many comps the prior counts as: with 1-3 comps it dominates, with 20 it moves the median a quarter.
// 6, not 3, since the prior names the product and sees the photo: k=6 beat k=3 on the hand labels
// (44% vs 47% mean error) and on 500 Mercari sold listings with text-matched comps (0.55-0.70 vs 0.59-0.81 RMSLE).
export const PRIOR_WEIGHT = Number(process.env.PRICING_PRIOR_WEIGHT ?? 6);

export interface EstimateOpts {
  /** Claude's guess in cents (see price-prior.ts), already for the item's condition: comps get the condition factor, the prior doesn't. */
  prior?: { cents: number; lowCents: number; highCents: number };
  priorWeight?: number;
  /** Comps borrowed from a similar item (Apify down): together they count as one comp, not n. On 174 real
   *  listing photos, loosely matched comps at full weight took RMSLE from 0.94 (the prior alone) to 1.1-1.4. */
  borrowed?: boolean;
}

export type Estimate = { est: number; low: number; high: number; n: number; fromPrior: boolean };

export function estimate(comps: Comp[], condition: string, opts: EstimateOpts = {}): Estimate | null {
  const k = opts.priorWeight ?? PRIOR_WEIGHT;
  const prior = opts.prior && opts.prior.cents > 0 ? opts.prior : null;
  const prices = comps.map(c => c.priceCents).sort((a, b) => a - b);
  const f = CONDITION_FACTOR[condition] ?? 1;
  const r = (x: number) => Math.round(x / 100) * 100; // whole dollars
  if (prices.length === 0) {
    // No comps at all: the prior alone, with its own range.
    return prior ? { est: r(prior.cents), low: r(prior.lowCents), high: r(prior.highCents), n: 0, fromPrior: true } : null;
  }
  // Drop outliers (bundles, parts-only, typos): anything beyond 3x either side of the median.
  const m = quantile(prices, 0.5);
  const trimmed = prices.filter(p => p >= m / 3 && p <= m * 3);
  const n = trimmed.length;
  const w = opts.borrowed ? 1 : n;
  // Shrink toward the prior: w comps vs k pseudo-comps, each quartile toward the prior's range.
  const blend = (q: number, p: number | undefined) => {
    const x = quantile(trimmed, q) * f;
    return p === undefined ? x : (w * x + k * p) / (w + k);
  };
  return {
    est: r(blend(0.5, prior?.cents)),
    low: r(blend(0.25, prior?.lowCents)),
    high: r(blend(0.75, prior?.highCents)),
    n,
    fromPrior: !!prior,
  };
}

export function queryFor(it: Item): string {
  const name = it.name || it.category;
  // Vision often names the brand already ("EIZO 23-inch monitor"); don't search "EIZO EIZO ...".
  const brand = it.brand && !name.toLowerCase().includes(it.brand.toLowerCase()) ? it.brand : '';
  return [brand, name].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}

// One line for the event log, e.g. "Kept 11 of 17 comps (5 by rules, 1 by Claude: ...)".
export function filterSummary(f: FilterResult, total: number): string {
  if (f.mode === 'off') return `Comp filter off (PRICING_COMP_FILTER=0), using all ${total} comps`;
  const parts = [`${f.droppedByRules.length} by rules`];
  if (f.claude === 'ok' || f.claude === 'cached') {
    parts.push(`${f.droppedByClaude.length} by Claude${f.claude === 'cached' ? ' [REPLAYED]' : ''}: ${f.reason}`);
  }
  return `Kept ${f.comps.length} of ${total} comps (dropped ${parts.join(', ')})`;
}

const inFlight = new Set<bigint>();
// Items waiting out a transient failure (Apify's free plan allows 5 concurrent actor runs; a scan
// that imports 30 items at once used to fail most of them).
const coolingDown = new Set<bigint>();
const attempts = new Map<bigint, number>();
// Each item runs one actor per comps source (2 by default), so 2 items keep us under Apify's 5.
const CONCURRENCY = Math.max(1, Number(process.env.PRICING_CONCURRENCY ?? 2));
const MAX_ATTEMPTS = 3;
const RETRY_BASE_MS = Number(process.env.PRICING_RETRY_BASE_MS ?? 30_000);

/** Errors worth retrying later: rate/concurrency limits, upstream 5xx, network trouble. */
export function isTransientPricingError(err: unknown): boolean {
  return /concurrent-runs-limit|actor-memory-limit|memory limit of \d+MB|rate.?limit|too many requests|HTTP (?:429|5\d\d)\b|fetch failed|ECONNRESET|ETIMEDOUT|EAI_AGAIN|ENOTFOUND|socket hang up|timed? ?out|aborted/i.test(String(err));
}

// Price after vision has had its chance: details done/failed, or no photos to look at.
// RoomPlan's catch-all categories. "other" or "storage" alone buys junk comps, so items named only
// that wait until vision (or the user, via rename_item) gives them a real name.
const GENERIC_NAMES = new Set(['', 'other', 'unknown', 'object', 'item', 'storage']);

export function isGenericQuery(it: Item): boolean {
  return !it.brand && GENERIC_NAMES.has((it.name || it.category).trim().toLowerCase());
}

/** Borrowed comps (a similar item's cache) that Claude kept none of: don't price from them. */
export function rejectsBorrowed(similarTo: string, f: Pick<FilterResult, 'claude' | 'error'>): boolean {
  return similarTo !== '' && f.claude === 'failed' && /^kept none/.test(f.error ?? '');
}

export function needsPricing(it: Item): boolean {
  if (it.pricingStatus !== 'pending' || inFlight.has(it.id) || coolingDown.has(it.id) || isGenericQuery(it)) return false;
  return it.detailsStatus === 'done' || it.detailsStatus === 'failed' || it.photoUrls.length === 0;
}

async function price(conn: Conn, it: Item, retry: (it: Item, delayMs: number) => void): Promise<void> {
  if (isBuiltInFixture(it)) {
    // A toilet or radiator stays with the building: no comps (and no Apify spend), no estimate.
    conn.reducers.setItemStage({ itemId: it.id, stage: 'done', field: 'pricing' });
    logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'result', message: `Not priced: "${it.name}" is a built-in fixture that stays with the building`, refTable: 'item', refId: it.id, data: { builtIn: true } });
    return;
  }
  inFlight.add(it.id);
  const q = queryFor(it);
  conn.reducers.setItemStage({ itemId: it.id, stage: 'running', field: 'pricing' });
  logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'tool_call', message: `Looking up comps for "${q}"`, refTable: 'item', refId: it.id });
  try {
    let similarTo = '';
    // Claude's comps-free guess runs alongside the lookup; it never fails pricing.
    const photoUrl = it.photoUrls.at(-1);
    const priorP = (photoUrl ? loadPriorPhoto(photoUrl).catch(() => undefined) : Promise.resolve(undefined))
      .then(photo => pricePrior(it, { cacheFile: priorCacheFile(q), photo }).then(r => ({ r, photo: !!photo })))
      .catch((err: unknown) => ({ r: { status: 'failed', error: String(err) } as PriorResult, photo: false }));
    const { comps: raw, replayed } = await compsSource(q, it).catch((err: unknown) => {
      // Apify can't run (out of credit, daily cap, no token): reuse the real cached comps of the most
      // similar item we have, labeled as such. The relevance filter below still checks them against
      // this item. No match: fail as before.
      const unavailable = !isTransientPricingError(err) && (isApifyUnavailable(err) || /comps lookup failed/i.test(String(err)));
      const sim = unavailable ? similarCachedComps(q, it.category) : null;
      if (!sim) throw err;
      similarTo = sim.query;
      logEvent(conn, {
        owner: it.owner,
        agent: 'pricing',
        kind: 'tool_call',
        message: `[REPLAYED] No live comps (${String(err).replace(/^Error: /, '').slice(0, 120)}); using cached real comps for a similar item "${sim.query}"`,
        refTable: 'item',
        refId: it.id,
        data: { query: q, similarTo: sim.query, score: Number(sim.score.toFixed(2)), replayed: true, reason: String(err).slice(0, 300) },
      });
      return { comps: sim.comps, replayed: true };
    });
    // Drop accessories/parts/bundles/other products before they skew the estimate.
    const f = await filterComps(it, raw, { cacheFile: filterCacheFile(q) });
    // The lookup takes seconds, and the sweep, vision or the user may have renamed (or deleted) the
    // item meanwhile: comps and a price for the old query would be wrong, so price it again instead.
    const now = conn.db.item.id.find(it.id);
    if (!now) return;
    if (queryFor(now) !== q) {
      // Its update arrives after `finally` clears inFlight, so onUpdate queues it again.
      conn.reducers.setItemStage({ itemId: it.id, stage: 'pending', field: 'pricing' });
      logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'plan', message: `Renamed to "${queryFor(now)}" while pricing "${q}": dropped those comps, re-pricing`, refTable: 'item', refId: it.id, data: { query: q, newQuery: queryFor(now), repriced: true } });
      return;
    }
    if (rejectsBorrowed(similarTo, f)) {
      // Borrowed comps that Claude says are all a different product: no price beats a wrong one.
      conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'pricing' });
      logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'error', message: `No live comps, and the cached comps for "${similarTo}" aren't this item (${f.error}); not priced`, refTable: 'item', refId: it.id, data: { query: q, similarTo, borrowedRejected: true } });
      return;
    }
    const comps = f.comps;
    const dropped = raw.length - comps.length;
    if (f.claude === 'failed') {
      logEvent(conn, {
        owner: it.owner,
        agent: 'pricing',
        kind: 'error',
        message: `Claude comp filter failed (${f.error}), using rule-filtered comps`,
        refTable: 'item',
        refId: it.id,
        data: { query: q, fallback: true, reason: f.error },
      });
    }
    if (raw.length) {
      logEvent(conn, {
        owner: it.owner,
        agent: 'pricing',
        kind: 'tool_call',
        message: filterSummary(f, raw.length),
        refTable: 'item',
        refId: it.id,
        data: {
          query: q,
          mode: f.mode,
          claude: f.claude,
          kept: comps.length,
          dropped,
          droppedTitles: [...f.droppedByRules, ...f.droppedByClaude].map(d => `${d.comp.title} (${d.why})`),
        },
      });
    }
    // Always written, even empty: add_comps replaces the item's comps, so a re-price that ends with
    // none clears the old query's comps instead of leaving them behind the new estimate (the app
    // builds its value ranges and "≈" counts from them).
    conn.reducers.addComps({
      itemId: it.id,
      comps: comps.slice(0, 20).map(c => ({ source: c.source, title: c.title, url: c.url, priceCents: BigInt(c.priceCents) })),
    });
    const { r: prior, photo: sawPhoto } = await priorP;
    if (prior.status === 'ok' || prior.status === 'cached') {
      logEvent(conn, {
        owner: it.owner,
        agent: 'pricing',
        kind: 'tool_call',
        message: `${prior.status === 'cached' ? '[REPLAYED] ' : ''}Claude's price guess without comps${sawPhoto ? ', from the photo' : ''}: ~$${Math.round(prior.cents / 100)} for ${prior.reason}`,
        refTable: 'item',
        refId: it.id,
        data: { query: q, priorCents: prior.cents, priorLowCents: prior.lowCents, priorHighCents: prior.highCents, photo: sawPhoto, replayed: prior.status === 'cached' },
      });
    } else if (prior.status === 'failed') {
      logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'error', message: `Claude price guess failed (${prior.error.slice(0, 160)}), estimating from comps alone`, refTable: 'item', refId: it.id, data: { query: q, fallback: true } });
    }
    const priorOk = prior.status === 'ok' || prior.status === 'cached' ? prior : undefined;
    const priorCents = priorOk?.cents;
    const e = estimate(comps, it.condition, { prior: priorOk, borrowed: similarTo !== '' });
    if (!e) {
      conn.reducers.setEstValue({ itemId: it.id, estValueCents: 0n, estLowCents: 0n, estHighCents: 0n });
      logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'result', message: `No comps for "${q}", valued at $0`, refTable: 'item', refId: it.id });
      return;
    }
    conn.reducers.setEstValue({ itemId: it.id, estValueCents: BigInt(e.est), estLowCents: BigInt(e.low), estHighCents: BigInt(e.high) });
    logEvent(conn, {
      owner: it.owner,
      agent: 'pricing',
      kind: 'result',
      message: `${similarTo ? `[REPLAYED, similar item "${similarTo}"] ` : replayed ? '[REPLAYED] ' : ''}${q}: ~$${e.est / 100} ($${e.low / 100}-$${e.high / 100}) ${e.n === 0 ? "from Claude's guess alone (no comps)" : `from ${comps.length} comps${e.fromPrior ? " + Claude's guess" : ''}`}${dropped ? ` (${dropped} irrelevant dropped)` : ''}`,
      refTable: 'item',
      refId: it.id,
      data: { query: q, replayed, ...(similarTo ? { similarTo } : {}), ...e, n: comps.length, priorCents: priorCents ?? null, dropped, filter: f.mode, filterClaude: f.claude },
    });
  } catch (err) {
    const n = (attempts.get(it.id) ?? 0) + 1;
    attempts.set(it.id, n);
    if (isTransientPricingError(err) && n < MAX_ATTEMPTS) {
      const delayMs = RETRY_BASE_MS * 3 ** (n - 1);
      coolingDown.add(it.id);
      conn.reducers.setItemStage({ itemId: it.id, stage: 'pending', field: 'pricing' });
      logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'error', message: `Comps lookup busy, retrying in ${Math.round(delayMs / 1000)} s (attempt ${n}/${MAX_ATTEMPTS}): ${String(err).slice(0, 200)}`, refTable: 'item', refId: it.id });
      retry(it, delayMs);
    } else {
      conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'pricing' });
      logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'error', message: String(err), refTable: 'item', refId: it.id });
    }
  } finally {
    inFlight.delete(it.id);
  }
}

// Prices items from marketplace comps (#6).
export const pricingAgent: Agent = {
  name: 'pricing',
  start(conn) {
    const queue: Item[] = [];
    let running = 0;
    const pump = () => {
      while (running < CONCURRENCY && queue.length > 0) {
        const queued = queue.shift()!;
        // The row may have been renamed or deleted while queued: price what's there now.
        const it = conn.db.item.id.find(queued.id);
        if (!it || !needsPricing(it)) continue;
        running++;
        void price(conn, it, retry).finally(() => {
          running--;
          pump();
        });
      }
    };
    // Generic items already being marked failed, so updates still in flight don't log it twice.
    const givingUp = new Set<bigint>();
    const maybe = (it: Item) => {
      if (it.pricingStatus !== 'pending') givingUp.delete(it.id);
      else if (isGenericQuery(it) && (it.detailsStatus === 'done' || it.detailsStatus === 'failed')) {
        // Vision had its chance and left a catch-all name ("storage", "other"): nothing will name it
        // now, so don't leave it "pricing..." forever (sort waits on pricing). A rename re-prices it.
        if (givingUp.has(it.id)) return;
        givingUp.add(it.id);
        conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'pricing' });
        logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'result', message: `Not priced: "${it.name || it.category}" is too generic to look up; rename it to price it`, refTable: 'item', refId: it.id, data: { query: queryFor(it), generic: true } });
        return;
      }
      if (needsPricing(it) && !queue.some(q => q.id === it.id)) {
        queue.push(it);
        pump();
      }
    };
    function retry(it: Item, delayMs: number) {
      setTimeout(() => {
        coolingDown.delete(it.id);
        const row = conn.db.item.id.find(it.id);
        if (row) maybe(row);
      }, delayMs).unref?.();
    }
    // PRICING_RETRY_FAILED=1: items an earlier run gave up on (e.g. the Apify concurrency limit
    // before this queue existed) get one more try. Opt-in, since each retry spends Apify credit.
    if (process.env.PRICING_RETRY_FAILED === '1') for (const it of conn.db.item.iter()) {
      if (it.pricingStatus === 'failed' && !isGenericQuery(it)) {
        conn.reducers.setItemStage({ itemId: it.id, stage: 'pending', field: 'pricing' });
      }
    }
    // A previous worker that died (supervisor restart, maincloud republish) mid-lookup left its items
    // `running` forever: nothing else re-queues them. Only one worker runs, so put them back to pending
    // (the comps cache usually makes the retry a free replay; a paid comps call may be bought again).
    for (const it of conn.db.item.iter()) {
      if (it.pricingStatus === 'running' && !inFlight.has(it.id)) {
        conn.reducers.setItemStage({ itemId: it.id, stage: 'pending', field: 'pricing' });
      }
    }
    for (const it of conn.db.item.iter()) maybe(it);
    conn.db.item.onInsert((_ctx, it) => maybe(it));
    conn.db.item.onUpdate((_ctx, old, it) => {
      // A rename after pricing finished (vision after a new photo, the user's rename_item): the old
      // price is for another query. Running items are re-checked at the end of price().
      if (queryFor(old) !== queryFor(it) && (it.pricingStatus === 'done' || it.pricingStatus === 'failed') && !inFlight.has(it.id) && !isBuiltInFixture(it)) {
        conn.reducers.setItemStage({ itemId: it.id, stage: 'pending', field: 'pricing' });
        logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'plan', message: `Name changed, re-pricing: "${queryFor(old)}" is now "${queryFor(it)}"`, refTable: 'item', refId: it.id, data: { query: queryFor(it), oldQuery: queryFor(old), repriced: true } });
        return;
      }
      maybe(it);
    });
  },
};
