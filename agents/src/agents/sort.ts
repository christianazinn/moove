import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import { logEvent } from '../events.js';

// Auto-sort (#8): keep / sell / donate / trash from pure rules, no model calls. The reducer
// (set_auto_disposition) never overrides a user's choice and forces 'undecided' on possibly
// sentimental items. Auto decisions follow their inputs: if vision, pricing or the user's
// fragile/sentimental flags change after sorting, the item is re-sorted (or parked if sentimental).

const envNum = (name: string, dflt: number) => {
  const n = Number(process.env[name] || dflt);
  return Number.isFinite(n) && n >= 0 ? n : dflt;
};

// Rough cost to move a cubic meter of stuff on a local move (movers + truck + packing),
// ~ $60/m^3 (a 2-bedroom of ~25 m^3 at $1.5k). Every item costs at least MIN_MOVE to box and
// carry, and fragile items cost FRAGILE_FACTOR more (padding, special boxes).
export const MOVE_CENTS_PER_M3 = Math.round(envNum('SORT_MOVE_USD_PER_M3', 60) * 100);
export const MIN_MOVE_CENTS = 200;
export const FRAGILE_FACTOR = 1.5;
// Below this a resale listing isn't worth the hassle: donate instead of sell.
export const SELL_MIN_CENTS = Math.round(envNum('SORT_SELL_MIN_USD', 25) * 100);
// Worth moving only if it's worth this much more than the move costs; in between, sell it.
export const KEEP_MARGIN = 1.25;
// What set_auto_disposition writes for sentimental items; once the user clears the flag we re-sort.
export const SENTIMENTAL_REASON = 'possibly sentimental - your call';

export type Disposition = 'keep' | 'sell' | 'donate' | 'trash' | 'undecided';
export type SortInput = Pick<
  Item,
  'name' | 'category' | 'condition' | 'estValueCents' | 'widthM' | 'heightM' | 'depthM' | 'fragile'
>;
export type SortGate = SortInput &
  Pick<Item, 'disposition' | 'dispositionSource' | 'dispositionReason' | 'maybeSentimental' | 'pricingStatus' | 'detailsStatus' | 'photoUrls'>;

const usd = (cents: number) => (cents > 0 && cents < 100 ? '<$1' : `$${Math.round(cents / 100)}`);
const has = (it: SortInput, words: string[]) => {
  const s = `${it.category} ${it.name}`.toLowerCase();
  return words.some(w => new RegExp(`\\b${w}s?\\b`).test(s)); // whole words, so 'bed' isn't 'bedside'
};

// Built into the house (RoomPlan detects these too): they stay, so there is nothing to sort.
const BUILT_IN = ['toilet', 'bathtub', 'sink', 'fireplace', 'stair'];
const BEDDING = ['mattress', 'bed'];
const SOFT_GOODS = ['clothing', 'clothes', 'book', 'textile', 'linen'];

export function moveCostCents(it: SortInput): number {
  const vol = Math.max(0, it.widthM) * Math.max(0, it.heightM) * Math.max(0, it.depthM);
  const c = Math.max(MIN_MOVE_CENTS, vol * MOVE_CENTS_PER_M3) * (it.fragile ? FRAGILE_FACTOR : 1);
  return Math.round(c);
}

// The rules. Planet-first: trash only what's in poor shape and not worth selling; anything usable
// is donated instead.
export function decide(it: SortInput): { disposition: Disposition; reason: string } {
  if (has(it, BUILT_IN)) return { disposition: 'undecided', reason: 'Built-in fixture: stays with the house' };
  const v = Number(it.estValueCents); // -1 unknown, 0 = no comps found
  const known = v > 0;
  const cost = moveCostCents(it);
  const poor = it.condition === 'poor';
  const worth = known ? `Worth ~${usd(v)}` : 'No resale data';
  const toMove = `~${usd(cost)} to move${it.fragile ? ' (fragile)' : ''}`;

  // Used mattresses barely resell (and donation centers refuse worn ones), but you need a bed.
  if (has(it, BEDDING) && !has(it, SOFT_GOODS)) { // bed linen is linen, not a bed
    if (poor) return { disposition: 'trash', reason: `Worn bed${known ? ` (~${usd(v)})` : ''}: won't resell or be accepted as a donation, trash` };
    return { disposition: 'keep', reason: `Beds rarely resell${known ? ` (~${usd(v)})` : ''}; ${toMove}: keep` };
  }
  if (poor) {
    if (known && v >= SELL_MIN_CENTS) return { disposition: 'sell', reason: `Poor shape but worth ~${usd(v)}: sell as-is` };
    return { disposition: 'trash', reason: `Poor shape and ${known ? `worth only ~${usd(v)}` : v === 0 ? 'no resale value' : 'no resale data'}: trash` };
  }
  if (has(it, SOFT_GOODS) && (!known || v < SELL_MIN_CENTS))
    return { disposition: 'donate', reason: `${worth}, too little to list: donate` };
  if (!known) return { disposition: 'keep', reason: `${worth}; ${toMove}: keep for now` };
  if (v < cost)
    return v >= SELL_MIN_CENTS
      ? { disposition: 'sell', reason: `${worth} but ${toMove}: sell` }
      : { disposition: 'donate', reason: `${worth} but ${toMove}: donate` };
  if (v < cost * KEEP_MARGIN && v >= SELL_MIN_CENTS)
    return { disposition: 'sell', reason: `${worth}, ${toMove}: barely worth moving, sell` };
  return { disposition: 'keep', reason: `${worth}, ${toMove}: keep` };
}

// What to write for an item now, or null to leave it alone. Never touches user-set items.
// Sentimental items are parked (the reducer forces undecided + SENTIMENTAL_REASON), even if
// they were auto-sorted before the flag was set. Others are sorted once pricing is settled and
// vision has had its chance, and re-sorted whenever decide() no longer matches what's stored.
export function nextSort(it: SortGate): { disposition: Disposition; reason: string } | null {
  if (it.dispositionSource !== 'auto') return null;
  if (it.maybeSentimental) {
    const parked = it.disposition === 'undecided' && it.dispositionReason === SENTIMENTAL_REASON;
    return parked ? null : { disposition: 'undecided', reason: SENTIMENTAL_REASON };
  }
  if (it.pricingStatus !== 'done' && it.pricingStatus !== 'failed') return null;
  if (it.photoUrls.length > 0 && it.detailsStatus !== 'done' && it.detailsStatus !== 'failed') return null;
  const d = decide(it);
  return d.disposition === it.disposition && d.reason === it.dispositionReason ? null : d;
}

const inFlight = new Set<bigint>();

function sort(conn: Conn, it: Item, d: { disposition: Disposition; reason: string }): void {
  inFlight.add(it.id);
  logEvent(conn, {
    owner: it.owner,
    agent: 'sort',
    kind: 'result',
    message: `${it.name}: ${d.reason}`,
    refTable: 'item',
    refId: it.id,
    data: { ...d, previous: it.disposition, estValueCents: it.estValueCents, moveCostCents: moveCostCents(it), condition: it.condition, fragile: it.fragile },
  });
  // Clear in-flight once the reducer settles, by which time the cache has the new row.
  void Promise.resolve(conn.reducers.setAutoDisposition({ itemId: it.id, disposition: d.disposition, reason: d.reason }))
    .catch(err => logEvent(conn, { owner: it.owner, agent: 'sort', kind: 'error', message: String(err), refTable: 'item', refId: it.id }))
    .finally(() => inFlight.delete(it.id));
}

// Sorts priced items into keep/sell/donate/trash (#8).
export const sortAgent: Agent = {
  name: 'sort',
  start(conn) {
    const maybe = (it: Item) => {
      if (inFlight.has(it.id)) return;
      const d = nextSort(it);
      if (d) sort(conn, it, d);
    };
    for (const it of conn.db.item.iter()) maybe(it);
    conn.db.item.onInsert((_ctx, it) => maybe(it));
    conn.db.item.onUpdate((_ctx, _old, it) => maybe(it));
  },
};
