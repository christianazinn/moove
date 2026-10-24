import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// The daily Apify spend cap for comps lookups (no network: fetch is mocked).
const dir = mkdtempSync(path.join(tmpdir(), "apify-spend-"));
process.chdir(dir); // comps caches are written under ./fixtures/comps: keep them out of the repo
process.env.APIFY_SPEND_FILE = path.join(dir, "spend.json");
process.env.APIFY_MAX_USD_PER_DAY = "0.5";
process.env.APIFY_TOKEN = "test-token-not-real";
process.env.APIFY_SOURCES = "ebay,fb";
const { lookupComps, apifySpentToday, ApifyCapError } = await import("../src/integrations/apify.js");

const realFetch = globalThis.fetch;
let calls = 0;
globalThis.fetch = (async () => {
  calls++;
  return new Response(JSON.stringify(Array.from({ length: 10 }, (_, i) => ({ title: `chair ${i}`, price: 20 + i, url: `https://x/${i}` }))), { status: 200 });
}) as typeof fetch;

test("each live run adds results x per-result price to today's total", async () => {
  const q = `e2e spend test chair ${process.pid}`;
  const r = await lookupComps(q);
  assert.equal(r.replayed, false);
  assert.equal(calls, 2); // one run per source
  const spent = apifySpentToday();
  assert.equal(spent.runs, 2);
  assert.equal(Number(spent.usd.toFixed(3)), Number((10 * 0.004 + 10 * 0.0062).toFixed(3)));
  // second lookup of the same query is a free cache hit
  await lookupComps(q);
  assert.equal(calls, 2);
});

test("over the daily cap, an uncached lookup is refused before any run", async () => {
  const today = new Date().toISOString().slice(0, 10);
  writeFileSync(process.env.APIFY_SPEND_FILE!, JSON.stringify({ [today]: { usd: 0.6, runs: 14 } }));
  calls = 0;
  await assert.rejects(lookupComps(`never cached ${process.pid}`), (e: unknown) => e instanceof ApifyCapError && /~\$0\.60 of \$0\.50 today \(14 runs\)/.test(String(e)));
  assert.equal(calls, 0);
  globalThis.fetch = realFetch;
});
