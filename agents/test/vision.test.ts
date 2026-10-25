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

const details = { name: "black mesh office chair", category: "chair", material: "black mesh", brand: "", condition: "good" as const, fragile: false, maybeSentimental: false, notes: "", identifyConfidence: "low" as const, closeupHint: "" };

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
      setItemIdentify: async (a: Record<string, unknown>) => void calls.push({ name: "setItemIdentify", args: a }),
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
  assert.deepEqual(calls.map(c => c.name), ["setItemStage", "setItemDetails", "setItemIdentify"]);
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

test("writes vision's confidence and close-up hint (#276)", async () => {
  setVisionDeps({
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async () => ({ ...details, name: "Apple MacBook Pro", brand: "Apple", identifyConfidence: "medium" as const, closeupHint: "model number on the bottom case" }),
  });
  const { conn, calls } = fakeConn([item({ id: 9n })]);
  visionAgent.start(conn);
  await sleep(30);
  const id = calls.find(c => c.name === "setItemIdentify");
  assert.deepEqual(id?.args, { itemId: 9n, confidence: "medium", closeupHint: "model number on the bottom case" });
});

test("a module without set_item_identify still gets the details", async () => {
  setVisionDeps({ load: async u => ({ mediaType: "image/jpeg", data: u }), call: async () => details });
  const { conn, calls, events } = fakeConn([item({ id: 10n })]);
  (conn.reducers as unknown as Record<string, unknown>).setItemIdentify = async () => { throw new Error("no such reducer"); };
  visionAgent.start(conn);
  await sleep(30);
  assert.ok(calls.some(c => c.name === "setItemDetails"));
  assert.equal(events.at(-1)!.kind, "result");
});

// #292: Google Lens refinement for unsure items where the model matters.
const laptopFirst = { ...details, name: "silver laptop", category: "electronics", identifyConfidence: "low" as const, closeupHint: "model number on the bottom" };
const laptopBox = { category: "other", widthM: 0.32, heightM: 0.02, depthM: 0.22 };
const lensMatches = { matches: [{ title: "Apple MacBook Pro 14-inch M1 Pro 2021", source: "eBay", price: "$849.00" }], replayed: false, costUsd: 0.02 };

test("an unsure laptop gets a Google Lens look and a sharper name", async () => {
  const prompts: string[] = [];
  setVisionDeps({
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async o => {
      prompts.push(o.text);
      return prompts.length === 1 ? laptopFirst : { ...laptopFirst, name: "Apple MacBook Pro 14-inch M1 Pro (2021)", brand: "Apple", identifyConfidence: "high" as const, closeupHint: "", fragile: false };
    },
    lens: async () => lensMatches,
  });
  const { conn, calls, events } = fakeConn([item({ id: 20n, photoUrls: ["https://t.trycloudflare.com/files/l.jpg"], ...laptopBox })]);
  visionAgent.start(conn);
  await sleep(30);
  assert.equal(prompts.length, 2);
  assert.match(prompts[1], /<untrusted kind="lens-matches">[\s\S]*MacBook Pro 14-inch M1 Pro 2021 \| eBay \| \$849\.00/);
  const det = calls.find(c => c.name === "setItemDetails")!;
  assert.equal(det.args.name, "Apple MacBook Pro 14-inch M1 Pro (2021)");
  assert.equal(det.args.brand, "Apple");
  assert.equal(calls.find(c => c.name === "setItemIdentify")!.args.confidence, "high");
  assert.ok(events.some(e => e.kind === "tool_call" && /Google Lens/.test(e.message)));
});

test("no Lens for sure answers, generic furniture or LAN photos", async () => {
  for (const [first, url] of [
    [{ ...laptopFirst, identifyConfidence: "high" as const }, "https://t.trycloudflare.com/files/a.jpg"],
    [details, "https://t.trycloudflare.com/files/a.jpg"],
    [laptopFirst, "http://192.168.1.5:8787/files/a.jpg"],
  ] as const) {
    let lensCalls = 0;
    setVisionDeps({ load: async u => ({ mediaType: "image/jpeg", data: u }), call: async () => first, lens: async () => { lensCalls++; return lensMatches; } });
    const { conn } = fakeConn([item({ id: 21n, photoUrls: [url] })]);
    visionAgent.start(conn);
    await sleep(30);
    assert.equal(lensCalls, 0, `${first.name} ${url}`);
  }
});

test("a Lens failure, an empty result or the cap keeps the first answer", async () => {
  for (const lens of [
    async () => { throw new Error("apify 502"); },
    async () => ({ matches: [], replayed: false, costUsd: 0.02 }),
    async () => ({ matches: [], replayed: false, costUsd: 0, refused: true }),
  ]) {
    let modelCalls = 0;
    setVisionDeps({ load: async u => ({ mediaType: "image/jpeg", data: u }), call: async () => { modelCalls++; return laptopFirst; }, lens });
    const { conn, calls } = fakeConn([item({ id: 22n, photoUrls: ["https://t.trycloudflare.com/files/l.jpg"], ...laptopBox })]);
    visionAgent.start(conn);
    await sleep(30);
    assert.equal(modelCalls, 1);
    assert.equal(calls.find(c => c.name === "setItemDetails")?.args.name, "silver laptop");
  }
});

test("Apify out of credit skips Lens with a plain result event, not an error", async () => {
  setVisionDeps({
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async () => laptopFirst,
    lens: async () => ({ matches: [], replayed: false, costUsd: 0, refused: true, reason: "Apify unavailable (out of credit)" }),
  });
  const { conn, calls, events } = fakeConn([item({ id: 23n, photoUrls: ["https://t.trycloudflare.com/files/l.jpg"], ...laptopBox })]);
  visionAgent.start(conn);
  await sleep(30);
  assert.equal(calls.find(c => c.name === "setItemDetails")?.args.name, "silver laptop");
  assert.ok(events.some(e => e.kind === "result" && e.message === "Skipped the Google Lens search: Apify unavailable (out of credit)"));
  assert.equal(events.filter(e => e.kind === "error").length, 0);
});

test("the second look never clears fragile or sentimental", async () => {
  let n = 0;
  setVisionDeps({
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async () => (++n === 1 ? { ...laptopFirst, fragile: true, maybeSentimental: true } : { ...laptopFirst, fragile: false, maybeSentimental: false }),
    lens: async () => lensMatches,
  });
  const { conn, calls } = fakeConn([item({ id: 23n, photoUrls: ["https://t.trycloudflare.com/files/l.jpg"], ...laptopBox })]);
  visionAgent.start(conn);
  await sleep(30);
  const det = calls.find(c => c.name === "setItemDetails")!;
  assert.equal(det.args.fragile, true);
  assert.equal(det.args.maybeSentimental, true);
});
