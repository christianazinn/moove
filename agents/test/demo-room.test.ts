import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import type { Item } from "../src/module_bindings/types.js";
import { cacheFile, type Comp } from "../src/integrations/apify.js";
import { estimate, queryFor } from "../src/agents/pricing.js";
import { preFilter } from "../src/agents/comp-filter.js";
import { decide } from "../src/agents/sort.js";
import { DEMO_COMMERCE_OBJECTS, DEMO_OBJECTS as BASE_OBJECTS, demoQuery, freshCommerceApproval, planCommerceReset } from "../scripts/demo-room.js";

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

const me = { toHexString: () => "aa" };
const other = { toHexString: () => "bb" };
const CHAIR = DEMO_COMMERCE_OBJECTS[0].scanObjectId;

test("--reset-commerce plan: only the seed user's chair in the seed room, only its pending listing approvals", () => {
  const items = [
    { id: 1n, roomId: 7n, scanObjectId: BASE_OBJECTS[0].scanObjectId, owner: me }, // one of the other 9
    { id: 2n, roomId: 7n, scanObjectId: CHAIR, owner: me }, // the seeded chair
    { id: 3n, roomId: 8n, scanObjectId: CHAIR, owner: me }, // a chair in another room
    { id: 4n, roomId: 7n, scanObjectId: CHAIR, owner: other }, // someone else's row
  ];
  const listings = [
    { id: 10n, itemId: 2n, status: "awaiting_approval" },
    { id: 11n, itemId: 2n, status: "posting" },
    { id: 12n, itemId: 1n, status: "awaiting_approval" },
    { id: 13n, itemId: 4n, status: "awaiting_approval" },
  ];
  const approvals = [
    { id: 20n, kind: "listing", refId: 10n, status: "pending" },
    { id: 21n, kind: "listing", refId: 10n, status: "approved" },
    { id: 22n, kind: "purchase", refId: 10n, status: "pending" }, // a deal whose id collides with the listing's
    { id: 23n, kind: "listing", refId: 12n, status: "pending" },
    { id: 24n, kind: "listing", refId: 13n, status: "pending" },
  ];
  const plan = planCommerceReset(7n, "aa", items, listings, approvals);
  assert.deepEqual(plan.deleteItemIds, [2n]);
  assert.deepEqual(plan.deny, [20n]);
  assert.deepEqual(plan.inFlight, [11n]);
  assert.deepEqual(plan.readd, DEMO_COMMERCE_OBJECTS);
  // Nothing seeded yet (or already deleted): nothing to undo, the chair is just added back.
  assert.deepEqual(planCommerceReset(9n, "aa", items, listings, approvals), { deny: [], deleteItemIds: [], readd: DEMO_COMMERCE_OBJECTS, inFlight: [] });
});

test("--reset-commerce waits for a pending approval on the re-added chair, never the deleted one's", () => {
  const items = [{ id: 2n, roomId: 7n, scanObjectId: CHAIR, owner: me }];
  const listings = [{ id: 10n, itemId: 2n, status: "awaiting_approval" }];
  const old = [{ id: 20n, kind: "listing", refId: 10n, status: "pending" }];
  assert.equal(freshCommerceApproval(7n, "aa", [2n], items, listings, old), undefined);
  const after = [...items, { id: 5n, roomId: 7n, scanObjectId: CHAIR, owner: me }];
  const drafted = [...listings, { id: 14n, itemId: 5n, status: "draft" }];
  assert.equal(freshCommerceApproval(7n, "aa", [2n], after, drafted, old), undefined, "drafted but not asked yet");
  const asked = [...old, { id: 30n, kind: "listing", refId: 14n, status: "pending" }, { id: 31n, kind: "listing", refId: 14n, status: "denied" }];
  assert.equal(freshCommerceApproval(7n, "aa", [2n], after, drafted, asked)?.id, 30n);
});
