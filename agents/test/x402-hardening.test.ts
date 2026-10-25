import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Item } from "../src/module_bindings/types.js";

// Restart/reconnect hardening for the x402 + paid-comps path. Own file (own process) so the env is
// set before the modules read it and payments.ts's per-process rail starts fresh.
process.env.X402_SIMULATE = "1";
process.env.PRICING_COMP_FILTER = "0";
process.env.PRICING_PRIOR = "0"; // the price prior would call Claude (config loads .env.local)
delete process.env.X402_SEED_BUDGETS;
delete process.env.AGENT_SPEND_CAP_USDC;
delete process.env.X402_MAX_PER_CALL_USDC;
delete process.env.PRICING_RETRY_FAILED;
const { paymentRail } = await import("../src/payments.js");
const { pricingAgent, setCompsSource } = await import("../src/agents/pricing.js");

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const owner = { toHexString: () => "owner" };
const ts = (ms: number) => ({ toMillis: () => BigInt(ms) });

async function quietly<T>(fn: () => Promise<T>): Promise<T> {
  const { log, warn } = console;
  console.log = () => {};
  console.warn = () => {};
  try {
    return await fn();
  } finally {
    console.log = log;
    console.warn = warn;
  }
}

test("paymentRail seeds the last 24h of this rail's non-failed x402 spend, so a restart can't reset budgets", async () => {
  const now = Date.now();
  const row = (p: Record<string, unknown>) => ({ rail: "x402", agent: "pricing", status: "settled", simulated: true, amountUsdMicros: 10_000n, createdAt: ts(now - 60_000), ...p });
  const payments = [
    row({}),
    row({ amountUsdMicros: 20_000n }),
    row({ status: "failed" }), // refunded: doesn't count
    row({ simulated: false }), // other rail mode: doesn't count
    row({ rail: "visa" }), // card spend has its own ledger
    row({ createdAt: ts(now - 25 * 3600 * 1000) }), // outside the 24h window
    row({ agent: "buy", amountUsdMicros: 5_000n }),
  ];
  const conn = { db: { payment: { iter: () => payments.values() } }, reducers: {} } as unknown as Conn;
  const rail = await quietly(() => paymentRail(conn));
  assert.equal(rail.simulated, true);
  const cap = 5_000_000n; // AGENT_SPEND_CAP_USDC default $5
  assert.equal(rail.remaining("pricing"), cap - 30_000n);
  assert.equal(rail.remaining("buy"), cap - 5_000n);
  assert.equal(rail.remaining("listing"), cap);
  // Memoized: a second caller (e.g. a reconnect path) gets the same seeded rail, not a fresh budget.
  assert.equal(await paymentRail(conn), rail);
});

test("an item left pricing_status=running by a worker restart is priced again", async () => {
  const rows = new Map<bigint, Item>();
  const mk = (id: bigint, pricingStatus: string) =>
    ({ id, owner, name: `lamp ${id}`, category: "lamp", brand: "", condition: "good", photoUrls: [], detailsStatus: "done", pricingStatus }) as unknown as Item;
  rows.set(1n, mk(1n, "running")); // the old worker died mid-lookup (after paying for comps)
  rows.set(2n, mk(2n, "done"));
  const updates: ((ctx: unknown, old: Item, it: Item) => void)[] = [];
  const set = (id: bigint, patch: Partial<Item>) => {
    // Like SpacetimeDB: the client cache (and onUpdate) changes after the reducer call returns.
    setImmediate(() => {
      const old = rows.get(id)!;
      const it = { ...old, ...patch } as Item;
      rows.set(id, it);
      updates.forEach((cb) => cb({}, old, it));
    });
  };
  const events: { kind: string; message: string; refId: bigint }[] = [];
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
      logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e),
    },
  } as unknown as Conn;
  const looked: string[] = [];
  setCompsSource(async (q) => {
    looked.push(q);
    return { comps: [4000, 5000, 6000].map((p) => ({ source: "ebay", title: "lamp", priceCents: p, url: "u" })), replayed: false };
  });
  await quietly(async () => {
    pricingAgent.start(conn);
    await sleep(100);
  });
  assert.deepEqual(looked, ["lamp 1"]);
  assert.equal(rows.get(1n)!.pricingStatus, "done");
  assert.equal(rows.get(2n)!.pricingStatus, "done");
});

test("simulated rail: concurrent calls (PRICING_CONCURRENCY) reserve synchronously and can't pass the cap", async () => {
  const { X402Rail, SpendLedger, SpendRefusedError } = await import("../src/integrations/x402.js");
  const payments: { status: string }[] = [];
  const sink = { recordPayment: async (p: { status: string }) => void payments.push(p), logAgentEvent: async () => {} };
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  // Every fetch blocks until all calls have started, so they all race the cap check together.
  const fetch = (async () => {
    await gate;
    return new Response("{}", { status: 200 });
  }) as unknown as typeof globalThis.fetch;
  const rail = new X402Rail({ sink: sink as never, ledger: new SpendLedger(25_000n, 10_000n), fetch });
  const calls = [1, 2, 3].map(() => rail.paidFetch({ owner: "o", agent: "pricing", purpose: "comps", quotedUsdMicros: 10_000n }, "http://127.0.0.1:1/x"));
  release();
  const results = await Promise.allSettled(calls);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 2);
  const refused = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
  assert.ok(refused.reason instanceof SpendRefusedError);
  assert.equal(payments.filter((p) => p.status === "settled").length, 2);
  assert.equal(rail.remaining("pricing"), 5_000n);
});

test("per-call max is inclusive: exactly the max is paid, one micro over is refused", async () => {
  const { SpendLedger, SpendRefusedError } = await import("../src/integrations/x402.js");
  const ledger = new SpendLedger(1_000_000n, 10_000n);
  ledger.reserve("pricing", 10_000n);
  assert.throws(() => ledger.reserve("pricing", 10_001n), SpendRefusedError);
  assert.equal(ledger.spentBy("pricing"), 10_000n);
  // A refund never drives spend negative (which would grant extra budget).
  ledger.release("pricing", 50_000n);
  assert.equal(ledger.remaining("pricing"), 1_000_000n);
});
