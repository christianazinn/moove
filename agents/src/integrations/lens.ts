// Reverse image search (#292): Google Lens on an item's own photo, through the Apify actor
// `zen-studio~google-lens-visual-search` (one image per run, about $0.008 per search + $0.01 per
// run start, Oct 2026). Google fetches the photo itself, so only public https photo URLs work.
// Results are cached in fixtures/lens/<hash>.json and replayed for free. Every title is
// third-party data: it reaches Claude only through untrusted.ts.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { isIP } from 'node:net';
import path from 'node:path';
import { config } from '../config.js';
import { reserveApifySpend } from './apify.js';
import { isBlockedAddress } from './photos.js';

export const LENS_ACTOR = 'zen-studio~google-lens-visual-search';

export interface LensMatch {
  /** Page title (untrusted). */
  title: string;
  /** Site name, e.g. "eBay", "Best Buy" (untrusted). */
  source: string;
  /** Price text when the page is a product listing, e.g. "$649.99" (untrusted), else "". */
  price: string;
}

export type LensResult = { matches: LensMatch[]; replayed: boolean; costUsd: number; refused?: boolean };

type Fetch = typeof fetch;

export const lensCacheFile = (photoUrl: string) =>
  path.join(config.lens.cacheDir, `${createHash('sha256').update(photoUrl).digest('hex').slice(0, 24)}.json`);

/** Google has to fetch the photo: https, no credentials, and not a LAN / loopback literal. */
export function isLensablePhoto(raw: string): boolean {
  try {
    const u = new URL(raw);
    if (u.protocol !== 'https:' || u.username || u.password) return false;
    const host = u.hostname.replace(/^\[|\]$/g, '');
    if (host === 'localhost' || host.endsWith('.local')) return false;
    return !(isIP(host) && isBlockedAddress(host));
  } catch {
    return false;
  }
}

const str = (v: unknown, max: number) => (typeof v === 'string' ? v.slice(0, max) : '');

/** Visual matches from the actor's dataset rows, without duplicates or empty titles, at most `max`. */
export function normalizeLensRows(rows: unknown[], max: number): LensMatch[] {
  const out: LensMatch[] = [];
  for (const row of rows as Record<string, unknown>[]) {
    const matches = Array.isArray(row?.visualMatches) ? (row.visualMatches as Record<string, unknown>[]) : [];
    for (const m of matches) {
      const title = str(m?.title, 300).trim();
      if (!title || out.some(o => o.title === title)) continue;
      out.push({ title, source: str(m?.source, 80).trim(), price: str(m?.price, 40).trim() });
      if (out.length >= max) return out;
    }
  }
  return out;
}

/**
 * Lens matches for one photo. A cached search is free; a live one books its cap
 * (`LENS_MAX_USD_PER_SEARCH`) against the daily Apify total first and is refused past it.
 */
export async function lensSearch(
  photoUrl: string,
  opts: { token?: string; fetch?: Fetch; cacheFile?: string; max?: number; maxUsd?: number } = {}
): Promise<LensResult> {
  const file = opts.cacheFile ?? lensCacheFile(photoUrl);
  if (existsSync(file)) return { matches: JSON.parse(readFileSync(file, 'utf8')) as LensMatch[], replayed: true, costUsd: 0 };
  const token = opts.token ?? config.apify.token;
  if (!token) return { matches: [], replayed: false, costUsd: 0 };
  const max = opts.max ?? config.lens.maxMatches;
  const maxUsd = opts.maxUsd ?? config.lens.maxUsdPerSearch;
  if (!reserveApifySpend(maxUsd)) return { matches: [], replayed: false, costUsd: 0, refused: true };
  const url = new URL(`https://api.apify.com/v2/acts/${LENS_ACTOR}/run-sync-get-dataset-items`);
  url.searchParams.set('maxTotalChargeUsd', String(maxUsd));
  url.searchParams.set('timeout', '90');
  const res = await (opts.fetch ?? fetch)(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
    body: JSON.stringify({ imageUrl: photoUrl, searchType: 'visual_matches', maxResults: max, countryCode: 'US' }),
    signal: AbortSignal.timeout(110_000),
  });
  if (!res.ok) throw new Error(`apify ${LENS_ACTOR}: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
  const rows = (await res.json()) as unknown[];
  const errored = Array.isArray(rows) && rows.some(r => typeof (r as Record<string, unknown>)?.error === 'string');
  const matches = normalizeLensRows(Array.isArray(rows) ? rows : [], max);
  // An unreachable photo comes back as an `error` row: don't cache it, a later photo URL may work.
  if (!errored) {
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(matches, null, 2));
  }
  return { matches, replayed: false, costUsd: maxUsd };
}
