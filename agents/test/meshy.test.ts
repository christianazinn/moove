import { test, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fixtureUsdz, generateModel, isZip, MeshyError } from '../src/integrations/meshy.js';
import { buildMeshyModel, meshyAgent, meshyClaimsModels, needsMeshyModel } from '../src/agents/meshy.js';
import { sam3dAgent } from '../src/agents/sam3d.js';
import { config, meshyEnabled } from '../src/config.js';
import type { Conn } from '../src/spacetime.js';
import type { Item } from '../src/module_bindings/types.js';

const API = 'https://api.meshy.ai/openapi/v1/image-to-3d';
const USDZ = Buffer.concat([Buffer.from('PK\x03\x04', 'latin1'), Buffer.alloc(60)]);

const item = (over: Partial<Item> = {}): Item =>
  ({
    id: 1n, owner: 'owner-1', name: 'IKEA Poang chair', category: 'chair', photoUrls: ['http://x/1.jpg'],
    detailsStatus: 'done', modelStatus: 'pending', modelSource: '', modelUrl: '', ...over,
  }) as unknown as Item;

// A fake Meshy API: create -> PENDING -> SUCCEEDED (or a given final task) -> USDZ download.
function fakeMeshy(opts: { final?: Record<string, unknown>; usdz?: Buffer; headers?: Record<string, string> } = {}) {
  const calls: string[] = [];
  let polls = 0;
  const f = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url);
    calls.push(`${init?.method ?? 'GET'} ${u}`);
    const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
    if (u === 'http://x/1.jpg') return new Response(Buffer.from([0xff, 0xd8, 0xff, 0xe0]), { headers: { 'content-type': 'image/jpeg' } });
    if (u === API && init?.method === 'POST') {
      assert.equal((init.headers as Record<string, string>).authorization, 'Bearer test-key');
      const body = JSON.parse(String(init.body));
      assert.match(body.image_url, /^data:image\/jpeg;base64,/);
      assert.deepEqual(body.target_formats, ['usdz']);
      return json({ result: 'task-1' });
    }
    if (u === `${API}/task-1`) {
      if (polls++ === 0) return json({ status: 'PENDING', progress: 0 });
      return json(opts.final ?? { status: 'SUCCEEDED', progress: 100, model_urls: { usdz: 'https://assets.meshy.ai/m.usdz' }, consumed_credits: 30 });
    }
    if (u === 'https://assets.meshy.ai/m.usdz') return new Response(new Uint8Array(opts.usdz ?? USDZ), { headers: opts.headers });
    return new Response('nope', { status: 404 });
  }) as typeof fetch;
  return { f, calls };
}

const req = { imageUrl: 'data:image/jpeg;base64,AAAA' };
const run = (f: typeof fetch, extra: { maxBytes?: number } = {}) => generateModel(req, { key: 'test-key', fetch: f, pollMs: 1, ...extra });

// A fake connection that records reducer calls.
function fakeConn(items: Item[] = []) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  let listeners = 0;
  // Reducers return promises (logEvent chains .catch on them).
  const rec = (name: string) => (args: Record<string, unknown>) => (calls.push({ name, args }), Promise.resolve());
  const conn = {
    db: { item: { iter: () => items[Symbol.iterator](), onInsert: () => void listeners++, onUpdate: () => void listeners++ } },
    reducers: { setItemStage: rec('setItemStage'), setItemModel: rec('setItemModel'), logAgentEvent: rec('logAgentEvent') },
  } as unknown as Conn;
  const events = () => calls.filter(c => c.name === 'logAgentEvent').map(c => ({ kind: c.args.kind as string, message: c.args.message as string, data: c.args.dataJson ? JSON.parse(c.args.dataJson as string) : undefined }));
  return { conn, calls, events, listeners: () => listeners };
}

let dir = '';
const saved = { meshy: { ...config.meshy }, sam3d: { ...config.sam3d }, uploadDir: config.uploadDir, fetch: globalThis.fetch };
before(() => {
  dir = mkdtempSync(path.join(tmpdir(), 'meshy-'));
  config.uploadDir = dir;
});
after(() => {
  rmSync(dir, { recursive: true, force: true });
  config.uploadDir = saved.uploadDir;
});
beforeEach(() => {
  Object.assign(config.meshy, saved.meshy);
  Object.assign(config.sam3d, saved.sam3d);
  // No test may reach the network unless it installs its own fake.
  globalThis.fetch = (async (u: string | URL) => { throw new Error(`unexpected fetch ${String(u)}`); }) as typeof fetch;
});
afterEach(() => {
  globalThis.fetch = saved.fetch;
});

test('off by default: needs MOOVE_MESHY_ENABLED=1 and a key (or simulated)', () => {
  assert.equal(meshyEnabled({}), false);
  assert.equal(meshyEnabled({ MESHY_API_KEY: 'k' }), false);
  assert.equal(meshyEnabled({ MOOVE_MESHY_ENABLED: '1' }), false);
  assert.equal(meshyEnabled({ MOOVE_MESHY_ENABLED: 'true', MESHY_API_KEY: 'k' }), false);
  assert.equal(meshyEnabled({ MOOVE_MESHY_ENABLED: '1', MESHY_API_KEY: 'k' }), true);
  assert.equal(meshyEnabled({ MOOVE_MESHY_ENABLED: '1', MESHY_SIMULATED: '1' }), true);
  config.meshy.enabled = false;
  const { conn, calls, listeners } = fakeConn([item()]);
  meshyAgent.start(conn);
  assert.equal(listeners(), 0);
  assert.equal(calls.length, 0);
});

test('needsMeshyModel: photo, vision finished, pending, not captured', () => {
  assert.equal(needsMeshyModel(item()), true);
  assert.equal(needsMeshyModel(item({ photoUrls: [] })), false);
  assert.equal(needsMeshyModel(item({ detailsStatus: 'pending' })), false);
  assert.equal(needsMeshyModel(item({ modelStatus: 'running' })), false);
  assert.equal(needsMeshyModel(item({ modelSource: 'capture' })), false);
});

test('generateModel: submits the photo, polls, downloads the USDZ', async () => {
  const { f, calls } = fakeMeshy();
  const r = await run(f);
  assert.equal(r.taskId, 'task-1');
  assert.equal(r.credits, 30);
  assert.ok(isZip(r.usdz));
  assert.deepEqual(calls, [`POST ${API}`, `GET ${API}/task-1`, `GET ${API}/task-1`, 'GET https://assets.meshy.ai/m.usdz']);
});

test('generateModel: a FAILED task surfaces its error, no download', async () => {
  const { f, calls } = fakeMeshy({ final: { status: 'FAILED', task_error: { message: 'no object found' }, consumed_credits: 0 } });
  await assert.rejects(run(f), (e: Error) => e instanceof MeshyError && /FAILED: no object found/.test(e.message));
  assert.ok(!calls.some(c => c.includes('m.usdz')));
  const canceled = fakeMeshy({ final: { status: 'CANCELED' } });
  await assert.rejects(run(canceled.f), /CANCELED/);
});

test('generateModel: rejects a download that is not a zip, non-https URLs and a missing key', async () => {
  await assert.rejects(run(fakeMeshy({ usdz: Buffer.from('<html>oops</html>') }).f), /not a USDZ/);
  await assert.rejects(run(fakeMeshy({ final: { status: 'SUCCEEDED', model_urls: { usdz: 'http://evil/m.usdz' } } }).f), /no USDZ/);
  await assert.rejects(run(fakeMeshy({ final: { status: 'SUCCEEDED', model_urls: { glb: 'https://a/m.glb' } } }).f), /no USDZ/);
  await assert.rejects(generateModel(req, { key: '', fetch: fakeMeshy().f }), /MESHY_API_KEY/);
});

test('generateModel: enforces the size cap (declared and actual)', async () => {
  await assert.rejects(run(fakeMeshy().f, { maxBytes: 10 }), /over 10 bytes/);
  await assert.rejects(run(fakeMeshy({ headers: { 'content-length': '999999' } }).f, { maxBytes: 1000 }), /over 1000 bytes/);
  assert.ok(isZip((await run(fakeMeshy().f, { maxBytes: USDZ.length })).usdz));
});

test('agent: photo -> Meshy -> USDZ in uploads -> set_item_model(meshy), events logged with cost', async () => {
  Object.assign(config.meshy, { enabled: true, simulated: false, usdPerRun: 0.6, maxUsd: 100 });
  process.env.MESHY_API_KEY = 'test-key';
  try {
    globalThis.fetch = fakeMeshy().f;
    // The real poll waits 5 s between checks; collapse it for the test.
    const realTimeout = globalThis.setTimeout;
    globalThis.setTimeout = ((fn: () => void) => realTimeout(fn, 0)) as typeof setTimeout;
    const { conn, calls, events } = fakeConn();
    try {
      await buildMeshyModel(conn, item());
    } finally {
      globalThis.setTimeout = realTimeout;
    }
    const set = calls.find(c => c.name === 'setItemModel')!;
    assert.equal(set.args.source, 'meshy');
    assert.match(set.args.url as string, /\/files\/[0-9a-f-]{36}\.usdz$/);
    assert.ok(isZip(readFileSync(path.join(dir, path.basename(set.args.url as string)))));
    const ev = events();
    assert.deepEqual(ev.map(e => e.kind), ['plan', 'tool_call', 'result']);
    assert.equal(ev[1].data.costUsd, 0.6);
    assert.equal(ev[2].data.credits, 30);
    assert.equal(ev[2].data.simulated, false);
  } finally {
    delete process.env.MESHY_API_KEY;
  }
});

test('agent: a failed Meshy task marks the model failed and logs an error', async () => {
  Object.assign(config.meshy, { enabled: true, simulated: false, usdPerRun: 0.6, maxUsd: 100 });
  process.env.MESHY_API_KEY = 'test-key';
  const realTimeout = globalThis.setTimeout;
  globalThis.setTimeout = ((fn: () => void) => realTimeout(fn, 0)) as typeof setTimeout;
  try {
    globalThis.fetch = fakeMeshy({ final: { status: 'FAILED', task_error: { message: 'bad photo' } } }).f;
    const { conn, calls, events } = fakeConn();
    await buildMeshyModel(conn, item({ id: 2n }));
    assert.ok(!calls.some(c => c.name === 'setItemModel'));
    assert.deepEqual(calls.filter(c => c.name === 'setItemStage').map(c => c.args.stage), ['running', 'failed']);
    assert.match(events().at(-1)!.message, /bad photo/);
  } finally {
    globalThis.setTimeout = realTimeout;
    delete process.env.MESHY_API_KEY;
  }
});

test('agent: spend cap refuses before any call or state change', async () => {
  Object.assign(config.meshy, { enabled: true, simulated: false, usdPerRun: 0.6, maxUsd: 0.5 });
  const { conn, calls, events } = fakeConn();
  await buildMeshyModel(conn, item({ id: 3n }));
  assert.ok(!calls.some(c => c.name === 'setItemStage' || c.name === 'setItemModel'));
  const ev = events();
  assert.equal(ev.length, 1);
  assert.equal(ev[0].kind, 'error');
  assert.equal(ev[0].data.refused, true);
  assert.equal(ev[0].data.capUsd, 0.5);
});

test('no double-processing: with Meshy enabled, SAM 3D stands down', () => {
  Object.assign(config.sam3d, { enabled: true });
  Object.assign(config.meshy, { enabled: false });
  assert.equal(meshyClaimsModels(), false);
  const plain = fakeConn([]);
  sam3dAgent.start(plain.conn);
  assert.equal(plain.listeners(), 2); // SAM 3D runs alone

  Object.assign(config.meshy, { enabled: true, simulated: true });
  assert.equal(meshyClaimsModels(), true);
  const both = fakeConn([]);
  sam3dAgent.start(both.conn);
  assert.equal(both.listeners(), 0); // SAM 3D never subscribes
  meshyAgent.start(both.conn);
  assert.equal(both.listeners(), 2); // Meshy owns the items
});

test('simulated: fixture USDZ, labeled simulated, no network, no spend', async () => {
  Object.assign(config.meshy, { enabled: true, simulated: true, usdPerRun: 0.6, maxUsd: 0 });
  const { conn, calls, events } = fakeConn();
  await buildMeshyModel(conn, item({ id: 4n }));
  const set = calls.find(c => c.name === 'setItemModel')!;
  assert.equal(set.args.source, 'meshy');
  const file = readFileSync(path.join(dir, path.basename(set.args.url as string)));
  assert.deepEqual(file, fixtureUsdz());
  const ev = events();
  assert.deepEqual(ev.map(e => e.kind), ['plan', 'tool_call', 'result']);
  assert.ok(ev.every(e => e.data.simulated === true));
  assert.ok(ev.every(e => e.message.startsWith('[SIMULATED]')));
  assert.equal(ev[1].data.costUsd, 0);
});

test('fixtureUsdz: a stored zip with one 64-byte-aligned .usda', () => {
  const z = fixtureUsdz();
  assert.ok(isZip(z));
  assert.equal(z.readUInt16LE(8), 0); // stored, not deflated
  const nameLen = z.readUInt16LE(26);
  const dataAt = 30 + nameLen + z.readUInt16LE(28);
  assert.equal(z.subarray(30, 30 + nameLen).toString(), 'model.usda');
  assert.equal(dataAt % 64, 0);
  assert.match(z.subarray(dataAt, dataAt + 9).toString(), /^#usda 1\.0/);
  assert.equal(z.readUInt32LE(z.length - 22), 0x06054b50); // end of central directory
});
