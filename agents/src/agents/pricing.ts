import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import { logEvent } from '../events.js';
import { filterCacheFile, lookupComps, type Comp, type CompsResult } from '../integrations/apify.js';
import { filterComps, type FilterResult } from './comp-filter.js';

// Where comps come from. Defaults to calling Apify directly; once the x402 rail (#7) is wired,
// swap in a source that buys them from the paywalled /x402/comps endpoint so every lookup is a
// logged agent payment.
export type CompsSource = (query: string, item: Item) => Promise<CompsResult>;
let compsSource: CompsSource = q => lookupComps(q);
export function setCompsSource(src: CompsSource): void {
  compsSource = src;
}

// Comps are mostly used listings in "good" shape; scale for the item's condition.
const CONDITION_FACTOR: Record<string, number> = { new: 1.15, like_new: 1.05, good: 1, fair: 0.8, poor: 0.55 };

const quantile = (sorted: number[], q: number) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.round(q * (sorted.length - 1))))];

export function estimate(comps: Comp[], condition: string): { est: number; low: number; high: number } | null {
  const prices = comps.map(c => c.priceCents).sort((a, b) => a - b);
  if (prices.length === 0) return null;
  // Drop outliers (bundles, parts-only, typos): anything beyond 3x either side of the median.
  const m = quantile(prices, 0.5);
  const trimmed = prices.filter(p => p >= m / 3 && p <= m * 3);
  const f = CONDITION_FACTOR[condition] ?? 1;
  const r = (x: number) => Math.round((x * f) / 100) * 100; // whole dollars
  return { est: r(quantile(trimmed, 0.5)), low: r(quantile(trimmed, 0.25)), high: r(quantile(trimmed, 0.75)) };
}

export function queryFor(it: Item): string {
  return [it.brand, it.name || it.category].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
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

// Price after vision has had its chance: details done/failed, or no photos to look at.
function needsPricing(it: Item): boolean {
  if (it.pricingStatus !== 'pending' || inFlight.has(it.id)) return false;
  return it.detailsStatus === 'done' || it.detailsStatus === 'failed' || it.photoUrls.length === 0;
}

async function price(conn: Conn, it: Item): Promise<void> {
  inFlight.add(it.id);
  const q = queryFor(it);
  conn.reducers.setItemStage({ itemId: it.id, stage: 'running', field: 'pricing' });
  logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'tool_call', message: `Looking up comps for "${q}"`, refTable: 'item', refId: it.id });
  try {
    const { comps: raw, replayed } = await compsSource(q, it);
    // Drop accessories/parts/bundles/other products before they skew the estimate.
    const f = await filterComps(it, raw, { cacheFile: filterCacheFile(q) });
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
    if (comps.length) {
      conn.reducers.addComps({
        itemId: it.id,
        comps: comps.slice(0, 20).map(c => ({ ...c, priceCents: BigInt(c.priceCents) })),
      });
    }
    const e = estimate(comps, it.condition);
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
      message: `${replayed ? '[REPLAYED] ' : ''}${q}: ~$${e.est / 100} ($${e.low / 100}-$${e.high / 100}) from ${comps.length} comps${dropped ? ` (${dropped} irrelevant dropped)` : ''}`,
      refTable: 'item',
      refId: it.id,
      data: { query: q, replayed, n: comps.length, dropped, filter: f.mode, filterClaude: f.claude, ...e },
    });
  } catch (err) {
    conn.reducers.setItemStage({ itemId: it.id, stage: 'failed', field: 'pricing' });
    logEvent(conn, { owner: it.owner, agent: 'pricing', kind: 'error', message: String(err), refTable: 'item', refId: it.id });
  } finally {
    inFlight.delete(it.id);
  }
}

// Prices items from marketplace comps (#6).
export const pricingAgent: Agent = {
  name: 'pricing',
  start(conn) {
    const maybe = (it: Item) => {
      if (needsPricing(it)) void price(conn, it);
    };
    for (const it of conn.db.item.iter()) maybe(it);
    conn.db.item.onInsert((_ctx, it) => maybe(it));
    conn.db.item.onUpdate((_ctx, _old, it) => maybe(it));
  },
};
