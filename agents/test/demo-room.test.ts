import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import type { Item } from "../src/module_bindings/types.js";
import { cacheFile, type Comp } from "../src/integrations/apify.js";
import { estimate, queryFor } from "../src/agents/pricing.js";
import { DEMO_OBJECTS, demoQuery } from "../scripts/demo-room.js";

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
