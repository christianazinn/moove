import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';

// Same shape as CompsLookup in paywall.ts (#7) so the x402 comps endpoint can serve this directly.
export interface Comp {
  source: string;
  title: string;
  priceCents: number;
  url: string;
}
export type CompsResult = { comps: Comp[]; replayed: boolean };

type Source = { name: string; actor: string; input: (q: string) => Record<string, unknown>; maxItems: number };

const city = config.apify.city;
const SOURCES: Record<string, Source> = {
  // Sold prices: the best signal for what something actually goes for.
  ebay: {
    name: 'ebay',
    actor: 'caffein.dev~ebay-sold-listings',
    input: q => ({ keywords: [q], count: 10, daysToScrape: 90, sortOrder: 'endedRecently', itemCondition: 'used' }),
    maxItems: 10,
  },
  // Local asking prices.
  fb: {
    name: 'fb',
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

// Actor outputs differ, so normalize tolerantly and drop rows without a usable price.
function normalize(source: string, rows: any[]): Comp[] {
  return rows
    .map(r => ({
      source,
      title: String(pick(r, ['title', 'name', 'marketplace_listing_title', 'custom_title']) ?? ''),
      priceCents: toCents(
        pick(r, ['soldPrice', 'price', 'listing_price.amount', 'listingPrice.amount', 'sellingPrice', 'formattedPrice', 'priceWithCurrency'])
      ),
      url: String(pick(r, ['url', 'itemUrl', 'listingUrl', 'link', 'marketplace_listing_url']) ?? ''),
    }))
    .filter(c => c.title && c.priceCents > 0);
}

// Cache path for a query, relative to agents/ (the worker's cwd).
export const cacheFile = (q: string) =>
  path.join('fixtures', 'comps', `${q.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80)}.json`);

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
  return normalize(src.name, (await res.json()) as any[]);
}

// Cache-only read: the comps saved for this query, or null. Never calls Apify, so screens like
// fraud (#18) can use comps for free without triggering a paid run.
export function cachedComps(query: string): Comp[] | null {
  const file = cacheFile(query);
  return existsSync(file) ? (JSON.parse(readFileSync(file, 'utf8')) as Comp[]) : null;
}

// Comps for a free-text item query. Results are cached in fixtures/comps/ (keeps Apify spend
// down and doubles as the demo fallback). Cached results come back with replayed=true.
export async function lookupComps(query: string): Promise<CompsResult> {
  const cached = cachedComps(query);
  if (cached) return { comps: cached, replayed: true };
  const file = cacheFile(query);
  if (!config.apify.token) throw new Error('APIFY_TOKEN not set and no cached comps for this query');
  const settled = await Promise.allSettled(config.apify.sources.map(s => runActor(SOURCES[s], query)));
  const comps = settled.flatMap(r => (r.status === 'fulfilled' ? r.value : []));
  const errors = settled.flatMap(r => (r.status === 'rejected' ? [String(r.reason)] : []));
  if (comps.length === 0 && errors.length) throw new Error(errors.join('; '));
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(comps, null, 2));
  return { comps, replayed: false };
}
