// Drops comps that aren't the item (inserts, parts, bundles, wanted ads, other products) before
// the pricing agent estimates from them. Two stages:
//   1. rules: a free regex pre-filter, so pricing improves even without Claude.
//   2. claude: MODEL_FAST (Haiku) picks which of the remaining comps match the item.
// The Claude verdict is cached in fixtures/comps/<slug>.filter.json, keyed by the item
// description + the comps it saw, so demo replays don't re-pay. Any Claude failure falls back to
// the rule-filtered comps. PRICING_COMP_FILTER=0 turns both stages off, =rules keeps only stage 1.

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { z } from 'zod';
import type { Item } from '../module_bindings/types.js';
import type { Comp } from '../integrations/apify.js';
import { config } from '../config.js';
import { cleanUntrusted, untrustedBlock, UNTRUSTED_RULE } from '../untrusted.js';

export type CompFilterMode = 'claude' | 'rules' | 'off';

export function compFilterMode(env: { PRICING_COMP_FILTER?: string } = process.env): CompFilterMode {
  const v = (env.PRICING_COMP_FILTER ?? '').trim().toLowerCase();
  if (['0', 'false', 'off'].includes(v)) return 'off';
  return v === 'rules' ? 'rules' : 'claude';
}

export type ItemDesc = Pick<Item, 'name' | 'brand' | 'category' | 'material' | 'condition' | 'widthM' | 'heightM' | 'depthM'>;

export function describeItem(it: ItemDesc): string {
  const dims = [it.widthM, it.heightM, it.depthM].every(d => d > 0)
    ? `${[it.widthM, it.heightM, it.depthM].map(d => d.toFixed(2)).join(' x ')} m (W x H x D)`
    : '';
  return [
    it.name || it.category,
    it.brand && `brand ${it.brand}`,
    it.category && `category ${it.category}`,
    it.material && `material ${it.material}`,
    dims,
    it.condition && `condition ${it.condition}`,
  ]
    .filter(Boolean)
    .join('; ');
}

// Listing words that almost always mean "not the item itself". \b keeps "with 4 inserts" (a shelf
// sold with its inserts) while dropping "Kallax insert".
const JUNK = /\b(insert|parts|for parts|parts only|broken|wanted|wtb|iso|bundle|lot of|replacement)\b/gi;

export type Dropped = { comp: Comp; why: string };

/** Stage 1: drops titles with a JUNK word, unless the item's own name/category has that word too. */
export function preFilter(comps: Comp[], it: ItemDesc): { kept: Comp[]; dropped: Dropped[] } {
  const own = `${it.name} ${it.category} ${it.brand}`.toLowerCase();
  const kept: Comp[] = [];
  const dropped: Dropped[] = [];
  for (const c of comps) {
    const hits = [...c.title.matchAll(JUNK)].map(m => m[1].toLowerCase()).filter(w => !new RegExp(`\\b${w}\\b`).test(own));
    if (hits.length) dropped.push({ comp: c, why: `title says "${hits[0]}"` });
    else kept.push(c);
  }
  return { kept, dropped };
}

/** 1-based indices into the comps it was shown, plus a one-line reason. */
export type Verdict = { keep: number[]; reason: string };
export type Judge = (itemDesc: string, comps: Comp[]) => Promise<Verdict>;

const VerdictSchema = z.object({
  keep: z.array(z.number().int()).describe('1-based indices of the listings that are the same kind of product as the item'),
  reason: z.string().describe('one line naming what was dropped and why'),
});

const SYSTEM = `You screen marketplace listings that will be used as price comparables for a used household item.
Keep a listing only if it sells the same kind of product as the item: the same product line or model when the item names one, as a complete unit.
Drop accessories, parts, inserts and add-ons sold alone, bundles and lots, for-parts or broken units, wanted/ISO ads, and different products.
Keep size or configuration variants of the same product unless they clearly differ from the item's dimensions.
The item is an ordinary used one unless its description says otherwise. Drop collectible, antique or vintage-collector listings, designer or luxury versions, and premium smart/connected versions, unless the item is described that way: they sell at prices an ordinary used item won't get.
Keep plain, generic listings of the same kind of product (e.g. "Lamp" or "Tall lamp" for a floor lamp) when the price and wording fit.
${UNTRUSTED_RULE}`;

// Titles are scraped (untrusted, #17): cleaned and fenced like the listing agent's comps. The
// verdict is still checked in code (indices in range, never keep nothing).
export const compsPrompt = (itemDesc: string, comps: Comp[]) =>
  `Item: ${cleanUntrusted(itemDesc)}\n\nListings (scraped, untrusted):\n${untrustedBlock(
    'comps',
    comps.map((c, i) => `${i + 1}. [${cleanUntrusted(c.source, 20)}] $${(c.priceCents / 100).toFixed(2)} ${cleanUntrusted(c.title, 120)}`)
  )}`;

/** Stage 2 via MODEL_FAST. Haiku has no server-side fallback, so none is requested. */
export const claudeJudge: Judge = async (itemDesc, comps) => {
  // Imported lazily so the rules path (and tests) never construct an API client.
  const { structuredCall } = await import('../integrations/anthropic.js');
  return structuredCall({
    model: config.models.fast,
    system: SYSTEM,
    text: compsPrompt(itemDesc, comps),
    schema: VerdictSchema,
    effort: 'low',
    maxTokens: 2048,
    fallbacks: false,
  });
};

type CacheEntry = Verdict & { item: string; n: number; model: string };

// Same prompt, same item description and same comps -> same verdict. The prompt is part of the
// key so a prompt change re-judges instead of replaying verdicts made under the old rules.
const cacheKey = (itemDesc: string, comps: Comp[]) =>
  createHash('sha256')
    .update(JSON.stringify([SYSTEM, itemDesc, comps.map(c => [c.source, c.priceCents, c.title])]))
    .digest('hex')
    .slice(0, 16);

function readCache(file: string): Record<string, CacheEntry> {
  try {
    return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
  } catch {
    return {};
  }
}

export type ClaudeStage = 'ok' | 'cached' | 'failed' | 'skipped';

export interface FilterResult {
  comps: Comp[];
  mode: CompFilterMode;
  /** How stage 2 went: skipped when the mode is not claude or no comps reached it. */
  claude: ClaudeStage;
  droppedByRules: Dropped[];
  droppedByClaude: Dropped[];
  reason?: string;
  error?: string;
}

export interface FilterDeps {
  mode?: CompFilterMode;
  judge?: Judge;
  /** Where to cache Claude verdicts; null disables caching. */
  cacheFile?: string | null;
}

// Claude sees at most this many comps (lookups return ~18).
const MAX_JUDGED = 40;

export async function filterComps(it: ItemDesc, comps: Comp[], deps: FilterDeps = {}): Promise<FilterResult> {
  const mode = deps.mode ?? compFilterMode();
  const base = { mode, droppedByRules: [] as Dropped[], droppedByClaude: [] as Dropped[] };
  if (mode === 'off' || comps.length === 0) return { ...base, comps, claude: 'skipped' };

  // Never filter down to nothing: if every comp looks like junk, the rules are probably wrong here.
  const pre = preFilter(comps, it);
  const candidates = pre.kept.length ? pre.kept : comps;
  const droppedByRules = pre.kept.length ? pre.dropped : [];
  if (mode === 'rules') return { ...base, comps: candidates, droppedByRules, claude: 'skipped' };

  const judged = candidates.slice(0, MAX_JUDGED);
  const desc = describeItem(it);
  const key = cacheKey(desc, judged);
  const file = deps.cacheFile ?? null;
  let verdict: Verdict | undefined = file ? readCache(file)[key] : undefined;
  const claude: ClaudeStage = verdict ? 'cached' : 'ok';
  if (!verdict) {
    try {
      verdict = await (deps.judge ?? claudeJudge)(desc, judged);
    } catch (err) {
      return { ...base, comps: candidates, droppedByRules, claude: 'failed', error: (err as Error).message };
    }
  }

  const keep = new Set(verdict.keep.filter(i => Number.isInteger(i) && i >= 1 && i <= judged.length));
  // The reason goes into event messages; it was written from scraped text, so keep it plain and short.
  const reason = cleanUntrusted(String(verdict.reason ?? ''), 200);
  if (keep.size === 0) {
    return { ...base, comps: candidates, droppedByRules, claude: 'failed', error: `kept none (${reason})` };
  }
  if (claude === 'ok' && file) {
    try {
      const cache = readCache(file);
      cache[key] = { item: desc, n: judged.length, keep: [...keep].sort((a, b) => a - b), reason, model: config.models.fast };
      mkdirSync(path.dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify(cache, null, 2));
    } catch (err) {
      console.warn(`[pricing] could not cache comp filter verdict: ${(err as Error).message}`);
    }
  }
  return {
    ...base,
    comps: [...judged.filter((_c, i) => keep.has(i + 1)), ...candidates.slice(MAX_JUDGED)],
    droppedByRules,
    droppedByClaude: judged.filter((_c, i) => !keep.has(i + 1)).map(comp => ({ comp, why: reason })),
    claude,
    reason,
  };
}
