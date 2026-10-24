// The multi-source SAM 3D build (#84) against a fake connection, with fake photos, image search,
// Claude and fal. Own file so the SAM3D_* env is set before config.ts reads it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { Conn } from '../src/spacetime.js';
import type { Item } from '../src/module_bindings/types.js';

process.env.FAL_KEY = 'test-key';
process.env.SAM3D_MAX_USD = '0.20';
process.env.SAM3D_USD_PER_RUN = '0.02';
process.env.SAM3D_SELECT_USD = '0.04';
process.env.SAM3D_IMAGE_SEARCH_MAX_USD = '0.03';
process.env.SAM3D_WEB_IMAGES_MAX = '4';
process.env.SAM3D_MAX_ATTEMPTS = '2';
process.env.SAM3D_CONCURRENCY = '1';
const { build, needsModel, resetSam3dState, sam3dAgent, setSam3dDeps } = await import('../src/agents/sam3d.js');
const { Sam3dUnavailableError } = await import('../src/integrations/sam3d.js');
type Deps = import('../src/agents/sam3d.js').Sam3dDeps;
type PickOutput = import('../src/agents/sam3d-select.js').PickOutput;

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => 'owner' };

function jpeg(width: number, height: number): string {
  const sof = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 255, width >> 8, width & 255, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  return Buffer.from([0xff, 0xd8, ...sof, 0xff, 0xd9]).toString('base64');
}
const photo = (w = 1600, h = 1200) => ({ mediaType: 'image/jpeg' as const, data: jpeg(w, h) });
const GLB = Buffer.from('glTF\x02\0\0\0rest');

const baseItem = (over: Partial<Item> = {}): Item =>
  ({
    id: 1n, owner, name: 'Herman Miller Aeron chair', brand: 'Herman Miller', category: 'chair', material: 'mesh', scanObjectId: 'obj-1',
    widthM: 0.7, depthM: 0.7, heightM: 1.1, photoUrls: ['http://w/files/scan.jpg', 'http://w/files/user.jpg'],
    detailsStatus: 'done', modelStatus: 'pending', modelSource: '', modelUrl: '', ...over,
  }) as unknown as Item;

function fakeConn(items: Item[] = []) {
  const rows = new Map(items.map(i => [i.id, i]));
  const updates: ((ctx: unknown, old: Item, it: Item) => void)[] = [];
  const events: { kind: string; message: string; dataJson: string }[] = [];
  const stages: string[] = [];
  const models: { url: string; source: string }[] = [];
  const set = (it: Item) => {
    const old = rows.get(it.id)!;
    rows.set(it.id, it);
    for (const cb of updates) cb({}, old, it);
  };
  const conn = {
    db: {
      item: {
        iter: () => rows.values(),
        onInsert: () => {},
        onUpdate: (cb: (ctx: unknown, old: Item, it: Item) => void) => updates.push(cb),
      },
    },
    reducers: {
      setItemStage: (a: { itemId: bigint; stage: string }) => {
        stages.push(a.stage);
        const it = rows.get(a.itemId);
        if (it) set({ ...it, modelStatus: a.stage } as Item);
      },
      setItemModel: (a: { itemId: bigint; url: string; source: string }) => {
        models.push(a);
        const it = rows.get(a.itemId);
        if (it) set({ ...it, modelUrl: a.url, modelSource: a.source, modelStatus: 'done' } as Item);
      },
      logAgentEvent: async (e: { kind: string; message: string; dataJson: string }) => void events.push(e),
    },
  };
  return { conn: conn as unknown as Conn, events, stages, models, set, get: (id: bigint) => rows.get(id)! };
}

function fakeDeps(over: Partial<Deps> = {}) {
  const calls = { search: 0, pick: [] as { text: string; images: number }[], reconstruct: [] as { imageUrl: string; box?: unknown; prompt: string }[] };
  const deps: Deps = {
    loadPhoto: async url => (url.includes('scan') ? photo(800, 600) : photo()),
    loadWebImage: async url => {
      if (url.includes('broken')) throw new Error('404');
      return photo(1000, 1000);
    },
    compImages: () => [{ url: 'https://i.ebayimg.com/web0.jpg', title: 'Herman Miller Aeron size B', origin: 'https://ebay/1', source: 'ebay' }],
    searchImages: async () => {
      calls.search++;
      return {
        images: [
          { url: 'https://cdn.example/web1.jpg', title: 'Aeron chair, graphite', origin: 'https://store', source: 'google' },
          { url: 'https://cdn.example/broken.jpg', title: 'gone', origin: '', source: 'google' },
        ],
        replayed: false,
        costUsd: 0.007,
      };
    },
    pick: async o => {
      calls.pick.push({ text: o.text, images: o.images.length });
      // Images: 1 scan, 2 user, 3 eBay listing, 4 Google (the broken one never loaded).
      return {
        images: [
          { image: 1, sameProduct: true, wholeObject: false, score: 4, box: null, reason: 'cut off at the top' },
          { image: 2, sameProduct: true, wholeObject: true, score: 6, box: { x_min: 0.2, y_min: 0.1, x_max: 0.8, y_max: 0.95 }, reason: 'whole chair, cluttered' },
          { image: 3, sameProduct: false, wholeObject: true, score: 8, box: null, reason: 'a Steelcase, not an Aeron' },
          { image: 4, sameProduct: true, wholeObject: true, score: 9, box: { x_min: 0.1, y_min: 0.05, x_max: 0.9, y_max: 0.95 }, reason: 'catalog shot on white' },
        ],
      } satisfies PickOutput;
    },
    reconstruct: async req => {
      calls.reconstruct.push(req);
      return { glb: GLB, sourceUrl: 'https://fal/m.glb', requestId: `r${calls.reconstruct.length}` };
    },
    saveGlb: async () => 'http://w/files/model.glb',
    ...over,
  };
  return { deps, calls };
}

const data = (e: { dataJson: string }) => (e.dataJson ? JSON.parse(e.dataJson) : {});

test('picks a verified web image of the product, with its box, and records the source', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  const { deps, calls } = fakeDeps();
  await build(f.conn, it, deps);

  assert.equal(calls.search, 1);
  assert.deepEqual(calls.pick.map(p => p.images), [4]);
  assert.match(calls.pick[0].text, /Image 3: web image/);
  assert.equal(calls.reconstruct.length, 1);
  assert.deepEqual(calls.reconstruct[0].box, { x_min: 100, y_min: 50, x_max: 900, y_max: 950 }, 'box in the web image pixels');
  assert.equal(calls.reconstruct[0].prompt, 'Herman Miller Aeron chair');
  assert.deepEqual(f.models, [{ itemId: 1n, url: 'http://w/files/model.glb', source: 'sam3d' }]);
  assert.deepEqual(f.stages, ['running']);

  const kinds = f.events.map(e => e.kind);
  assert.deepEqual(kinds, ['plan', 'tool_call', 'tool_call', 'result', 'tool_call', 'result']);
  const pick = data(f.events[3]);
  assert.equal(pick.chosen.source, 'web');
  assert.equal(pick.chosen.webSource, 'google');
  assert.deepEqual(pick.rejected.map((r: { n: number }) => r.n), [3]);
  const fal = data(f.events[4]);
  assert.equal(fal.costUsd, 0.02);
  assert.ok(fal.spentUsd > 0.06 && fal.spentUsd < 0.08, `spent ${fal.spentUsd}`); // search + pick + fal
  const done = data(f.events[5]);
  assert.equal(done.source, 'web');
  assert.equal(done.imageUrl, 'https://cdn.example/web1.jpg');
});

test('a failed SAM 3D run falls back to the next-best image', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  let n = 0;
  const { deps, calls } = fakeDeps({
    reconstruct: async req => {
      calls.reconstruct.push(req);
      if (n++ === 0) throw new Error('result: 422 nothing segmented');
      return { glb: GLB, sourceUrl: 'https://fal/m.glb', requestId: 'r2' };
    },
  });
  await build(f.conn, it, deps);
  assert.equal(calls.reconstruct.length, 2);
  assert.equal(f.models.length, 1);
  const err = f.events.find(e => e.kind === 'error')!;
  assert.match(err.message, /failed on the web image \(google\).*trying the photo 2/);
  const last = data(f.events.at(-1)!);
  assert.equal(last.source, 'user');
  assert.equal(last.attempt, 2);
});

test('every attempt failing marks the model failed', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  const { deps, calls } = fakeDeps({
    reconstruct: async req => {
      calls.reconstruct.push(req);
      throw new Error('boom');
    },
  });
  await build(f.conn, it, deps);
  assert.equal(calls.reconstruct.length, 2, 'SAM3D_MAX_ATTEMPTS');
  assert.deepEqual(f.stages, ['running', 'failed']);
  assert.match(f.events.at(-1)!.message, /failed after 2 attempt/);
});

test('fal unavailable (e.g. no balance): one try, item left pending and backed off', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  const { deps, calls } = fakeDeps({
    reconstruct: async req => {
      calls.reconstruct.push(req);
      throw new Sam3dUnavailableError('submit: 403 {"detail":"Exhausted balance"}');
    },
  });
  assert.equal(await build(f.conn, it, deps), 'retry-later');
  assert.equal(calls.reconstruct.length, 1, "doesn't burn the next image");
  assert.deepEqual(f.stages, ['running', 'pending']);
  const err = f.events.at(-1)!;
  assert.match(err.message, /unavailable, will retry/);
  assert.equal(data(err).retryLater, true);
  assert.equal(needsModel(f.get(1n)), false, 'backing off');
  assert.equal(needsModel(f.get(1n), Date.now() + 601_000), true, 'after the back-off');
});

test('generic items skip the web; a single photo skips Claude', async () => {
  resetSam3dState();
  const it = baseItem({ name: 'office chair', brand: '', photoUrls: ['http://w/files/scan.jpg'] });
  const f = fakeConn([it]);
  const { deps, calls } = fakeDeps();
  await build(f.conn, it, deps);
  assert.equal(calls.search, 0);
  assert.equal(calls.pick.length, 0);
  assert.equal(calls.reconstruct.length, 1);
  assert.equal(data(f.events.at(-1)!).source, 'scan');
});

test('when Claude fails, the newest own photo is used and web images are not', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  const { deps, calls } = fakeDeps({ pick: async () => { throw new Error('no API key'); } });
  await build(f.conn, it, deps);
  assert.equal(calls.reconstruct.length, 1);
  assert.equal(calls.reconstruct[0].box, undefined);
  assert.ok(f.events.some(e => e.kind === 'error' && /Image pick failed/.test(e.message)));
  assert.equal(data(f.events.at(-1)!).source, 'user');
});

test('a failed image search still builds from photos and listing images', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  const { deps, calls } = fakeDeps({ searchImages: async () => { throw new Error('apify 402'); } });
  await build(f.conn, it, deps);
  assert.deepEqual(calls.pick.map(p => p.images), [3]);
  assert.ok(f.events.some(e => e.kind === 'error' && /Image search .* failed/.test(e.message)));
  assert.equal(f.models.length, 1);
});

test('the spend cap stops searches, picks and fal runs', async () => {
  resetSam3dState();
  const f = fakeConn();
  const { deps, calls } = fakeDeps();
  // $0.20 cap, ~$0.067 per item with search + pick + fal.
  // Items 1-2 get everything, 3 skips the pick, 4 skips search and pick, 5 is refused.
  for (let i = 1n; i <= 5n; i++) await build(f.conn, baseItem({ id: i }), deps);
  assert.equal(calls.search, 3);
  assert.equal(calls.pick.length, 2);
  assert.equal(calls.reconstruct.length, 4);
  const refusals = f.events.filter(e => data(e).refused);
  assert.ok(refusals.length >= 1);
  assert.match(refusals.at(-1)!.message, /Spend cap/);
});

test('a photo added mid-build re-queues the item once the build ends', async () => {
  resetSam3dState();
  const it = baseItem();
  const f = fakeConn([it]);
  let release!: () => void;
  const gate = new Promise<void>(r => (release = r));
  const { deps, calls } = fakeDeps({
    reconstruct: async req => {
      calls.reconstruct.push(req);
      if (calls.reconstruct.length === 1) await gate;
      return { glb: GLB, sourceUrl: 'https://fal/m.glb', requestId: 'r' };
    },
  });
  setSam3dDeps(deps);
  sam3dAgent.start(f.conn);
  await sleep(10);
  assert.equal(calls.reconstruct.length, 1, 'first build is running');
  // add_item_photo: new photo, vision and model re-queued.
  f.set({ ...f.get(1n), photoUrls: [...it.photoUrls, 'http://w/files/new.jpg'], detailsStatus: 'pending', modelStatus: 'pending' } as Item);
  release();
  await sleep(10);
  assert.equal(f.get(1n).modelStatus, 'pending', 'set back to pending after our set_item_model');
  assert.equal(calls.reconstruct.length, 1, 'waits for vision');
  f.set({ ...f.get(1n), detailsStatus: 'done' } as Item);
  await sleep(10);
  assert.equal(calls.reconstruct.length, 2, 'rebuilt with the new photo');
  assert.ok(calls.pick.at(-1)!.text.includes('photographed by its owner'));
  assert.equal(calls.pick.at(-1)!.images, 5, 'three own photos + two web');
});
