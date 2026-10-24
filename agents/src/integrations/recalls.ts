// Product recall check over x402: before the listing agent sells an item, the "safety" agent pays a
// third-party x402 service ($0.002 USDC on Base Sepolia) for a US CPSC recall search on the item's
// brand, then matches the recalls against the item's name here. Selling a recalled consumer product is illegal in the US (CPSA), so a probable match
// makes the listing ask the user for approval, with the recall in the approval summary.
//
// Service: https://api.stablecoingateways.com/v1/recalls?q=<product or brand>&source=cpsc (listed in
// the CDP x402 Bazaar). It goes through the worker's shared rail (payments.ts), so the per-agent
// budget, the per-call max and X402_ALLOWED_PAYEES all apply.
//
// Off unless RECALL_CHECK_X402=1. It never fails a listing: a refusal, a non-2xx answer, a timeout or
// a body we can't read logs one event and the listing goes ahead. Only branded items are checked (an
// unbranded "dresser" matches every dresser recall). The service is a keyword search of CPSC product
// text, so "IKEA Malm dresser" finds nothing while "IKEA" finds IKEA's recalls: we search the brand
// and match name words locally. Each brand is paid for once: successful reports are cached in memory
// and in .cache/recalls/ (gitignored), so a restart doesn't pay again.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Identity } from 'spacetimedb';
import type { Item } from '../module_bindings/types.js';
import type { EventKind } from '../events.js';
import { isGenericQuery, queryFor } from '../agents/pricing.js';
import { simulatedLabel } from './simulated.js';
import { EXPLORER_TX_URL, SpendRefusedError, type X402Rail } from './x402.js';

export const RECALLS_URL = 'https://api.stablecoingateways.com/v1/recalls';
/** The service's Base Sepolia payTo. Add it to X402_ALLOWED_PAYEES if that allowlist is set. */
export const RECALLS_PAYEE = '0x3177FA489523ddF60f293898f7Ee5912576f3d9b';
/** $0.002 per lookup (2000 USDC atomic units). Used as the simulated rail's quote. */
export const RECALL_QUOTE_USD_MICROS = 2_000n;
export const RECALL_AGENT = 'safety';
const MAX_QUERY = 80; // the service rejects longer q

/** RECALL_CHECK_X402 gate: off unless set to 1/true/on. */
export function recallCheckEnabled(env: { RECALL_CHECK_X402?: string } = process.env): boolean {
  return ['1', 'true', 'on'].includes((env.RECALL_CHECK_X402 ?? '').trim().toLowerCase());
}

export interface Recall {
  title: string;
  recallNumber: string;
  date: string;
  description: string;
  /** Product names from the recall (CPSC `products[].name`), joined with "; ". */
  products: string;
  hazard: string;
  url: string;
}

/** What the service returned for one query (a brand). Cached and shared by every item of that brand. */
export interface RecallReport {
  query: string;
  recalls: Recall[];
  retrievedAt: string;
}

const str = (v: unknown): string => (typeof v === 'string' ? v : typeof v === 'number' ? String(v) : '');

/**
 * Reads the service's JSON. Seen on a real call: {data: {query, source, cpsc: [{source, recall_number,
 * date, title, description, products: [{name, model, units}], hazards: [], remedies: [], injuries: [],
 * manufacturers: [], url}], fda, partial_errors, provenance, retrieved_at}, receipt}. At most 10 recalls
 * per query, newest first. Defensive about the shape; throws if there's no recall list at all.
 */
export function parseRecallResponse(body: unknown): { recalls: Recall[]; retrievedAt: string } {
  const root = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
  const data = (root.data && typeof root.data === 'object' ? root.data : root) as Record<string, unknown>;
  const list = data.cpsc ?? data.recalls ?? data.results;
  if (!Array.isArray(list)) throw new Error('recall response had no CPSC list');
  const recalls = list
    .filter((r): r is Record<string, unknown> => !!r && typeof r === 'object')
    .map(r => ({
      title: str(r.title ?? r.Title).trim(),
      recallNumber: str(r.recall_number ?? r.recallNumber ?? r.RecallNumber).trim(),
      date: str(r.date ?? r.recall_date ?? r.RecallDate).trim(),
      description: str(r.description ?? r.Description).trim(),
      products: (Array.isArray(r.products) ? r.products : [])
        .map(p => str((p as { name?: unknown } | null)?.name).trim())
        .filter(Boolean)
        .join('; '),
      hazard: (Array.isArray(r.hazards) ? r.hazards.map(str) : [str(r.hazard)]).filter(Boolean).join(' ').trim(),
      url: str(r.url ?? r.link ?? r.URL).trim(),
    }))
    .filter(r => r.title || r.recallNumber);
  return { recalls, retrievedAt: str(data.retrieved_at ?? root.retrieved_at) };
}

// Words too common to tie a recall to an item.
const STOP = new Set(['the', 'and', 'for', 'with', 'set', 'new', 'used', 'old', 'small', 'large', 'big', 'piece', 'black', 'white', 'gray', 'grey', 'brown', 'wood', 'wooden', 'metal']);
const stem = (w: string) => w.replace(/(?:es|s)$/, '');
const words = (s: string) => s.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length >= 3 && !STOP.has(w)).map(stem);

/** A recall probably covers the item when it names the brand and (if the name has any) one name word. */
export function probableMatches(recalls: Recall[], item: { brand: string; name: string }): Recall[] {
  const brand = words(item.brand);
  if (brand.length === 0) return [];
  const name = words(item.name).filter(w => !brand.includes(w));
  return recalls.filter(r => {
    const text = new Set(words(`${r.title} ${r.products} ${r.description}`));
    return brand.every(w => text.has(w)) && (name.length === 0 || name.some(w => text.has(w)));
  });
}

/** The query to pay for (the brand), or null for unbranded or catch-all items (not worth paying for). */
export function recallQuery(it: Item): string | null {
  if (!it.brand.trim() || isGenericQuery(it)) return null;
  const q = it.brand.replace(/\s+/g, ' ').trim().slice(0, MAX_QUERY).trim();
  return q.length >= 2 ? q : null;
}

export function recallUrl(query: string): string {
  return `${RECALLS_URL}?q=${encodeURIComponent(query)}&source=cpsc`;
}

/** One line for the event log and the approval summary. */
export function describeMatch(r: Recall): string {
  return `${r.title.replace(/"/g, "'") || 'CPSC recall'}${r.recallNumber ? ` (#${r.recallNumber})` : ''}`;
}

export type RecallOutcome =
  | { status: 'skipped'; reason: string }
  | { status: 'checked'; report: RecallReport; matches: Recall[]; replayed: boolean; txHash?: string }
  | { status: 'unavailable'; reason: string; refused: boolean };

type LogFn = (e: { owner: Identity; agent: string; kind: EventKind; message: string; refTable?: string; refId?: bigint; data?: unknown }) => void;

export interface RecallCheckDeps {
  rail: X402Rail | Promise<X402Rail>;
  log: LogFn;
  env?: { RECALL_CHECK_X402?: string; RECALL_CHECK_TIMEOUT_MS?: string };
  /** Where reports are cached across restarts. Default agents/.cache/recalls; null = memory only. */
  cacheDir?: string | null;
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60) || 'item';

export interface RecallChecker {
  check(it: Item): Promise<RecallOutcome>;
  /** Probable recalls for this item from a report already paid for (no network, no payment). Undefined when the gate is off or nothing is cached. */
  cached(it: Item): Recall[] | undefined;
}

export function createRecallChecker(deps: RecallCheckDeps): RecallChecker {
  const env = deps.env ?? process.env;
  const cacheDir = deps.cacheDir === undefined ? fileURLToPath(new URL('../../.cache/recalls/', import.meta.url)) : deps.cacheDir;
  const memory = new Map<string, RecallReport>();
  const inFlight = new Map<string, Promise<RecallOutcome>>();
  const timeoutMs = Number(env.RECALL_CHECK_TIMEOUT_MS ?? '') || 15_000;

  const fromDisk = (q: string): RecallReport | undefined => {
    if (!cacheDir) return undefined;
    try {
      const r = JSON.parse(readFileSync(path.join(cacheDir, `${slug(q)}.json`), 'utf8')) as RecallReport;
      return r.query === q && Array.isArray(r.recalls) ? r : undefined;
    } catch {
      return undefined;
    }
  };
  const lookup = (q: string): RecallReport | undefined => {
    const hit = memory.get(q) ?? fromDisk(q);
    if (hit) memory.set(q, hit);
    return hit;
  };
  const save = (r: RecallReport) => {
    memory.set(r.query, r);
    if (!cacheDir) return;
    try {
      mkdirSync(cacheDir, { recursive: true });
      writeFileSync(path.join(cacheDir, `${slug(r.query)}.json`), JSON.stringify(r, null, 2));
    } catch (err) {
      console.warn(`[safety] could not cache the recall report for "${r.query}": ${String(err)}`);
    }
  };

  async function pay(it: Item, q: string): Promise<RecallOutcome> {
    const ref = { owner: it.owner, agent: RECALL_AGENT, refTable: 'item', refId: it.id };
    let simulated = false;
    try {
      const rail = await deps.rail;
      simulated = rail.simulated;
      const { response, payment } = await rail.paidFetch(
        { ...ref, purpose: `CPSC recall check for '${q}'`, quotedUsdMicros: RECALL_QUOTE_USD_MICROS },
        recallUrl(q),
        { headers: { accept: 'application/json' }, signal: AbortSignal.timeout(timeoutMs) },
      );
      if (!response.ok) throw new Error(`recall service answered HTTP ${response.status}`);
      const body = await response.json().catch(() => {
        throw new Error('recall service returned bad JSON');
      });
      const { recalls, retrievedAt } = parseRecallResponse(body);
      const report: RecallReport = { query: q, recalls, retrievedAt };
      save(report);
      const txHash = payment?.txHash || undefined;
      return { status: 'checked', report, matches: logReport(it, report, false, txHash), replayed: false, txHash };
    } catch (err) {
      // The rail already logged refusals and payment failures; this records that the listing goes on.
      const refused = err instanceof SpendRefusedError;
      const reason = (err as Error)?.message ?? String(err);
      const message = `Recall check for "${q}" ${refused ? 'refused' : 'unavailable'} (${reason}); listing goes ahead without it`;
      deps.log({ ...ref, kind: 'tool_call', message: simulated ? simulatedLabel(message) : message, data: { query: q, fallback: true, refused, reason, simulated } });
      return { status: 'unavailable', reason, refused };
    }
  }

  /** Logs the verdict for this item and returns its probable matches. */
  function logReport(it: Item, r: RecallReport, replayed: boolean, txHash?: string): Recall[] {
    const tag = replayed ? '[REPLAYED] ' : '';
    const matches = probableMatches(r.recalls, it);
    const label = queryFor(it);
    const first = matches[0];
    const message = first
      ? `${tag}Possible CPSC recall for "${label}": ${describeMatch(first)}${matches.length > 1 ? ` and ${matches.length - 1} more` : ''}`
      : r.recalls.length
        ? `${tag}No CPSC recalls match "${label}" (${r.recalls.length} other ${r.query} recall${r.recalls.length === 1 ? '' : 's'} checked)`
        : `${tag}No CPSC recalls found for "${r.query}"`;
    deps.log({
      owner: it.owner,
      agent: RECALL_AGENT,
      kind: 'result',
      message,
      refTable: 'item',
      refId: it.id,
      data: {
        query: r.query,
        item: label,
        source: 'cpsc',
        service: RECALLS_URL,
        replayed,
        results: r.recalls.length,
        possibleRecall: matches.length > 0,
        matches: matches.slice(0, 5).map(m => ({ title: m.title, recallNumber: m.recallNumber, date: m.date, url: m.url })),
        ...(txHash ? { txHash, explorer: EXPLORER_TX_URL + txHash } : {}),
      },
    });
    return matches;
  }

  return {
    cached(it) {
      if (!recallCheckEnabled(env)) return undefined;
      const q = recallQuery(it);
      const r = q ? lookup(q) : undefined;
      return r ? probableMatches(r.recalls, it) : undefined;
    },
    async check(it) {
      if (!recallCheckEnabled(env)) return { status: 'skipped', reason: 'RECALL_CHECK_X402 is off' };
      const q = recallQuery(it);
      if (!q) return { status: 'skipped', reason: 'no brand to check' };
      const hit = lookup(q);
      if (hit) return { status: 'checked', report: hit, matches: logReport(it, hit, true), replayed: true };
      // Two items with the same query at once share one paid call.
      const pending = inFlight.get(q);
      if (pending) {
        const o = await pending;
        return o.status === 'checked' ? { ...o, matches: logReport(it, o.report, true), replayed: true, txHash: undefined } : o;
      }
      const p = pay(it, q).finally(() => inFlight.delete(q));
      inFlight.set(q, p);
      return p;
    },
  };
}
