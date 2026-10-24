// Deal search for the buy agent (#15). Live search belongs to the shared Apify client (#6); until
// it is unavailable, `fixtureDealSource` serves a hand-made sample set from fixtures/deals.json and labels
// every result "sample data" (real cached Apify results say "cached replay" instead).
//
// Everything a deal source returns is untrusted text from the open web: it is sanitized here, never
// put into an LLM prompt as instructions, and only used as data (title, price, url, seller).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export type Condition = 'new' | 'like_new' | 'good' | 'fair' | 'unknown';

export interface DealCandidate {
  source: string; // ikea | target | amazon | wayfair | fb | craigslist | ebay | ...
  title: string;
  priceCents: bigint;
  url: string;
  seller: string;
  condition: Condition;
  /** Miles away for local pickup; -1 when it ships. */
  distanceMiles: number;
  /** `visa`: a merchant we can pay by card. `seller_message`: marketplace seller, the agent drafts a message instead. */
  checkout: 'visa' | 'seller_message';
  replay: boolean;
  /** Hand-made demo data, not from any real search. Labeled "sample data". */
  sample?: boolean;
  /**
   * A planted demo scam from fixtures/deals.json (always also `sample`): served only for the item
   * names in its `plantedFor`, always written, so the demo can show the fraud block live.
   */
  planted?: boolean;
}

export interface DealQuery {
  name: string;
  category: string;
}

export interface DealSource {
  name: string;
  /** True when results are not from a live search. */
  replay: boolean;
  search(q: DealQuery): Promise<DealCandidate[]>;
}

const CONTROL = /[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/g;

/** Strips control/bidi characters and collapses whitespace; scraped text is data, not instructions. */
export function sanitizeText(s: unknown, max = 140): string {
  return String(s ?? '').replace(CONTROL, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

function safeUrl(s: unknown): string {
  try {
    const u = new URL(String(s));
    return u.protocol === 'https:' || u.protocol === 'http:' ? u.toString() : '';
  } catch {
    return '';
  }
}

const CONDITIONS: readonly Condition[] = ['new', 'like_new', 'good', 'fair', 'unknown'];

/** Turns one raw scraped/fixture record into a candidate, or undefined if it is unusable. */
export function toCandidate(raw: Record<string, unknown>, replay: boolean): DealCandidate | undefined {
  const cents = Number(raw.priceCents);
  const url = safeUrl(raw.url);
  const title = sanitizeText(raw.title);
  if (!Number.isFinite(cents) || cents <= 0 || !url || !title) return undefined;
  const condition = CONDITIONS.includes(raw.condition as Condition) ? (raw.condition as Condition) : 'unknown';
  const distance = Number(raw.distanceMiles);
  return {
    source: sanitizeText(raw.source, 24).toLowerCase() || 'web',
    title,
    priceCents: BigInt(Math.round(cents)),
    url,
    seller: sanitizeText(raw.seller, 80),
    condition,
    distanceMiles: Number.isFinite(distance) ? distance : -1,
    checkout: raw.checkout === 'visa' && CARD_CHECKOUT_SOURCES.has(String(raw.source).toLowerCase()) ? 'visa' : 'seller_message',
    replay,
  };
}

type FixtureRow = Record<string, unknown> & { keywords?: string[]; planted?: boolean; plantedFor?: string[] };

const itemName = (q: DealQuery) => q.name.trim().toLowerCase();

function matchScore(q: DealQuery, keywords: string[]): number {
  const hay = ` ${q.name} ${q.category} `.toLowerCase();
  let best = 0;
  for (const k of keywords) {
    const kw = k.toLowerCase();
    if (hay.includes(` ${kw} `) || hay.includes(` ${kw}s `)) best = Math.max(best, kw.length + 10);
    else if (hay.includes(kw)) best = Math.max(best, kw.length);
  }
  return best;
}

/** Replays fixtures/deals.json: picks the keyword group that best matches the item. */
export function fixtureDealSource(rows?: FixtureRow[]): DealSource {
  const load = (): FixtureRow[] => {
    if (rows) return rows;
    const path = fileURLToPath(new URL('../../fixtures/deals.json', import.meta.url));
    return (JSON.parse(readFileSync(path, 'utf8')) as { deals: FixtureRow[] }).deals;
  };
  return {
    name: 'sample data (hand-made fixtures)',
    replay: true,
    async search(q) {
      const all = load();
      // Planted demo scams only show up for the exact item names they were planted for.
      const planted = all.filter(r => r.planted && (r.plantedFor ?? []).some(n => n.toLowerCase() === itemName(q)));
      const scored = all.filter(r => !r.planted).map(r => ({ r, s: matchScore(q, r.keywords ?? []) })).filter(x => x.s > 0);
      const top = Math.max(0, ...scored.map(x => x.s));
      // Keep the whole group sharing the best keyword set.
      const groupKey = top ? JSON.stringify(scored.find(x => x.s === top)!.r.keywords) : '';
      return [
        ...scored.filter(x => JSON.stringify(x.r.keywords) === groupKey).map(x => ({ c: toCandidate(x.r, true), planted: false })),
        ...planted.map(r => ({ c: toCandidate(r, true), planted: true })),
      ]
        .map(({ c, planted }): DealCandidate | undefined => (c ? { ...c, sample: true, ...(planted ? { planted: true } : {}) } : undefined))
        .filter((c): c is DealCandidate => !!c);
    },
  };
}

// ---------- ranking ----------

export interface RankedDeal extends DealCandidate {
  score: number;
  why: string;
}

// Live sources score unknown distances as 25 mi, so say "distance unknown" rather than a made-up number.
const distanceLabel = (c: DealCandidate): string =>
  c.distanceMiles < 0 ? 'ships' : c.seller.includes('distance unknown') ? 'distance unknown' : `${c.distanceMiles} mi`;

const CONDITION_SCORE: Record<Condition, number> = { new: 1, like_new: 0.85, good: 0.65, fair: 0.4, unknown: 0.3 };

/**
 * Ranks by price (cheapest = 1), condition and distance (shipping counts as close), with a small
 * bonus for merchants we can actually check out by card. Deterministic so the demo is repeatable.
 */
export function rankDeals(cands: DealCandidate[]): RankedDeal[] {
  if (!cands.length) return [];
  const min = Number(cands.reduce((m, c) => (c.priceCents < m ? c.priceCents : m), cands[0].priceCents));
  return cands
    .map(c => {
      const price = min / Number(c.priceCents);
      const cond = CONDITION_SCORE[c.condition];
      const dist = c.distanceMiles < 0 ? 0.8 : Math.max(0, 1 - c.distanceMiles / 25);
      const pay = c.checkout === 'visa' ? 1 : 0;
      const score = 0.5 * price + 0.25 * cond + 0.15 * dist + 0.1 * pay;
      const why = [
        `${Math.round(price * 100)}% of best price`,
        c.condition.replace('_', ' '),
        distanceLabel(c),
        c.checkout === 'visa' ? 'card checkout' : 'message seller',
      ].join(', ');
      return { ...c, score: Math.round(score * 1000) / 1000, why };
    })
    .sort((a, b) => b.score - a.score || (a.priceCents < b.priceCents ? -1 : 1));
}

// Retail merchants the buy agent may pay by card. Marketplace deals (fb, craigslist, ...) can't be
// paid through an API, so the agent drafts a message to the seller instead.
export const CARD_CHECKOUT_SOURCES = new Set(['ikea', 'target', 'amazon', 'wayfair']);

/** Short text stored in deal.seller_info: who, condition, distance, how to pay, replay label. */
export function sellerInfo(d: RankedDeal): string {
  return [
    d.seller || d.source,
    d.condition.replace('_', ' '),
    // The seller text already says "distance unknown" when a source has no coordinates.
    ...(d.seller.includes('distance unknown') ? [] : [distanceLabel(d)]),
    d.checkout === 'visa' ? 'Visa checkout' : 'message seller',
    `score ${d.score.toFixed(2)}`,
    ...(d.sample ? ['sample data'] : d.replay ? ['cached replay'] : []),
  ].join(' · ');
}
