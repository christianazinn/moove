import { test } from "node:test";
import assert from "node:assert/strict";
import { listable, visionSettled } from "../src/agents/listing.js";

test("listing waits for vision only when there is a photo to look at", () => {
  assert.equal(visionSettled({ detailsStatus: "pending", photoUrls: [] }), true); // scanned, no photo
  assert.equal(visionSettled({ detailsStatus: "pending", photoUrls: ["https://w/files/a.jpg"] }), false);
  assert.equal(visionSettled({ detailsStatus: "running", photoUrls: ["https://w/files/a.jpg"] }), false);
  assert.equal(visionSettled({ detailsStatus: "done", photoUrls: ["https://w/files/a.jpg"] }), true);
  assert.equal(visionSettled({ detailsStatus: "failed", photoUrls: ["https://w/files/a.jpg"] }), true);
});

test("built-in fixtures are never listed, even when sorted to sell", () => {
  assert.equal(listable({ disposition: "sell", name: "white two-piece elongated toilet", category: "appliance" }), false);
  assert.equal(listable({ disposition: "sell", name: "white wall-mounted bathroom sink with chrome faucet", category: "appliance" }), false);
  assert.equal(listable({ disposition: "sell", name: "red plush stuffed animal toy", category: "decor" }), true);
  assert.equal(listable({ disposition: "keep", name: "office chair", category: "chair" }), false);
});
