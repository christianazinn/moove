// OPTIONAL listed rates for POST /moves/quotes (APIFY_MOVERS=1, off by default): local movers' own
// advertised hourly rates from Craigslist's "labor & moving" services section, scraped with the
// Craigslist actor the buy agent already uses (ivanvs~craigslist-scraper-pay-per-result, see
// deals-apify.ts). Each run books its maxTotalChargeUsd into the shared daily Apify total first
// (reserveApifySpend, APIFY_MAX_USD_PER_DAY); over the cap it's skipped. Runs are cached in
// .cache/movers/ and replayed (labeled) from there or from committed fixtures/movers-live-<city>.json.
//
// Ad titles are untrusted text: they're cleaned, cut short, and only ever shown as data. A rate is
// taken only from a title that says "$NN/hr" (or "per hour"); the price shown is that advertised
// rate times our estimated hours, so it's still labeled an estimate, with the ad's URL as the source.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../config.js';
import { apifySpentToday, reserveApifySpend } from '../integrations/apify.js';
import { sanitizeText } from '../integrations/deals.js';
import { roundHigh, roundLow, type MoverQuote, type QuoteInput } from './rates.js';

export const MOVERS_ACTOR = 'ivanvs~craigslist-scraper-pay-per-result';
/** The actor's own minimum max charge. */
const MIN_CHARGE_USD = 0.1;

export interface ListedAd {
  title: string;
  url: string;
  /** Advertised rate for the ad's crew, in cents an hour. */
  rateCents: number;
  /** Crew size the ad names ("2 movers"), or null. */
  crew: number | null;
}

export interface ListedRatesResult {
  ads: ListedAd[];
  replayed: boolean;
  /** Why nothing ran live (cap, no token, error), for the agent event. */
  notice?: string;
  capped?: boolean;
}

type Fetch = typeof fetch;
export interface ListedRatesOptions {
  token?: string;
  city?: string;
  maxAds?: number;
  maxUsdPerRun?: number;
  fetch?: Fetch;
  cacheDir?: string;
  replayDir?: string;
  spendFile?: string;
  maxUsdPerDay?: number;
  now?: () => Date;
}

/** "$65/hr", "$120 per hour", "$90/hour" -> cents; "2 movers"/"two men" -> crew. Sane rates only. */
export function parseRate(title: string): { rateCents: number; crew: number | null } | null {
  const m = title.match(/\$\s?(\d{2,3})(?:\.\d{2})?\s*(?:\/|per|an|a)\s*(?:hr|hour|h)\b/i);
  if (!m) return null;
  const rate = Number(m[1]);
  if (!(rate >= 40 && rate <= 400)) return null;
  const words: Record<string, number> = { two: 2, three: 3, four: 4 };
  const c = title.match(/\b(\d|two|three|four)\s*(?:movers|men|guys|helpers|man crew|person crew)\b/i);
  const crew = c ? Number(c[1]) || words[c[1].toLowerCase()] || null : null;
  return { rateCents: rate * 100, crew: crew && crew >= 1 && crew <= 6 ? crew : null };
}

function canonicalCraigslist(u: unknown): string {
  try {
    const url = new URL(String(u));
    const host = url.hostname.toLowerCase();
    return url.protocol === 'https:' || url.protocol === 'http:'
      ? /(^|\.)craigslist\.org$/.test(host) && /\.html$/.test(url.pathname) ? `https://${host}${url.pathname}` : ''
      : '';
  } catch {
    return '';
  }
}

/** Ads with a parseable hourly rate, deduped by URL. */
export function adsFromRows(rows: unknown): ListedAd[] {
  if (!Array.isArray(rows)) return [];
  const seen = new Set<string>();
  const out: ListedAd[] = [];
  for (const r of rows) {
    if (!r || typeof r !== 'object') continue;
    const row = r as Record<string, unknown>;
    if (row.label != null && row.label !== 'post') continue;
    const title = sanitizeText(row.title, 80);
    const url = canonicalCraigslist(row.url);
    const rate = parseRate(title);
    if (!title || !url || !rate || seen.has(url)) continue;
    seen.add(url);
    out.push({ title, url, ...rate });
  }
  return out;
}

export async function findListedRates(opts: ListedRatesOptions = {}): Promise<ListedRatesResult> {
  const city = (opts.city ?? config.moves.craigslistCity).replace(/[^a-z0-9]/gi, '').toLowerCase() || 'sfbay';
  const maxAds = opts.maxAds ?? 20;
  const charge = Math.max(opts.maxUsdPerRun ?? config.apify.maxUsdPerRun, MIN_CHARGE_USD);
  const cacheDir = opts.cacheDir ?? fileURLToPath(new URL('../../.cache/movers/', import.meta.url));
  const replayDir = opts.replayDir ?? fileURLToPath(new URL('../../fixtures/', import.meta.url));
  const file = (dir: string) => path.join(dir, `movers-live-${city}.json`);
  const token = opts.token ?? config.apify.token;
  let notice: string | undefined;
  let capped = false;

  if (!token) notice = 'APIFY_TOKEN is not set';
  else {
    const spend = { file: opts.spendFile ?? config.apify.spendFile, cap: opts.maxUsdPerDay ?? config.apify.maxUsdPerDay };
    if (!reserveApifySpend(charge, spend)) {
      const s = apifySpentToday(spend.file);
      capped = true;
      notice = `Apify daily spend cap reached (~$${s.usd.toFixed(2)} of $${spend.cap.toFixed(2)} today)`;
    } else {
      try {
        const url = new URL(`https://api.apify.com/v2/acts/${MOVERS_ACTOR}/run-sync-get-dataset-items`);
        url.searchParams.set('maxItems', String(maxAds));
        url.searchParams.set('maxTotalChargeUsd', String(charge));
        url.searchParams.set('timeout', '120');
        const res = await (opts.fetch ?? fetch)(url, {
          method: 'POST',
          headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
          body: JSON.stringify({ urls: [{ url: `https://${city}.craigslist.org/search/lbs?query=movers` }], maxAge: 30 }),
          signal: AbortSignal.timeout(150_000),
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const ads = adsFromRows(await res.json());
        try {
          mkdirSync(cacheDir, { recursive: true });
          const body = { _note: 'Cached live Craigslist mover ads (labor & moving) for POST /moves/quotes. Only titles with an hourly rate and the ad URL are kept. Rows read back are labeled as a replay.', city, fetchedAt: (opts.now ?? (() => new Date()))().toISOString(), actor: MOVERS_ACTOR, ads };
          writeFileSync(file(cacheDir), JSON.stringify(body, null, 2) + '\n');
        } catch {
          // best effort
        }
        if (ads.length) return { ads, replayed: false };
        notice = 'the live search found no ads with an hourly rate';
      } catch (err) {
        notice = `the live search failed (${sanitizeText(String(err instanceof Error ? err.message : err), 120)})`;
      }
    }
  }
  for (const f of [file(cacheDir), file(replayDir)]) {
    if (!existsSync(f)) continue;
    try {
      const ads = adsFromRows((JSON.parse(readFileSync(f, 'utf8')) as { ads?: unknown[] }).ads?.map(a => ({ ...(a as object), label: 'post' })));
      if (ads.length) return { ads, replayed: true, notice, capped };
    } catch {
      // unreadable cache
    }
  }
  return { ads: [], replayed: false, notice, capped };
}

/** Up to `max` listed-rate quotes: the ad's hourly rate (scaled to our crew) times our hours (2 h min), +1 h on the high end. */
export function listedQuotes(ads: ListedAd[], q: QuoteInput, replayed: boolean, max = 3): MoverQuote[] {
  const hours = Math.max(q.hours, 2);
  return ads.slice(0, max).map((ad, i) => {
    const rate = ad.crew ? (ad.rateCents * q.crew) / ad.crew : ad.rateCents;
    return {
      id: `listed-${i + 1}`,
      kind: 'listed rate' as const,
      moverType: 'full' as const,
      provider: ad.title,
      lowCents: roundLow(rate * hours),
      highCents: roundHigh(rate * (hours + 1)),
      includes: [`Advertised $${ad.rateCents / 100}/h${ad.crew ? ` for ${ad.crew} movers` : ''}`, `~${hours} h, plus 1 h on the high end`],
      assumptions: [ad.crew && ad.crew !== q.crew ? `Scaled to ${q.crew} movers` : 'Crew size as advertised', ...(replayed ? ['[REPLAYED] from a cached search'] : [])],
      estimate: true as const,
      simulated: false as const,
      source: { name: 'Craigslist ad', url: ad.url },
    };
  });
}
