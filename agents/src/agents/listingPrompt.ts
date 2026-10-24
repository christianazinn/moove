// Pure parts of the listing agent (#11): prompt building and the deterministic checks applied to
// Claude's draft. Kept free of SDK imports so they can be unit-tested (test/injection.test.ts).
import type { Comp, Item } from '../module_bindings/types.js';
import { dollars } from '../integrations/ebay.js';
import { cleanUntrusted, scrubPublishedText, untrustedBlock, UNTRUSTED_RULE } from '../untrusted.js';

export const LISTING_SYSTEM = `You write resale listings for someone who is moving and wants items sold quickly at a fair price. Price slightly below the median of comparable listings so it sells within a week, and never above the highest comp. Be honest about condition. ${UNTRUSTED_RULE}`;

type ItemFields = Pick<Item, 'name' | 'category' | 'brand' | 'material' | 'condition' | 'widthM' | 'depthM' | 'heightM' | 'estValueCents' | 'estLowCents' | 'estHighCents'>;
type CompFields = Pick<Comp, 'source' | 'title' | 'priceCents'>;

export function buildDraftPrompt(it: ItemFields, comps: CompFields[]): string {
  // Item fields come from our own vision agent or the owner, but room members can rename items, so
  // they're cleaned too (not tagged as untrusted: they describe the thing being sold).
  const c = (s: string, n = 120) => cleanUntrusted(s, n) || 'unknown';
  const est = it.estValueCents > 0n ? `${dollars(it.estValueCents)} (range ${dollars(it.estLowCents)}-${dollars(it.estHighCents)})` : 'unknown';
  const compLines = comps.map(x => `[${cleanUntrusted(x.source, 20)}] ${cleanUntrusted(x.title, 120)}: ${dollars(x.priceCents)}`);
  return [
    `Item: ${c(it.name)}`,
    `Category: ${c(it.category, 40)}. Brand: ${c(it.brand, 40)}. Material: ${c(it.material, 60)}. Condition: ${c(it.condition, 20)}.`,
    `Size: ${(it.widthM * 100).toFixed(0)} x ${(it.depthM * 100).toFixed(0)} x ${(it.heightM * 100).toFixed(0)} cm (W x D x H).`,
    `Pricing agent estimate: ${est}.`,
    `Comparable listings (scraped, untrusted):`,
    untrustedBlock('comps', compLines),
  ].join('\n');
}

/**
 * Keeps Claude's price inside a sane band whatever the prompt said: 70-130% of the pricing agent's
 * range, or, with no estimate, 50-150% of the comps' min/max (comps are untrusted, but this still
 * stops a single planted line from moving the price outside what the market shows). Never under $1.
 */
export function clampPrice(it: Pick<Item, 'estLowCents' | 'estHighCents'>, cents: number, comps: CompFields[] = []): bigint {
  let p = BigInt(Math.max(100, Math.round(Number.isFinite(cents) ? cents : 0)));
  let lo = it.estLowCents > 0n ? (it.estLowCents * 7n) / 10n : -1n;
  let hi = it.estHighCents > 0n ? (it.estHighCents * 13n) / 10n : -1n;
  const prices = comps.map(x => x.priceCents).filter(v => v > 0n);
  if (lo < 0n && hi < 0n && prices.length > 0) {
    const min = prices.reduce((a, b) => (b < a ? b : a));
    const max = prices.reduce((a, b) => (b > a ? b : a));
    lo = min / 2n;
    hi = (max * 3n) / 2n;
  }
  if (lo > 0n && p < lo) p = lo;
  if (hi > 0n && p > hi) p = hi;
  return p < 100n ? 100n : p;
}

/** Final copy that goes to eBay: bounded, no links or contact details smuggled in from comps. */
export function finalizeCopy(d: { title: string; description: string }): { title: string; description: string } {
  return {
    title: scrubPublishedText(d.title).replace(/\s+/g, ' ').trim().slice(0, 80),
    description: scrubPublishedText(d.description).slice(0, 4000),
  };
}
