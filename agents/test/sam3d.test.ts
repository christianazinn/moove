import { test } from 'node:test';
import assert from 'node:assert/strict';
import { glbUrlFrom, reconstruct, Sam3dError, Sam3dUnavailableError } from '../src/integrations/sam3d.js';
import { needsModel, promptFor } from '../src/agents/sam3d.js';
import type { Item } from '../src/module_bindings/types.js';

const item = (over: Partial<Item> = {}): Item =>
  ({
    id: 1n, name: 'Herman Miller Aeron chair', category: 'chair', photoUrls: ['http://x/1.jpg'],
    detailsStatus: 'done', modelStatus: 'pending', modelSource: '', modelUrl: '', ...over,
  }) as unknown as Item;

test('needsModel: photo, vision finished, pending, not captured', () => {
  assert.equal(needsModel(item()), true);
  assert.equal(needsModel(item({ photoUrls: [] })), false);
  assert.equal(needsModel(item({ detailsStatus: 'pending' })), false);
  assert.equal(needsModel(item({ detailsStatus: 'failed' })), true);
  assert.equal(needsModel(item({ modelStatus: 'done' })), false);
  assert.equal(needsModel(item({ modelSource: 'capture' })), false);
});

test('promptFor: short, plain text, falls back to category', () => {
  assert.equal(promptFor(item()), 'Herman Miller Aeron chair');
  assert.equal(promptFor(item({ name: '' })), 'chair');
  assert.equal(promptFor(item({ name: 'Lamp <script>{"x":1}' })), 'Lamp  script   x  1');
  assert.ok(promptFor(item({ name: 'a'.repeat(200) })).length <= 80);
});

test('glbUrlFrom: single mesh, then per-object, else undefined', () => {
  assert.equal(glbUrlFrom({ model_glb: { url: 'https://a/m.glb' } }), 'https://a/m.glb');
  assert.equal(glbUrlFrom({ individual_glbs: [{}, { url: 'https://a/1.glb' }] }), 'https://a/1.glb');
  assert.equal(glbUrlFrom({ gaussian_splat: { url: 'https://a/s.ply' } }), undefined);
  assert.equal(glbUrlFrom(null), undefined);
});

// A fake fal queue: submit -> IN_PROGRESS -> COMPLETED -> result -> GLB download.
function fakeFal(result: unknown, glb = Buffer.from('glTF\x02\0\0\0rest-of-file')) {
  const calls: string[] = [];
  let polls = 0;
  const f = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url);
    calls.push(`${init?.method ?? 'GET'} ${u}`);
    const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
    if (u === 'https://queue.fal.run/fal-ai/sam-3/3d-objects') {
      assert.equal((init?.headers as Record<string, string>).authorization, 'Key test-key');
      const body = JSON.parse(String(init?.body));
      assert.match(body.image_url, /^data:image\/jpeg;base64,/);
      assert.equal(body.prompt, 'office chair');
      return json({ request_id: 'r1', status_url: 'https://q/status', response_url: 'https://q/result' });
    }
    if (u === 'https://q/status') return json({ status: polls++ === 0 ? 'IN_PROGRESS' : 'COMPLETED' });
    if (u === 'https://q/result') return json(result);
    if (u === 'https://cdn/m.glb') return new Response(glb);
    return new Response('nope', { status: 404 });
  }) as typeof fetch;
  return { f, calls };
}

test('reconstruct: submits, polls, downloads the GLB', async () => {
  const { f, calls } = fakeFal({ model_glb: { url: 'https://cdn/m.glb' } });
  const r = await reconstruct({ imageUrl: 'data:image/jpeg;base64,AAAA', prompt: 'office chair' }, { key: 'test-key', fetch: f, pollMs: 1 });
  assert.equal(r.requestId, 'r1');
  assert.equal(r.glb.subarray(0, 4).toString('latin1'), 'glTF');
  assert.deepEqual(calls.map(c => c.split(' ')[1]), ['https://queue.fal.run/fal-ai/sam-3/3d-objects', 'https://q/status', 'https://q/status', 'https://q/result', 'https://cdn/m.glb']);
});

test('reconstruct: rejects a download that is not a GLB, and missing keys', async () => {
  const { f } = fakeFal({ model_glb: { url: 'https://cdn/m.glb' } }, Buffer.from('<html>oops</html>'));
  await assert.rejects(reconstruct({ imageUrl: 'data:image/jpeg;base64,AAAA', prompt: 'office chair' }, { key: 'test-key', fetch: f, pollMs: 1 }), Sam3dError);
  await assert.rejects(reconstruct({ imageUrl: 'x', prompt: 'y' }, { key: '', fetch: f }), /FAL_KEY/);
});

test('reconstruct: an account or quota refusal is "unavailable", a bad photo is a plain failure', async () => {
  const answer = (status: number) => (async () => new Response('{"detail":"Exhausted balance"}', { status })) as unknown as typeof fetch;
  const req = { imageUrl: 'data:image/jpeg;base64,AAAA', prompt: 'chair' };
  for (const status of [401, 403, 429, 503]) {
    await assert.rejects(reconstruct(req, { key: 'k', fetch: answer(status) }), Sam3dUnavailableError, String(status));
  }
  await assert.rejects(reconstruct(req, { key: 'k', fetch: answer(400) }), (e: unknown) => e instanceof Sam3dError && !(e instanceof Sam3dUnavailableError));
});
