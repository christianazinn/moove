// The demo room: a college-student bedroom as RoomPlan would report it, seeded by `npm run seed:demo`.
// Names are what the pricing agent searches for (no photos, so vision never renames them and the brand
// stays ''), and every query has a committed real cache in fixtures/comps/, so pricing the demo room
// never calls Apify. `npm run comps:prefetch` fills any missing cache; test/demo-room.test.ts checks it.
import type { Item, ScanObjectInput } from "../src/module_bindings/types.js";
import { queryFor } from "../src/agents/pricing.js";

export const DEMO_ROOM_NAME = "Bedroom";
export const DEMO_HOME = "old";

// sentimental/sell: what the seed does as the user after import (flag it, or tap Sell).
type DemoObject = ScanObjectInput & { sentimental?: boolean; sell?: boolean };

// RoomPlan categories where one exists (bed, table, chair, storage, refrigerator, television);
// otherwise the iOS category the app already styles (lamp) or a descriptive one. Dims are meters.
const obj = (scanObjectId: string, name: string, category: string, [widthM, heightM, depthM]: [number, number, number], sentimental = false, sell = false): DemoObject => ({
  scanObjectId: `demo-bedroom-${scanObjectId}`,
  name,
  category,
  widthM,
  heightM,
  depthM,
  photoUrl: "",
  sentimental,
  sell,
});

export const DEMO_OBJECTS: DemoObject[] = [
  // RoomPlan reports the bed (frame + mattress) as one object.
  obj("bed", "Full size metal bed frame", "bed", [1.4, 0.36, 1.95]),
  obj("desk", "IKEA Micke desk", "table", [1.05, 0.75, 0.5]),
  obj("chair", "Mesh office chair", "chair", [0.64, 1.02, 0.62]),
  obj("shelf", "IKEA Kallax shelf", "storage", [0.77, 1.47, 0.39]),
  obj("fridge", "Mini fridge", "refrigerator", [0.48, 0.85, 0.5]),
  obj("tv", "TCL 32 inch TV", "television", [0.73, 0.48, 0.18]),
  obj("monitor", "Dell 27 inch monitor", "electronics", [0.61, 0.45, 0.18]),
  obj("lamp", "Floor lamp", "lamp", [0.3, 1.7, 0.3]),
  // Flagged sentimental after import (vision would, but seeded items have no photos).
  obj("guitar", "Yamaha acoustic guitar", "instrument", [0.38, 1.02, 0.12], true),
];

// Opt-in commerce story (SEED_COMMERCE=1 npm run seed:demo): an item the listing agent drafts over the
// $100 approval threshold. Its query has the committed real replay herman-miller-office-chair.json (#63,
// ~$350 from rule-filtered comps). The sort rules would say keep (worth far more than the ~$28 to move
// it), so the seed sets it to sell as the user, like a student tapping Sell. Size B Aeron: 69 x 104 x 67 cm.
export const DEMO_COMMERCE_OBJECTS: DemoObject[] = [obj("aeron", "Herman Miller office chair", "chair", [0.69, 1.04, 0.67], false, true)];

// The item as import_scan stores it (no brand, material or condition), for keys like the price prior's.
export function demoItemDesc(o: ScanObjectInput) {
  return { name: o.name || o.category, category: o.category, brand: "", material: "", condition: "", widthM: o.widthM, heightM: o.heightM, depthM: o.depthM };
}

// Exactly the string the pricing agent will look up for a freshly imported object.
export function demoQuery(o: ScanObjectInput): string {
  return queryFor({ brand: "", name: o.name || o.category, category: o.category } as Item);
}

// --reset-commerce (seed-demo.ts): what to undo so the chair's approval beat can run again. A user can't
// re-open a listing (update_listing is worker-only), and set_disposition keep->sell doesn't re-draft an item
// that already has a listing (the listing agent drafts once per item id). So the only user-side reset is:
// deny any still-pending approval on the chair's listings, delete the chair, add it back (it re-prices from
// the committed replay) and tap Sell again. The listing agent then drafts a listing for the new item id (one
// live Claude call on maincloud) and asks for approval. Pure, so it's tested: it only ever picks the seed
// user's commerce items in the seed user's room, never another item or another user's rows.
type ResetItem = { id: bigint; roomId: bigint; scanObjectId: string; owner: { toHexString(): string } };
type ResetListing = { id: bigint; itemId: bigint; status: string };
type ResetApproval = { id: bigint; kind: string; refId: bigint; status: string };
export type CommerceResetPlan = {
  deny: bigint[]; // pending listing approvals on the chair's listings
  deleteItemIds: bigint[];
  readd: DemoObject[]; // every commerce object, added back after the deletes
  inFlight: bigint[]; // listings mid-post ('posting', #216): they finish posting; the reset doesn't wait
};

const COMMERCE_IDS = new Set(DEMO_COMMERCE_OBJECTS.map((o) => o.scanObjectId));
const commerceItemsIn = <T extends ResetItem>(roomId: bigint, ownerHex: string, items: Iterable<T>) =>
  [...items].filter((i) => i.roomId === roomId && i.owner.toHexString() === ownerHex && COMMERCE_IDS.has(i.scanObjectId));

export function planCommerceReset(roomId: bigint, ownerHex: string, items: Iterable<ResetItem>, listings: Iterable<ResetListing>, approvals: Iterable<ResetApproval>): CommerceResetPlan {
  const deleteItemIds = commerceItemsIn(roomId, ownerHex, items).map((i) => i.id);
  const chairListings = [...listings].filter((l) => deleteItemIds.includes(l.itemId));
  const listingIds = new Set(chairListings.map((l) => l.id));
  const deny = [...approvals].filter((a) => a.kind === "listing" && a.status === "pending" && listingIds.has(a.refId)).map((a) => a.id);
  return { deny, deleteItemIds, readd: DEMO_COMMERCE_OBJECTS, inFlight: chairListings.filter((l) => l.status === "posting").map((l) => l.id) };
}

// The approval a reset waits for: the newest pending listing approval on a commerce item that isn't one
// the reset deleted.
export function freshCommerceApproval<A extends ResetApproval>(
  roomId: bigint,
  ownerHex: string,
  deletedItemIds: Iterable<bigint>,
  items: Iterable<ResetItem>,
  listings: Iterable<ResetListing>,
  approvals: Iterable<A>
): A | undefined {
  const old = new Set(deletedItemIds);
  const fresh = new Set(commerceItemsIn(roomId, ownerHex, items).filter((i) => !old.has(i.id)).map((i) => i.id));
  const ls = new Set([...listings].filter((l) => fresh.has(l.itemId)).map((l) => l.id));
  return [...approvals].filter((a) => a.kind === "listing" && a.status === "pending" && ls.has(a.refId)).sort((a, b) => (b.id > a.id ? 1 : -1))[0];
}
