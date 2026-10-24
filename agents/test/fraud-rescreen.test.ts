import { test, mock, afterEach } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Deal } from "../src/module_bindings/types.js";

// Re-screen of deals stuck at fraud_score -1 (a set_deal_fraud that failed all 3 tries used to leave
// the purchase at "Waiting for the fraud screen" until a restart). Fake timers: the sweep runs every
// 60 s and only picks deals unscored for 30 s+. Own file so the env is set before fraud.ts reads it.
process.env.FRAUD_SETTLE_MS = "40";
process.env.FRAUD_RETRY_DELAY_MS = "5";
delete process.env.FRAUD_RESCREEN_MS; // defaults: every 60 s, deals unscored for 30 s+
delete process.env.FRAUD_RESCREEN_AGE_MS;
const { fraudAgent, setAiTextDetector, stopFraudAgent, RESCREEN_MAX_ATTEMPTS, SET_FRAUD_TRIES } = await import("../src/agents/fraud.js");

const owner = { toHexString: () => "owner" };
const flush = () => new Promise(r => setImmediate(r));
/** Moves the fake clock forward in small steps, letting async screens and retries run between. */
async function advance(ms: number, step = 5) {
  for (let t = 0; t < ms; t += step) {
    mock.timers.tick(step);
    await flush();
  }
}

function fakeConn(failTimes: number) {
  const deals = new Map<bigint, Deal>();
  const inserts: ((ctx: unknown, d: Deal) => void)[] = [];
  const updates: ((ctx: unknown, old: Deal, d: Deal) => void)[] = [];
  const events: { kind: string; message: string; refId: bigint }[] = [];
  let calls = 0;
  const conn = {
    db: {
      deal: {
        iter: () => deals.values(),
        onInsert: (cb: (ctx: unknown, d: Deal) => void) => inserts.push(cb),
        onUpdate: (cb: (ctx: unknown, old: Deal, d: Deal) => void) => updates.push(cb),
      },
      shoppingItem: { id: { find: (id: bigint) => ({ id, name: "rescreen lamp no cached comps" }) } },
    },
    reducers: {
      setDealFraud: async (a: { dealId: bigint; fraudScore: number; aiTextScore: number; reasons: string[] }) => {
        if (calls++ < failTimes) throw new Error("SenderError: timeout");
        const old = deals.get(a.dealId)!;
        const d = { ...old, fraudScore: a.fraudScore, aiTextScore: a.aiTextScore, fraudReasons: a.reasons };
        deals.set(d.id, d);
        for (const cb of updates) cb({}, old, d);
      },
      logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e),
    },
  };
  const insert = () => {
    const d = {
      id: 1n,
      owner,
      shoppingItemId: 1n,
      source: "fb",
      title: "Floor lamp, works great",
      priceCents: 1500n,
      url: "https://example.com/item/1",
      sellerInfo: "Marketplace seller, Berkeley (4.8 stars) · good · 1 mi · message seller",
      fraudScore: -1,
      aiTextScore: -1,
      fraudReasons: [],
    } as unknown as Deal;
    deals.set(d.id, d);
    for (const cb of inserts) cb({}, d);
    return d;
  };
  return { conn: conn as unknown as Conn, deals, insert, events, calls: () => calls };
}

afterEach(() => {
  stopFraudAgent();
  mock.timers.reset();
});

test("fraud re-screen: a deal whose first screen failed every try is scored by the 60 s sweep", async () => {
  mock.timers.enable({ apis: ["setTimeout", "setInterval", "Date"] });
  setAiTextDetector(null);
  const f = fakeConn(SET_FRAUD_TRIES); // the first screen's 3 tries all fail, the next one works
  await fraudAgent.start(f.conn);
  const d = f.insert();
  await advance(200);
  assert.equal(f.calls(), SET_FRAUD_TRIES);
  assert.equal(f.deals.get(d.id)!.fraudScore, -1, "stuck after the first screen");

  await advance(59_000);
  assert.equal(f.calls(), SET_FRAUD_TRIES, "nothing more before the sweep");
  await advance(1_200);
  assert.equal(f.calls(), SET_FRAUD_TRIES + 1, "the 60 s sweep re-screened it once");
  assert.notEqual(f.deals.get(d.id)!.fraudScore, -1);
  assert.equal(f.events.filter(e => e.kind === "result" && e.refId === d.id).length, 1);

  // Scored now: later sweeps leave it alone.
  await advance(125_000, 50);
  assert.equal(f.calls(), SET_FRAUD_TRIES + 1);
});

test("fraud re-screen: young deals wait, and a deal that never scores is retried at most 3 times", async () => {
  mock.timers.enable({ apis: ["setTimeout", "setInterval", "Date"] });
  setAiTextDetector(null);
  const f = fakeConn(Infinity);
  await fraudAgent.start(f.conn);
  // Inserted 40 s in: at the 60 s sweep it is only 20 s old (under 30 s), so it waits for the next one.
  await advance(40_000, 100);
  const d = f.insert();
  await advance(200);
  assert.equal(f.calls(), SET_FRAUD_TRIES);
  await advance(20_000, 50);
  assert.equal(f.calls(), SET_FRAUD_TRIES, "too young at the 60 s sweep");
  await advance(60_000, 50);
  assert.equal(f.calls(), 2 * SET_FRAUD_TRIES, "re-screened at the 120 s sweep");

  await advance(10 * 60_000, 100);
  assert.equal(f.calls(), (1 + RESCREEN_MAX_ATTEMPTS) * SET_FRAUD_TRIES, "capped: no endless loop");
  const gaveUp = f.events.filter(e => e.kind === "error" && e.refId === d.id && /gave up/.test(e.message));
  assert.equal(gaveUp.length, 1, "one give-up event");
  assert.equal(f.deals.get(d.id)!.fraudScore, -1);
});

test("fraud re-screen: the sweep timer is unref()'d and cleared by stopFraudAgent", async () => {
  const realSetInterval = globalThis.setInterval;
  let unrefd = false;
  let handle: NodeJS.Timeout | undefined;
  globalThis.setInterval = ((fn: () => void, ms: number) => {
    handle = realSetInterval(fn, ms);
    const unref = handle.unref.bind(handle);
    handle.unref = () => ((unrefd = true), unref());
    return handle;
  }) as typeof setInterval;
  try {
    await fraudAgent.start(fakeConn(0).conn);
  } finally {
    globalThis.setInterval = realSetInterval;
  }
  assert.ok(handle && unrefd);
  assert.equal(handle.hasRef(), false);
  stopFraudAgent();
});

test("fraud re-screen: after stopFraudAgent no sweep runs", async () => {
  mock.timers.enable({ apis: ["setTimeout", "setInterval", "Date"] });
  setAiTextDetector(null);
  const f = fakeConn(Infinity);
  await fraudAgent.start(f.conn);
  f.insert();
  await advance(200);
  assert.equal(f.calls(), SET_FRAUD_TRIES);
  stopFraudAgent();
  await advance(5 * 60_000, 100);
  assert.equal(f.calls(), SET_FRAUD_TRIES);
});
