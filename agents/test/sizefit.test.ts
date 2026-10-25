import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { Item, Scan, ScanPhoto } from "../src/module_bindings/types.js";

// Size checks on agent renames and sweep finds (#267): pure functions, then the sweep and vision
// agents against fake connections.
const { kindOf, outOfRange, renameMisfit, scannedTwin, boxText } = await import("../src/sizefit.js");
const { vetSweep, sweep, isBuiltIn } = await import("../src/agents/sweep.js");
const { visionAgent, setVisionDeps } = await import("../src/agents/vision.js");
type SweepResult = import("../src/agents/sweep.js").SweepResult;

const owner = { toHexString: () => "owner" };
const box = (w: number, d: number, h: number) => ({ widthM: w, depthM: d, heightM: h });
const lamp = { name: "lamp", category: "lamp", ...box(0.3, 0.3, 1.5) };

test("kindOf reads the head noun, aliases and plurals", () => {
  assert.equal(kindOf("white throw pillow"), "pillow");
  assert.equal(kindOf("Cushions (set of 2)"), "pillow");
  assert.equal(kindOf("black standing floor lamp"), "lamp");
  assert.equal(kindOf("walnut lamp table"), "table");
  assert.equal(kindOf("TCL 32 inch TV"), "television");
  assert.equal(kindOf("IKEA Kallax shelf"), "bookshelf");
  assert.equal(kindOf("washerDryer"), "washerdryer");
  assert.equal(kindOf("desk with drawers"), "desk");
  assert.equal(kindOf("dining chairs set"), "chair");
  assert.equal(kindOf("books, about 30"), undefined);
  assert.equal(kindOf("other"), undefined);
  assert.equal(kindOf(""), undefined);
});

test("outOfRange mirrors ObjectSanity's bounds with 15% slack", () => {
  assert.equal(outOfRange("table", box(1.05, 0.5, 0.75)), null);
  assert.equal(outOfRange("table", box(1.05, 0.5, 1.38)), null); // 1.2 m + 15%
  assert.match(outOfRange("table", box(1.05, 0.5, 1.4))!, /height is too big/);
  assert.match(outOfRange("pillow", box(0.3, 0.3, 1.5))!, /1\.50 m height is too big/);
  assert.equal(outOfRange("pillow", box(0.5, 0.15, 0.45)), null);
  assert.equal(outOfRange("lamp", box(0.3, 0.3, 1.5)), null);
  assert.equal(outOfRange("guitar", box(0.38, 0.12, 1.02)), null);
  assert.equal(outOfRange("instrument", box(9, 9, 9)), null, "unknown kind: no opinion");
  assert.equal(outOfRange("pillow", box(0, 0, 0)), null, "no measured size: no opinion");
});

test("renameMisfit rejects a tall lamp renamed pillow, allows plausible and same-kind renames", () => {
  const m = renameMisfit(lamp, { name: "pillow", category: "decor" });
  assert.ok(m);
  assert.equal(m!.message, 'Kept "lamp": "pillow" doesn\'t fit a 0.30×0.30×1.50 m box (1.50 m height is too big for a pillow)');
  assert.ok(renameMisfit(lamp, { name: "beige linen cushion", category: "pillow" }));
  assert.equal(renameMisfit(lamp, { name: "black arc floor lamp", category: "lamp" }), null);
  assert.equal(renameMisfit(lamp, { name: "fiddle leaf fig", category: "plant" }), null);
  assert.equal(renameMisfit(lamp, { name: "Yamaha acoustic guitar", category: "instrument" }), null);
  // RoomPlan storage that is really a Kallax shelf or an ottoman
  const storage = { name: "storage", category: "storage" };
  assert.equal(renameMisfit({ ...storage, ...box(0.77, 0.39, 1.47) }, { name: "white IKEA Kallax shelf", category: "storage" }), null);
  assert.equal(renameMisfit({ ...storage, ...box(0.5, 0.5, 0.45) }, { name: "gray tufted ottoman", category: "ottoman" }), null);
  assert.ok(renameMisfit({ ...storage, ...box(0.5, 0.5, 0.45) }, { name: "queen bed", category: "bed" }));
  // a box that already doesn't fit its own kind isn't blocked from keeping that kind
  assert.equal(renameMisfit({ name: "table", category: "table", ...box(1, 0.5, 2) }, { name: "oak table", category: "table" }), null);
});

const it = (id: bigint, name: string, category: string, b: ReturnType<typeof box>, scanObjectId = `rp-${id}`) =>
  ({ id, owner, roomId: 7n, scanId: 5n, scanObjectId, name, category, brand: "", photoUrls: [], ...b }) as unknown as Item;

test("scannedTwin: same kind (or one the scanner confuses) and similar size, scanned items only, once each", () => {
  const items = [
    it(1n, "storage", "storage", box(0.5, 0.5, 0.45)),
    it(2n, "table", "table", box(1.2, 0.6, 0.75)),
    it(3n, "Floor rug", "rug", box(2, 1.5, 0.02), "photo:5"),
    it(4n, "chair", "chair", box(0.6, 0.6, 0.9)),
  ];
  const find = (name: string, category: string, b: ReturnType<typeof box>) => ({ name, category, ...b });
  assert.equal(scannedTwin(find("gray ottoman", "ottoman", box(0.55, 0.5, 0.42)), items, new Set())?.id, 1n);
  assert.equal(scannedTwin(find("oak writing desk", "desk", box(1.1, 0.55, 0.76)), items, new Set())?.id, 2n);
  assert.equal(scannedTwin(find("black floor lamp", "lamp", box(0.3, 0.3, 1.6)), items, new Set()), undefined, "no scanned lamp");
  assert.equal(scannedTwin(find("big dining table", "table", box(2.4, 1.0, 0.75)), items, new Set()), undefined, "too different in size");
  assert.equal(scannedTwin(find("wool rug", "rug", box(2, 1.5, 0.02)), items, new Set()), undefined, "sweep finds aren't scanned items");
  assert.equal(scannedTwin(find("mesh office chair", "chair", box(0.6, 0.6, 1.0)), items, new Set([4n])), undefined, "already explained");
});

const detail = { material: "", brand: "", condition: "good" as const, fragile: false, maybeSentimental: false, photoIndex: 0, confidence: 0.9 };

test("vetSweep: a misfit rename is kept out, a twin of a scanned item isn't added", () => {
  const items = [it(1n, "lamp", "lamp", box(0.3, 0.3, 1.5)), it(2n, "storage", "storage", box(0.5, 0.5, 0.45)), it(3n, "chair", "chair", box(0.6, 0.6, 0.9))];
  const r: SweepResult = {
    matches: [
      { itemId: "1", name: "pillow", category: "decor", ...detail },
      { itemId: "3", name: "black mesh office chair", category: "chair", ...detail },
    ],
    newItems: [
      { name: "gray ottoman", category: "ottoman", ...detail, widthM: 0.55, depthM: 0.5, heightM: 0.42 },
      { name: "second gray ottoman", category: "ottoman", ...detail, widthM: 0.55, depthM: 0.5, heightM: 0.42 },
      { name: "wooden desk chair", category: "chair", ...detail, widthM: 0.55, depthM: 0.55, heightM: 0.9 },
    ],
  };
  const v = vetSweep(r, items, ["https://w/files/a.jpg"]);
  assert.deepEqual(v.matches.map(m => m.item.id), [3n]);
  assert.deepEqual(v.kept.map(k => [k.item.id, k.name]), [[1n, "pillow"]]);
  // the storage box absorbs one ottoman; the chair was matched by name, so a new chair is new
  assert.deepEqual(v.newItems.map(n => n.name), ["second gray ottoman", "wooden desk chair"]);
  assert.deepEqual(v.twins.map(t => [t.name, t.item.id]), [["gray ottoman", 2n]]);
  assert.match(v.twins[0].message, /^Skipped "gray ottoman": the scan already has "storage" \(0\.50×0\.50×0\.45 m\) in this room$/);
});

test("sweep logs the kept name and the skipped twin, and calls neither reducer for them", async () => {
  const items = [it(1n, "lamp", "lamp", box(0.3, 0.3, 1.5)), it(2n, "storage", "storage", box(0.5, 0.5, 0.45))];
  const scan = { id: 5n, owner, roomId: 7n, sweepStatus: "pending" } as unknown as Scan;
  const calls: string[] = [];
  const events: { kind: string; message: string; refTable: string; refId: bigint }[] = [];
  const rec = (n: string) => async () => void calls.push(n);
  const conn = {
    db: {
      item: { iter: () => items.values() },
      scanPhoto: { iter: () => [{ id: 1n, owner, scanId: 5n, url: "https://w/files/a.jpg" } as unknown as ScanPhoto].values() },
    },
    reducers: {
      setSweepStatus: rec("setSweepStatus"),
      applySweepMatch: rec("applySweepMatch"),
      addSweepItem: rec("addSweepItem"),
      logAgentEvent: async (e: (typeof events)[number]) => void events.push(e),
    },
  } as unknown as Conn;
  await sweep(conn, scan, {
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async () => ({
      matches: [{ itemId: "1", name: "pillow", category: "decor", ...detail }],
      newItems: [{ name: "gray ottoman", category: "ottoman", ...detail, widthM: 0.55, depthM: 0.5, heightM: 0.42 }],
    }),
  });
  assert.deepEqual(calls, ["setSweepStatus", "setSweepStatus"]);
  const kept = events.find(e => e.message.startsWith('Kept "lamp"'));
  assert.ok(kept, "kept-name event");
  assert.equal(kept!.refTable, "item");
  assert.equal(kept!.refId, 1n);
  assert.ok(events.some(e => e.message.startsWith('Skipped "gray ottoman"')));
  assert.match(events.at(-1)!.message, /Named 0 scanned object\(s\) and found 0/);
});

test("vision keeps a scanned item's name and category when its answer can't fit the box", async () => {
  const row = { ...it(9n, "lamp", "lamp", box(0.3, 0.3, 1.5)), photoUrls: ["https://w/files/a.jpg"], detailsStatus: "pending" } as unknown as Item;
  const calls: Record<string, unknown>[] = [];
  const events: { kind: string; message: string }[] = [];
  const conn = {
    db: { item: { iter: () => [row].values(), id: { find: () => row }, onInsert: () => {}, onUpdate: () => {} } },
    reducers: {
      setItemStage: async () => {},
      setItemDetails: async (a: Record<string, unknown>) => void calls.push(a),
      logAgentEvent: async (e: { kind: string; message: string }) => void events.push(e),
    },
  } as unknown as Conn;
  setVisionDeps({
    load: async u => ({ mediaType: "image/jpeg", data: u }),
    call: async () => ({ name: "white throw pillow", category: "decor", material: "linen", brand: "", condition: "good", fragile: false, maybeSentimental: false, notes: "", identifyConfidence: "low", closeupHint: "" }),
  });
  visionAgent.start(conn);
  await new Promise(r => setTimeout(r, 30));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "");
  assert.equal(calls[0].category, "");
  assert.equal(calls[0].material, "linen");
  assert.ok(events.some(e => e.message === 'Kept "lamp": "white throw pillow" doesn\'t fit a 0.30×0.30×1.50 m box (1.50 m height is too big for a pillow)'));
});

test("vetSweep: parts of the room aren't inventory (shutters behind Rio's bed came back as an item)", () => {
  const r: SweepResult = {
    matches: [],
    newItems: [
      { name: "white plantation window shutters", category: "decor", ...detail, widthM: 1.2, depthM: 0.05, heightM: 1.5 },
      { name: "wooden door", category: "other", ...detail, widthM: 0.9, depthM: 0.05, heightM: 2.0 },
      { name: "box fan", category: "fan", ...detail, widthM: 0.5, depthM: 0.2, heightM: 0.5 },
      { name: "window fan", category: "fan", ...detail, widthM: 0.6, depthM: 0.2, heightM: 0.4 },
      { name: "shower caddy", category: "decor", ...detail, widthM: 0.3, depthM: 0.15, heightM: 0.6 },
    ],
  };
  const v = vetSweep(r, [], ["https://w/files/a.jpg"]);
  assert.deepEqual(v.newItems.map(n => n.name), ["box fan", "window fan", "shower caddy"]);
  assert.deepEqual(v.builtIns, ["white plantation window shutters", "wooden door"]);
});

test("isBuiltIn: fixtures and window coverings, but not movable things that mention them", () => {
  for (const name of ["vertical blinds", "bay window", "radiator", "light switch", "ceiling light", "fireplace", "built-in bookshelf", "toilet", "bathroom sink", "curtain rod"]) {
    assert.equal(isBuiltIn({ name, category: "other" }), true, name);
  }
  for (const name of ["floor lamp", "wall art", "wall clock", "window AC unit", "door mat", "floor mirror", "plant", "wall-mounted TV", "linen curtains"]) {
    assert.equal(isBuiltIn({ name, category: "decor" }), false, name);
  }
});

test("a scanned \"vacuum\" box can be reclassified as an e-scooter", () => {
  // A real scan: an e-scooter came in as "vacuum" in a ~1.0×0.95×0.66 m box (either axis order).
  for (const b of [box(1.0, 0.95, 0.66), box(1.0, 0.66, 0.95)]) {
    const vacuum = { name: "vacuum", category: "vacuum", ...b };
    for (const name of ["black Segway Ninebot e-scooter", "electric kick scooter", "Xiaomi escooter", "scooter"]) {
      assert.equal(renameMisfit(vacuum, { name, category: "scooter" }), null, `${name} ${boxText(b)}`);
    }
  }
  assert.equal(kindOf("black Segway Ninebot e-scooter"), "scooter");
  assert.equal(kindOf("Xiaomi escooter"), "scooter");
  // Still a size check: a scooter can't be 3 m tall.
  const tall = { name: "vacuum", category: "vacuum", ...box(1.0, 0.95, 3.0) };
  assert.match(renameMisfit(tall, { name: "e-scooter", category: "scooter" })!.message, /too big for a scooter/);
});
