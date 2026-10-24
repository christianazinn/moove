import { test } from "node:test";
import assert from "node:assert/strict";
import { visionSettled } from "../src/agents/listing.js";

test("listing waits for vision only when there is a photo to look at", () => {
  assert.equal(visionSettled({ detailsStatus: "pending", photoUrls: [] }), true); // scanned, no photo
  assert.equal(visionSettled({ detailsStatus: "pending", photoUrls: ["https://w/files/a.jpg"] }), false);
  assert.equal(visionSettled({ detailsStatus: "running", photoUrls: ["https://w/files/a.jpg"] }), false);
  assert.equal(visionSettled({ detailsStatus: "done", photoUrls: ["https://w/files/a.jpg"] }), true);
  assert.equal(visionSettled({ detailsStatus: "failed", photoUrls: ["https://w/files/a.jpg"] }), true);
});
