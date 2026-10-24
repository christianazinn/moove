import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import type { Item } from "../src/module_bindings/types.js";
import { cacheFile, type Comp } from "../src/integrations/apify.js";
import { estimate, queryFor } from "../src/agents/pricing.js";
import { preFilter } from "../src/agents/comp-filter.js";
import { decide } from "../src/agents/sort.js";
import { DEMO_COMMERCE_OBJECTS, DEMO_OBJECTS as BASE_OBJECTS, demoQuery } from "../scripts/demo-room.js";

// Every check covers the opt-in commerce items (SEED_COMMERCE=1) too.
const DEMO_OBJECTS = [...BASE_OBJECTS, ...DEMO_COMMERCE_OBJECTS];

test("demo objects have unique scan ids and queries, and plausible dims", () => {
  assert.equal(new Set(DEMO_OBJECTS.map((o) => o.scanObjectId)).size, DEMO_OBJECTS.length);
  assert.equal(new Set(DEMO_OBJECTS.map(demoQuery)).size, DEMO_OBJECTS.length);
  for (const o of DEMO_OBJECTS) {
    for (const d of [o.widthM, o.heightM, o.depthM]) assert.ok(d > 0.05 && d < 2.5, `${o.name}: ${d} m`);
    assert.equal(o.photoUrl, "", "photos would send the item through vision (Claude) and change its query");
  }
});

test("demoQuery is what the pricing agent searches for an imported, photo-less item", () => {
  for (const o of DEMO_OBJECTS) {
    // As import_scan inserts it: name falls back to category, brand ''.
    const item = { name: o.name || o.category, category: o.category, brand: "" } as Item;
    assert.equal(demoQuery(o), queryFor(item));
  }
});

test("every demo query has a committed, non-empty real comps cache that prices", () => {
  for (const o of DEMO_OBJECTS) {
    const file = cacheFile(demoQuery(o));
    assert.ok(existsSync(file), `missing ${file}: run npm run comps:prefetch`);
    const comps = JSON.parse(readFileSync(file, "utf8")) as Comp[];
    assert.ok(comps.length > 0, `${file} is empty`);
    for (const c of comps) assert.ok(c.title && c.priceCents > 0 && c.url.startsWith("http"), `${file}: bad comp ${JSON.stringify(c)}`);
    const e = estimate(comps, "");
    assert.ok(e && e.est > 0 && e.low <= e.est && e.est <= e.high, `${file}: no usable estimate`);
  }
});

test("SEED_COMMERCE items are set to sell and priced from their replay over the $100 approval threshold", () => {
  assert.ok(DEMO_COMMERCE_OBJECTS.length > 0);
  for (const o of DEMO_COMMERCE_OBJECTS) {
    assert.equal(o.sell, true, `${o.name}: the seed sets it to sell`);
    assert.ok(!o.sentimental, `${o.name}: sentimental items are never listed`);
    const comps = JSON.parse(readFileSync(cacheFile(demoQuery(o)), "utf8")) as Comp[];
    const it = { name: o.name, category: o.category, brand: "", material: "", condition: "", widthM: o.widthM, heightM: o.heightM, depthM: o.depthM, fragile: false };
    // Rule-filtered comps are the floor: what pricing uses when the Claude filter is unavailable.
    const e = estimate(preFilter(comps, it).kept, "");
    assert.ok(e && e.est > 10_000, `${o.name}: ~$${(e?.est ?? 0) / 100} is not over the $100 threshold`);
    // Why the seed taps Sell: on value alone the sort rules would keep it.
    assert.equal(decide({ ...it, estValueCents: BigInt(e.est) }).disposition, "keep");
  }
});
