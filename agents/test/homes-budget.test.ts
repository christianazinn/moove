import { test } from "node:test";
import assert from "node:assert/strict";

// Homes import spend cap (#150 review follow-up). Own file so the env is set before config.ts reads it:
// a non-numeric HOMES_MAX_PAID_CALLS used to become NaN, and NaN meant no cap at all.
process.env.HOMES_MAX_PAID_CALLS = "30x";
process.env.HOMES_SPEND_WINDOW_H = "soon";
const warnings: string[] = [];
const realWarn = console.warn;
console.warn = (...a: unknown[]) => void warnings.push(a.map(String).join(" "));
const { config } = await import("../src/config.js");
console.warn = realWarn;
const { numberFromEnv, resetCapWarnings } = await import("../src/integrations/caps.js");
const { resetHomesBudget, seedHomesBudget, takePaidCall, OverCapError } = await import("../src/homes/budget.js");
const { readFloorPlan } = await import("../src/homes/floorplanVision.js");
const { findFloorPlanInPhotos } = await import("../src/homes/floorplanFinder.js");

const useAll = () => {
  while (takePaidCall());
};

test("a non-numeric HOMES_MAX_PAID_CALLS / HOMES_SPEND_WINDOW_H warns and uses the defaults (30 per 24 h)", () => {
  assert.equal(config.homes.maxPaidCalls, 30);
  assert.equal(config.homes.spendWindowH, 24);
  assert.ok(warnings.some(w => /WARNING: HOMES_MAX_PAID_CALLS="30x" is not a number >= 0; using the default 30/.test(w)), warnings.join("\n"));
  assert.ok(warnings.some(w => /HOMES_SPEND_WINDOW_H="soon" is not a number > 0; using the default 24/.test(w)));
  // So the cap really holds: the 31st paid step in a window is refused.
  resetHomesBudget();
  const now = Date.now();
  for (let i = 0; i < 30; i++) assert.equal(takePaidCall(now), true);
  assert.equal(takePaidCall(now), false);
  resetHomesBudget();
});

test("numberFromEnv: valid values pass, unset/empty is the default, NaN/Infinity/out of range warn once", () => {
  resetCapWarnings();
  const msgs: string[] = [];
  const w = (m: string) => void msgs.push(m);
  assert.equal(numberFromEnv("12", "HOMES_MAX_PAID_CALLS", 30, { min: 0 }, w), 12);
  assert.equal(numberFromEnv("0", "HOMES_MAX_PAID_CALLS", 30, { min: 0 }, w), 0, "0 = no paid import steps");
  assert.equal(numberFromEnv(undefined, "HOMES_MAX_PAID_CALLS", 30, { min: 0 }, w), 30);
  assert.equal(numberFromEnv(" ", "HOMES_MAX_PAID_CALLS", 30, { min: 0 }, w), 30);
  assert.equal(msgs.length, 0);
  for (const bad of ["abc", "NaN", "Infinity", "-1"]) assert.equal(numberFromEnv(bad, "HOMES_MAX_PAID_CALLS", 30, { min: 0 }, w), 30, bad);
  assert.equal(numberFromEnv("0", "HOMES_SPEND_WINDOW_H", 24, { above: 0 }, w), 24, "a 0 h window would drop every stamp (no cap)");
  assert.equal(msgs.length, 5);
  numberFromEnv("abc", "HOMES_MAX_PAID_CALLS", 30, { min: 0 }, w);
  assert.equal(msgs.length, 5, "same bad value warned once");
});

const img = { mediaType: "image/png" as const, data: "AAAA" };
const ctx = { address: null, beds: null, baths: null, sqft: null };
const reading = { rooms: [], notes: "" } as never;

test("a floor-plan read answered from LLM_REPLAY takes no slot, works over the cap and logs paid: false", async () => {
  resetHomesBudget();
  useAll();
  const logs: { kind: string; message: string; data?: { paid?: boolean; replayed?: boolean } }[] = [];
  let calls = 0;
  await readFloorPlan([img], {
    context: ctx,
    log: (kind, message, data) => void logs.push({ kind, message, data: data as never }),
    isRecorded: () => true,
    call: async () => (calls++, reading),
  });
  assert.equal(calls, 1, "a replay still runs over the cap (it costs nothing)");
  const tc = logs.find(l => l.kind === "tool_call")!;
  assert.match(tc.message, /^\[REPLAYED\]/);
  assert.equal(tc.data?.paid, false);
  assert.equal(tc.data?.replayed, true);

  // Under the cap, a replay leaves every slot free; a live read takes one.
  resetHomesBudget();
  await readFloorPlan([img], { context: ctx, log: () => {}, isRecorded: () => true, call: async () => reading });
  let free = 0;
  while (takePaidCall()) free++;
  assert.equal(free, config.homes.maxPaidCalls);
  resetHomesBudget();
  const live: typeof logs = [];
  await readFloorPlan([img], { context: ctx, log: (kind, message, data) => void live.push({ kind, message, data: data as never }), isRecorded: () => false, call: async () => reading });
  assert.equal(live.find(l => l.kind === "tool_call")!.data?.paid, true);
  free = 0;
  while (takePaidCall()) free++;
  assert.equal(free, config.homes.maxPaidCalls - 1);
  resetHomesBudget();
});

test("replayed steps aren't re-counted on restart (seed only counts paid: true)", () => {
  const now = Date.now();
  const ev = (detail: unknown) => ({ agent: "homes", kind: "tool_call", dataJson: JSON.stringify({ requestId: "r", detail }), createdAt: { toMillis: () => BigInt(now - 1000) } });
  assert.equal(seedHomesBudget([ev({ paid: true }), ev({ paid: false, replayed: true }), ev({ paid: false, replayed: true })], now), 1);
  resetHomesBudget();
});

test("listing-photo classifier: a recorded answer runs over the cap for free, a live one is refused with OverCapError", async () => {
  const photos = [{ url: "https://photos.zillowstatic.com/fp/a.jpg", thumb: null, caption: null }];
  const verdicts = { images: [{ index: 0, floorPlan: true, confidence: 0.9 }] };
  const loadImage = async () => img;
  resetHomesBudget();
  useAll();
  const logs: { kind: string; data?: { paid?: boolean } }[] = [];
  let classified = 0;
  const r = await findFloorPlanInPhotos(photos, {
    log: (kind, _m, data) => void logs.push({ kind, data: data as never }),
    loadImage,
    isRecorded: () => true,
    classify: async () => (classified++, verdicts),
  });
  assert.equal(classified, 1);
  assert.equal(r.images.length, 1);
  assert.equal(logs.find(l => l.kind === "tool_call")!.data?.paid, false);

  await assert.rejects(
    findFloorPlanInPhotos(photos, { log: () => {}, loadImage, isRecorded: () => false, classify: async () => (classified++, verdicts) }),
    (e: unknown) => e instanceof OverCapError
  );
  assert.equal(classified, 1, "over the cap, no live classifier call");
  resetHomesBudget();
});
