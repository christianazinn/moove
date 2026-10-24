import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Only complete lookups are cached: a half-failed one (one actor at its concurrency limit) used to
// pin the query to one source forever, and an empty one to "$0" (Rio's audit: 18 of 50 caches).
const dir = mkdtempSync(path.join(tmpdir(), "apify-cache-"));
process.chdir(dir); // caches go to ./fixtures/comps
process.env.APIFY_SPEND_FILE = path.join(dir, "spend.json");
process.env.APIFY_MAX_USD_PER_DAY = "0";
process.env.APIFY_TOKEN = "test-token-not-real";
process.env.APIFY_SOURCES = "ebay,fb";
const { lookupComps, cachedComps, cacheFile } = await import("../src/integrations/apify.js");
const { rejectsBorrowed } = await import("../src/agents/pricing.js");

const rows = (n: number) => JSON.stringify(Array.from({ length: n }, (_, i) => ({ title: `chair ${i}`, price: 20 + i, url: `https://x/${i}` })));
let fbFails = false;
let empty = false;
globalThis.fetch = (async (u: URL) => {
  if (empty) return new Response("[]", { status: 200 });
  if (fbFails && String(u).includes("facebook")) return new Response("concurrent-runs-limit", { status: 402 });
  return new Response(rows(5), { status: 200 });
}) as typeof fetch;

test("a lookup where one source failed is returned but not cached", async () => {
  fbFails = true;
  const r = await lookupComps("partial chair");
  assert.equal(r.comps.length, 5);
  assert.equal(existsSync(cacheFile("partial chair")), false);
  fbFails = false;
});

test("a complete lookup is cached and replayed", async () => {
  const r = await lookupComps("complete chair");
  assert.equal(r.comps.length, 10);
  assert.equal(existsSync(cacheFile("complete chair")), true);
  assert.equal((await lookupComps("complete chair")).replayed, true);
});

test("an empty lookup isn't cached, and an old empty cache is a miss", async () => {
  empty = true;
  const r = await lookupComps("nothing chair");
  assert.deepEqual(r.comps, []);
  assert.equal(existsSync(cacheFile("nothing chair")), false);
  empty = false;
  mkdirSync(path.dirname(cacheFile("old empty")), { recursive: true });
  writeFileSync(cacheFile("old empty"), "[]");
  assert.equal(cachedComps("old empty"), null);
  assert.equal((await lookupComps("old empty")).replayed, false);
});

test("borrowed comps Claude kept none of are rejected; others aren't", () => {
  assert.equal(rejectsBorrowed("chair", { claude: "failed", error: "kept none (all toys)" }), true);
  assert.equal(rejectsBorrowed("", { claude: "failed", error: "kept none (all toys)" }), false, "own comps fall back as before");
  assert.equal(rejectsBorrowed("chair", { claude: "failed", error: "timeout" }), false, "a Claude error keeps the rule-filtered comps");
  assert.equal(rejectsBorrowed("chair", { claude: "ok" }), false);
});
