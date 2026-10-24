import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Google Lens reverse image search (#292), with fetch mocked: no network, no Apify spend.
const dir = mkdtempSync(path.join(tmpdir(), "lens-"));
process.env.APIFY_SPEND_FILE = path.join(dir, "spend.json");
process.env.APIFY_MAX_USD_PER_DAY = "0.05";
process.env.LENS_CACHE_DIR = path.join(dir, "lens");
const { isLensablePhoto, normalizeLensRows, lensSearch, lensCacheFile } = await import("../src/integrations/lens.js");
const { apifySpentToday } = await import("../src/integrations/apify.js");

const row = {
  imageUrl: "https://t.trycloudflare.com/files/a.jpg",
  visualMatches: [
    { title: "Apple MacBook Pro 14-inch M1 Pro 2021 Space Gray", source: "eBay", price: "$849.00", link: "https://ebay.com/x" },
    { title: "Apple MacBook Pro 14-inch M1 Pro 2021 Space Gray", source: "Swappa", price: "$899.00" },
    { title: "", source: "nothing" },
    { title: "Laptop stand", source: "Amazon", price: "" },
  ],
};

test("only public https photos can be searched (Google fetches them)", () => {
  assert.equal(isLensablePhoto("https://abc.trycloudflare.com/files/a.jpg"), true);
  assert.equal(isLensablePhoto("http://abc.trycloudflare.com/files/a.jpg"), false);
  assert.equal(isLensablePhoto("https://192.168.1.20:8787/files/a.jpg"), false);
  assert.equal(isLensablePhoto("https://localhost/files/a.jpg"), false);
  assert.equal(isLensablePhoto("https://user:pw@host.com/a.jpg"), false);
  assert.equal(isLensablePhoto("not a url"), false);
});

test("normalizes visual matches: titled, deduplicated, capped", () => {
  const m = normalizeLensRows([row], 8);
  assert.deepEqual(m.map(x => x.title), ["Apple MacBook Pro 14-inch M1 Pro 2021 Space Gray", "Laptop stand"]);
  assert.equal(m[0].price, "$849.00");
  assert.equal(normalizeLensRows([row], 1).length, 1);
  assert.deepEqual(normalizeLensRows([{ nope: 1 }, null as unknown as object], 8), []);
});

test("a live search books its cap first, caches, and replays for free", async () => {
  let calls = 0;
  let sent: Record<string, unknown> = {};
  const fake = (async (_u: URL, init: RequestInit) => {
    calls++;
    sent = JSON.parse(String(init.body));
    return new Response(JSON.stringify([row]), { status: 200 });
  }) as unknown as typeof fetch;
  const url = "https://t.trycloudflare.com/files/live.jpg";
  const live = await lensSearch(url, { token: "test", fetch: fake, maxUsd: 0.02 });
  assert.equal(live.replayed, false);
  assert.equal(live.matches.length, 2);
  assert.equal(sent.imageUrl, url);
  assert.equal(sent.searchType, "visual_matches");
  assert.equal(Number(apifySpentToday().usd.toFixed(3)), 0.02);
  const again = await lensSearch(url, { token: "test", fetch: fake });
  assert.equal(again.replayed, true);
  assert.equal(again.costUsd, 0);
  assert.equal(calls, 1);
});

test("refused past the daily Apify cap, without calling Apify", async () => {
  let calls = 0;
  const fake = (async () => { calls++; return new Response("[]"); }) as unknown as typeof fetch;
  // 0.02 already booked above; two more would pass the 0.05 cap
  await lensSearch("https://t.trycloudflare.com/files/b.jpg", { token: "test", fetch: (async () => new Response(JSON.stringify([row]))) as unknown as typeof fetch, maxUsd: 0.02 });
  const r = await lensSearch("https://t.trycloudflare.com/files/c.jpg", { token: "test", fetch: fake, maxUsd: 0.02 });
  assert.equal(r.refused, true);
  assert.equal(calls, 0);
});

test("an unreachable photo isn't cached, so a later try can work", async () => {
  const url = "https://t.trycloudflare.com/files/gone.jpg";
  const fake = (async () => new Response(JSON.stringify([{ error: "image not reachable" }]))) as unknown as typeof fetch;
  const r = await lensSearch(url, { token: "test", fetch: fake, maxUsd: 0.001, cacheFile: lensCacheFile(url) });
  assert.deepEqual(r.matches, []);
  const again = await lensSearch(url, { token: "test", fetch: fake, maxUsd: 0.001 });
  assert.equal(again.replayed, false);
});

test("no APIFY_TOKEN: no search", async () => {
  const r = await lensSearch("https://t.trycloudflare.com/files/x.jpg", { token: "" });
  assert.deepEqual(r, { matches: [], replayed: false, costUsd: 0 });
});
