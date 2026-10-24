// Import a new home from a listing link (#89): POST /homes/import (route in upload.ts).
//
// Terms-safe by default: the listing page is NEVER requested. The address is read out of the link's
// path (ported from MoveWise backend/homes.py parse_listing_url). Rooms come from floor-plan images
// the user uploaded (Claude vision, floorplanVision.ts). Without images the response has
// floorPlan: null and the app estimates a plan locally from beds/baths/sqft (MooveKit EstimatedFloorPlan).
// The only path that fetches anything from a listing site is the opt-in Apify Zillow scraper
// (zillowApify.ts): it needs APIFY_TOKEN *and* useScraper: true in the request, and is labeled in notes.
import { randomUUID } from 'node:crypto';
import type { Identity } from 'spacetimedb';
import { z } from 'zod';
import { config } from '../config.js';
import { logEvent, type EventKind } from '../events.js';
import { loadImage, type ImageInput } from '../integrations/anthropic.js';
import type { Conn } from '../spacetime.js';
import { readFloorPlan, summarizePlan, type FloorPlan } from './floorplanVision.js';
import { cleanUntrusted } from '../untrusted.js';
import { seedHomesBudget } from './budget.js';
import { scrapeZillow } from './zillowApify.js';

export type Site = 'zillow' | 'redfin' | 'realtor' | 'apartments' | 'streeteasy' | 'other';

export type ParsedListing = { site: Site; address: string | null; building: string | null; note: string | null };

export type HomesLog = (kind: EventKind, message: string, data?: unknown) => void;

// ---------------------------------------------------------------- address parsing from URL slugs (no network)

const STATES = new Set(
  ('AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH ' +
    'OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY PR').split(' ')
);
const STREET_SUFFIXES = new Set(
  ('st street ave av avenue rd road blvd boulevard dr drive ln lane ct court pl place way ter terrace pkwy parkway hwy ' +
    'highway cir circle sq square trl trail loop row aly alley plz plaza pt point xing crossing walk path pike run bnd ' +
    'bend cv cove hts heights ests mall park broadway bowery').split(' ')
);
const UNIT_WORDS = new Set(['apt', 'unit', 'ste', 'suite', '#', 'fl', 'floor', 'ph', 'rm', 'bldg', 'lot']);
const DIRECTIONS = new Set(['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw']);
// First words of common multi-word city names (for slugs where the street/city split is ambiguous).
const CITY_PREFIXES = new Set(
  ('san los las new st saint fort ft salt santa el palo long north south east west jersey kansas oklahoma virginia ' +
    'grand baton corpus colorado little white mount mt cape port del la').split(' ')
);
const NYC_BOROUGHS: Record<string, string> = {
  new_york: 'New York', manhattan: 'New York', brooklyn: 'Brooklyn', queens: 'Queens',
  bronx: 'Bronx', the_bronx: 'Bronx', staten_island: 'Staten Island',
};
const SITE_LABEL: Record<Site, string> = {
  zillow: 'Zillow', redfin: 'Redfin', realtor: 'Realtor.com', apartments: 'Apartments.com', streeteasy: 'StreetEasy', other: 'listing',
};

const isState = (t: string) => t.length === 2 && STATES.has(t.toUpperCase());
const capitalize = (w: string) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();

function cap(word: string): string {
  const w = word.trim();
  if (!w) return w;
  if (w.startsWith('#')) return w.toUpperCase();
  const lw = w.toLowerCase();
  if (DIRECTIONS.has(lw) || isState(w)) return w.toUpperCase();
  if (/^\d+[a-z]{0,2}$/.test(lw)) return /^\d+[a-z]$/.test(lw) ? lw.toUpperCase() : lw; // 4B, but 50th
  if (lw.startsWith('mc') && lw.length > 2) return `Mc${capitalize(lw.slice(2))}`;
  return capitalize(lw);
}

const title = (words: string[]) => words.filter(Boolean).map(cap).join(' ');

function decode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

const slugTokens = (slug: string) => decode(slug).split(/[-+\s]+/).filter(Boolean);

/** ['123','main','st','apt','4b','seattle'] -> [street tokens, city tokens]. */
function splitStreetCity(tokens: string[]): [string[], string[]] {
  let last = -1;
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i].toLowerCase();
    if (STREET_SUFFIXES.has(t) && i > 0) {
      last = i;
      // a trailing direction ("Main St NW") belongs to the street
      if (i + 1 < tokens.length && DIRECTIONS.has(tokens[i + 1].toLowerCase()) && i + 2 < tokens.length) last = i + 1;
    } else if (UNIT_WORDS.has(t) && i > 0 && i + 1 < tokens.length) {
      last = i + 1;
      i++;
    }
  }
  if (last >= 0 && last < tokens.length - 1) return [tokens.slice(0, last + 1), tokens.slice(last + 1)];
  // No suffix found: guess the city is the last 1 (or 2 with a known prefix) tokens.
  if (tokens.length >= 3 && CITY_PREFIXES.has(tokens[tokens.length - 2].toLowerCase())) return [tokens.slice(0, -2), tokens.slice(-2)];
  if (tokens.length >= 2) return [tokens.slice(0, -1), tokens.slice(-1)];
  return [tokens, []];
}

function fmtAddress(street: string[], city: string[] | string, state: string | null, zip: string | null): string {
  const s = title(street).replace(/\s#\s*/g, ' #');
  const c = typeof city === 'string' ? city : title(city);
  const tail = [(state ?? '').toUpperCase(), zip ?? ''].filter(Boolean).join(' ');
  return [s, c, tail].filter(Boolean).join(', ');
}

/** '123-Main-St-APT-4B-Seattle-WA-98101' -> '123 Main St Apt 4B, Seattle, WA 98101'. */
function addressFromDashed(slug: string): string | null {
  const tok = slugTokens(slug);
  const zip = tok.length && /^\d{5}$/.test(tok[tok.length - 1]) ? tok.pop()! : null;
  const st = tok.length && isState(tok[tok.length - 1]) ? tok.pop()!.toUpperCase() : null;
  if (!tok.length) return null;
  const [street, city] = splitStreetCity(tok);
  return fmtAddress(street, city, st, zip);
}

/** 'the-addison-seattle-wa' -> ['The Addison', 'The Addison, Seattle, WA']. */
function nameCityState(slug: string): [string | null, string | null] {
  const tok = slugTokens(slug);
  const lastTok = tok[tok.length - 1];
  if (lastTok && !isState(lastTok) && /\d/.test(lastTok) && /[a-z]/i.test(lastTok)) tok.pop(); // trailing listing id
  const st = tok.length && isState(tok[tok.length - 1]) ? tok.pop()!.toUpperCase() : null;
  if (!tok.length) return [null, null];
  let name: string[];
  let city: string[];
  if (tok.length >= 3 && CITY_PREFIXES.has(tok[tok.length - 2].toLowerCase())) [name, city] = [tok.slice(0, -2), tok.slice(-2)];
  else if (tok.length >= 2) [name, city] = [tok.slice(0, -1), tok.slice(-1)];
  else [name, city] = [tok, []];
  const n = title(name);
  return [n, [n, title(city), st].filter(Boolean).join(', ')];
}

/** Normalized https URL (no query/hash: those are tracking), or null if it isn't a link. */
export function normalizeListingUrl(url: string): URL | null {
  let raw = url.trim();
  if (!raw) return null;
  if (!/^[a-z]+:\/\//i.test(raw)) raw = `https://${raw}`;
  try {
    const u = new URL(raw);
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
    if (!u.hostname.includes('.')) return null;
    u.protocol = 'https:';
    u.search = '';
    u.hash = '';
    u.username = '';
    u.password = '';
    return u;
  } catch {
    return null;
  }
}

const hostIs = (host: string, domain: string) => host === domain || host.endsWith(`.${domain}`);

/** Reads {site, address, building} from a listing link. Pure string parsing: nothing is fetched. */
export function parseListingUrl(url: string): ParsedListing {
  const out: ParsedListing = { site: 'other', address: null, building: null, note: null };
  const u = normalizeListingUrl(url);
  if (!u) return { ...out, note: "That doesn't look like a link. Type the address instead." };
  const host = u.hostname.toLowerCase();
  const parts = u.pathname.split('/').filter(Boolean).map(decode);
  try {
    if (hostIs(host, 'zillow.com')) {
      out.site = 'zillow';
      const i = parts.indexOf('homedetails');
      if (i >= 0) {
        const slug = parts[i + 1];
        if (slug && !slug.endsWith('_zpid')) out.address = addressFromDashed(slug);
      } else if (parts[0] === 'b' && parts.length > 1) {
        // /b/<building-name-city-st>/<id>/
        [out.building, out.address] = nameCityState(parts[1]);
      } else if (parts[0] === 'apartments' && parts.length > 2) {
        // /apartments/<city-st>/<building>/<id>/
        const cityTok = slugTokens(parts[1]);
        const st = cityTok.length && isState(cityTok[cityTok.length - 1]) ? cityTok[cityTok.length - 1].toUpperCase() : null;
        const city = title(st ? cityTok.slice(0, -1) : cityTok);
        out.building = title(slugTokens(parts[2]));
        out.address = [out.building, city, st].filter(Boolean).join(', ');
      }
    } else if (hostIs(host, 'redfin.com')) {
      out.site = 'redfin';
      // /<ST>/<City>/<street-zip>[/unit-<u>]/home/<id>
      if (parts.length >= 3 && isState(parts[0]) && parts[2] !== 'home' && parts[2] !== 'apartment') {
        const tok = slugTokens(parts[2]);
        const zip = tok.length && /^\d{5}$/.test(tok[tok.length - 1]) ? tok.pop()! : null;
        const unit = parts.length > 3 && parts[3].toLowerCase().startsWith('unit-') ? parts[3].slice(5) : null;
        if (tok.length) out.address = fmtAddress([...tok, ...(unit ? ['unit', unit] : [])], title(slugTokens(parts[1])), parts[0], zip);
      }
    } else if (hostIs(host, 'realtor.com')) {
      out.site = 'realtor';
      const idx = parts.findIndex(p => p.startsWith('realestateandhomes-detail') || p.startsWith('rentals'));
      if (idx >= 0 && idx + 1 < parts.length) {
        // /realestateandhomes-detail/123-Main-St_Austin_TX_78701_M12345-67890
        const segs = parts[idx + 1].split('_').filter(s => !/^M[\d-]+$/.test(s));
        if (segs.length >= 4) {
          out.address = fmtAddress(slugTokens(segs[0]), title(slugTokens(segs[1])), segs[2], /^\d{5}$/.test(segs[3]) ? segs[3] : null);
        } else if (segs.length === 3) {
          out.address = fmtAddress(slugTokens(segs[0]), title(slugTokens(segs[1])), segs[2], null);
        }
      }
    } else if (hostIs(host, 'apartments.com')) {
      out.site = 'apartments';
      if (parts.length) {
        const tok = slugTokens(parts[0]);
        if (tok.length && /^\d+[a-z]?$/i.test(tok[0])) out.address = addressFromDashed(parts[0]);
        else [out.building, out.address] = nameCityState(parts[0]);
      }
    } else if (hostIs(host, 'streeteasy.com')) {
      out.site = 'streeteasy';
      if (parts.length >= 2 && parts[0] === 'building') {
        let slug = parts[1];
        const unit = parts.length > 2 ? parts[2] : null;
        let borough = 'New York';
        const m = slug.match(/-(new_york|manhattan|brooklyn|queens|bronx|the_bronx|staten_island)$/);
        if (m) {
          borough = NYC_BOROUGHS[m[1]];
          slug = slug.slice(0, m.index);
        }
        const tok = slugTokens(slug);
        if (tok.length && /^\d+$/.test(tok[0])) {
          out.address = fmtAddress([...tok, ...(unit ? [`#${unit.toUpperCase()}`] : [])], borough, 'NY', null);
        } else {
          out.building = title(tok);
          out.address = `${out.building}${unit ? ` #${unit.toUpperCase()}` : ''}, ${borough}, NY`;
        }
      } else if (parts[0] === 'rental' || parts[0] === 'sale') {
        out.note = "This StreetEasy link has only a listing number, so we couldn't read an address from it. Type the address instead.";
      }
    }
  } catch {
    // a malformed slug just means no address
  }
  // The slug is decoded user input: no bidi/zero-width/control characters or tags into the home name
  // or the public agent_event log.
  out.address = out.address ? cleanUntrusted(out.address, 160) || null : null;
  out.building = out.building ? cleanUntrusted(out.building, 120) || null : null;
  if (out.address === null && out.note === null) {
    out.note =
      out.site === 'other'
        ? "That site isn't one we can read an address from (Zillow, Redfin, Realtor.com, Apartments.com, StreetEasy). Type the address instead."
        : "We couldn't read an address from that link. Type the address instead.";
  }
  return out;
}

// ---------------------------------------------------------------- request / response

export class ImportInputError extends Error {}

const count = z.number().finite().min(0).max(100).nullish();
const ImportBody = z
  .object({
    url: z.string().max(2048).nullish(),
    address: z.string().max(300).nullish(),
    beds: count,
    baths: count,
    sqft: z.number().finite().min(0).max(100_000).nullish(),
    floorPlanImageUrls: z.array(z.string().max(2048)).max(4).nullish(),
    useScraper: z.boolean().nullish(),
  })
  .passthrough();
export type ImportRequest = z.infer<typeof ImportBody>;

export type ImportResult = {
  name: string;
  address: string | null;
  site: Site | null;
  beds: number | null;
  baths: number | null;
  sqft: number | null;
  floorPlan: FloorPlan | null;
  method: 'floorplan' | 'scraper' | 'facts';
  notes: string[];
  listingUrl: string | null;
  simulated: boolean;
};

/** Validates the JSON body; throws ImportInputError (-> 400) on bad input. */
export function parseImportBody(body: unknown): ImportRequest {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) throw new ImportInputError('body must be a JSON object');
  const r = ImportBody.safeParse(body);
  if (!r.success) {
    const i = r.error.issues[0];
    throw new ImportInputError(`${i.path.join('.') || 'body'}: ${i.message}`);
  }
  const b = r.data;
  const has = (s: string | null | undefined) => typeof s === 'string' && s.trim() !== '';
  if (!has(b.url) && !has(b.address) && b.beds == null && b.baths == null && b.sqft == null && !b.floorPlanImageUrls?.length) {
    throw new ImportInputError('send a url, an address, beds/baths/sqft or floorPlanImageUrls');
  }
  return b;
}

// ---------------------------------------------------------------- agent_event logging

// The import request comes over plain HTTP with no caller identity yet (POST auth waits on #1), so
// there is no user to own the events. Until then they are written under the worker's own identity
// (attached from index.ts once SpacetimeDB is connected); before that they only go to the console.
// When the upload server gets auth, pass the caller's identity here instead.
let eventSink: { conn: Conn; owner: Identity } | undefined;
export function attachHomesEvents(conn: Conn, owner: Identity): void {
  eventSink = { conn, owner };
  const n = seedHomesBudget(conn.db.agentEvent.iter());
  console.log(`[homes] paid import steps in the last ${config.homes.spendWindowH} h: ${n} of ${config.homes.maxPaidCalls}`);
}

function requestLog(requestId: string): HomesLog {
  return (kind, message, data) => {
    const payload = { requestId, ...(data === undefined ? {} : { detail: data }) };
    if (eventSink) logEvent(eventSink.conn, { owner: eventSink.owner, agent: 'homes', kind, message, data: payload });
    else console.log(`[homes] ${kind}: ${message}`);
  };
}

// ---------------------------------------------------------------- the endpoint

const errText = (e: unknown) => (e instanceof Error ? e.message : String(e)).slice(0, 200);
const round1 = (n: number) => Math.round(n * 10) / 10;

function homeName(address: string | null, building: string | null, beds: number | null): string {
  const first = address?.split(',')[0].trim();
  if (first) return first.slice(0, 48);
  if (building) return building.slice(0, 48);
  if (beds != null) return beds === 0 ? 'Studio' : `${round1(beds)}-bed home`;
  return 'New home';
}

export type ImportDeps = {
  log?: HomesLog;
  loadImage?: (url: string) => Promise<ImageInput>;
  readFloorPlan?: typeof readFloorPlan;
  scrapeZillow?: typeof scrapeZillow;
  apifyToken?: string;
};

/** POST /homes/import. Throws ImportInputError for bad input; other failures become notes. */
export async function importHome(body: unknown, deps: ImportDeps = {}): Promise<ImportResult> {
  const req = parseImportBody(body);
  const log = deps.log ?? requestLog(randomUUID());
  const notes: string[] = [];
  const url = req.url?.trim() || null;
  let address = req.address ? cleanUntrusted(req.address, 160) || null : null;
  let beds = req.beds ?? null;
  let baths = req.baths ?? null;
  let sqft = req.sqft ?? null;
  let site: Site | null = null;
  let building: string | null = null;
  let listingUrl: string | null = null;
  let method: ImportResult['method'] = 'facts';

  const what = [url && 'a link', address && 'an address', (beds ?? baths ?? sqft) != null && 'beds/baths/sqft', req.floorPlanImageUrls?.length && `${req.floorPlanImageUrls.length} floor-plan image(s)`]
    .filter(Boolean)
    .join(', ');
  log('plan', `Importing a new home from ${what}${req.useScraper ? ' (scraper requested)' : ''}`);

  // 1. The link: read the address from the URL path only. The page is never opened.
  if (url) {
    const parsed = parseListingUrl(url);
    site = parsed.site;
    building = parsed.building;
    listingUrl = normalizeListingUrl(url)?.toString() ?? null;
    if (parsed.address && !address) {
      address = parsed.address;
      notes.push(`Address read from the ${SITE_LABEL[site]} link; the page itself was not opened.`);
    }
    if (parsed.note && !address) notes.push(parsed.note);
    log('result', parsed.address ? `Read "${parsed.address}" from the ${SITE_LABEL[site]} link (page not opened)` : `No address in the ${SITE_LABEL[site]} link`, { site });
  }

  // 2. Optional, opt-in only: the Apify Zillow scraper (fetches the listing, against Zillow's terms).
  let scrapedImages: ImageInput[] = [];
  if (req.useScraper) {
    const token = deps.apifyToken ?? config.apify.token;
    if (!token) notes.push('Scraper not used: APIFY_TOKEN is not set on the worker.');
    else if (site !== 'zillow' || !listingUrl) notes.push('Scraper not used: it only reads Zillow links.');
    else {
      try {
        const s = await (deps.scrapeZillow ?? scrapeZillow)(listingUrl, { token, log });
        notes.push('Fetched with an Apify Zillow scraper', ...s.notes);
        address = address ?? s.address;
        beds = beds ?? s.beds;
        baths = baths ?? s.baths;
        sqft = sqft ?? s.sqft;
        scrapedImages = s.floorPlanImages;
        method = 'scraper';
      } catch (err) {
        log('error', `Apify Zillow scraper failed: ${errText(err)}`);
        notes.push("The Zillow scraper didn't return this listing, so it wasn't used.");
      }
    }
  }

  // 3. Floor-plan images: the user's uploads win over scraped ones.
  let floorPlan: FloorPlan | null = null;
  let images: ImageInput[] = scrapedImages;
  let fromUser = false;
  if (req.floorPlanImageUrls?.length) {
    const load = deps.loadImage ?? loadImage;
    const loaded = await Promise.allSettled(req.floorPlanImageUrls.map(u => load(u)));
    const ok = loaded.flatMap(r => (r.status === 'fulfilled' ? [r.value] : []));
    const failed = loaded.length - ok.length;
    if (failed) {
      const why = loaded.find(r => r.status === 'rejected') as PromiseRejectedResult | undefined;
      log('error', `${failed} floor-plan image(s) could not be loaded: ${errText(why?.reason)}`);
      notes.push(`${failed} floor-plan image${failed === 1 ? '' : 's'} couldn't be loaded (send URLs from POST /upload).`);
    }
    if (ok.length) {
      images = ok;
      fromUser = true;
    }
  }
  if (images.length) {
    const context = { address, beds, baths, sqft };
    const r = await (deps.readFloorPlan ?? readFloorPlan)(images, { context, log });
    notes.push(...r.notes);
    floorPlan = r.floorPlan;
    if (floorPlan && fromUser) method = 'floorplan';
  }
  if (!floorPlan) notes.push('No floor plan read, so the app estimates one from beds, baths and size ("Estimated").');

  // Fill missing facts from the plan we read.
  if (floorPlan) {
    const s = summarizePlan(floorPlan);
    beds = beds ?? s.beds;
    baths = baths ?? s.baths;
    sqft = sqft ?? s.sqft;
  }

  const result: ImportResult = {
    name: homeName(address, building, beds),
    address,
    site,
    beds: beds == null ? null : round1(beds),
    baths: baths == null ? null : round1(baths),
    sqft: sqft == null ? null : Math.round(sqft),
    floorPlan,
    method,
    notes,
    listingUrl,
    simulated: false,
  };
  log('result', `${result.name}: ${floorPlan ? `${floorPlan.rooms.length} rooms from the floor plan` : 'no floor plan (app estimates)'} via ${method}`, {
    method,
    site,
    beds: result.beds,
    baths: result.baths,
    sqft: result.sqft,
    rooms: floorPlan?.rooms.length ?? 0,
  });
  return result;
}
