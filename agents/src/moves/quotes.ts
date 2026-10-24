// POST /moves/quotes (route in upload.ts): the "movers" agent for the app's Pack screen.
// Input {volumeM3, truckSize, trucks?, crew, hours, miles?, fromZip?, fromCity?, toZip?, toCity?, moveDate?, roomId?}.
// Output {quotes, steps, note, ratesAsOf}: three rate-table ESTIMATES (DIY truck rental, labor-only
// movers, full-service local movers; rates.ts), plus up to three Craigslist "listed rate" quotes when
// APIFY_MOVERS=1 (listedRates.ts). Nothing here is a booked or binding quote, so every quote has
// `estimate: true`, and listed ones carry the ad's URL. No Claude call.
//
// Every step writes an agent_event (agent "movers") and is also returned in `steps` for the app.
// Like POST /homes/import the request has no caller identity (upload POST auth waits on #1), so the
// events are owned by the worker; `roomId` is only recorded in the event data, never trusted to pick
// an owner (anyone who can reach the port could otherwise write into someone's activity feed).
import { randomUUID } from 'node:crypto';
import type { Identity } from 'spacetimedb';
import { z } from 'zod';
import { config } from '../config.js';
import { logEvent, type EventKind } from '../events.js';
import type { Conn } from '../spacetime.js';
import { sanitizeText } from '../integrations/deals.js';
import { estimateQuotes, MOVER_RATES, TRUCK_LABEL, TRUCK_SIZES, type MoverQuote, type QuoteInput, type TruckSize } from './rates.js';
import { findListedRates, listedQuotes, type ListedRatesResult } from './listedRates.js';

export class QuoteInputError extends Error {}

export const QUOTES_NOTE = 'Estimates from published rates. Call to book.';

const Body = z.object({
  volumeM3: z.number().finite().min(0).max(500),
  truckSize: z.enum(TRUCK_SIZES as [TruckSize, ...TruckSize[]]),
  trucks: z.number().int().min(1).max(10).optional(),
  crew: z.number().int().min(1).max(8),
  hours: z.number().finite().min(0.5).max(24),
  miles: z.number().finite().min(0).max(500).optional(),
  fromZip: z.string().regex(/^\d{5}$/).optional(),
  toZip: z.string().regex(/^\d{5}$/).optional(),
  fromCity: z.string().max(80).optional(),
  toCity: z.string().max(80).optional(),
  moveDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  roomId: z.union([z.number().int().min(0), z.string().regex(/^\d{1,20}$/)]).optional(),
});

export interface QuoteRequest extends QuoteInput {
  fromZip?: string;
  toZip?: string;
  fromCity?: string;
  toCity?: string;
  moveDate?: string;
  roomId?: string;
}

const city = (s?: string) => (s ? sanitizeText(s.replace(/[^A-Za-z .,'-]/g, ' '), 40) || undefined : undefined);

/** Validates the JSON body; throws QuoteInputError (-> 400). Hours go to the quarter hour, miles to whole miles. */
export function parseQuoteBody(body: unknown): QuoteRequest {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) throw new QuoteInputError('body must be a JSON object');
  const r = Body.safeParse(body);
  if (!r.success) {
    const i = r.error.issues[0];
    throw new QuoteInputError(`${i.path.join('.') || 'body'}: ${i.message}`);
  }
  const b = r.data;
  return {
    volumeM3: Math.round(b.volumeM3 * 10) / 10,
    truckSize: b.truckSize,
    trucks: b.trucks ?? 1,
    crew: b.crew,
    hours: Math.max(0.5, Math.round(b.hours * 4) / 4),
    ...(b.miles !== undefined ? { miles: Math.round(b.miles) } : {}),
    ...(b.fromZip ? { fromZip: b.fromZip } : {}),
    ...(b.toZip ? { toZip: b.toZip } : {}),
    ...(city(b.fromCity) ? { fromCity: city(b.fromCity) } : {}),
    ...(city(b.toCity) ? { toCity: city(b.toCity) } : {}),
    ...(b.moveDate ? { moveDate: b.moveDate } : {}),
    ...(b.roomId !== undefined ? { roomId: String(b.roomId) } : {}),
  };
}

export interface QuoteStep {
  kind: EventKind;
  message: string;
}

export interface QuotesResponse {
  quotes: MoverQuote[];
  steps: QuoteStep[];
  note: string;
  ratesAsOf: string;
  /** Where the numbers were worked out. The app shows "Estimated on this phone" for its own fallback. */
  computedBy: 'worker';
}

// ---------------------------------------------------------------- agent_event logging

let eventSink: { conn: Conn; owner: Identity } | undefined;
export function attachMovesEvents(conn: Conn, owner: Identity): void {
  eventSink = { conn, owner };
}

export interface QuoteDeps {
  listedRates?: () => Promise<ListedRatesResult>;
  apifyMovers?: boolean;
  log?: (kind: EventKind, message: string, data: unknown) => void;
}

const usd = (c: number) => `$${Math.round(c / 100).toLocaleString('en-US')}`;
const hrs = (h: number) => (Number.isInteger(h) ? `${h}` : h.toFixed(2).replace(/0$/, ''));

/** The movers agent. Throws QuoteInputError for bad input. */
export async function getMoverQuotes(body: unknown, deps: QuoteDeps = {}): Promise<QuotesResponse> {
  const q = parseQuoteBody(body);
  const requestId = randomUUID();
  const steps: QuoteStep[] = [];
  const log = (kind: EventKind, message: string, data?: unknown) => {
    steps.push({ kind, message });
    const payload = { requestId, ...(q.roomId ? { roomId: q.roomId } : {}), ...(data === undefined ? {} : { detail: data }) };
    if (deps.log) deps.log(kind, message, payload);
    else if (eventSink) logEvent(eventSink.conn, { owner: eventSink.owner, agent: 'movers', kind, message, data: payload });
    else console.log(`[movers] ${kind}: ${message}`);
  };

  const truck = (q.trucks > 1 ? `${q.trucks} × ` : 'a ') + TRUCK_LABEL[q.truckSize].replace(/^(\d+) ft/, "$1'");
  const route = q.fromCity || q.fromZip ? ` from ${q.fromCity ?? q.fromZip}${q.toCity || q.toZip ? ` to ${q.toCity ?? q.toZip}` : ''}` : '';
  log('plan', `Requested quotes for ${truck}, ${q.crew} movers, ~${hrs(q.hours)} h${route}`, { request: q });

  log('tool_call', `Read the mover rate table (rates as of ${MOVER_RATES.asOf})`, { sources: MOVER_RATES.sources });
  const quotes = estimateQuotes(q);
  for (const e of quotes) {
    log('result', `Estimate: ${e.provider} ${usd(e.lowCents)}–${usd(e.highCents)}`, { quoteId: e.id, lowCents: e.lowCents, highCents: e.highCents, estimate: true, source: e.source });
  }

  if (deps.apifyMovers ?? config.moves.apifyMovers) {
    log('tool_call', `Searching Craigslist for local movers' advertised rates (Apify)`, { city: config.moves.craigslistCity });
    try {
      const found = await (deps.listedRates ?? (() => findListedRates()))();
      if (found.capped) log('result', `Apify daily spend cap reached: skipped the live search${found.ads.length ? ', using a cached one' : ''}`, { apifyCap: true, refused: true });
      const listed = listedQuotes(found.ads, q, found.replayed);
      for (const l of listed) {
        log('result', `${found.replayed ? '[REPLAYED] ' : ''}Listed rate: ${l.provider.slice(0, 50)} ${usd(l.lowCents)}–${usd(l.highCents)}`, { quoteId: l.id, url: l.source.url, replayed: found.replayed, estimate: true });
      }
      if (!listed.length) log('result', `No listed rates found${found.notice ? `: ${found.notice}` : ''}`, { notice: found.notice ?? null });
      quotes.push(...listed);
    } catch (err) {
      log('error', `Listed-rate search failed: ${sanitizeText(err instanceof Error ? err.message : String(err), 160)}`);
    }
  }

  log('result', `${quotes.length} quotes ready. ${QUOTES_NOTE}`, { count: quotes.length, kinds: quotes.map(x => x.kind) });
  return { quotes, steps, note: QUOTES_NOTE, ratesAsOf: MOVER_RATES.asOf, computedBy: 'worker' };
}
