import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Item } from "../src/module_bindings/types.js";

// A rename (vision after a new photo, the sweep, the user) must never leave an item priced under its
// old name, and a catch-all name vision couldn't fix must not leave it "pricing..." forever.
process.env.PRICING_CONCURRENCY = "1";
process.env.PRICING_COMP_FILTER = "0";
process.env.PRICING_PRIOR = "0"; // no live Claude price guesses in tests
const { pricingAgent, setCompsSource } = await import("../src/agents/pricing.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => "owner" };
const comps = (p: number) => [p, p, p].map(c => ({ source: "ebay", title: "x", priceCents: c, url: "u" }));

function fakeConn(items: Partial<Item>[]) {
  const rows = new Map<bigint, Item>();
  for (const o of items) {
    rows.set(o.id!, { owner, name: "", category: "chair", brand: "", condition: "good", photoUrls: [], detailsStatus: "done", pricingStatus: "pending", ...o } as unknown as Item);
  }
  const updates: ((ctx: unknown, old: Item, it: Item) => void)[] = [];
  const events: { message: string; refId?: bigint }[] = [];
  const priced: { itemId: bigint; estValueCents: bigint }[] = [];
  const added: { itemId: bigint; comps: unknown[] }[] = [];
  const set = (id: bigint, patch: Partial<Item>) => {
    const old = rows.get(id);
    if (!old) return;
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
    // Like SpacetimeDB, a reducer's row update reaches the client later, not inside the call.
    reducers: {
      setItemStage: async (a: { itemId: bigint; stage: string }) => setImmediate(() => set(a.itemId, { pricingStatus: a.stage })),
      setEstValue: async (a: { itemId: bigint; estValueCents: bigint }) => {
        priced.push(a);
        setImmediate(() => set(a.itemId, { pricingStatus: "done", estValueCents: a.estValueCents } as Partial<Item>));
      },
      addComps: async (a: { itemId: bigint; comps: unknown[] }) => void added.push(a),
      logAgentEvent: async (e: { message: string; refId?: bigint }) => void events.push(e),
    },
  };
  return { conn: conn as unknown as Conn, rows, set, events, priced, added };
}

test("a done item renamed later (vision after a new photo) is priced again under the new name", async () => {
  const queries: string[] = [];
  setCompsSource(async q => {
    queries.push(q);
    return { comps: comps(q === "chair" ? 2000 : 9000), replayed: true };
  });
  const f = fakeConn([{ id: 1n, name: "chair" }]);
  pricingAgent.start(f.conn);
  await sleep(150);
  assert.equal(f.rows.get(1n)!.estValueCents, 2000n);
  f.set(1n, { name: "black mesh office chair" });
  await sleep(150);
  assert.deepEqual(queries, ["chair", "black mesh office chair"]);
  assert.equal(f.rows.get(1n)!.pricingStatus, "done");
  assert.equal(f.rows.get(1n)!.estValueCents, 9000n);
  assert.ok(f.events.some(e => /^Name changed, re-pricing/.test(e.message)));
  // An update that doesn't change the query (condition, a stage) never re-prices.
  f.set(1n, { condition: "fair" });
  await sleep(150);
  assert.equal(queries.length, 2);
});

test("a rename during the lookup drops the old query's comps and price, then re-prices", async () => {
  const queries: string[] = [];
  let f!: ReturnType<typeof fakeConn>;
  setCompsSource(async q => {
    queries.push(q);
    // the sweep renames the item while its comps are being fetched
    if (q === "table") f.set(2n, { name: "round walnut dining table" });
    await sleep(5);
    return { comps: comps(q === "table" ? 3000 : 12000), replayed: true };
  });
  f = fakeConn([{ id: 2n, name: "table", category: "table" }]);
  pricingAgent.start(f.conn);
  await sleep(300);
  assert.deepEqual(queries, ["table", "round walnut dining table"]);
  assert.deepEqual(f.priced.map(p => p.estValueCents), [12000n], "never priced from the old query");
  assert.equal(f.added.length, 1, "the old query's comps were not written");
  assert.equal(f.rows.get(2n)!.pricingStatus, "done");
  assert.ok(f.events.some(e => /while pricing "table": dropped those comps, re-pricing/.test(e.message)));
});

test("a queued item is priced as it is now: renamed rows under the new name, deleted rows not at all", async () => {
  const queries: string[] = [];
  setCompsSource(async q => {
    queries.push(q);
    await sleep(10);
    return { comps: comps(4000), replayed: true };
  });
  const f = fakeConn([{ id: 3n, name: "lamp" }, { id: 4n, name: "desk" }, { id: 5n, name: "bike" }]);
  pricingAgent.start(f.conn); // concurrency 1: "lamp" runs, the others wait
  f.rows.set(4n, { ...f.rows.get(4n)!, name: "standing desk" }); // renamed in the DB while queued
  f.rows.delete(5n); // deleted while queued
  await sleep(300);
  assert.deepEqual(queries, ["lamp", "standing desk"]);
});

test("a catch-all name vision couldn't fix is marked failed (once), and a rename prices it", async () => {
  const queries: string[] = [];
  setCompsSource(async q => {
    queries.push(q);
    return { comps: comps(5000), replayed: true };
  });
  const f = fakeConn([{ id: 6n, name: "storage", category: "storage", detailsStatus: "failed" }, { id: 7n, name: "other", category: "other", detailsStatus: "pending", photoUrls: ["https://x/a.jpg"] }]);
  pricingAgent.start(f.conn);
  await sleep(150);
  assert.equal(f.rows.get(6n)!.pricingStatus, "failed");
  assert.equal(f.events.filter(e => e.refId === 6n && /too generic/.test(e.message)).length, 1);
  // vision hasn't run yet on item 7: still waiting for a name
  assert.equal(f.rows.get(7n)!.pricingStatus, "pending");
  f.set(6n, { name: "white IKEA Kallax shelf" });
  await sleep(150);
  assert.deepEqual(queries, ["white IKEA Kallax shelf"]);
  assert.equal(f.rows.get(6n)!.pricingStatus, "done");
});
