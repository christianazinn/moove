// Pricing pays for its comps over x402 (#7). The worker serves the paywalled /x402/comps endpoint
// (paywall.ts) backed by the Apify lookup, and the pricing agent buys each item's comps from it
// through the shared x402 rail, so every pricing run is a logged agent payment (real on Base
// Sepolia with CDP keys, labeled simulated otherwise).
//
// Payments must never break pricing: if the rail refuses (over budget) or the paid call fails for
// any reason, the source falls back to calling the lookup directly and logs that it did.

import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { Identity } from 'spacetimedb';
import type { Conn } from '../spacetime.js';
import type { Item } from '../module_bindings/types.js';
import type { CompsSource } from '../agents/pricing.js';
import { config } from '../config.js';
import { logEvent, type EventKind } from '../events.js';
import { paymentRail } from '../payments.js';
import { COMPS_ROUTE, createCompsPaywall, type CompsLookup } from '../paywall.js';
import { lookupComps, type CompsResult } from './apify.js';
import { SpendRefusedError, type RailEnv, type X402Rail } from './x402.js';

/** What one comps report costs ($0.01, matching COMPS_PRICE_USD). Used by the simulated rail. */
export const COMPS_QUOTE_USD_MICROS = 10_000n;

/** PRICING_PAY_X402 gate: on unless set to 0/false/off. */
export function pricingPaysX402(env: { PRICING_PAY_X402?: string } = process.env): boolean {
  return !['0', 'false', 'off'].includes((env.PRICING_PAY_X402 ?? '').trim().toLowerCase());
}

export interface CompsPaywallServer {
  server: Server;
  baseUrl: string;
  paywalled: boolean;
}

/** Serves createCompsPaywall(lookup) on 127.0.0.1:X402_PORT (8402). */
export async function startCompsPaywall(
  opts: { lookup?: CompsLookup; port?: number; env?: RailEnv } = {},
): Promise<CompsPaywallServer> {
  const { app, paywalled, payTo } = await createCompsPaywall(opts.lookup ?? lookupComps, opts.env ?? process.env);
  const server = await new Promise<Server>((resolve, reject) => {
    const s = app.listen(opts.port ?? config.x402Port, '127.0.0.1', () => resolve(s));
    s.once('error', reject);
  });
  const { port } = server.address() as AddressInfo;
  const baseUrl = `http://127.0.0.1:${port}`;
  console.log(`[x402] comps paywall on ${baseUrl}${COMPS_ROUTE} (${paywalled ? `paywalled, payTo ${payTo}` : 'not paywalled'})`);
  return { server, baseUrl, paywalled };
}

type LogFn = (e: {
  owner: Identity;
  agent: string;
  kind: EventKind;
  message: string;
  refTable?: string;
  refId?: bigint;
  data?: unknown;
}) => void;

export interface PaidCompsDeps {
  rail: X402Rail | Promise<X402Rail>;
  /** Direct (unpaid) lookup used as the fallback. */
  lookup: CompsLookup;
  log: LogFn;
}

/** Testable core of paidCompsSource: no SpacetimeDB needed. */
export function createPaidCompsSource(deps: PaidCompsDeps, baseUrl: string): CompsSource {
  return async (query: string, item: Item): Promise<CompsResult> => {
    const url = `${baseUrl}${COMPS_ROUTE}?q=${encodeURIComponent(query)}`;
    try {
      const rail = await deps.rail;
      const { response } = await rail.paidFetch(
        {
          owner: item.owner,
          agent: 'pricing',
          purpose: `comps for '${query}'`,
          refTable: 'item',
          refId: item.id,
          quotedUsdMicros: COMPS_QUOTE_USD_MICROS,
        },
        url,
      );
      if (!response.ok) throw new Error(`comps endpoint answered HTTP ${response.status}`);
      const body = (await response.json()) as Partial<CompsResult>;
      if (!Array.isArray(body.comps)) throw new Error('comps endpoint returned no comps array');
      return { comps: body.comps, replayed: !!body.replayed };
    } catch (err) {
      // The rail already logged refusals (and its own payment failures); this only records the fallback.
      const refused = err instanceof SpendRefusedError;
      deps.log({
        owner: item.owner,
        agent: 'pricing',
        kind: refused ? 'tool_call' : 'error',
        message: refused
          ? `x402 payment refused, looking up comps for "${query}" directly (unpaid)`
          : `Paid comps lookup failed (${(err as Error).message}), looking up "${query}" directly (unpaid)`,
        refTable: 'item',
        refId: item.id,
        data: { query, fallback: true, refused, reason: (err as Error).message },
      });
      return deps.lookup(query);
    }
  };
}

/** CompsSource that buys comps from the paywall at baseUrl through the worker's shared x402 rail. */
export function paidCompsSource(conn: Conn, baseUrl: string): CompsSource {
  return createPaidCompsSource({ rail: paymentRail(conn), lookup: lookupComps, log: e => logEvent(conn, e) }, baseUrl);
}
