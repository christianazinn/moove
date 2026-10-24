// x402-paywalled "premium comps" endpoint (#7), served by the worker.
//
// The pricing agent buys comps from this endpoint over x402, so the payment flow is real end to end
// on Base Sepolia even when no third-party x402 data service fits. Payment goes from the
// `moove-agents` CDP wallet to a separate CDP receiver wallet provisioned by createX402Server.
//
// Without CDP keys (or with X402_SIMULATE=1) the route is served unpaywalled, and the simulated
// rail labels the matching payment rows `simulated: true`.

import express, { type Express } from "express";
import { BASE_SEPOLIA, hasCdpKeys, type RailEnv } from "./integrations/x402.js";

export const COMPS_ROUTE = "/x402/comps";
export const COMPS_PRICE_USD = "$0.01";

export interface Comp {
  source: string;
  title: string;
  priceCents: number;
  url: string;
}

/** Looks up comps for an item description. #6's Apify client plugs in here. */
export type CompsLookup = (query: string) => Promise<{ comps: Comp[]; replayed: boolean }>;

export interface CompsPaywall {
  app: Express;
  paywalled: boolean;
  /** CDP wallet receiving the payments (undefined when not paywalled). */
  payTo?: string;
}

export async function createCompsPaywall(lookup: CompsLookup, env: RailEnv = process.env): Promise<CompsPaywall> {
  const app = express();
  const paywalled = env.X402_SIMULATE !== "1" && hasCdpKeys(env);
  let payTo: string | undefined;

  if (paywalled) {
    const { createX402Server } = await import("@coinbase/cdp-sdk/x402");
    const { paymentMiddlewareFromHTTPServer } = await import("@x402/express");
    const server = await createX402Server({
      environment: "development",
      payToConfig: { type: "eoa" },
      routes: {
        [`GET ${COMPS_ROUTE}`]: {
          price: COMPS_PRICE_USD,
          networks: [BASE_SEPOLIA],
          description: "Moove premium comps report: comparable used-item listings for one item",
        },
      },
    });
    payTo = server.payToEvmAddress;
    // Same class at runtime (both load @x402/core's ESM build), but cdp-sdk's .d.ts files resolve
    // @x402/core's CJS declarations, so TS sees two incompatible x402HTTPResourceServer types.
    app.use(paymentMiddlewareFromHTTPServer(server as unknown as Parameters<typeof paymentMiddlewareFromHTTPServer>[0]));
  }

  app.get(COMPS_ROUTE, async (req, res) => {
    const q = typeof req.query.q === "string" ? req.query.q.trim() : "";
    if (!q) {
      res.status(400).json({ error: "missing ?q=<item description>" });
      return;
    }
    try {
      const { comps, replayed } = await lookup(q);
      res.json({ query: q, comps, replayed, paywalled });
    } catch (err) {
      res.status(502).json({ error: `comps lookup failed: ${(err as Error).message}` });
    }
  });

  return { app, paywalled, payTo };
}
