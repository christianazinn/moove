import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Deal } from "../src/module_bindings/types.js";

// The fraud agent's loop (#18) against a fake connection: settle batching, one screen per deal,
// already-scored rows skipped, and the failure paths. Own file so FRAUD_SETTLE_MS can be set
// before fraud.ts reads it (node --test runs each file in its own process).
process.env.FRAUD_SETTLE_MS = "40";
process.env.FRAUD_RETRY_DELAY_MS = "5";
const { fraudAgent, setAiTextDetector } = await import("../src/agents/fraud.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => "owner" };

function fakeConn(opts: { failFraudFor?: bigint; failTimes?: number } = {}) {
  const deals = new Map<bigint, Deal>();
  const inserts: ((ctx: unknown, d: Deal) => void)[] = [];
  const updates: ((ctx: unknown, old: Deal, d: Deal) => void)[] = [];
  const fraudCalls: { dealId: bigint; fraudScore: number; aiTextScore: number; reasons: string[] }[] = [];
  const events: { kind: string; message: string; refId: bigint }[] = [];
  let failed = 0;
  const conn = {
    db: {
      deal: {
        iter: () => deals.values(),
        onInsert: (cb: (ctx: unknown, d: Deal) => void) => inserts.push(cb),
        onUpdate: (cb: (ctx: unknown, old: Deal, d: Deal) => void) => updates.push(cb),
      },
      shoppingItem: { id: { find: (id: bigint) => ({ id, name: "review lamp no cached comps" }) } },
    },
    reducers: {
      setDealFraud: async (a: { dealId: bigint; fraudScore: number; aiTextScore: number; reasons: string[] }) => {
        fraudCalls.push(a);
        if (a.dealId === opts.failFraudFor && (opts.failTimes === undefined || failed++ < opts.failTimes)) throw new Error("SenderError: no deal");
        const old = deals.get(a.dealId)!;
        const d = { ...old, fraudScore: a.fraudScore, aiTextScore: a.aiTextScore, fraudReasons: a.reasons };
        deals.set(d.id, d);
        for (const cb of updates) cb({}, old, d);
      },
      logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e), // reducers return promises (events.ts .catch()es them)
    },
  };
  let nextId = 1n;
  const insert = (o: Partial<Deal> = {}) => {
    const d = {
      id: nextId++,
      owner,
      shoppingItemId: 1n,
      source: "fb",
      title: "Floor lamp, works great",
      priceCents: 1500n,
      url: `https://example.com/item/${nextId}`,
      sellerInfo: "Marketplace seller, Berkeley (4.8 stars) · good · 1 mi · message seller",
      fraudScore: -1,
      aiTextScore: -1,
      fraudReasons: [],
      ...o,
    } as unknown as Deal;
    deals.set(d.id, d);
    for (const cb of inserts) cb({}, d);
    return d;
  };
  return { conn: conn as unknown as Conn, deals, insert, fraudCalls, events };
}

test("fraud agent: a burst is screened once per deal after it settles, scored rows are skipped", async () => {
  const seen: string[] = [];
  setAiTextDetector({ name: "stub", score: async t => (seen.push(t), /boom/i.test(t) ? Promise.reject(new Error("HTTP 500")) : 0.1) });
  const f = fakeConn();
  // Already scored before start: never re-screened.
  f.deals.set(99n, { id: 99n, owner, shoppingItemId: 1n, source: "ikea", title: "HEKTAR floor lamp, dark gray", priceCents: 6999n, url: "u99", sellerInfo: "IKEA", fraudScore: 0, aiTextScore: 0.1, fraudReasons: [] } as unknown as Deal);
  await fraudAgent.start(f.conn);
  f.insert({ source: "ikea", title: "HEKTAR floor lamp, dark gray", priceCents: 6999n });
  await sleep(10);
  f.insert({ source: "target", title: "Arc floor lamp, brass", priceCents: 5999n });
  await sleep(10);
  assert.equal(f.fraudCalls.length, 0, "nothing screened while the burst is still arriving");
  const scam = f.insert({ title: "Designer arc floor lamp, marble base", priceCents: 400n, sellerInfo: "Marketplace seller, new account, 0 ratings" });
  const boom = f.insert({ title: "Boom box shaped novelty floor lamp", priceCents: 5000n });
  await sleep(120);

  assert.deepEqual(f.fraudCalls.map(c => c.dealId).sort(), [1n, 2n, 3n, 4n], "each new deal exactly once, scored row 99 untouched");
  const s = f.fraudCalls.find(c => c.dealId === scam.id)!;
  assert.ok(s.fraudScore >= 0.7, String(s.fraudScore));
  assert.match(s.reasons[0], /below the other deals/);
  // Detector failure: an error event, and the deal is still scored with ai_text_score -1.
  assert.equal(f.fraudCalls.find(c => c.dealId === boom.id)!.aiTextScore, -1);
  assert.ok(f.events.some(e => e.kind === "error" && e.refId === boom.id && /AI-text check failed/.test(e.message)));
  assert.equal(f.events.filter(e => e.kind === "result").length, 4);
  assert.equal(seen.filter(t => t === "HEKTAR floor lamp, dark gray").length, 1);
  // The same IKEA product as row 99 under another URL is a catalog repeat, not a reused listing.
  assert.deepEqual(f.fraudCalls.find(c => c.dealId === 1n), { dealId: 1n, fraudScore: 0, aiTextScore: 0.1, reasons: [] });

  // A late deal for the same item is screened against the earlier ones; nothing else re-runs.
  f.insert({ source: "fb", title: "Lamp", priceCents: 300n });
  await sleep(80);
  assert.equal(f.fraudCalls.length, 5);
  assert.equal(f.fraudCalls[4].aiTextScore, -1, "titles under FRAUD_AI_TEXT_MIN_CHARS are not sent");
  assert.ok(!seen.includes("Lamp"));
  setAiTextDetector(null);
});

test("fraud agent: set_deal_fraud is retried 3 times, then logs one error and leaves the deal for the next pass", async () => {
  setAiTextDetector(null);
  const f = fakeConn({ failFraudFor: 1n });
  await fraudAgent.start(f.conn);
  const d = f.insert();
  await sleep(120);
  assert.equal(f.fraudCalls.length, 3);
  const errors = f.events.filter(e => e.kind === "error" && e.refId === d.id);
  assert.equal(errors.length, 1, "one error event, on the final failure only");
  assert.match(errors[0].message, /Fraud screen failed.*after 3 tries/);
  assert.equal(f.deals.get(d.id)!.fraudScore, -1);
  assert.ok(!f.events.some(e => e.kind === "result" && e.refId === d.id));
});

test("fraud agent: a set_deal_fraud that fails once is retried and the deal gets scored", async () => {
  setAiTextDetector(null);
  const f = fakeConn({ failFraudFor: 1n, failTimes: 1 });
  await fraudAgent.start(f.conn);
  const d = f.insert();
  await sleep(120);
  assert.equal(f.fraudCalls.length, 2);
  assert.notEqual(f.deals.get(d.id)!.fraudScore, -1);
  assert.ok(!f.events.some(e => e.kind === "error" && e.refId === d.id));
  assert.equal(f.events.filter(e => e.kind === "result" && e.refId === d.id).length, 1);
});
