import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';

// Same shape as CompsLookup in paywall.ts (#7) so the x402 comps endpoint can serve this directly.
export interface Comp {
  source: string;
  title: string;
  priceCents: number;
  url: string;
  /** Listing photo, when the actor returned one. Only the SAM 3D agent uses it (as a candidate
   *  product image); older caches don't have it. Never sent to the add_comps reducer. */
  imageUrl?: string;
}
export type CompsResult = { comps: Comp[]; replayed: boolean };

// usdPerItem: the actor's pay-per-result price on the free tier (Oct 2026), for the daily spend cap.
type Source = { name: string; actor: string; input: (q: string) => Record<string, unknown>; maxItems: number; usdPerItem: number };

const city = config.apify.city;
const SOURCES: Record<string, Source> = {
  // Sold prices: the best signal for what something actually goes for.
  ebay: {
    name: 'ebay',
    usdPerItem: 0.004,
    actor: 'caffein.dev~ebay-sold-listings',
    input: q => ({ keywords: [q], count: 10, daysToScrape: 90, sortOrder: 'endedRecently', itemCondition: 'used' }),
    maxItems: 10,
  },
  // Local asking prices.
  fb: {
    name: 'fb',
    usdPerItem: 0.0062,
    actor: 'apify~facebook-marketplace-scraper',
    input: q => ({
      startUrls: [{ url: `https://www.facebook.com/marketplace/${city.fb}/search?query=${encodeURIComponent(q)}` }],
      resultsLimit: 8,
    }),
    maxItems: 8,
  },
  // Off by default: the actor has no result-count input, so cost is less predictable.
  craigslist: {
    name: 'craigslist',
    usdPerItem: 0.005,
    actor: 'ivanvs~craigslist-scraper',
    input: q => ({ urls: [{ url: `https://${city.craigslist}.craigslist.org/search/sss?query=${encodeURIComponent(q)}` }], maxAge: 30 }),
    maxItems: 10,
  },
};

const pick = (o: any, keys: string[]): unknown => {
  for (const k of keys) {
    const v = k.split('.').reduce((a, p) => (a == null ? a : a[p]), o);
    if (v != null && v !== '') return v;
  }
  return undefined;
};

function toCents(v: unknown): number {
  if (typeof v === 'number') return Math.round(v * 100);
  if (typeof v === 'string') {
    const m = v.replace(/,/g, '').match(/\d+(\.\d+)?/);
    if (m) return Math.round(parseFloat(m[0]) * 100);
  }
  return -1;
}

// Listing photo fields: eBay sold listings (caffein.dev) and FB Marketplace (apify) dataset schemas.
const IMAGE_KEYS = [
  'fullResThumbnailUrl',
  'thumbnailUrl',
  'primary_listing_photo.photo_image_url',
  'primaryListingPhoto.photo_image_url',
  'primary_listing_photo.image.uri',
  'image',
  'imageUrl',
];
const httpsOrUndefined = (v: unknown): string | undefined => (typeof v === 'string' && /^https:\/\//i.test(v) ? v : undefined);

// Actor outputs differ, so normalize tolerantly and drop rows without a usable price.
export function normalize(source: string, rows: any[]): Comp[] {
  return rows
    .map(r => ({
      source,
      title: String(pick(r, ['title', 'name', 'marketplace_listing_title', 'custom_title']) ?? ''),
      priceCents: toCents(
        pick(r, ['soldPrice', 'price', 'listing_price.amount', 'listingPrice.amount', 'sellingPrice', 'formattedPrice', 'priceWithCurrency'])
      ),
      url: String(pick(r, ['url', 'itemUrl', 'listingUrl', 'link', 'marketplace_listing_url']) ?? ''),
      imageUrl: httpsOrUndefined(pick(r, IMAGE_KEYS)),
    }))
    .filter(c => c.title && c.priceCents > 0)
    .map(c => (c.imageUrl ? c : { source: c.source, title: c.title, priceCents: c.priceCents, url: c.url }));
}

export const compsSlug = (q: string) => q.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80);
// Cache path for a query, relative to agents/ (the worker's cwd).
export const cacheFile = (q: string) => path.join('fixtures', 'comps', `${compsSlug(q)}.json`);
// The pricing agent's relevance-filter verdicts for this query's comps sit next to them.
export const filterCacheFile = (q: string) => path.join('fixtures', 'comps', `${compsSlug(q)}.filter.json`);

async function runActor(src: Source, q: string): Promise<Comp[]> {
  const url = new URL(`https://api.apify.com/v2/acts/${src.actor}/run-sync-get-dataset-items`);
  url.searchParams.set('maxItems', String(src.maxItems));
  url.searchParams.set('maxTotalChargeUsd', String(config.apify.maxUsdPerRun));
  url.searchParams.set('timeout', '120');
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${config.apify.token}` },
    body: JSON.stringify(src.input(q)),
    signal: AbortSignal.timeout(150_000),
  });
  if (!res.ok) throw new Error(`apify ${src.actor}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  const rows = (await res.json()) as any[];
  // Every run bills at least its start; count at least one result's worth.
  addApifySpend(Math.max(1, Array.isArray(rows) ? rows.length : 0) * src.usdPerItem);
  return normalize(src.name, Array.isArray(rows) ? rows : []);
}

// ---------- daily Apify spend cap ----------
// The free plan has about $5/month, and a scan that names 30 objects means about 60 runs. The estimated
// cost of every live comps run (results x the actor's per-result price) goes into a per-day total
// in APIFY_SPEND_FILE. Past APIFY_MAX_USD_PER_DAY, lookups without a cache are refused.
// The buy agent's live deal search (deals-apify.ts, #185) counts into the same total through
// reserveApifySpend(), which books each run's maxTotalChargeUsd before the run starts.
export class ApifyCapError extends Error {}
type ApifySpend = Record<string, { usd: number; runs: number }>;
const apifyDay = (d = new Date()) => d.toISOString().slice(0, 10);
function readApifySpend(file = config.apify.spendFile): ApifySpend {
  try {
    return JSON.parse(readFileSync(file, 'utf8')) as ApifySpend;
  } catch {
    return {};
  }
}
export function apifySpentToday(file = config.apify.spendFile): { usd: number; runs: number } {
  return readApifySpend(file)[apifyDay()] ?? { usd: 0, runs: 0 };
}
function addApifySpend(usd: number, file = config.apify.spendFile): void {
  const log = readApifySpend(file);
  const t = log[apifyDay()] ?? { usd: 0, runs: 0 };
  try {
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify({ ...log, [apifyDay()]: { usd: t.usd + usd, runs: t.runs + 1 } }, null, 2));
  } catch (err) {
    console.warn(`[apify] couldn't record spend: ${String(err)}`);
  }
}

/**
 * Books one run of up to `usd` (the run's maxTotalChargeUsd) into today's total before it starts.
 * Returns false and books nothing when that would pass APIFY_MAX_USD_PER_DAY (0 = no cap). The read
 * and write are synchronous, so parallel runs in one worker can't both squeeze under the cap.
 */
export function reserveApifySpend(usd: number, opts: { file?: string; cap?: number } = {}): boolean {
  const file = opts.file ?? config.apify.spendFile;
  const cap = opts.cap ?? config.apify.maxUsdPerDay;
  if (cap > 0 && apifySpentToday(file).usd + usd > cap + 1e-9) return false;
  addApifySpend(usd, file);
  return true;
}

// Cache-only read: the comps saved for this query, or null. Never calls Apify, so screens like
// fraud (#18) can use comps for free without triggering a paid run.
export function cachedComps(query: string): Comp[] | null {
  const file = cacheFile(query);
  if (!existsSync(file)) return null;
  const comps = JSON.parse(readFileSync(file, 'utf8')) as Comp[];
  // An empty cache (from before only complete lookups were saved) is a miss, not "worth $0".
  return comps.length ? comps : null;
}

// When Apify can't run (out of credit, the daily cap, no token), the pricing agent falls back to the
// cached real comps of the most similar query it has. Similarity is overlap of "thing" words: colors,
// materials and placement words don't count, so "white wall-mounted hair dryer" never matches "white
// wall-mounted sink". The candidate must share a thing word with the query or its category, and the best
// Jaccard over thing words wins.
const STOP = new Set([
  'with', 'and', 'the', 'for', 'of', 'in', 'on', 'to', 'cm', 'inch', 'size', 'used', 'new',
  'white', 'black', 'gray', 'grey', 'brown', 'red', 'blue', 'green', 'yellow', 'orange', 'pink', 'purple', 'beige', 'tan',
  'silver', 'gold', 'chrome', 'clear', 'dark', 'light', 'wood', 'wooden', 'metal', 'plastic', 'glass', 'fabric', 'leather',
  'mesh', 'oak', 'pine', 'wall', 'mounted', 'floor', 'standing', 'small', 'large', 'tall', 'big', 'mini', 'round', 'square',
  'rectangular', 'thin', 'flat', 'open', 'bathroom', 'kitchen', 'office', 'patterned', 'decorative', 'piece', 'two', 'full',
]);
const BROAD_CATEGORIES = new Set(['other', 'unknown', 'object', 'item', 'storage', 'electronics', 'decor', 'appliance', 'kitchenware', 'clothes', 'books', 'art', 'photos', 'instrument']);
const words = (s: string) => new Set(s.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 1 && !STOP.has(w)));
export function similarCachedComps(query: string, category = '', dir = path.join('fixtures', 'comps')): { query: string; comps: Comp[]; score: number } | null {
  const q = words(query);
  const rawQ = new Set(query.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean));
  // Broad categories ("electronics", "decor") say too little to borrow someone else's prices.
  const cat = new Set([...words(category)].filter(w => !BROAD_CATEGORIES.has(w)));
  let best: { file: string; score: number } | null = null;
  let files: string[] = [];
  try {
    files = readdirSync(dir).filter(f => f.endsWith('.json') && !f.endsWith('.filter.json'));
  } catch {
    return null;
  }
  for (const f of files) {
    const slug = f.slice(0, -'.json'.length);
    if (slug === compsSlug(query)) continue; // that's the exact cache, already tried
    const w = words(slug.replace(/-/g, ' '));
    const shared = [...w].filter(x => q.has(x) || cat.has(x));
    if (!shared.length || shared.every(x => BROAD_CATEGORIES.has(x))) continue;
    // Ties (e.g. "chair" vs "mesh office chair") go to the candidate sharing more words overall.
    const raw = slug.split('-').filter(x => rawQ.has(x)).length;
    const score = shared.length / new Set([...q, ...w]).size + raw * 0.01;
    if (!best || score > best.score) best = { file: f, score };
  }
  if (!best) return null;
  try {
    const comps = JSON.parse(readFileSync(path.join(dir, best.file), 'utf8')) as Comp[];
    return comps.length ? { query: best.file.slice(0, -'.json'.length).replace(/-/g, ' '), comps, score: best.score } : null;
  } catch {
    return null;
  }
}

/** Apify can't run at all right now: retrying won't help, but a similar cached query might. */
export function isApifyUnavailable(err: unknown): boolean {
  return err instanceof ApifyCapError || /Monthly usage hard limit|platform-feature-disabled|APIFY_TOKEN not set|spend cap reached|HTTP 40[23]\b/i.test(String(err));
}

// Comps for a free-text item query. Results are cached in fixtures/comps/ (keeps Apify spend
// down and doubles as the demo fallback). Cached results come back with replayed=true.
export async function lookupComps(query: string): Promise<CompsResult> {
  const cached = cachedComps(query);
  if (cached) return { comps: cached, replayed: true };
  const file = cacheFile(query);
  if (!config.apify.token) throw new Error('APIFY_TOKEN not set and no cached comps for this query');
  const cap = config.apify.maxUsdPerDay;
  const spent = apifySpentToday();
  if (cap > 0 && spent.usd >= cap) {
    throw new ApifyCapError(`Apify daily spend cap reached: ~$${spent.usd.toFixed(2)} of $${cap.toFixed(2)} today (${spent.runs} runs); raise APIFY_MAX_USD_PER_DAY to continue`);
  }
  const settled = await Promise.allSettled(config.apify.sources.map(s => runActor(SOURCES[s], query)));
  const comps = settled.flatMap(r => (r.status === 'fulfilled' ? r.value : []));
  const errors = settled.flatMap(r => (r.status === 'rejected' ? [String(r.reason)] : []));
  if (comps.length === 0 && errors.length) throw new Error(errors.join('; '));
  // Save only a complete lookup: a source that failed (concurrency limit, timeout) would
  // otherwise leave the query on one source's comps forever, and an empty result on "$0".
  if (errors.length === 0 && comps.length > 0) {
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(comps, null, 2));
  } else if (errors.length) {
    console.warn(`[apify] "${query}": not caching a partial lookup (${errors.join('; ').slice(0, 200)})`);
  }
  return { comps, replayed: false };
}
