// Live deal search for the buy agent (#15): active for-sale listings (not sold comps) scraped through
// Apify, behind the DealSource interface from deals.ts.
//
// Actors (IDs, input schemas and pricing checked against the Apify API/store on 2026-10-23):
//   fb          apify~facebook-marketplace-scraper        input {startUrls, resultsLimit}; ~$0.0062/listing (free tier)
//   craigslist  ivanvs~craigslist-scraper-pay-per-result  input {urls, maxAge}; ~$0.006/ad, no start fee, no result-count
//                                                         input (capped with the run's maxItems), minimum max charge $0.10
//   ebay        automation-lab~ebay-scraper               input {searchQueries, listingType: 'buy_it_now', maxProductsPerSearch,
//                                                         maxSearchPages}; $0.001 start + ~$0.00345/product
// With the default 6 per source, one item costs about $0.10 on Apify's free tier. Sources run in parallel,
// and each run is capped by `maxTotalChargeUsd` and a 120 s actor timeout. Each run also books that
// maxTotalChargeUsd into the per-day Apify total shared with pricing comps (apify.ts, #170/#185); past
// APIFY_MAX_USD_PER_DAY the run is skipped with a notice and the search falls back as below.
//
// Fallback chain, each step labeled: live search -> last cached live search for the same query
// (fixtures/deals-live-<query>.json, replay: true) -> the hand-curated fixtureDealSource (replay: true).
// The cache stores only the trimmed fields we use (no descriptions, phone numbers or emails), so it is
// safe to commit as a demo fixture.
//
// Everything scraped is untrusted text: it only ever becomes data (title, price, url, seller), is
// sanitized by toCandidate(), and is never put into an LLM prompt as instructions.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../config.js';
import { apifySpentToday, reserveApifySpend } from './apify.js';
import { fixtureDealSource, sanitizeText, toCandidate, type DealCandidate, type DealQuery, type DealSource } from './deals.js';

type Env = Record<string, string | undefined>;
type Raw = Record<string, unknown>;
export type ApifySourceName = 'fb' | 'craigslist' | 'ebay';

/** One trimmed listing, in the shape toCandidate() accepts. This is what the cache stores. */
export interface RawDeal extends Raw {
  source: ApifySourceName;
  title: string;
  priceCents: number;
  url: string;
  seller: string;
  condition: string;
  distanceMiles: number;
  checkout: 'seller_message';
}

export interface ApifyDealOptions {
  token?: string;
  sources?: ApifySourceName[];
  perSource?: number;
  maxUsdPerRun?: number;
  city?: { fb: string; craigslist: string };
  /** Buyer's location, for distances when a listing has coordinates. */
  home?: { lat: number; lng: number };
  /** Where live searches are cached at runtime (gitignored). Default: agents/.cache/deals. */
  cacheDir?: string;
  /** Committed live replays, read after the runtime cache. Default: agents/fixtures (or cacheDir if only that is given). */
  replayDir?: string;
  fetch?: typeof fetch;
  /** Used when live and cache both come back empty. Default: fixtureDealSource(). */
  fallback?: DealSource;
  now?: () => Date;
  /** Shared daily Apify spend log (#170/#185). Default: APIFY_SPEND_FILE (.cache/apify-spend.json). */
  spendFile?: string;
  /** Daily Apify cap shared with pricing comps, in USD; 0 = no cap. Default: APIFY_MAX_USD_PER_DAY ($2). */
  maxUsdPerDay?: number;
}

// Distance used for a local listing whose location we can't measure: the far edge of rankDeals'
// 25-mile scale, so an unknown distance never beats a known one. The seller text says "distance unknown".
export const UNKNOWN_DISTANCE_MILES = 25;

// ---------- small helpers (pick/toCents adapted from apify.ts (#6), where they are module-private) ----------

const pick = (o: unknown, keys: string[]): unknown => {
  for (const k of keys) {
    const v = k.split('.').reduce<any>((a, p) => (a == null ? a : a[p]), o);
    if (v != null && v !== '') return v;
  }
  return undefined;
};

/** Dollars (number or "$1,200" / "1200") to cents; -1 when there is no single usable price. */
export function toCents(v: unknown): number {
  if (typeof v === 'number') return Number.isFinite(v) ? Math.round(v * 100) : -1;
  if (typeof v === 'string') {
    if (/\bto\b|-\s*\$/i.test(v)) return -1; // "$10 to $20" ranges: not one price
    const m = v.replace(/,/g, '').match(/\d+(\.\d+)?/);
    if (m) return Math.round(parseFloat(m[0]) * 100);
  }
  return -1;
}

const str = (v: unknown, max = 140) => sanitizeText(typeof v === 'object' ? '' : v, max);

function isUsd(v: unknown): boolean {
  return v == null || v === '' || String(v).toUpperCase() === 'USD';
}

/** Lowercase condition text from any marketplace to the deal Condition vocabulary. */
export function mapCondition(v: unknown): string {
  const s = String(v ?? '').toLowerCase();
  if (!s) return 'unknown';
  if (/like new|open box|excellent|mint/.test(s)) return 'like_new';
  if (/refurb|good|pre-?owned/.test(s)) return 'good';
  if (/fair|salvage|parts/.test(s)) return 'fair';
  if (/\bused\b/.test(s)) return 'good';
  if (/\bnew\b/.test(s)) return 'new';
  return 'unknown';
}

function haversineMiles(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const r = (d: number) => (d * Math.PI) / 180;
  const h = Math.sin(r(b.lat - a.lat) / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(r(b.lng - a.lng) / 2) ** 2;
  return 3958.8 * 2 * Math.asin(Math.sqrt(h));
}

function distance(home: ApifyDealOptions['home'], lat: unknown, lng: unknown): number | undefined {
  const la = Number(lat);
  const ln = Number(lng);
  if (!home || lat == null || lng == null || !Number.isFinite(la) || !Number.isFinite(ln)) return undefined;
  return Math.round(haversineMiles(home, { lat: la, lng: ln }) * 10) / 10;
}

/** Canonical listing URL (drops tracking params) used for dedupe and storage. */
export function canonicalUrl(source: ApifySourceName, u: unknown): string {
  let url: URL;
  try {
    url = new URL(String(u));
  } catch {
    return '';
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return '';
  const host = url.hostname.toLowerCase();
  if (source === 'ebay') {
    const id = url.pathname.match(/\/itm\/(?:[^/]+\/)?(\d{9,})/)?.[1];
    if (!/(^|\.)ebay\.com$/.test(host)) return '';
    return id ? `https://www.ebay.com/itm/${id}` : `${url.origin}${url.pathname}`;
  }
  if (source === 'fb') {
    const id = url.pathname.match(/\/marketplace\/item\/(\d+)/)?.[1];
    return id && /(^|\.)facebook\.com$/.test(host) ? `https://www.facebook.com/marketplace/item/${id}/` : '';
  }
  return /(^|\.)craigslist\.org$/.test(host) && /\.html$/.test(url.pathname) ? `https://${host}${url.pathname}` : '';
}

// ---------- per-actor normalizers ----------

type Normalizer = (r: Raw, home: ApifyDealOptions['home']) => RawDeal | undefined;

const normalizeFb: Normalizer = (r, home) => {
  if (r.error || pick(r, ['is_sold', 'isSold']) === true || pick(r, ['is_pending', 'isPending']) === true) return undefined;
  if (pick(r, ['is_live', 'isLive']) === false || pick(r, ['is_hidden', 'isHidden']) === true) return undefined;
  if (!isUsd(pick(r, ['listing_price.currency', 'listingPrice.currency']))) return undefined;
  const city = str(pick(r, ['location.reverse_geocode.city', 'location.city']), 40);
  const state = str(pick(r, ['location.reverse_geocode.state', 'location.state']), 20);
  const where = [city, state].filter(Boolean).join(', ') || str(pick(r, ['locationText.text']), 60);
  const miles = distance(home, pick(r, ['location.latitude', 'location.lat']), pick(r, ['location.longitude', 'location.lng']));
  // Privacy: FB sellers are private people, so their names are never read or stored.
  return {
    source: 'fb',
    title: str(pick(r, ['marketplace_listing_title', 'listingTitle', 'custom_title', 'customTitle'])),
    priceCents: toCents(pick(r, ['listing_price.amount', 'listingPrice.amount', 'listing_price.formatted_amount', 'listingPrice.formatted_amount'])),
    url: canonicalUrl('fb', pick(r, ['listingUrl', 'itemUrl'])),
    seller: sellerText('FB Marketplace seller', where, miles),
    condition: mapCondition(r.condition),
    distanceMiles: miles ?? UNKNOWN_DISTANCE_MILES,
    checkout: 'seller_message',
  };
};

const normalizeCraigslist: Normalizer = (r, home) => {
  if (r.label != null && r.label !== 'post') return undefined;
  const miles = distance(home, r.latitude, r.longitude);
  return {
    source: 'craigslist',
    title: str(r.title),
    priceCents: toCents(r.price),
    url: canonicalUrl('craigslist', r.url),
    seller: sellerText('Craigslist seller', str(r.location, 60), miles),
    condition: mapCondition(r.condition),
    distanceMiles: miles ?? UNKNOWN_DISTANCE_MILES,
    checkout: 'seller_message',
  };
};

const normalizeEbay: Normalizer = r => {
  if (r.type != null && r.type !== 'product') return undefined;
  const lt = String(r.listingType ?? '').toLowerCase();
  if (lt.includes('auction') || Number(r.bidCount) > 0) return undefined; // active, but not a fixed price
  if (!isUsd(r.currency)) return undefined;
  // eBay handles can be personal accounts, so like FB sellers they aren't stored.
  const fb = str(r.sellerFeedbackPercent, 8);
  const ship = str(r.shippingCost, 30);
  return {
    source: 'ebay',
    title: str(r.title),
    priceCents: typeof r.price === 'number' ? toCents(r.price) : toCents(r.priceString),
    url: canonicalUrl('ebay', r.url),
    seller: ['eBay seller', feedbackText(fb), ship].filter(Boolean).join(', '),
    condition: mapCondition(r.condition),
    distanceMiles: -1,
    checkout: 'seller_message',
  };
};

// "0%" means no feedback yet, not a 0% rating.
function feedbackText(pct: string): string {
  if (!pct) return '';
  return Number.parseFloat(pct) > 0 ? `${pct.replace(/%?$/, '%')} positive` : 'new seller';
}

/** Rewrites any stored seller text that names a private person (older caches) to the anonymous form. */
export function scrubSeller(source: string, seller: string): string {
  let s = seller.replace(/\b0(\.0+)?% positive\b/, 'new seller');
  if (source === 'fb') s = s.replace(/^FB Marketplace: [^,]*/, 'FB Marketplace seller');
  if (source === 'ebay') s = s.replace(/^eBay: [^,]*/, 'eBay seller');
  return s;
}

function sellerText(who: string, where: string, miles: number | undefined): string {
  return [who, where, miles == null ? 'distance unknown' : ''].filter(Boolean).join(', ');
}

// ---------- actor table ----------

interface ActorSpec {
  actor: string;
  input: (q: string, n: number, city: { fb: string; craigslist: string }) => Raw;
  normalize: Normalizer;
  /** The actor's own minimum for maxTotalChargeUsd. */
  minChargeUsd: number;
}

export const ACTORS: Record<ApifySourceName, ActorSpec> = {
  fb: {
    actor: 'apify~facebook-marketplace-scraper',
    input: (q, n, city) => ({
      startUrls: [{ url: `https://www.facebook.com/marketplace/${encodeURIComponent(city.fb)}/search?query=${encodeURIComponent(q)}` }],
      resultsLimit: n,
    }),
    normalize: normalizeFb,
    minChargeUsd: 0.0062,
  },
  craigslist: {
    actor: 'ivanvs~craigslist-scraper-pay-per-result',
    input: (q, _n, city) => ({
      urls: [{ url: `https://${encodeURIComponent(city.craigslist)}.craigslist.org/search/sss?query=${encodeURIComponent(q)}` }],
      maxAge: 14,
    }),
    normalize: normalizeCraigslist,
    minChargeUsd: 0.1,
  },
  ebay: {
    actor: 'automation-lab~ebay-scraper',
    input: (q, n) => ({ searchQueries: [q], marketplace: 'US', listingType: 'buy_it_now', maxProductsPerSearch: n, maxSearchPages: 1, sort: 'best_match' }),
    normalize: normalizeEbay,
    minChargeUsd: 0,
  },
};

const isSource = (s: string): s is ApifySourceName => s in ACTORS;

/** Normalizes one actor's dataset items, dropping rows without a price, title or listing URL. */
export function normalizeRows(source: ApifySourceName, rows: unknown, home?: ApifyDealOptions['home']): RawDeal[] {
  if (!Array.isArray(rows)) return [];
  const out: RawDeal[] = [];
  for (const r of rows) {
    if (!r || typeof r !== 'object') continue;
    const d = ACTORS[source].normalize(r as Raw, home);
    if (d && d.title && d.url && d.priceCents > 0) out.push(d);
  }
  return out;
}

/** Dedupes by listing URL, then by same source + title + price (reposts). Keeps the first. */
export function dedupe<T extends { source: string; title: string; priceCents: number | bigint; url: string }>(rows: T[]): T[] {
  const seen = new Set<string>();
  return rows.filter(d => {
    const keys = [`u:${d.url}`, `t:${d.source}|${d.title.toLowerCase()}|${d.priceCents}`];
    if (keys.some(k => seen.has(k))) return false;
    keys.forEach(k => seen.add(k));
    return true;
  });
}

/** Search text for a shopping item: its name, sanitized and kept short. */
export function queryText(q: DealQuery): string {
  return sanitizeText(q.name, 60) || sanitizeText(q.category, 60);
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60) || 'item';

// ---------- the source ----------

export function createApifyDealSource(opts: ApifyDealOptions = {}): DealSource {
  // Craigslist is off by default (as in pricing, #6): its actor is slow and often blocked.
  const sources = (opts.sources?.length ? opts.sources : (['fb', 'ebay'] as ApifySourceName[])).filter(isSource);
  const perSource = Math.max(1, Math.min(opts.perSource ?? 6, 20));
  const maxUsd = opts.maxUsdPerRun ?? 0.1;
  const city = opts.city ?? { fb: 'sanfrancisco', craigslist: 'sfbay' };
  const cacheDir = opts.cacheDir ?? fileURLToPath(new URL('../../.cache/deals/', import.meta.url));
  const replayDir = opts.replayDir ?? opts.cacheDir ?? fileURLToPath(new URL('../../fixtures/', import.meta.url));
  const doFetch = opts.fetch ?? fetch;
  const now = opts.now ?? (() => new Date());
  let fallback = opts.fallback;
  let lastReplay = !opts.token;

  const cacheFile = (q: string, dir = cacheDir) => path.join(dir, `deals-live-${slug(q)}.json`);
  const spend = { file: opts.spendFile ?? config.apify.spendFile, cap: opts.maxUsdPerDay ?? config.apify.maxUsdPerDay };
  // The most a run can cost (Apify stops it there). This is what the daily cap books before the run.
  const runChargeUsd = (source: ApifySourceName) => Math.max(maxUsd, ACTORS[source].minChargeUsd);

  async function runActor(source: ApifySourceName, q: string): Promise<RawDeal[]> {
    const spec = ACTORS[source];
    const url = new URL(`https://api.apify.com/v2/acts/${spec.actor}/run-sync-get-dataset-items`);
    url.searchParams.set('maxItems', String(perSource));
    url.searchParams.set('maxTotalChargeUsd', String(runChargeUsd(source)));
    url.searchParams.set('timeout', '120');
    const res = await doFetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${opts.token}` },
      body: JSON.stringify(spec.input(q, perSource, city)),
      signal: AbortSignal.timeout(150_000),
    });
    if (!res.ok) throw new Error(`apify ${spec.actor}: HTTP ${res.status} ${sanitizeText(await res.text(), 200)}`);
    return normalizeRows(source, await res.json(), opts.home).slice(0, perSource);
  }

  function readCache(q: string): RawDeal[] {
    // Runtime cache first, then the replays committed to fixtures/ (never overwritten by live runs).
    const file = [cacheFile(q), cacheFile(q, replayDir)].find(f => existsSync(f));
    if (!file) return [];
    try {
      const parsed = JSON.parse(readFileSync(file, 'utf8')) as { rows?: unknown };
      const rows = Array.isArray(parsed.rows) ? (parsed.rows as RawDeal[]) : [];
      return rows.map(r => ({ ...r, seller: scrubSeller(String(r.source ?? ''), String(r.seller ?? '')) }));
    } catch {
      return [];
    }
  }

  function writeCache(q: string, rows: RawDeal[], errors: string[]): void {
    try {
      mkdirSync(cacheDir, { recursive: true });
      const body = {
        _note: 'Cached live Apify search (active listings) for the buy agent (#15). Trimmed to the fields we use. Rows read back from this file are labeled as a replay.',
        query: q,
        fetchedAt: now().toISOString(),
        actors: Object.fromEntries(sources.map(s => [s, ACTORS[s].actor])),
        errors,
        rows: rows.map(r => ({ ...r, seller: scrubSeller(r.source, r.seller) })),
      };
      writeFileSync(cacheFile(q), JSON.stringify(body, null, 2) + '\n');
    } catch {
      // Caching is best effort; a read-only checkout must not break live search.
    }
  }

  const toCands = (rows: RawDeal[], replay: boolean): DealCandidate[] =>
    dedupe(rows.map(r => toCandidate(r, replay)).filter((c): c is DealCandidate => !!c));

  return {
    name: `Apify live listings (${sources.join(', ')})`,
    /** Reflects the most recent search: true when it came from a cache or the curated fixtures. */
    get replay() {
      return lastReplay;
    },
    async search(dq, hooks) {
      const q = queryText(dq);
      fallback ??= fixtureDealSource();
      // Marketplace listings can't be paid through an API, so the matching sample retail rows (still
      // labeled "sample data") ride along: every item keeps at least one card-checkout option. So does
      // a planted demo scam for this item, if any (also "sample data"), so the fraud block shows live.
      const withRetail = async (found: DealCandidate[]) => [...found, ...(await fallback!.search(dq)).filter(c => c.checkout === 'visa' || c.planted)];
      if (q && opts.token) {
        // Daily Apify cap shared with pricing comps (#170, #185): each run books its maxTotalChargeUsd
        // before it starts. A run that would pass the cap is skipped, and if all are, this search
        // falls back exactly as with no token (cached replay, then sample data). Replays are free.
        const allowed = sources.filter(s => reserveApifySpend(runChargeUsd(s), spend));
        const skipped = sources.filter(s => !allowed.includes(s));
        if (skipped.length) {
          const spent = apifySpentToday(spend.file);
          const instead = allowed.length ? `searching only ${allowed.join(', ')} live` : 'using cached replays / sample deals instead of a live search';
          hooks?.onNotice?.({
            message: `Apify daily spend cap reached (~$${spent.usd.toFixed(2)} of $${spend.cap.toFixed(2)} today, ${spent.runs} runs): skipped the live ${skipped.join(', ')} search for "${q}", ${instead}. Raise APIFY_MAX_USD_PER_DAY to search live again.`,
            data: { apifyCap: true, refused: true, skipped, allowed, spentUsd: spent.usd, runs: spent.runs, capUsd: spend.cap, query: q },
          });
        }
        const settled = await Promise.allSettled(allowed.map(s => runActor(s, q)));
        const rows = dedupe(settled.flatMap(r => (r.status === 'fulfilled' ? r.value : [])));
        const errors = settled.flatMap(r => (r.status === 'rejected' ? [sanitizeText(String(r.reason), 300)] : []));
        if (rows.length) {
          writeCache(q, rows, errors);
          lastReplay = false;
          return withRetail(toCands(rows, false));
        }
      }
      const cached = q ? readCache(q) : [];
      lastReplay = true;
      if (cached.length) return withRetail(toCands(cached, true));
      return fallback.search(dq);
    },
  };
}

// ---------- selection ----------

/**
 * Picks the buy agent's deal source from env. DEALS_SOURCE=apify|fixtures, default apify. apify with
 * APIFY_TOKEN searches live; without one it replays committed live searches (fixtures/deals-live-*.json,
 * labeled "cached replay"), then the hand-made sample data (labeled "sample data").
 */
/**
 * True when the deal source chosen from this env can never search live (DEALS_SOURCE=fixtures, or
 * apify without APIFY_TOKEN), so every search is a replay or sample data. With a token, whether a
 * given search was live is only known after it runs (the daily cap or an empty result can fall back
 * to a replay), so read that from the returned candidates' `replay`, not from the source.
 */
export function dealSourceReplayOnly(env: Env = process.env): boolean {
  const mode = env.DEALS_SOURCE?.trim().toLowerCase() || 'apify';
  return mode !== 'apify' || !env.APIFY_TOKEN?.trim();
}

export function createDealSource(env: Env = process.env, overrides: Partial<ApifyDealOptions> = {}): DealSource {
  const token = env.APIFY_TOKEN?.trim() || undefined;
  // Default apify: live with a token, otherwise committed live replays, then the sample data.
  const mode = (env.DEALS_SOURCE?.trim().toLowerCase() || 'apify') as string;
  if (mode !== 'apify') return overrides.fallback ?? fixtureDealSource();
  const num = (k: string) => {
    const v = env[k]?.trim();
    return v ? Number(v) : NaN;
  };
  const lat = num('DEALS_HOME_LAT');
  const lng = num('DEALS_HOME_LNG');
  const sources = (env.DEALS_APIFY_SOURCES ?? '').split(',').map(s => s.trim().toLowerCase()).filter(isSource);
  return createApifyDealSource({
    token,
    sources: sources.length ? sources : undefined,
    perSource: Number.isFinite(num('DEALS_PER_SOURCE')) ? num('DEALS_PER_SOURCE') : undefined,
    maxUsdPerRun: Number.isFinite(num('APIFY_MAX_USD_PER_RUN')) ? num('APIFY_MAX_USD_PER_RUN') : undefined,
    city: { fb: env.MARKET_CITY_FB?.trim() || 'sanfrancisco', craigslist: env.MARKET_CITY_CRAIGSLIST?.trim() || 'sfbay' },
    home: Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : undefined,
    spendFile: env.APIFY_SPEND_FILE?.trim() || undefined,
    maxUsdPerDay: Number.isFinite(num('APIFY_MAX_USD_PER_DAY')) ? num('APIFY_MAX_USD_PER_DAY') : undefined,
    ...overrides,
  });
}
