import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { estimate, queryFor } from "../src/agents/pricing.js";
import type { Item } from "../src/module_bindings/types.js";
import { pricePrior } from "../src/agents/price-prior.js";
import type { Comp } from "../src/integrations/apify.js";

const comps = (...usd: number[]): Comp[] => usd.map((d, i) => ({ source: "ebay", title: `c${i}`, priceCents: d * 100, url: `https://x/${i}` }));
const it = { name: "Mesh office chair", brand: "", category: "chair", material: "", condition: "", widthM: 0, heightM: 0, depthM: 0 };
const tmpCache = () => path.join(mkdtempSync(path.join(tmpdir(), "price-prior-")), "q.prior.json");

test("without a prior the estimate is the plain comps median, as before", () => {
  assert.deepEqual(estimate(comps(10, 20, 30, 40, 50), ""), { est: 3000, low: 2000, high: 4000, n: 5, fromPrior: false });
});

test("the prior counts as PRIOR_WEIGHT comps: it dominates few comps and fades with many", () => {
  // 1 comp at $20, prior $80, k = 3 -> (20 + 3*80) / 4 = $65
  assert.equal(estimate(comps(20), "", { priorCents: 8000, priorWeight: 3 })!.est, 6500);
  // 15 comps at $20 -> (15*20 + 3*80) / 18 = $30
  assert.equal(estimate(comps(...Array(15).fill(20)), "", { priorCents: 8000, priorWeight: 3 })!.est, 3000);
});

test("no comps: the prior alone with a wide range; no comps and no prior: null", () => {
  assert.deepEqual(estimate([], "", { priorCents: 5000 }), { est: 5000, low: 3000, high: 7000, n: 0, fromPrior: true });
  assert.equal(estimate([], ""), null);
});

test("condition scales the blended estimate", () => {
  assert.equal(estimate(comps(100), "poor", { priorCents: 10_000 })!.est, 5500);
});

test("pricePrior caches Claude's answer and replays it without calling again", async () => {
  const cacheFile = tmpCache();
  let calls = 0;
  const judge = async () => (calls++, { newRetailUsd: 200, usedUsd: 60, reason: "generic mesh task chair" });
  assert.deepEqual(await pricePrior(it, { cacheFile, judge, enabled: true }), { status: "ok", cents: 6000, reason: "generic mesh task chair" });
  assert.deepEqual(await pricePrior(it, { cacheFile, judge, enabled: true }), { status: "cached", cents: 6000, reason: "generic mesh task chair" });
  assert.equal(calls, 1);
  assert.ok(readFileSync(cacheFile, "utf8").includes("Mesh office chair"));
});

test("pricePrior: a used price above new is capped at new; nonsense and errors are failures, never a price", async () => {
  const capped = await pricePrior(it, { cacheFile: null, enabled: true, judge: async () => ({ newRetailUsd: 50, usedUsd: 90, reason: "" }) });
  assert.equal(capped.status === "ok" && capped.cents, 5000);
  assert.equal((await pricePrior(it, { cacheFile: null, enabled: true, judge: async () => ({ newRetailUsd: 0, usedUsd: 0, reason: "" }) })).status, "failed");
  assert.equal((await pricePrior(it, { cacheFile: null, enabled: true, judge: async () => { throw new Error("SpendCapError"); } })).status, "failed");
});

test("pricePrior is off with PRICING_PRIOR=0 and never calls Claude in cacheOnly mode", async () => {
  const judge = async () => assert.fail("must not call Claude");
  assert.equal((await pricePrior(it, { enabled: false, judge })).status, "off");
  assert.equal((await pricePrior(it, { cacheFile: tmpCache(), cacheOnly: true, enabled: true, judge })).status, "missing");
});

test("the median of an even number of comps is the midpoint", () => {
  assert.equal(estimate(comps(60, 160), "")!.est, 11000);
});

test("queryFor doesn't repeat a brand the name already has", () => {
  assert.equal(queryFor({ brand: "EIZO", name: "EIZO 23-inch monitor", category: "electronics" } as Item), "EIZO 23-inch monitor");
  assert.equal(queryFor({ brand: "IKEA", name: "Kallax shelf", category: "storage" } as Item), "IKEA Kallax shelf");
});
