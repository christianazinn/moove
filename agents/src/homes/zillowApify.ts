// OPTIONAL Zillow scraper path for POST /homes/import (#89). Scraping Zillow is against its terms, so
// this runs only when the worker has APIFY_TOKEN *and* the request says useScraper: true, and the
// response notes say "Fetched with an Apify Zillow scraper". Never on by default.
//
// Actor (checked against the Apify API on 2026-10-23): maxcopell~zillow-detail-scraper ("Zillow
// Detail Scraper", latest build 0.0.150 of 2026-10-16, not deprecated). Input {startUrls: [{url}],
// propertyStatus}; pay per result, ~$0.0036 on the free tier. Each run is capped by maxItems=1,
// maxTotalChargeUsd (APIFY_MAX_USD_PER_RUN) and a 120 s timeout. Override with APIFY_ZILLOW_ACTOR.
// Fields used (curated output schema): listingAddress.full, bedrooms, bathrooms, livingArea, and
// photos whose caption (or field name) says floor plan. Only photos.zillowstatic.com images are loaded.
//
// No photo captioned as a floor plan? floorplanFinder.ts classifies the other listing photos in one
// MODEL_FAST call and passes any floor plans it finds on like captioned ones.
//
// Runs are cached (trimmed: facts, floor-plan and listing photo URLs + captions, no agent or
// description text) in .cache/zillow/<zpid>.json, so the same link never pays twice; a cached hit is
// labeled a replay. The photo classification's outcome is written into the same entry.
import { apifyFetch } from '../integrations/apify-runs.js';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';
import type { EventKind } from '../events.js';
import { loadPhoto, type ImageInput } from '../integrations/photos.js';
import { cleanUntrusted } from '../untrusted.js';
import { OVER_CAP_NOTE, OverCapError, takePaidCall } from './budget.js';
import { findFloorPlanInPhotos, type ListingPhoto, type PhotoPlanScan } from './floorplanFinder.js';

type Log = (kind: EventKind, message: string, data?: unknown) => void;

export type ZillowFacts = {
  address: string | null;
  beds: number | null;
  baths: number | null;
  sqft: number | null;
  floorPlanImageUrls: string[];
  /** Every listing photo in order (zillowstatic only), for the floor-plan finder. Older caches lack it. */
  listingPhotos?: ListingPhoto[];
};
type CacheEntry = ZillowFacts & { fetchedAt?: string; photoPlanScan?: PhotoPlanScan };
export type ScrapeResult = ZillowFacts & { floorPlanImages: ImageInput[]; notes: string[]; replayed: boolean };

const IMAGE_HOST = 'photos.zillowstatic.com';
const FLOOR_PLAN_RE = /floor\s*-?\s*plan/i;
const CACHE_DIR = path.join('.cache', 'zillow');

/** Only https://www.zillow.com/... links go to the actor (it is paid, and points at Zillow only). */
export function zillowRunUrl(listingUrl: string): string | null {
  try {
    const u = new URL(listingUrl);
    const host = u.hostname.toLowerCase();
    if (u.protocol !== 'https:' || !(host === 'zillow.com' || host === 'www.zillow.com')) return null;
    return `https://www.zillow.com${u.pathname}`;
  } catch {
    return null;
  }
}

const cacheKey = (url: string) =>
  url.match(/(\d+)_zpid/)?.[1] ?? url.replace(/^https:\/\/www\.zillow\.com\//, '').replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').slice(0, 100);

const num = (v: unknown, max: number): number | null => {
  const n = typeof v === 'string' ? parseFloat(v.replace(/,/g, '')) : typeof v === 'number' ? v : NaN;
  return Number.isFinite(n) && n >= 0 && n <= max ? n : null;
};

function zillowImage(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  try {
    const u = new URL(v);
    return u.protocol === 'https:' && u.hostname === IMAGE_HOST ? u.toString() : null;
  } catch {
    return null;
  }
}

/** Floor-plan image URLs anywhere in a row: photos captioned "floor plan", or URLs under a floorPlan* key. */
export function findFloorPlanImages(row: unknown, max = 4): string[] {
  const found = new Set<string>();
  const walk = (v: unknown, keyPath: string, depth: number) => {
    if (found.size >= max || depth > 6 || v == null) return;
    if (Array.isArray(v)) return v.slice(0, 200).forEach(x => walk(x, keyPath, depth + 1));
    if (typeof v !== 'object') {
      const url = FLOOR_PLAN_RE.test(keyPath) ? zillowImage(v) : null;
      if (url) found.add(url);
      return;
    }
    const o = v as Record<string, unknown>;
    const caption = [o.caption, o.description, o.title, o.label].find(x => typeof x === 'string') as string | undefined;
    if (caption && FLOOR_PLAN_RE.test(caption)) {
      const url = zillowImage(o.url) ?? zillowImage((o.hiRes as unknown) ?? null);
      if (url) found.add(url);
    }
    for (const [k, x] of Object.entries(o)) walk(x, `${keyPath}.${k}`, depth + 1);
  };
  walk(row, '', 0);
  return [...found].slice(0, max);
}

const MAX_LISTING_PHOTOS = 200;
const SKIP_PHOTO_KEYS = /agent|broker|attribution|logo|avatar|profile|floor\s*-?\s*plan|nearby|similar|comparable/i;

/** The largest variant, and the largest one at most 640 px wide, from a Zillow mixedSources object. */
function variants(mixed: unknown): { large: string | null; small: string | null } {
  const list: { url: string; width: number }[] = [];
  if (mixed && typeof mixed === 'object') {
    for (const arr of Object.values(mixed as Record<string, unknown>)) {
      if (!Array.isArray(arr)) continue;
      for (const v of arr.slice(0, 20)) {
        const url = zillowImage(v?.url);
        const width = typeof v?.width === 'number' ? v.width : NaN;
        if (url && Number.isFinite(width)) list.push({ url, width });
      }
    }
  }
  if (!list.length) return { large: null, small: null };
  list.sort((a, b) => a.width - b.width);
  const small = [...list].reverse().find(v => v.width <= 640) ?? null;
  return { large: list[list.length - 1].url, small: small?.url ?? null };
}

/**
 * The listing's photos, in listing order: objects with a zillowstatic url / hiRes / mixedSources
 * (and their caption), or bare zillowstatic URL strings in a photo-ish array. Agent logos, nearby
 * homes and the floor-plan fields are skipped. Captions are scraped text, so they are cleaned.
 */
export function extractListingPhotos(row: unknown): ListingPhoto[] {
  const out: ListingPhoto[] = [];
  const seen = new Set<string>();
  const add = (url: string | null, thumb: string | null, caption: unknown) => {
    if (!url || seen.has(url) || out.length >= MAX_LISTING_PHOTOS) return;
    seen.add(url);
    const c = typeof caption === 'string' ? cleanUntrusted(caption, 120) : '';
    out.push({ url, thumb: thumb && thumb !== url ? thumb : null, caption: c || null });
  };
  const walk = (v: unknown, key: string, depth: number) => {
    if (out.length >= MAX_LISTING_PHOTOS || depth > 6 || v == null) return;
    if (Array.isArray(v)) {
      for (const x of v.slice(0, MAX_LISTING_PHOTOS)) {
        if (typeof x === 'string') {
          if (/photo|image|picture/i.test(key)) add(zillowImage(x), null, null);
        } else walk(x, key, depth + 1);
      }
      return;
    }
    if (typeof v !== 'object') return;
    const o = v as Record<string, unknown>;
    const caption = [o.caption, o.description, o.title, o.label].find(x => typeof x === 'string');
    const mixed = variants(o.mixedSources);
    const url = zillowImage(o.hiRes) ?? mixed.large ?? zillowImage(o.url);
    if (url) return add(url, mixed.small, caption);
    for (const [k, x] of Object.entries(o)) if (!SKIP_PHOTO_KEYS.test(k)) walk(x, k, depth + 1);
  };
  walk(row, '', 0);
  return out;
}

/** One actor row -> the facts we use. Everything is scraped (untrusted) and cleaned. */
export function extractZillowFacts(row: Record<string, any>): ZillowFacts {
  const la = row.listingAddress ?? {};
  const raw = row.address ?? {};
  const full =
    (typeof la.full === 'string' && la.full) ||
    [raw.streetAddress, raw.city, [raw.state, raw.zipcode].filter(Boolean).join(' ')].filter(x => typeof x === 'string' && x).join(', ');
  return {
    address: full ? cleanUntrusted(full, 160) || null : null,
    beds: num(row.bedrooms ?? row.beds, 50),
    baths: num(row.bathrooms ?? row.baths, 50),
    sqft: num(row.livingArea ?? row.livingAreaValue, 100_000),
    floorPlanImageUrls: findFloorPlanImages(row),
    listingPhotos: extractListingPhotos(row),
  };
}

async function runActor(url: string, token: string, fetchImpl: typeof fetch): Promise<Record<string, any>> {
  const api = new URL(`https://api.apify.com/v2/acts/${config.apify.zillowActor}/run-sync-get-dataset-items`);
  api.searchParams.set('maxItems', '1');
  api.searchParams.set('maxTotalChargeUsd', String(config.apify.maxUsdPerRun));
  api.searchParams.set('timeout', '120');
  const rental = /\/(b|apartments)\//.test(url);
  const res = await apifyFetch(api, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ startUrls: [{ url }], propertyStatus: rental ? 'FOR_RENT' : 'FOR_SALE' }),
    signal: AbortSignal.timeout(150_000),
  }, fetchImpl);
  if (!res.ok) throw new Error(`apify ${config.apify.zillowActor}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  const rows = (await res.json()) as unknown;
  const row = Array.isArray(rows) ? rows.find(r => r && typeof r === 'object' && !(r as any).error) : undefined;
  if (!row) throw new Error('the actor returned no listing');
  return row as Record<string, any>;
}

type ScrapeOpts = {
  token: string;
  log: Log;
  fetch?: typeof fetch;
  loadImage?: (url: string) => Promise<ImageInput>;
  cacheDir?: string;
  classify?: Parameters<typeof findFloorPlanInPhotos>[1]['classify'];
};

// The same listing imported twice at once (a double tap, a retry) shares one paid run: the cache is
// only written when a run finishes, up to 150 s later.
const inFlight = new Map<string, Promise<ScrapeResult>>();

/** Runs (or replays) the Zillow actor for one listing and loads its floor-plan images. */
export async function scrapeZillow(listingUrl: string, opts: ScrapeOpts): Promise<ScrapeResult> {
  const url = zillowRunUrl(listingUrl);
  if (!url) throw new Error('not a zillow.com link');
  const file = path.join(opts.cacheDir ?? CACHE_DIR, `${cacheKey(url)}.json`);
  const running = inFlight.get(file);
  if (running) return running;
  const p = scrapeOnce(url, file, opts).finally(() => inFlight.delete(file));
  inFlight.set(file, p);
  return p;
}

async function scrapeOnce(url: string, file: string, opts: ScrapeOpts): Promise<ScrapeResult> {
  const { log } = opts;
  const notes: string[] = [];
  let facts: ZillowFacts;
  let cachedScan: PhotoPlanScan | undefined;
  let replayed = false;
  if (existsSync(file)) {
    const cached = JSON.parse(readFileSync(file, 'utf8')) as CacheEntry;
    cachedScan = cached.photoPlanScan;
    facts = cached;
    replayed = true;
    notes.push(`Replayed a cached Apify Zillow result${cached.fetchedAt ? ` from ${cached.fetchedAt.slice(0, 10)}` : ''}.`);
    log('tool_call', `[REPLAYED] Apify Zillow scraper result for ${url}`, { actor: config.apify.zillowActor });
  } else {
    if (!takePaidCall()) throw new Error(OVER_CAP_NOTE);
    log('tool_call', `Running Apify ${config.apify.zillowActor} for ${url} (cap $${config.apify.maxUsdPerRun})`, { actor: config.apify.zillowActor, maxUsd: config.apify.maxUsdPerRun, paid: true });
    facts = extractZillowFacts(await runActor(url, opts.token, opts.fetch ?? fetch));
    writeCache(file, { ...facts, fetchedAt: new Date().toISOString() });
  }
  const { listingPhotos = [], ...shown } = facts;
  log('result', `Zillow scraper: ${[facts.address, facts.beds != null && `${facts.beds} bd`, facts.baths != null && `${facts.baths} ba`, facts.sqft != null && `${facts.sqft} sqft`].filter(Boolean).join(', ') || 'no facts'}; ${facts.floorPlanImageUrls.length} floor-plan image(s), ${listingPhotos.length} photo(s)`, { ...shown, photos: listingPhotos.length, replayed });

  // Floor-plan images: zillowstatic only, through the same SSRF-safe loader as item photos.
  const load =
    opts.loadImage ??
    ((u: string) => loadPhoto(u, { publicUploadBaseUrl: config.publicUploadBaseUrl, uploadDir: config.uploadDir, allowedHosts: [IMAGE_HOST] }));
  const loaded = await Promise.allSettled(facts.floorPlanImageUrls.slice(0, 4).map(load));
  const floorPlanImages = loaded.flatMap(r => (r.status === 'fulfilled' ? [r.value] : []));
  if (facts.floorPlanImageUrls.length && !floorPlanImages.length) {
    log('error', "Zillow floor-plan images couldn't be loaded");
    notes.push("The listing's floor-plan images couldn't be loaded.");
  } else if (!facts.floorPlanImageUrls.length) {
    // Nothing captioned as a floor plan: look for one among the listing photos.
    const found = await photoFloorPlans(listingPhotos, cachedScan, { log, load, classify: opts.classify });
    floorPlanImages.push(...found.images);
    notes.push(found.note);
    if (found.scan) {
      try {
        const entry = JSON.parse(readFileSync(file, 'utf8')) as CacheEntry;
        writeCache(file, { ...entry, photoPlanScan: found.scan });
      } catch (err) {
        console.warn(`[homes] couldn't cache the floor-plan photo scan: ${String(err)}`);
      }
    }
  }
  return { ...facts, floorPlanImages, notes, replayed };
}

function writeCache(file: string, entry: CacheEntry): void {
  try {
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(entry, null, 2));
  } catch (err) {
    console.warn(`[homes] couldn't cache the Zillow result: ${String(err)}`);
  }
}

const NO_PLAN_NOTE = 'The Zillow listing has no floor-plan image.';

/**
 * Floor plans among the listing photos (one MODEL_FAST call, or the cached outcome). Never throws:
 * any failure means no images, and the app estimates the plan. `scan` is set only when there is a
 * fresh outcome to cache.
 */
async function photoFloorPlans(
  photos: ListingPhoto[],
  cached: PhotoPlanScan | undefined,
  deps: { log: Log; load: (url: string) => Promise<ImageInput>; classify?: Parameters<typeof findFloorPlanInPhotos>[1]['classify'] }
): Promise<{ images: ImageInput[]; note: string; scan?: PhotoPlanScan }> {
  const { log, load } = deps;
  if (!photos.length) return { images: [], note: NO_PLAN_NOTE };
  const found = (n: number) => `The floor plan was found among the listing photos (${n} image${n === 1 ? '' : 's'}).`;
  const none = (checked: number) => `${NO_PLAN_NOTE} No floor plan was found among ${checked} listing photo${checked === 1 ? '' : 's'}.`;
  const summary = (scan: PhotoPlanScan) => ({ checked: scan.checked, picked: scan.picked.map(p => ({ photoIndex: p.photoIndex, confidence: p.confidence })) });

  if (cached) {
    const settled = await Promise.allSettled(cached.picked.map(p => load(p.url).catch(() => (p.thumb ? load(p.thumb) : Promise.reject(new Error('unloadable'))))));
    const images = settled.flatMap(r => (r.status === 'fulfilled' ? [r.value] : []));
    log('result', `[REPLAYED] ${images.length ? `Found ${images.length} floor plan${images.length === 1 ? '' : 's'} in the listing photos` : 'No floor plan in the listing photos; estimating from beds/baths/sqft'}`, { ...summary(cached), replayed: true });
    return { images, note: images.length ? found(images.length) : none(cached.checked) };
  }

  log('plan', `Looking for a floor plan among ${photos.length} listing photos`, { photos: photos.length });
  try {
    const r = await findFloorPlanInPhotos(photos, { log, loadImage: load, classify: deps.classify });
    const n = r.images.length;
    log('result', n ? `Found ${n} floor plan${n === 1 ? '' : 's'} in the listing photos` : 'No floor plan in the listing photos; estimating from beds/baths/sqft', summary(r.scan));
    return { images: r.images, note: n ? found(n) : none(r.scan.checked), scan: r.scan };
  } catch (err) {
    // The budget slot is taken inside findFloorPlanInPhotos (a recorded LLM_REPLAY answer takes none).
    if (err instanceof OverCapError) {
      log('error', OVER_CAP_NOTE);
      return { images: [], note: `${NO_PLAN_NOTE} ${OVER_CAP_NOTE}` };
    }
    log('error', `Floor-plan search in the listing photos failed: ${(err instanceof Error ? err.message : String(err)).slice(0, 200)}`);
    return { images: [], note: `${NO_PLAN_NOTE} Checking the listing photos for one failed.` };
  }
}
