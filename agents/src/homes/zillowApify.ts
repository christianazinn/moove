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
// Runs are cached (trimmed: facts + floor-plan image URLs, no agent or description text) in
// .cache/zillow/<zpid>.json, so the same link never pays twice; a cached hit is labeled a replay.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';
import type { EventKind } from '../events.js';
import { loadPhoto, type ImageInput } from '../integrations/photos.js';
import { cleanUntrusted } from '../untrusted.js';

type Log = (kind: EventKind, message: string, data?: unknown) => void;

export type ZillowFacts = {
  address: string | null;
  beds: number | null;
  baths: number | null;
  sqft: number | null;
  floorPlanImageUrls: string[];
};
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
  };
}

async function runActor(url: string, token: string, fetchImpl: typeof fetch): Promise<Record<string, any>> {
  const api = new URL(`https://api.apify.com/v2/acts/${config.apify.zillowActor}/run-sync-get-dataset-items`);
  api.searchParams.set('maxItems', '1');
  api.searchParams.set('maxTotalChargeUsd', String(config.apify.maxUsdPerRun));
  api.searchParams.set('timeout', '120');
  const rental = /\/(b|apartments)\//.test(url);
  const res = await fetchImpl(api, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ startUrls: [{ url }], propertyStatus: rental ? 'FOR_RENT' : 'FOR_SALE' }),
    signal: AbortSignal.timeout(150_000),
  });
  if (!res.ok) throw new Error(`apify ${config.apify.zillowActor}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  const rows = (await res.json()) as unknown;
  const row = Array.isArray(rows) ? rows.find(r => r && typeof r === 'object' && !(r as any).error) : undefined;
  if (!row) throw new Error('the actor returned no listing');
  return row as Record<string, any>;
}

/** Runs (or replays) the Zillow actor for one listing and loads its floor-plan images. */
export async function scrapeZillow(
  listingUrl: string,
  opts: { token: string; log: Log; fetch?: typeof fetch; loadImage?: (url: string) => Promise<ImageInput>; cacheDir?: string }
): Promise<ScrapeResult> {
  const url = zillowRunUrl(listingUrl);
  if (!url) throw new Error('not a zillow.com link');
  const { log } = opts;
  const file = path.join(opts.cacheDir ?? CACHE_DIR, `${cacheKey(url)}.json`);
  const notes: string[] = [];
  let facts: ZillowFacts;
  let replayed = false;
  if (existsSync(file)) {
    const cached = JSON.parse(readFileSync(file, 'utf8')) as ZillowFacts & { fetchedAt?: string };
    facts = cached;
    replayed = true;
    notes.push(`Replayed a cached Apify Zillow result${cached.fetchedAt ? ` from ${cached.fetchedAt.slice(0, 10)}` : ''}.`);
    log('tool_call', `[REPLAYED] Apify Zillow scraper result for ${url}`, { actor: config.apify.zillowActor });
  } else {
    log('tool_call', `Running Apify ${config.apify.zillowActor} for ${url} (cap $${config.apify.maxUsdPerRun})`, { actor: config.apify.zillowActor, maxUsd: config.apify.maxUsdPerRun });
    facts = extractZillowFacts(await runActor(url, opts.token, opts.fetch ?? fetch));
    try {
      mkdirSync(path.dirname(file), { recursive: true });
      writeFileSync(file, JSON.stringify({ ...facts, fetchedAt: new Date().toISOString() }, null, 2));
    } catch (err) {
      console.warn(`[homes] couldn't cache the Zillow result: ${String(err)}`);
    }
  }
  log('result', `Zillow scraper: ${[facts.address, facts.beds != null && `${facts.beds} bd`, facts.baths != null && `${facts.baths} ba`, facts.sqft != null && `${facts.sqft} sqft`].filter(Boolean).join(', ') || 'no facts'}; ${facts.floorPlanImageUrls.length} floor-plan image(s)`, { ...facts, replayed });

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
    notes.push('The Zillow listing has no floor-plan image.');
  }
  return { ...facts, floorPlanImages, notes, replayed };
}
