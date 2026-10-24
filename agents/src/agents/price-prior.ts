// A comps-free guess at what the item sells for used, from Claude's product knowledge. The pricing
// agent blends it into the comps median (pricing.ts estimate(), weighted as PRICING_PRIOR_WEIGHT
// comps), so 1-3 comps no longer set the price alone, and an item with no comps still gets one.
// The answer is cached in fixtures/comps/<slug>.prior.json, keyed by the prompt + item description,
// so replays don't re-pay. Any failure means no prior (pricing works as before). PRICING_PRIOR=0
// turns it off.

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { z } from 'zod';
import { config } from '../config.js';
import { compsSlug } from '../integrations/apify.js';
import { cleanUntrusted } from '../untrusted.js';
import { describeItem, type ItemDesc } from './comp-filter.js';

export const priorEnabled = (env: { PRICING_PRIOR?: string } = process.env) =>
  !['0', 'false', 'off'].includes((env.PRICING_PRIOR ?? '').trim().toLowerCase());

export const priorCacheFile = (q: string) => path.join('fixtures', 'comps', `${compsSlug(q)}.prior.json`);

export type Prior = { newRetailUsd: number; usedUsd: number; reason: string };
export type PriorJudge = (itemDesc: string) => Promise<Prior>;

const PriorSchema = z.object({
  newRetailUsd: z.number().describe('typical price new today for this product (or the closest ordinary equivalent), USD'),
  usedUsd: z.number().describe('what an ordinary used one in good condition actually sells for locally (Facebook Marketplace, Craigslist, eBay sold), USD'),
  reason: z.string().describe('one line: the product you assumed and the discount applied'),
});

const SYSTEM = `You estimate resale prices for used household items being sold before a move (San Francisco Bay Area).
Give the price an ordinary used one in good condition actually sells for, not the asking price, and not a collector, designer or luxury price unless the item is described that way.
Bulky furniture usually sells for 20-40% of new, mainstream electronics 30-60% depending on age, brand-name office chairs and instruments hold more.
If the description is vague, assume the most common mid-range version.`;

/** Sonnet (MODEL_VISION's default): Haiku's price knowledge is noticeably worse. */
export const claudePrior: PriorJudge = async itemDesc => {
  const { structuredCall } = await import('../integrations/anthropic.js');
  return structuredCall({
    model: config.models.estimate,
    system: SYSTEM,
    text: `Item: ${cleanUntrusted(itemDesc)}`,
    schema: PriorSchema,
    effort: 'low',
    maxTokens: 2048,
  });
};

type CacheEntry = Prior & { item: string; model: string };

const cacheKey = (itemDesc: string) => createHash('sha256').update(JSON.stringify([SYSTEM, itemDesc])).digest('hex').slice(0, 16);

function readCache(file: string): Record<string, CacheEntry> {
  try {
    return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
  } catch {
    return {};
  }
}

export type PriorResult =
  | { status: 'ok' | 'cached'; cents: number; reason: string }
  | { status: 'off' | 'missing' }
  | { status: 'failed'; error: string };

export interface PriorDeps {
  judge?: PriorJudge;
  /** Where to cache answers; null disables caching. */
  cacheFile?: string | null;
  /** Only read the cache, never call Claude (scripts/pricing-eval.ts). */
  cacheOnly?: boolean;
  enabled?: boolean;
}

export async function pricePrior(it: ItemDesc, deps: PriorDeps = {}): Promise<PriorResult> {
  if (!(deps.enabled ?? priorEnabled())) return { status: 'off' };
  const desc = describeItem(it);
  const key = cacheKey(desc);
  const file = deps.cacheFile ?? null;
  const hit = file ? readCache(file)[key] : undefined;
  if (hit) return { status: 'cached', cents: Math.round(hit.usedUsd * 100), reason: hit.reason };
  if (deps.cacheOnly) return { status: 'missing' };
  let p: Prior;
  try {
    p = await (deps.judge ?? claudePrior)(desc);
  } catch (err) {
    return { status: 'failed', error: (err as Error).message };
  }
  // A sane used price: positive, and not above new (a model slip would otherwise anchor every estimate).
  const usd = Math.min(p.usedUsd, p.newRetailUsd > 0 ? p.newRetailUsd : Infinity);
  if (!(usd > 0) || !Number.isFinite(usd)) return { status: 'failed', error: `unusable prior ${JSON.stringify(p).slice(0, 120)}` };
  const reason = cleanUntrusted(String(p.reason ?? ''), 200);
  if (file) {
    try {
      const cache = readCache(file);
      cache[key] = { item: desc, newRetailUsd: p.newRetailUsd, usedUsd: usd, reason, model: config.models.estimate };
      mkdirSync(path.dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify(cache, null, 2));
    } catch (err) {
      console.warn(`[pricing] could not cache price prior: ${(err as Error).message}`);
    }
  }
  return { status: 'ok', cents: Math.round(usd * 100), reason };
}
