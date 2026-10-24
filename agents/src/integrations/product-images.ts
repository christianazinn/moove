// Web images of a specific product, as extra candidates for SAM 3D (#84). Two sources:
// - listing photos in the cached comps for the same query (free; only comps fetched since the
//   Apify normalizer started keeping `imageUrl` have them), and
// - a Google Images search on Apify (`hooli~google-images-scraper`, pay per image, about
//   $0.0035 each on the free tier), capped by result count and maxTotalChargeUsd, and cached in
//   fixtures/product-images/<slug>.json like comps. A cached hit is replayed for free.
// Everything here is third-party data: titles go to Claude only through untrusted.ts, and image
// URLs are fetched only by loadWebImage (https, public addresses, no redirects, image bytes only).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { config } from '../config.js';
import { sniffType } from '../imagemeta.js';
import { cachedComps, compsSlug } from './apify.js';
import { assertPublicHost, isBlockedAddress, type ImageInput, type ImageMediaType, PhotoUrlError } from './photos.js';
import { isIP } from 'node:net';

export const IMAGE_SEARCH_ACTOR = 'hooli~google-images-scraper';
/** Per-image price on Apify's free tier (Oct 2026). Used for the event log and the spend cap. */
export const IMAGE_SEARCH_USD_PER_IMAGE = 0.0035;

export interface WebImage {
  url: string;
  /** Alt text / listing title (untrusted). */
  title: string;
  /** Page the image is on (untrusted, for the event log only). */
  origin: string;
  source: 'google' | 'ebay' | 'fb' | 'craigslist';
  width?: number;
  height?: number;
}

export type ImageSearchResult = { images: WebImage[]; replayed: boolean; costUsd: number };

export const imagesCacheFile = (q: string) => path.join('fixtures', 'product-images', `${compsSlug(q)}.json`);

const httpsUrl = (v: unknown): string | undefined => {
  if (typeof v !== 'string' || v.length > 2048) return undefined;
  try {
    const u = new URL(v);
    return u.protocol === 'https:' && !u.username && !u.password ? u.toString() : undefined;
  } catch {
    return undefined;
  }
};

/** Normalizes Google Images actor rows: https image URLs only, at most `max`. */
export function normalizeImageRows(rows: unknown[], max: number): WebImage[] {
  const out: WebImage[] = [];
  for (const r of rows as Record<string, unknown>[]) {
    const url = httpsUrl(r?.imageUrl) ?? httpsUrl(r?.contentUrl);
    if (!url || out.some(o => o.url === url)) continue;
    const w = Number(r.imageWidth);
    const h = Number(r.imageHeight);
    out.push({
      url,
      title: String(r.title ?? ''),
      origin: String(r.origin ?? ''),
      source: 'google',
      ...(w > 0 && h > 0 ? { width: w, height: h } : {}),
    });
    if (out.length >= max) break;
  }
  return out;
}

/** Listing photos from the comps already cached for this query. Never calls Apify. */
export function compImages(query: string, max: number): WebImage[] {
  const comps = cachedComps(query) ?? [];
  const out: WebImage[] = [];
  for (const c of comps) {
    const url = httpsUrl(c.imageUrl);
    if (!url || out.some(o => o.url === url)) continue;
    out.push({ url, title: c.title, origin: c.url, source: (['ebay', 'fb', 'craigslist'].includes(c.source) ? c.source : 'ebay') as WebImage['source'] });
    if (out.length >= max) break;
  }
  return out;
}

type Fetch = typeof fetch;

/** Google Images search for a product, cached per query. No APIFY_TOKEN and no cache: empty. */
export async function searchProductImages(
  query: string,
  opts: { max?: number; maxUsd?: number; token?: string; fetch?: Fetch; cacheFile?: string } = {}
): Promise<ImageSearchResult> {
  const file = opts.cacheFile ?? imagesCacheFile(query);
  if (existsSync(file)) return { images: JSON.parse(readFileSync(file, 'utf8')) as WebImage[], replayed: true, costUsd: 0 };
  const token = opts.token ?? config.apify.token;
  if (!token) return { images: [], replayed: false, costUsd: 0 };
  const max = opts.max ?? config.sam3d.webImagesMax;
  const maxUsd = opts.maxUsd ?? config.sam3d.imageSearchMaxUsd;
  const url = new URL(`https://api.apify.com/v2/acts/${IMAGE_SEARCH_ACTOR}/run-sync-get-dataset-items`);
  url.searchParams.set('maxItems', String(max));
  url.searchParams.set('maxTotalChargeUsd', String(maxUsd));
  url.searchParams.set('timeout', '90');
  const res = await (opts.fetch ?? fetch)(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    // A product shot on a plain background is what single-image 3D wants.
    body: JSON.stringify({ queries: [`${query} product photo`], maxResultsPerQuery: max }),
    signal: AbortSignal.timeout(110_000),
  });
  if (!res.ok) throw new Error(`apify ${IMAGE_SEARCH_ACTOR}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  const rows = (await res.json()) as unknown[];
  const images = normalizeImageRows(Array.isArray(rows) ? rows : [], max);
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, JSON.stringify(images, null, 2));
  return { images, replayed: false, costUsd: Math.min(maxUsd, rows.length * IMAGE_SEARCH_USD_PER_IMAGE) };
}

/** Largest web image we download (Claude's per-image limit is 5 MB). */
export const MAX_WEB_IMAGE_BYTES = 4.5 * 1024 * 1024;
const MEDIA: readonly ImageMediaType[] = ['image/jpeg', 'image/png', 'image/webp'];

type Lookup = (host: string) => Promise<{ address: string }[]>;

/** Downloads a web product image without SSRF: https only, every resolved address public, no
 *  redirects, `PRODUCT_IMAGE_HOSTS` (if set) as an allowlist, a size cap, a timeout, and the bytes
 *  must really be a JPEG/PNG/WebP. Returns the raw bytes too (for the pixel size). */
export async function loadWebImage(
  raw: string,
  deps: { fetch?: (url: URL, init: RequestInit) => Promise<Response>; lookup?: Lookup; allowedHosts?: readonly string[] } = {}
): Promise<ImageInput & { bytes: Buffer }> {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new PhotoUrlError('not a valid URL');
  }
  if (u.protocol !== 'https:') throw new PhotoUrlError('only https web images are fetched');
  if (u.username || u.password) throw new PhotoUrlError('credentials in image URLs are not allowed');
  const host = u.hostname.toLowerCase();
  const allowed = deps.allowedHosts ?? config.sam3d.productImageHosts;
  if (allowed.length && !allowed.includes(host)) throw new PhotoUrlError(`host ${host} is not in PRODUCT_IMAGE_HOSTS`);
  if (isIP(host.replace(/^\[|\]$/g, '')) !== 0 && isBlockedAddress(host)) throw new PhotoUrlError(`host ${host} is a private address`);
  await assertPublicHost(u.hostname, deps.lookup);
  const res = await (deps.fetch ?? fetch)(u, { redirect: 'error', signal: AbortSignal.timeout(15_000) });
  if (!res.ok) throw new Error(`fetch ${host}: ${res.status}`);
  if (Number(res.headers.get('content-length') ?? '0') > MAX_WEB_IMAGE_BYTES) throw new PhotoUrlError('image is too large');
  const bytes = Buffer.from(await res.arrayBuffer());
  if (bytes.length > MAX_WEB_IMAGE_BYTES) throw new PhotoUrlError('image is too large');
  const mediaType = MEDIA.find(t => t === sniffType(bytes));
  if (!mediaType) throw new PhotoUrlError('not a JPEG, PNG or WebP image');
  return { mediaType, data: bytes.toString('base64'), bytes };
}
