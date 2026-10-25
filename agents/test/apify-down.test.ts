import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Apify out of credit (403 "Monthly usage hard limit"): noted once, then live runs are skipped for a
// while instead of failing (or being paid for over x402) once per item. No network: fetch is mocked.
const dir = mkdtempSync(path.join(tmpdir(), "apify-down-"));
process.chdir(dir); // caches go to ./fixtures/comps
process.env.APIFY_SPEND_FILE = path.join(dir, "spend.json");
process.env.APIFY_MAX_USD_PER_DAY = "5";
process.env.APIFY_TOKEN = "test-token-not-real";
process.env.APIFY_SOURCES = "ebay,fb";
const {
  lookupComps,
  cacheFile,
  isApifyOutOfCredit,
  isApifyUnavailable,
  apifyDownReason,
  clearApifyDown,
  compsLiveUnavailable,
  reserveApifySpend,
  releaseApifySpend,
  apifySpentToday,
} = await import("../src/integrations/apify.js");

let calls = 0;
globalThis.fetch = (async () => {
  calls++;
  return new Response('{"error":{"type":"platform-feature-disabled","message":"Monthly usage hard limit exceeded"}}', { status: 403 });
}) as typeof fetch;

test("out of credit vs. transient limits", () => {
  assert.equal(isApifyOutOfCredit(new Error('apify x: HTTP 403 {"message":"Monthly usage hard limit exceeded"}')), true);
  assert.equal(isApifyOutOfCredit("apify x: HTTP 402 Payment required"), true);
  assert.equal(isApifyOutOfCredit('apify x: HTTP 402 {"type":"concurrent-runs-limit-exceeded"}'), false);
  assert.equal(isApifyOutOfCredit("apify x: HTTP 502 bad gateway"), false);
});

test("every source out of credit: the breaker opens and later lookups skip Apify", async () => {
  clearApifyDown();
  await assert.rejects(lookupComps("never cached lamp"), /HTTP 403/);
  assert.equal(calls, 2);
  assert.match(apifyDownReason() ?? "", /Monthly usage hard limit/);
  await assert.rejects(lookupComps("never cached rug"), (e: unknown) => {
    assert.match(String(e), /Apify unavailable \(out of credit\)/);
    assert.equal(isApifyUnavailable(e), true, "pricing borrows similar cached comps for it");
    return true;
  });
  assert.equal(calls, 2, "no second doomed run");
  assert.match(compsLiveUnavailable() ?? "", /^Apify unavailable \(out of credit\)/);
  // A cached query is still served.
  mkdirSync(path.dirname(cacheFile("cached lamp")), { recursive: true });
  writeFileSync(cacheFile("cached lamp"), JSON.stringify([{ source: "ebay", title: "lamp", priceCents: 2000, url: "u" }]));
  assert.equal((await lookupComps("cached lamp")).replayed, true);
  // The window passes: Apify is tried again.
  assert.equal(apifyDownReason(Date.now() + 11 * 60_000), null);
  clearApifyDown();
  assert.equal(compsLiveUnavailable(), null);
});

test("a released reservation doesn't count toward the daily cap", () => {
  const before = apifySpentToday();
  assert.equal(reserveApifySpend(0.1), true);
  releaseApifySpend(0.1);
  const after = apifySpentToday();
  assert.equal(Number(after.usd.toFixed(6)), Number(before.usd.toFixed(6)));
  assert.equal(after.runs, before.runs);
});
