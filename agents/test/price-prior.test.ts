import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { estimate, queryFor } from "../src/agents/pricing.js";
import type { Item } from "../src/module_bindings/types.js";
import { pricePrior, priorRange, RANGE_Q, type Prior, type PriorJudge } from "../src/agents/price-prior.js";
import type { ImageInput } from "../src/integrations/photos.js";
import type { Comp } from "../src/integrations/apify.js";

const comps = (...usd: number[]): Comp[] => usd.map((d, i) => ({ source: "ebay", title: `c${i}`, priceCents: d * 100, url: `https://x/${i}` }));
const it = { name: "Mesh office chair", brand: "", category: "chair", material: "", condition: "", widthM: 0, heightM: 0, depthM: 0 };
const tmpCache = () => path.join(mkdtempSync(path.join(tmpdir(), "price-prior-")), "q.prior.json");

test("without a prior the estimate is the plain comps median, as before", () => {
  assert.deepEqual(estimate(comps(10, 20, 30, 40, 50), ""), { est: 3000, low: 2000, high: 4000, n: 5, fromPrior: false });
});

const P = (cents: number, lowCents = cents, highCents = cents) => ({ prior: { cents, lowCents, highCents } });
const answer = (p50: number, extra: Partial<Prior> = {}): Prior => ({ identifiedProduct: "generic mesh task chair", itemForm: "full_product", specificity: 0.4, newRetailUsd: 200, p10: p50 / 2, p50, p90: p50 * 2, ...extra });

test("the prior counts as PRIOR_WEIGHT comps: it dominates few comps and fades with many", () => {
  // 1 comp at $20, prior $80, k = 3 -> (20 + 3*80) / 4 = $65
  assert.equal(estimate(comps(20), "", { ...P(8000), priorWeight: 3 })!.est, 6500);
  // 15 comps at $20 -> (15*20 + 3*80) / 18 = $30
  assert.equal(estimate(comps(...Array(15).fill(20)), "", { ...P(8000), priorWeight: 3 })!.est, 3000);
});

test("borrowed comps (a similar item's, Apify down) count as one comp together", () => {
  // 11 comps at $100 vs a $1250 prior, k = 6: own comps (11*100 + 6*1250) / 17 = $506; borrowed (100 + 6*1250) / 7 = $1086
  assert.equal(estimate(comps(...Array(11).fill(100)), "", { ...P(125_000), priorWeight: 6 })!.est, 50_600);
  assert.equal(estimate(comps(...Array(11).fill(100)), "", { ...P(125_000), priorWeight: 6, borrowed: true })!.est, 108_600);
});

test("no comps: the prior alone with its own range; no comps and no prior: null", () => {
  assert.deepEqual(estimate([], "", P(5000, 3000, 8000)), { est: 5000, low: 3000, high: 8000, n: 0, fromPrior: true });
  assert.equal(estimate([], ""), null);
});

test("condition scales the comps but not the prior, which Claude already gave for the condition", () => {
  // comps $100 x 0.55 (poor) = $55, prior $40 for a poor one: (55 + 3*40) / 4 = $43.75 -> $44
  assert.equal(estimate(comps(100), "poor", { ...P(4000), priorWeight: 3 })!.est, 4400);
  assert.equal(estimate([], "poor", P(4000))!.est, 4000);
});

test("priorRange: p50 is the estimate, the range scales with Claude's own p10-p90 spread, floored", () => {
  const wide = priorRange(answer(100, { p10: 25, p90: 400 })); // ln(16) = 2.77 -> half-width 0.36 * 2.77
  assert.equal(wide.cents, 10_000);
  assert.equal(wide.lowCents, Math.round(100 * Math.exp(-RANGE_Q * Math.log(16)) * 100));
  const tight = priorRange(answer(100, { p10: 99, p90: 101 })); // floor 0.3 -> half-width 0.108
  assert.equal(tight.highCents, Math.round(100 * Math.exp(RANGE_Q * 0.3) * 100));
  assert.equal(priorRange(answer(90, { newRetailUsd: 50 })).cents, 5000); // never above new
});

test("pricePrior caches Claude's answer and replays it without calling again", async () => {
  const cacheFile = tmpCache();
  let calls = 0;
  const judge = async () => (calls++, answer(60));
  const first = await pricePrior(it, { cacheFile, judge, enabled: true });
  assert.equal(first.status, "ok");
  assert.equal(first.status === "ok" && first.cents, 6000);
  assert.equal(first.status === "ok" && first.reason, "generic mesh task chair");
  const again = await pricePrior(it, { cacheFile, judge, enabled: true });
  assert.equal(again.status, "cached");
  assert.equal(calls, 1);
  assert.ok(readFileSync(cacheFile, "utf8").includes("Mesh office chair"));
});

test("pricePrior: the photo goes to Claude and is part of the cache key", async () => {
  const cacheFile = tmpCache();
  const seen: (string | undefined)[] = [];
  const judge: PriorJudge = async (_d, photo) => (seen.push(photo?.data), answer(60));
  const photo = { mediaType: "image/jpeg", data: "AAAA" } as ImageInput;
  await pricePrior(it, { cacheFile, judge, enabled: true });
  await pricePrior(it, { cacheFile, judge, enabled: true, photo });
  assert.equal((await pricePrior(it, { cacheFile, judge, enabled: true, photo })).status, "cached");
  assert.deepEqual(seen, [undefined, "AAAA"]);
});

test("pricePrior: an accessory says so in the reason; nonsense and errors are failures, never a price", async () => {
  const acc = await pricePrior(it, { cacheFile: null, enabled: true, judge: async () => answer(15, { identifiedProduct: "iPhone case", itemForm: "case_or_cover" }) });
  assert.equal(acc.status === "ok" && acc.reason, "iPhone case (case or cover)");
  assert.equal((await pricePrior(it, { cacheFile: null, enabled: true, judge: async () => answer(0) })).status, "failed");
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
