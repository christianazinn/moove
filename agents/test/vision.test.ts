import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Item } from "../src/module_bindings/types.js";

// The vision agent (#5) against a fake connection: who gets identified, what gets written, the
// failure paths, and the concurrency cap. Own file so VISION_CONCURRENCY is set before import.
process.env.VISION_CONCURRENCY = "2";
const { visionAgent, needsVision, setVisionDeps } = await import("../src/agents/vision.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => "owner" };
const item = (o: Partial<Item>): Item =>
  ({ id: 1n, owner, name: "chair", category: "chair", widthM: 0.6, heightM: 1, depthM: 0.6, photoUrls: ["https://w/files/a.jpg"], detailsStatus: "pending", ...o }) as unknown as Item;

const details = { name: "black mesh office chair", category: "chair", material: "black mesh", brand: "", condition: "good" as const, fragile: false, maybeSentimental: false, notes: "" };

function fakeConn(rows: Item[]) {
  const byId = new Map(rows.map(r => [r.id, r]));
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const events: { kind: string; message: string }[] = [];
  const conn = {
    db: {
      item: {
        iter: () => [...byId.values()].values(),
        id: { find: (id: bigint) => byId.get(id) },
        onInsert: () => {},
        onUpdate: () => {},
      },
    },
    reducers: {
      setItemStage: async (a: Record<string, unknown>) => void calls.push({ name: "setItemStage", args: a }),
      setItemDetails: async (a: Record<string, unknown>) => void calls.push({ name: "setItemDetails", args: a }),
      logAgentEvent: async (e: { kind: string; message: string }) => void events.push(e),
    },
  };
  return { conn: conn as unknown as Conn, calls, events };
}

test("only pending items with a photo need vision", () => {
  assert.equal(needsVision(item({})), true);
  assert.equal(needsVision(item({ photoUrls: [] })), false);
  assert.equal(needsVision(item({ detailsStatus: "done" })), false);
  assert.equal(needsVision(item({ detailsStatus: "failed" })), false);
});

test("identifies an item, skipping photos that fail to load", async () => {
  let sentImages = -1;
  setVisionDeps({
    load: async url => {
      if (url.endsWith("bad.jpg")) throw new Error("404");
      return { mediaType: "image/jpeg", data: url };
    },
    call: async o => {
      sentImages = o.images.length;
      assert.match(o.text, /category "chair", 0\.60 x 0\.60 x 1\.00 m/);
      return details;
    },
  });
  const { conn, calls, events } = fakeConn([item({ photoUrls: ["https://w/files/bad.jpg", "https://w/files/a.jpg"] })]);
  visionAgent.start(conn);
  await sleep(30);
  assert.equal(sentImages, 1);
  assert.deepEqual(calls.map(c => c.name), ["setItemStage", "setItemDetails"]);
  assert.equal(calls[0].args.stage, "running");
  assert.equal(calls[1].args.name, "black mesh office chair");
  assert.equal(events.at(-1)!.kind, "result");
});

test("no loadable photo or a model error marks details failed and logs why", async () => {
  for (const d of [
    { load: async () => { throw new Error("host not allowed"); }, call: async () => details },
    { load: async (u: string) => ({ mediaType: "image/jpeg" as const, data: u }), call: async () => { throw new Error("declined"); } },
  ]) {
    setVisionDeps(d);
    const { conn, calls, events } = fakeConn([item({ id: 7n })]);
    visionAgent.start(conn);
    await sleep(30);
    assert.equal(calls.at(-1)!.args.stage, "failed");
    assert.equal(events.at(-1)!.kind, "error");
    assert.match(events.at(-1)!.message, /host not allowed|declined/);
  }
});

test("at most VISION_CONCURRENCY identifications run at once", async () => {
  let active = 0;
  let peak = 0;
  setVisionDeps({
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async () => {
      active++;
      peak = Math.max(peak, active);
      await sleep(10);
      active--;
      return details;
    },
  });
  const rows = Array.from({ length: 7 }, (_, i) => item({ id: BigInt(100 + i) }));
  const { conn, calls } = fakeConn(rows);
  visionAgent.start(conn);
  await sleep(150);
  assert.equal(peak, 2);
  assert.equal(calls.filter(c => c.name === "setItemDetails").length, 7);
});
