import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { estimateQuotes, truckCostCents, roundHigh, roundLow } from '../src/moves/rates.js';
import { getMoverQuotes, parseQuoteBody, QuoteInputError, QUOTES_NOTE } from '../src/moves/quotes.js';
import { adsFromRows, findListedRates, listedQuotes, parseRate } from '../src/moves/listedRates.js';

const dir = mkdtempSync(path.join(tmpdir(), 'moove-movers-'));
after(() => rmSync(dir, { recursive: true, force: true }));

// ---------- rate math (golden numbers; MooveKit MoverRatesTests.swift checks the same ones) ----------

test('rate table: 15 ft truck, 2 movers, 4 h, default 25 miles', () => {
  const q = estimateQuotes({ volumeM3: 14, truckSize: 'ft15', trucks: 1, crew: 2, hours: 4 });
  assert.deepEqual(truckCostCents({ volumeM3: 14, truckSize: 'ft15', trucks: 1, crew: 2, hours: 4 }), [7345, 11220]);
  assert.deepEqual(q.map(x => [x.id, x.lowCents, x.highCents]), [
    ['estimate-diy', 7000, 12000],
    ['estimate-labor', 35000, 52000],
    ['estimate-full', 60000, 90000],
  ]);
  for (const x of q) {
    assert.equal(x.kind, 'estimate');
    assert.equal(x.estimate, true);
    assert.equal(x.simulated, false);
    assert.ok(x.source.name && x.source.url?.startsWith('https://'));
    assert.ok(x.includes.length > 0);
    assert.ok(x.lowCents < x.highCents);
  }
  assert.match(q[0].assumptions.join(' '), /25 miles of driving \(assumed/);
});

test('rate table: minimum hours, several trucks, given miles', () => {
  const q = estimateQuotes({ volumeM3: 60, truckSize: 'ft26', trucks: 2, crew: 3, hours: 1, miles: 10 });
  assert.deepEqual(q.map(x => [x.lowCents, x.highCents]), [
    [13000, 19000],
    [34000, 49000],
    [54000, 81000],
  ]);
  assert.match(q[0].includes[0], /2 × 26 ft truck/);
  assert.match(q[1].includes[0], /3 movers .*~2 h/);
  assert.match(q[2].includes[0], /~3 h with travel/);
});

test('rounding: low down, high up, to $10', () => {
  assert.equal(roundLow(7999), 7000);
  assert.equal(roundHigh(7001), 8000);
  assert.equal(roundHigh(8000), 8000);
});

// ---------- input ----------

test('parseQuoteBody validates and normalizes', () => {
  const q = parseQuoteBody({ volumeM3: 12.34, truckSize: 'ft15', crew: 2, hours: 3.4, miles: 12.6, fromCity: 'Berkeley<script>', roomId: 7 });
  assert.equal(q.volumeM3, 12.3);
  assert.equal(q.hours, 3.5);
  assert.equal(q.miles, 13);
  assert.equal(q.trucks, 1);
  assert.equal(q.roomId, '7');
  assert.equal(q.fromCity, 'Berkeley script');
  assert.throws(() => parseQuoteBody({ volumeM3: 5, truckSize: 'bus', crew: 2, hours: 3 }), QuoteInputError);
  assert.throws(() => parseQuoteBody({ volumeM3: 5, truckSize: 'ft10', crew: 0, hours: 3 }), QuoteInputError);
  assert.throws(() => parseQuoteBody({ volumeM3: 5, truckSize: 'ft10', crew: 2, hours: 3, fromZip: '9470' }), QuoteInputError);
  assert.throws(() => parseQuoteBody([1]), QuoteInputError);
});

// ---------- the agent ----------

test('every step is logged as an agent event and returned', async () => {
  const events: { kind: string; message: string; data: any }[] = [];
  const r = await getMoverQuotes({ volumeM3: 14, truckSize: 'ft15', crew: 2, hours: 4, roomId: '3' }, { apifyMovers: false, log: (kind, message, data) => events.push({ kind, message, data }) });
  assert.equal(r.quotes.length, 3);
  assert.equal(r.note, QUOTES_NOTE);
  assert.equal(r.computedBy, 'worker');
  assert.deepEqual(r.steps.map(s => s.message), events.map(e => e.message));
  assert.equal(events[0].message, "Requested quotes for a 15' truck, 2 movers, ~4 h");
  assert.ok(events.some(e => e.message === 'Estimate: Full-service local movers $600–$900'));
  assert.ok(events.every(e => e.data.requestId && e.data.roomId === '3'));
  assert.ok(!events.some(e => /Craigslist/.test(e.message)), 'listed rates are off by default');
});

test('APIFY_MOVERS: listed rates are added, labeled, with source URLs', async () => {
  const events: string[] = [];
  const r = await getMoverQuotes(
    { volumeM3: 14, truckSize: 'ft15', crew: 2, hours: 4 },
    {
      apifyMovers: true,
      log: (_k, m) => events.push(m),
      listedRates: async () => ({ ads: [{ title: '2 movers $90/hr', url: 'https://sfbay.craigslist.org/eby/lbs/d/x/1.html', rateCents: 9000, crew: 2 }], replayed: true }),
    }
  );
  assert.equal(r.quotes.length, 4);
  const l = r.quotes[3];
  assert.equal(l.kind, 'listed rate');
  assert.equal(l.estimate, true);
  assert.equal(l.source.url, 'https://sfbay.craigslist.org/eby/lbs/d/x/1.html');
  assert.deepEqual([l.lowCents, l.highCents], [36000, 45000]);
  assert.ok(events.some(m => m.startsWith('[REPLAYED] Listed rate:')));
});

test('listed-rate failures are logged, estimates still returned', async () => {
  const kinds: string[] = [];
  const r = await getMoverQuotes({ volumeM3: 5, truckSize: 'ft10', crew: 2, hours: 2 }, { apifyMovers: true, log: k => kinds.push(k), listedRates: async () => { throw new Error('boom'); } });
  assert.equal(r.quotes.length, 3);
  assert.ok(kinds.includes('error'));
});

// ---------- listed rates (Craigslist via Apify) ----------

test('parseRate reads hourly rates and crew sizes, rejects the rest', () => {
  assert.deepEqual(parseRate('Two movers $95/hr licensed'), { rateCents: 9500, crew: 2 });
  assert.deepEqual(parseRate('Moving help $60 per hour'), { rateCents: 6000, crew: null });
  assert.equal(parseRate('Movers, call for price'), null);
  assert.equal(parseRate('$5/hr movers'), null);
  assert.equal(parseRate('Truck $900 flat'), null);
});

test('adsFromRows keeps craigslist posts with a rate, deduped', () => {
  const ads = adsFromRows([
    { title: '3 men $150/hr', url: 'https://sfbay.craigslist.org/sfc/lbs/d/a/1.html' },
    { title: '3 men $150/hr', url: 'https://sfbay.craigslist.org/sfc/lbs/d/a/1.html' },
    { title: 'Movers $80/hr', url: 'https://evil.example/1.html' },
    { title: 'ad', url: 'https://sfbay.craigslist.org/sfc/lbs/d/a/2.html', label: 'ad' },
  ]);
  assert.equal(ads.length, 1);
  assert.equal(ads[0].crew, 3);
});

test('listedQuotes scales the advertised rate to our crew', () => {
  const [q] = listedQuotes([{ title: '3 men $150/hr', url: 'https://x.craigslist.org/a.html', rateCents: 15000, crew: 3 }], { volumeM3: 5, truckSize: 'ft10', trucks: 1, crew: 2, hours: 3 }, false);
  assert.deepEqual([q.lowCents, q.highCents], [30000, 40000]);
  assert.match(q.assumptions[0], /Scaled to 2 movers/);
});

test('findListedRates: respects the daily Apify cap, books spend, caches and replays', async () => {
  const spendFile = path.join(dir, 'spend.json');
  const cacheDir = path.join(dir, 'cache');
  let calls = 0;
  const fakeFetch = (async () => {
    calls++;
    return new Response(JSON.stringify([{ title: '2 movers $100/hr', url: 'https://sfbay.craigslist.org/eby/lbs/d/m/9.html' }]), { status: 200 });
  }) as unknown as typeof fetch;
  const opts = { token: 't', city: 'sfbay', fetch: fakeFetch, cacheDir, replayDir: path.join(dir, 'none'), spendFile, maxUsdPerDay: 0.15, maxUsdPerRun: 0.1 };
  const live = await findListedRates(opts);
  assert.equal(calls, 1);
  assert.equal(live.replayed, false);
  assert.equal(live.ads[0].rateCents, 10000);
  assert.ok(JSON.parse(readFileSync(spendFile, 'utf8')));
  // A second run would pass the $0.15 cap: no fetch, the cached search comes back labeled.
  const capped = await findListedRates(opts);
  assert.equal(calls, 1);
  assert.equal(capped.capped, true);
  assert.equal(capped.replayed, true);
  assert.equal(capped.ads.length, 1);
});

test('findListedRates without a token never fetches', async () => {
  let calls = 0;
  const r = await findListedRates({ token: '', fetch: (async () => { calls++; return new Response('[]'); }) as unknown as typeof fetch, cacheDir: path.join(dir, 'c2'), replayDir: path.join(dir, 'none'), spendFile: path.join(dir, 's2.json') });
  assert.equal(calls, 0);
  assert.deepEqual(r.ads, []);
  assert.match(r.notice ?? '', /APIFY_TOKEN/);
});

// ---------- the HTTP endpoint ----------

let server: Server;
let base = '';
before(async () => {
  process.env.UPLOAD_DIR = path.join(dir, 'uploads');
  process.env.PUBLIC_UPLOAD_BASE_URL = 'http://public.example';
  const { startUploadServer } = await import('../src/upload.js');
  server = startUploadServer(0);
  await new Promise(r => server.once('listening', r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(() => server?.close());

const post = (body: string, type = 'application/json') => fetch(`${base}/moves/quotes`, { method: 'POST', headers: { 'content-type': type }, body });

test('POST /moves/quotes returns three labeled estimates', async () => {
  const res = await post(JSON.stringify({ volumeM3: 14, truckSize: 'ft15', crew: 2, hours: 4 }));
  assert.equal(res.status, 200);
  const j = (await res.json()) as any;
  assert.equal(j.quotes.length, 3);
  assert.deepEqual(j.quotes.map((q: any) => q.provider), ['DIY truck rental', 'Labor-only movers', 'Full-service local movers']);
  for (const q of j.quotes) {
    for (const k of ['id', 'kind', 'moverType', 'provider', 'lowCents', 'highCents', 'includes', 'assumptions', 'estimate', 'simulated', 'source']) assert.ok(k in q, k);
  }
  assert.equal(j.note, 'Estimates from published rates. Call to book.');
  assert.ok(Array.isArray(j.steps) && j.steps.length >= 5);
});

test('POST /moves/quotes rejects bad input', async () => {
  assert.equal((await post('{"truckSize":"ft15"}')).status, 400);
  assert.equal((await post('not json')).status, 400);
  assert.equal((await post('{}', 'text/plain')).status, 415);
  assert.equal((await post(JSON.stringify({ pad: 'x'.repeat(9000) }))).status, 413);
});

