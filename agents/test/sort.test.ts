import { test } from "node:test";
import assert from "node:assert/strict";
import { decide, moveCostCents, needsSort, SENTIMENTAL_REASON, type SortGate, type SortInput } from "../src/agents/sort.js";

/** A 0.5 x 0.5 x 0.4 m (0.1 m^3, ~$6 to move) item in good shape, unpriced. */
function item(over: Partial<Omit<SortInput, "estValueCents">> & { est?: number } = {}): SortInput {
  const { est = -1, ...rest } = over;
  return { name: "Side table", category: "furniture", condition: "good", widthM: 0.5, heightM: 0.5, depthM: 0.4, fragile: false, estValueCents: BigInt(est), ...rest };
}

/** Ready to sort: priced, no photos, untouched. */
function gate(over: Partial<SortGate> = {}): SortGate {
  return { disposition: "undecided", dispositionSource: "auto", dispositionReason: "", maybeSentimental: false, pricingStatus: "done", detailsStatus: "pending", photoUrls: [], ...over };
}

// A 2 x 0.9 x 0.9 m sofa is 1.62 m^3, ~$97 to move at $60/m^3.
const sofa = (est: number, over: Partial<SortInput> = {}) =>
  item({ name: "Sofa", category: "sofa", widthM: 2, heightM: 0.9, depthM: 0.9, est, ...over });

test("moving cost: volume x rate, a minimum per item, more for fragile", () => {
  assert.equal(moveCostCents(sofa(0)), 9720);
  assert.equal(moveCostCents(item({ widthM: 0.1, heightM: 0.1, depthM: 0.1 })), 200);
  assert.equal(moveCostCents(item({ widthM: 0, heightM: 0, depthM: 0 })), 200);
  assert.equal(moveCostCents(sofa(0, { fragile: true })), 14580);
});

test("worth less than the move but worth listing: sell, with the numbers", () => {
  assert.deepEqual(decide(sofa(5000)), { disposition: "sell", reason: "Worth ~$50 but ~$97 to move: sell" });
});

test("worth less than the move and too cheap to list: donate", () => {
  assert.deepEqual(decide(sofa(1500)), { disposition: "donate", reason: "Worth ~$15 but ~$97 to move: donate" });
});

test("just over the move cost: barely worth it, sell", () => {
  assert.equal(decide(sofa(11000)).disposition, "sell");
  assert.match(decide(sofa(11000)).reason, /~\$110, ~\$97 to move: barely worth moving/);
});

test("worth well over the move: keep", () => {
  assert.deepEqual(decide(sofa(40000)), { disposition: "keep", reason: "Worth ~$400, ~$97 to move: keep" });
});

test("small high-value electronics: keep; fragile is called out", () => {
  const d = decide(item({ name: "Monitor", category: "electronics", fragile: true, est: 15000 }));
  assert.deepEqual(d, { disposition: "keep", reason: "Worth ~$150, ~$9 to move (fragile): keep" });
});

test("fragile packing cost can tip a sofa from keep to sell", () => {
  assert.equal(decide(sofa(12500)).disposition, "keep");
  assert.equal(decide(sofa(12500, { fragile: true })).disposition, "sell");
});

test("poor condition: trash when cheap or unpriced, sell when still worth something", () => {
  assert.deepEqual(decide(item({ condition: "poor", est: 800 })), { disposition: "trash", reason: "Poor shape and worth only ~$8: trash" });
  assert.deepEqual(decide(item({ condition: "poor" })), { disposition: "trash", reason: "Poor shape and no resale value: trash" });
  assert.deepEqual(decide(item({ condition: "poor", est: 6000 })), { disposition: "sell", reason: "Poor shape but worth ~$60: sell as-is" });
});

test("planet-first: usable cheap items are donated, never trashed", () => {
  for (const condition of ["new", "like_new", "good", "fair", ""]) {
    assert.notEqual(decide(sofa(500, { condition })).disposition, "trash");
    assert.notEqual(decide(item({ condition, est: 100 })).disposition, "trash");
  }
});

test("beds and mattresses: keep (they rarely resell) unless in poor shape", () => {
  const bed = { name: "Queen mattress", category: "bed", widthM: 1.5, heightM: 0.3, depthM: 2 };
  assert.deepEqual(decide(item({ ...bed, est: 5000 })), { disposition: "keep", reason: "Beds rarely resell (~$50); ~$54 to move: keep" });
  assert.equal(decide(item({ ...bed })).disposition, "keep");
  assert.deepEqual(decide(item({ ...bed, condition: "poor", est: 5000 })), { disposition: "trash", reason: "Worn bed (~$50): won't resell or be accepted as a donation, trash" });
  // whole words only: a bedside table is ordinary furniture
  assert.equal(decide(item({ name: "Bedside table", est: 1000 })).disposition, "keep");
});

test("clothing and books that are cheap or unpriced: donate", () => {
  assert.deepEqual(decide(item({ name: "Paperbacks", category: "books", est: 800 })), { disposition: "donate", reason: "Worth ~$8, too little to list: donate" });
  assert.deepEqual(decide(item({ name: "Winter coats", category: "clothing" })), { disposition: "donate", reason: "No resale data, too little to list: donate" });
  // valuable ones fall through to the value-vs-cost rules
  assert.equal(decide(item({ name: "Designer jacket", category: "clothing", est: 30000 })).disposition, "keep");
});

test("unknown value (pricing failed, or no comps): keep for now", () => {
  assert.deepEqual(decide(sofa(-1)), { disposition: "keep", reason: "No resale data; ~$97 to move: keep for now" });
  assert.equal(decide(sofa(0)).disposition, "keep");
});

test("built-in fixtures are left undecided with a reason", () => {
  assert.deepEqual(decide(item({ name: "toilet", category: "toilet" })), { disposition: "undecided", reason: "Built-in fixture: stays with the house" });
});

test("needsSort: priced (or failed) items nobody decided yet", () => {
  assert.equal(needsSort(gate()), true);
  assert.equal(needsSort(gate({ pricingStatus: "failed" })), true);
  assert.equal(needsSort(gate({ pricingStatus: "pending" })), false);
  assert.equal(needsSort(gate({ pricingStatus: "running" })), false);
});

test("needsSort: waits for vision when there are photos", () => {
  assert.equal(needsSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "pending" })), false);
  assert.equal(needsSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "running" })), false);
  assert.equal(needsSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "done" })), true);
  assert.equal(needsSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "failed" })), true);
});

test("needsSort: never user-set, sentimental or already-sorted items", () => {
  assert.equal(needsSort(gate({ dispositionSource: "user" })), false);
  assert.equal(needsSort(gate({ dispositionSource: "user", disposition: "keep" })), false);
  assert.equal(needsSort(gate({ maybeSentimental: true })), false);
  assert.equal(needsSort(gate({ maybeSentimental: true, dispositionReason: SENTIMENTAL_REASON })), false);
  assert.equal(needsSort(gate({ disposition: "sell", dispositionReason: "Worth ~$50 but ~$97 to move: sell" })), false);
  // parked built-ins don't loop
  assert.equal(needsSort(gate({ dispositionReason: "Built-in fixture: stays with the house" })), false);
});

test("needsSort: re-sorts once the user clears the sentimental flag", () => {
  assert.equal(needsSort(gate({ dispositionReason: SENTIMENTAL_REASON })), true);
});
