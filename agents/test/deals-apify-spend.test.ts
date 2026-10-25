import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

// #185: the buy agent's live deal search counts into the same daily Apify total as pricing comps
// (#170), booking each run's maxTotalChargeUsd before it starts. No network: fetch is mocked.
const dir = mkdtempSync(path.join(tmpdir(), 'deals-apify-spend-'));
process.chdir(dir); // comps caches go under ./fixtures/comps: keep them out of the repo
process.env.APIFY_SPEND_FILE = path.join(dir, 'spend.json');
process.env.APIFY_MAX_USD_PER_DAY = '0.5';
process.env.APIFY_TOKEN = 'test-token-not-real';
process.env.APIFY_SOURCES = 'ebay,fb';
const { lookupComps, apifySpentToday, ApifyCapError } = await import('../src/integrations/apify.js');
const { createDealSource, ACTORS } = await import('../src/integrations/deals-apify.js');
const { fixtureDealSource } = await import('../src/integrations/deals.js');

const today = () => new Date().toISOString().slice(0, 10);
const setSpent = (usd: number, runs: number) => writeFileSync(process.env.APIFY_SPEND_FILE!, JSON.stringify({ [today()]: { usd, runs } }));

const FB_ROW = {
  listingUrl: 'https://www.facebook.com/marketplace/item/111111111111111/',
  marketplace_listing_title: 'Wood desk',
  listing_price: { amount: '60.00', currency: 'USD' },
};
const EBAY_ROW = { type: 'product', title: 'Oak desk', price: 80, currency: 'USD', url: 'https://www.ebay.com/itm/123456789012' };
let calls: string[] = [];
const mockFetch = (async (u: URL | string) => {
  const actor = String(u).match(/acts\/([^/]+)\//)![1];
  calls.push(actor);
  if (actor === ACTORS.fb.actor) return new Response(JSON.stringify([FB_ROW]), { status: 200 });
  if (actor === ACTORS.ebay.actor) return new Response(JSON.stringify([EBAY_ROW]), { status: 200 });
  // comps actors
  return new Response(JSON.stringify(Array.from({ length: 10 }, (_, i) => ({ title: `desk ${i}`, price: 20 + i, url: `https://x/${i}` }))), { status: 200 });
}) as typeof fetch;

const replayDir = mkdtempSync(path.join(dir, 'replays-'));
const source = () =>
  createDealSource(process.env, { fetch: mockFetch, cacheDir: mkdtempSync(path.join(dir, 'cache-')), replayDir, fallback: fixtureDealSource([]) });

test('each live deal run books its maxTotalChargeUsd into the shared daily total before it runs', async () => {
  setSpent(0, 0);
  calls = [];
  const notices: string[] = [];
  const deals = await source().search({ name: 'Desk', category: 'desk' }, { onNotice: n => notices.push(n.message) });
  assert.deepEqual(calls.sort(), [ACTORS.ebay.actor, ACTORS.fb.actor].sort());
  assert.ok(deals.length >= 2 && deals.every(d => !d.replay));
  assert.deepEqual(notices, []);
  const spent = apifySpentToday();
  assert.equal(spent.runs, 2);
  assert.equal(Number(spent.usd.toFixed(3)), 0.2); // 2 runs x the default $0.10 maxTotalChargeUsd
});

test('deal runs and comps runs share one cap: comps are refused once deal search used it up', async () => {
  setSpent(0.3, 3);
  calls = [];
  await source().search({ name: 'Desk', category: 'desk' }); // 2 x $0.10 -> $0.50
  assert.equal(calls.length, 2);
  assert.equal(Number(apifySpentToday().usd.toFixed(3)), 0.5);
  calls = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = mockFetch;
  try {
    await assert.rejects(lookupComps(`never cached ${process.pid}`), (e: unknown) => e instanceof ApifyCapError);
  } finally {
    globalThis.fetch = realFetch;
  }
  assert.equal(calls.length, 0);
});

test('past the cap: no run, a clear notice, and the no-token fallback (cached replay, then sample data)', async () => {
  setSpent(0.45, 9);
  calls = [];
  // A committed replay for this query, as fixtures/deals-live-*.json would be.
  writeFileSync(path.join(replayDir, 'deals-live-bed-frame.json'), JSON.stringify({ rows: [{ source: 'fb', title: 'Replayed bed frame', priceCents: 5000, url: 'https://www.facebook.com/marketplace/item/222222222222222/', seller: 'FB Marketplace seller', condition: 'good', distanceMiles: 5, checkout: 'seller_message' }] }));
  const notices: { message: string; data?: Record<string, unknown> }[] = [];
  const src = source();
  const replayed = await src.search({ name: 'Bed frame', category: 'bed' }, { onNotice: n => notices.push(n) });
  assert.equal(calls.length, 0, 'no Apify run past the cap');
  assert.ok(replayed.length === 1 && replayed[0].replay && replayed[0].title === 'Replayed bed frame');
  assert.equal(src.replay, true);
  assert.equal(notices.length, 1);
  assert.match(notices[0].message, /Apify daily spend cap reached \(~\$0\.45 of \$0\.50 today, 9 runs\)/);
  assert.match(notices[0].message, /using cached replays \/ sample deals instead/);
  assert.match(notices[0].message, /APIFY_MAX_USD_PER_DAY/);
  assert.deepEqual(notices[0].data?.skipped, ['fb', 'ebay']);
  assert.equal(notices[0].data?.refused, true);
  // Nothing was booked for the skipped runs.
  assert.deepEqual(apifySpentToday(), { usd: 0.45, runs: 9 });

  // No replay for this query: the sample-data fallback, same as with no APIFY_TOKEN.
  const sample = createDealSource(process.env, { fetch: mockFetch, cacheDir: mkdtempSync(path.join(dir, 'cache-')), replayDir }).search({ name: 'Desk chair', category: 'chair' });
  const rows = await sample;
  assert.ok(rows.length > 0 && rows.every(d => d.replay && d.sample));
  assert.equal(calls.length, 0);
});

test('a run that fits under the cap still goes live; only the rest are skipped', async () => {
  setSpent(0.35, 7);
  calls = [];
  const notices: string[] = [];
  await source().search({ name: 'Desk', category: 'desk' }, { onNotice: n => notices.push(n.message) });
  assert.deepEqual(calls, [ACTORS.fb.actor]); // fb booked $0.10 -> $0.45, ebay would pass $0.50
  assert.match(notices[0], /skipped the live ebay search for "Desk", searching only fb live/);
  assert.equal(Number(apifySpentToday().usd.toFixed(3)), 0.45);
});

test('Apify out of credit (403): the bookings are given back, the search says why, later searches skip live runs', async () => {
  const { clearApifyDown } = await import('../src/integrations/apify.js');
  setSpent(0.1, 1);
  calls = [];
  const broke = (async (u: URL | string) => {
    calls.push(String(u).match(/acts\/([^/]+)\//)![1]);
    return new Response('{"error":{"type":"platform-feature-disabled","message":"Monthly usage hard limit exceeded"}}', { status: 403 });
  }) as typeof fetch;
  const notices: { message: string; data?: Record<string, unknown> }[] = [];
  const src = () => createDealSource(process.env, { fetch: broke, cacheDir: mkdtempSync(path.join(dir, 'cache-')), replayDir, fallback: fixtureDealSource([]) });
  await src().search({ name: 'Bookshelf', category: 'bookshelf' }, { onNotice: n => notices.push(n) });
  assert.equal(calls.length, 2);
  const spent = () => ({ usd: Number(apifySpentToday().usd.toFixed(6)), runs: apifySpentToday().runs });
  assert.deepEqual(spent(), { usd: 0.1, runs: 1 }, 'no phantom spend for runs that never started');
  assert.equal(notices.length, 1);
  assert.match(notices[0].message, /^Live Apify search for "Bookshelf" failed \(.*HTTP 403.*\), using cached replays \/ sample deals instead/);
  assert.equal(notices[0].data?.apifyError, true);

  calls = [];
  notices.length = 0;
  await src().search({ name: 'Lamp', category: 'lamp' }, { onNotice: n => notices.push(n) });
  assert.equal(calls.length, 0, 'no doomed runs while Apify is out of credit');
  assert.deepEqual(spent(), { usd: 0.1, runs: 1 });
  assert.match(notices[0].message, /^Apify unavailable \(out of credit\): skipped the live search for "Lamp"/);
  clearApifyDown();
});

test('cached replays are free: no token never books spend', async () => {
  setSpent(0, 0);
  const noToken = { ...process.env, APIFY_TOKEN: '' };
  await createDealSource(noToken, { fetch: mockFetch, cacheDir: mkdtempSync(path.join(dir, 'cache-')), replayDir }).search({ name: 'Bed frame', category: 'bed' });
  assert.deepEqual(apifySpentToday(), { usd: 0, runs: 0 });
});
