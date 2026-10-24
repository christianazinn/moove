// #17 follow-up: checks for the holes found in the security pass over everything merged after #38.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { resetHomesBudget, seedHomesBudget, takePaidCall } from "../src/homes/budget.js";
import { planFromReading, readFloorPlan, type PlanReading } from "../src/homes/floorplanVision.js";
import { importHome, parseListingUrl } from "../src/homes/listing.js";
import { scrapeZillow } from "../src/homes/zillowApify.js";
import { config } from "../src/config.js";
import { falQueueUrl, reconstruct, Sam3dError } from "../src/integrations/sam3d.js";

const quiet = () => {};
const ZURL = "https://www.zillow.com/homedetails/1-Example-St-Austin-TX-78701/1234_zpid/";
const actorRow = { listingAddress: { full: "1 Example St, Austin, TX 78701" }, bedrooms: 1, bathrooms: 1, livingArea: 500 };

function countingActor() {
  let runs = 0;
  const fetchImpl = (async () => {
    runs++;
    await new Promise(r => setTimeout(r, 5));
    return new Response(JSON.stringify([actorRow]), { status: 200 });
  }) as typeof fetch;
  return { fetchImpl, runs: () => runs };
}

const useAll = () => {
  while (takePaidCall());
};

// ---------------------------------------------------------------- homes import spend cap

test("homes budget: at most HOMES_MAX_PAID_CALLS paid steps per window", () => {
  resetHomesBudget();
  const now = Date.now();
  for (let i = 0; i < config.homes.maxPaidCalls; i++) assert.equal(takePaidCall(now), true);
  assert.equal(takePaidCall(now), false);
  // The window slides: an hour past it, slots are free again.
  assert.equal(takePaidCall(now + (config.homes.spendWindowH + 1) * 3600_000), true);
  resetHomesBudget();
});

test("homes budget: restarts re-count paid steps from agent_event", () => {
  const now = Date.now();
  const ev = (detail: unknown, agoMs: number, agent = "homes", kind = "tool_call") => ({
    agent,
    kind,
    dataJson: JSON.stringify({ requestId: "r", detail }),
    createdAt: { toMillis: () => BigInt(now - agoMs) },
  });
  const n = seedHomesBudget(
    [
      ev({ paid: true }, 1000),
      ev({ paid: true }, 2000),
      ev({ paid: true }, (config.homes.spendWindowH + 1) * 3600_000), // too old
      ev({ photos: 3 }, 1000), // not a paid step
      ev({ paid: true }, 1000, "sam3d"), // another agent
      ev({ paid: true }, 1000, "homes", "result"),
    ],
    now
  );
  assert.equal(n, 2);
  resetHomesBudget();
});

test("homes budget: over the cap, the Zillow actor never runs", async () => {
  resetHomesBudget();
  useAll();
  const { fetchImpl, runs } = countingActor();
  const cacheDir = mkdtempSync(path.join(tmpdir(), "zillow-cap-"));
  await assert.rejects(scrapeZillow(ZURL, { token: "t", log: quiet, fetch: fetchImpl, cacheDir }), /budget/);
  assert.equal(runs(), 0);
  resetHomesBudget();
});

test("homes budget: over the cap, no floor-plan vision call", async () => {
  resetHomesBudget();
  useAll();
  let calls = 0;
  const r = await readFloorPlan([{ mediaType: "image/png", data: "AAAA" }], {
    context: { address: null, beds: null, baths: null, sqft: null },
    log: quiet,
    call: async () => {
      calls++;
      throw new Error("should not be called");
    },
  });
  assert.equal(calls, 0);
  assert.equal(r.floorPlan, null);
  assert.match(r.notes.join(" "), /budget/);
  resetHomesBudget();
});

test("the same Zillow link imported twice at once runs the paid actor once", async () => {
  resetHomesBudget();
  const { fetchImpl, runs } = countingActor();
  const cacheDir = mkdtempSync(path.join(tmpdir(), "zillow-dedupe-"));
  const opts = { token: "t", log: quiet, fetch: fetchImpl, cacheDir };
  const [a, b] = await Promise.all([scrapeZillow(ZURL, opts), scrapeZillow(ZURL, opts)]);
  assert.equal(runs(), 1);
  assert.equal(a.address, b.address);
  resetHomesBudget();
});

// ---------------------------------------------------------------- pasted links and plan bounds

test("addresses from a pasted link lose bidi/zero-width characters and tags", async () => {
  const p = parseListingUrl("https://www.zillow.com/homedetails/1-Main-St%E2%80%AE%E2%80%8B%3Cb%3EHi%3C%2Fb%3E-Austin-TX-78701/1_zpid/");
  assert.ok(p.address);
  assert.doesNotMatch(p.address!, /[‮​<>]/);
  const r = await importHome({ address: "1 Main St‮<script>x</script>" }, { log: quiet });
  assert.doesNotMatch(r.address!, /[‮<>]/);
  assert.doesNotMatch(r.name, /[‮<>]/);
});

test("a drawn layout can't scale a room past the 20 m cap", () => {
  const room = (left: number, right: number) => ({
    name: `Room ${left}`,
    kind: "bedroom" as const,
    dimensionLabel: "",
    widthM: 3,
    depthM: 3,
    image: 0,
    box: { left, top: 0.1, right, bottom: 0.12 }, // same scale both ways, so the drawn layout is used
    doors: [],
    windows: [],
  });
  const reading: PlanReading = { isFloorPlan: true, units: "meters", rooms: [room(0, 0.02), room(0.03, 0.05), room(0.06, 0.96)], notes: "" };
  const r = planFromReading(reading);
  for (const x of r.floorPlan?.rooms ?? []) {
    assert.ok(x.widthM <= 20.5 && x.depthM <= 20.5, `${x.name} is ${x.widthM} x ${x.depthM} m`);
  }
});

test("a room's door and window lists are capped", () => {
  const door = { wall: "N" as const, offsetM: 0.5, widthM: 0.8 };
  const reading: PlanReading = {
    isFloorPlan: true,
    units: "meters",
    rooms: [{ name: "Bedroom", kind: "bedroom", dimensionLabel: "", widthM: 4, depthM: 4, image: 0, box: null, doors: Array(500).fill(door), windows: Array(500).fill(door) }],
    notes: "",
  };
  const plan = planFromReading(reading).floorPlan;
  assert.ok(plan);
  assert.ok(plan!.doors.length <= 8 && plan!.windows.length <= 8, `${plan!.doors.length} doors, ${plan!.windows.length} windows`);
});

// ---------------------------------------------------------------- SAM 3D: FAL_KEY stays on fal.run

test("falQueueUrl: only https on fal.run", () => {
  assert.equal(falQueueUrl("https://queue.fal.run/fal-ai/x/requests/1/status"), "https://queue.fal.run/fal-ai/x/requests/1/status");
  for (const u of ["https://evil.test/status", "http://queue.fal.run/s", "https://fal.run.evil.test/s", "https://a@queue.fal.run/s", "nope", undefined]) {
    assert.throws(() => falQueueUrl(u), Sam3dError, String(u));
  }
});

test("reconstruct never sends the fal key to a status URL off fal.run", async () => {
  const seen: string[] = [];
  const f = (async (url: string | URL) => {
    seen.push(String(url));
    if (String(url).startsWith("https://queue.fal.run/")) {
      return new Response(JSON.stringify({ request_id: "r1", status_url: "https://evil.test/status", response_url: "https://evil.test/result" }));
    }
    return new Response(JSON.stringify({ status: "COMPLETED" }));
  }) as typeof fetch;
  await assert.rejects(reconstruct({ imageUrl: "data:image/jpeg;base64,AAAA", prompt: "chair" }, { key: "k", fetch: f, pollMs: 1 }), Sam3dError);
  assert.deepEqual(seen.filter(u => u.includes("evil.test")), []);
});
