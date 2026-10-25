import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Item } from "../src/module_bindings/types.js";

// The pricing agent's queue: bounded concurrency (Apify's free plan allows 5 concurrent actor
// runs) and transient failures retried instead of marked failed. Own file so the env is set
// before pricing.ts reads it.
process.env.PRICING_CONCURRENCY = "2";
process.env.PRICING_RETRY_BASE_MS = "20";
process.env.PRICING_COMP_FILTER = "0";
process.env.PRICING_PRIOR = "0"; // the price prior would call Claude (config loads .env.local)
const { pricingAgent, setCompsSource, isTransientPricingError } = await import("../src/agents/pricing.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => "owner" };

test("transient errors are recognized; permanent ones are not", () => {
  for (const e of [
    'apify caffein.dev~ebay-sold-listings: HTTP 402 {"error":{"type":"concurrent-runs-limit-exceeded"}}',
    "HTTP 429 Too Many Requests",
    "[SIMULATED] x402 payment for comps for 'sofa' failed (HTTP 502)",
    "TypeError: fetch failed",
    "The operation was aborted due to timeout",
  ]) assert.equal(isTransientPricingError(new Error(e)), true, e);
  for (const e of ["APIFY_TOKEN not set and no cached comps for this query", "HTTP 401 Unauthorized", "SyntaxError: bad JSON"])
    assert.equal(isTransientPricingError(new Error(e)), false, e);
});

function fakeConn(n: number, status = "pending") {
  const rows = new Map<bigint, Item>();
  for (let i = 1; i <= n; i++) {
    rows.set(BigInt(i), { id: BigInt(i), owner, name: `chair ${i}`, category: "chair", brand: "", condition: "good", photoUrls: [], detailsStatus: "done", pricingStatus: status } as unknown as Item);
  }
  const updates: ((ctx: unknown, old: Item, it: Item) => void)[] = [];
  const set = (id: bigint, patch: Partial<Item>) => {
    const old = rows.get(id)!;
    const it = { ...old, ...patch } as Item;
    rows.set(id, it);
    for (const cb of updates) cb({}, old, it);
  };
  const conn = {
    db: {
      item: {
        iter: () => [...rows.values()].values(),
        id: { find: (id: bigint) => rows.get(id) },
        onInsert: () => {},
        onUpdate: (cb: (typeof updates)[number]) => updates.push(cb),
      },
    },
    reducers: {
      setItemStage: async (a: { itemId: bigint; stage: string }) => set(a.itemId, { pricingStatus: a.stage }),
      setEstValue: async (a: { itemId: bigint; estValueCents: bigint }) => set(a.itemId, { pricingStatus: "done", estValueCents: a.estValueCents } as Partial<Item>),
      addComps: async () => {},
      logAgentEvent: async () => {},
    },
  };
  return { conn: conn as unknown as Conn, rows };
}

const comps = [5000, 6000, 7000].map(p => ({ source: "ebay", title: "office chair", priceCents: p, url: "u" }));

test("at most PRICING_CONCURRENCY lookups run at once; busy lookups retry, then price", async () => {
  let active = 0;
  let peak = 0;
  const calls = new Map<string, number>();
  setCompsSource(async q => {
    active++;
    peak = Math.max(peak, active);
    calls.set(q, (calls.get(q) ?? 0) + 1);
    await sleep(5);
    active--;
    // chair 3 hits the concurrency limit the first time only
    if (q === "chair 3" && calls.get(q) === 1) throw new Error('HTTP 402 {"type":"concurrent-runs-limit-exceeded"}');
    return { comps, replayed: false };
  });
  const { conn, rows } = fakeConn(6);
  pricingAgent.start(conn);
  await sleep(200);
  assert.equal(peak, 2);
  assert.equal(calls.get("chair 3"), 2);
  for (const it of rows.values()) assert.equal(it.pricingStatus, "done", `item ${it.id}`);
});
