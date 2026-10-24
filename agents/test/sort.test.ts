import { test } from "node:test";
import assert from "node:assert/strict";
import { decide, moveCostCents, nextSort, SENTIMENTAL_REASON, type SortGate, type SortInput } from "../src/agents/sort.js";

/** A 0.5 x 0.5 x 0.4 m (0.1 m^3, ~$6 to move) item in good shape, unpriced. */
function item(over: Partial<Omit<SortInput, "estValueCents">> & { est?: number } = {}): SortInput {
  const { est = -1, ...rest } = over;
  return { name: "Side table", category: "furniture", condition: "good", widthM: 0.5, heightM: 0.5, depthM: 0.4, fragile: false, estValueCents: BigInt(est), ...rest };
}

/** Ready to sort: priced at $150, no photos, untouched. */
function gate(over: Partial<SortGate> = {}): SortGate {
  return { ...item({ est: 15000 }), disposition: "undecided", dispositionSource: "auto", dispositionReason: "", maybeSentimental: false, pricingStatus: "done", detailsStatus: "pending", photoUrls: [], ...over };
}
/** gate(), already holding whatever decide() says for it. */
function sorted(over: Partial<SortGate> = {}): SortGate {
  const g = gate(over);
  const d = decide(g);
  return { ...g, disposition: d.disposition, dispositionReason: d.reason };
}
const KEEP_150 = { disposition: "keep", reason: "Worth ~$150, ~$6 to move: keep" };

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
  assert.deepEqual(decide(item({ condition: "poor" })), { disposition: "trash", reason: "Poor shape and no resale data: trash" });
  assert.deepEqual(decide(item({ condition: "poor", est: 0 })), { disposition: "trash", reason: "Poor shape and no resale value: trash" });
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
  // bed linen is linen
  assert.equal(decide(item({ name: "Bed sheets", category: "linen" })).disposition, "donate");
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
  assert.equal(decide(item({ name: "Stairs", category: "stairs" })).disposition, "undecided");
  assert.equal(decide(item({ name: "Spiral stair", category: "" })).disposition, "undecided");
});

test("nextSort: priced (or failed) items nobody decided yet", () => {
  assert.deepEqual(nextSort(gate()), KEEP_150);
  assert.deepEqual(nextSort(gate({ pricingStatus: "failed", estValueCents: -1n })), { disposition: "keep", reason: "No resale data; ~$6 to move: keep for now" });
  assert.equal(nextSort(gate({ pricingStatus: "pending" })), null);
  assert.equal(nextSort(gate({ pricingStatus: "running" })), null);
});

test("nextSort: waits for vision when there are photos", () => {
  assert.equal(nextSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "pending" })), null);
  assert.equal(nextSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "running" })), null);
  assert.deepEqual(nextSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "done" })), KEEP_150);
  assert.deepEqual(nextSort(gate({ photoUrls: ["http://x/a.jpg"], detailsStatus: "failed" })), KEEP_150);
});

test("nextSort: never user-set items; nothing to do once the stored decision matches", () => {
  assert.equal(nextSort(gate({ dispositionSource: "user" })), null);
  assert.equal(nextSort(gate({ dispositionSource: "user", disposition: "keep", maybeSentimental: true })), null);
  assert.equal(nextSort(sorted()), null);
  // parked built-ins don't loop
  assert.equal(nextSort(sorted({ name: "Toilet", category: "toilet" })), null);
});

test("nextSort: sentimental items are parked, including ones already auto-sorted", () => {
  const park = { disposition: "undecided", reason: SENTIMENTAL_REASON };
  assert.deepEqual(nextSort(gate({ maybeSentimental: true })), park);
  assert.deepEqual(nextSort(gate({ maybeSentimental: true, pricingStatus: "pending" })), park);
  assert.deepEqual(nextSort({ ...sorted(), maybeSentimental: true }), park);
  assert.equal(nextSort(gate({ maybeSentimental: true, dispositionReason: SENTIMENTAL_REASON })), null);
});

test("nextSort: re-sorts once the user clears the sentimental flag", () => {
  assert.deepEqual(nextSort(gate({ dispositionReason: SENTIMENTAL_REASON })), KEEP_150);
});

test("nextSort: re-sorts an auto decision when vision, pricing or flags change it", () => {
  const before = sorted(); // a $150 keep, sorted before any photo
  // vision later finds it's in poor shape, and re-pricing says it's cheap
  assert.deepEqual(nextSort({ ...before, condition: "poor", estValueCents: 800n, photoUrls: ["u"], detailsStatus: "done" }), { disposition: "trash", reason: "Poor shape and worth only ~$8: trash" });
  // vision or re-pricing still running: wait
  assert.equal(nextSort({ ...before, photoUrls: ["u"], detailsStatus: "running", condition: "poor" }), null);
  assert.equal(nextSort({ ...before, pricingStatus: "running" }), null);
  // marking a big item fragile can tip keep to sell
  const sofa = sorted({ name: "Sofa", category: "sofa", widthM: 2, heightM: 0.9, depthM: 0.9, estValueCents: 12500n });
  assert.equal(sofa.disposition, "keep");
  assert.equal(nextSort({ ...sofa, fragile: true })?.disposition, "sell");
});
