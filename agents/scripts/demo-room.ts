// The demo room: a college-student bedroom as RoomPlan would report it, seeded by `npm run seed:demo`.
// Names are what the pricing agent searches for (no photos, so vision never renames them and the brand
// stays ''), and every query has a committed real cache in fixtures/comps/, so pricing the demo room
// never calls Apify. `npm run comps:prefetch` fills any missing cache; test/demo-room.test.ts checks it.
import type { Item, ScanObjectInput } from "../src/module_bindings/types.js";
import { queryFor } from "../src/agents/pricing.js";

export const DEMO_ROOM_NAME = "Bedroom";
export const DEMO_HOME = "old";

type DemoObject = ScanObjectInput & { sentimental?: boolean };

// RoomPlan categories where one exists (bed, table, chair, storage, refrigerator, television);
// otherwise the iOS category the app already styles (lamp) or a descriptive one. Dims are meters.
const obj = (scanObjectId: string, name: string, category: string, [widthM, heightM, depthM]: [number, number, number], sentimental = false): DemoObject => ({
  scanObjectId: `demo-bedroom-${scanObjectId}`,
  name,
  category,
  widthM,
  heightM,
  depthM,
  photoUrl: "",
  sentimental,
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

// Exactly the string the pricing agent will look up for a freshly imported object.
export function demoQuery(o: ScanObjectInput): string {
  return queryFor({ brand: "", name: o.name || o.category, category: o.category } as Item);
}
