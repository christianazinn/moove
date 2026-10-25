import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isGenericQuery, needsPricing } from '../src/agents/pricing.js';
import type { Item } from '../src/module_bindings/types.js';

const item = (o: Partial<Item>): Item =>
  ({ id: 1n, name: '', category: 'other', brand: '', photoUrls: [], detailsStatus: 'pending', pricingStatus: 'pending', ...o }) as Item;

test('generic RoomPlan names are not priced until something names the item', () => {
  assert.equal(isGenericQuery(item({ name: 'other' })), true);
  assert.equal(isGenericQuery(item({ name: '', category: 'Storage' })), true);
  assert.equal(needsPricing(item({ name: 'other' })), false);
  // vision or a rename gives it a real name -> priced
  assert.equal(needsPricing(item({ name: 'IKEA Kallax shelf', detailsStatus: 'done' })), true);
  // a brand alone makes the query specific enough
  assert.equal(isGenericQuery(item({ name: 'storage', brand: 'IKEA' })), false);
});

test('specific names without photos are still priced right away', () => {
  assert.equal(needsPricing(item({ name: 'bicycle', category: 'bicycle' })), true);
  assert.equal(needsPricing(item({ name: 'bicycle', pricingStatus: 'done' })), false);
});

test('a built-in fixture is marked done without a comps lookup', async () => {
  const { pricingAgent, setCompsSource } = await import('../src/agents/pricing.js');
  let lookups = 0;
  setCompsSource(async () => { lookups++; return { comps: [], replayed: false }; });
  const toilet = item({ id: 7n, name: 'white two-piece elongated toilet', category: 'appliance', detailsStatus: 'done' });
  const stages: Record<string, unknown>[] = [];
  const events: { message: string }[] = [];
  const conn = {
    db: { item: { iter: () => [toilet].values(), id: { find: () => toilet }, onInsert: () => {}, onUpdate: () => {} } },
    reducers: {
      setItemStage: async (a: Record<string, unknown>) => void stages.push(a),
      logAgentEvent: async (e: { message: string }) => void events.push(e),
    },
  };
  pricingAgent.start(conn as never);
  await new Promise(r => setTimeout(r, 30));
  assert.equal(lookups, 0);
  assert.deepEqual(stages.at(-1), { itemId: 7n, stage: 'done', field: 'pricing' });
  assert.ok(events.some(e => /built-in fixture/.test(e.message)));
});

test('a generic item with no photo waits for the photo, then stops saying pricing', async () => {
  const { photoWaitLeftMs, PHOTO_WAIT_MS } = await import('../src/agents/pricing.js');
  const at = (ms: number) => ({ toMillis: () => BigInt(ms) }) as unknown as Item['createdAt'];
  const now = 10 * PHOTO_WAIT_MS;
  // just imported: the photo upload may still be retrying
  assert.equal(photoWaitLeftMs(item({ name: 'storage', createdAt: at(now - 60_000) }), now), PHOTO_WAIT_MS - 60_000);
  // past the app's retry window: time to give up
  assert.equal(photoWaitLeftMs(item({ name: 'storage', createdAt: at(now - PHOTO_WAIT_MS - 1) }), now), 0);
  // a photo, a real name or a finished stage: not this case
  assert.equal(photoWaitLeftMs(item({ name: 'storage', photoUrls: ['https://x/a.jpg'], createdAt: at(0) }), now), null);
  assert.equal(photoWaitLeftMs(item({ name: 'bicycle', category: 'bicycle', createdAt: at(0) }), now), null);
  assert.equal(photoWaitLeftMs(item({ name: 'storage', pricingStatus: 'failed', createdAt: at(0) }), now), null);
});

test('an old photo-less storage box is marked not priced when the worker starts', async () => {
  const { pricingAgent } = await import('../src/agents/pricing.js');
  const box = item({ id: 9n, name: 'storage', category: 'storage', createdAt: { toMillis: () => 0n } as unknown as Item['createdAt'] });
  const stages: Record<string, unknown>[] = [];
  const events: { message: string }[] = [];
  const conn = {
    db: { item: { iter: () => [box].values(), id: { find: () => box }, onInsert: () => {}, onUpdate: () => {} } },
    reducers: {
      setItemStage: async (a: Record<string, unknown>) => void stages.push(a),
      logAgentEvent: async (e: { message: string }) => void events.push(e),
    },
  };
  pricingAgent.start(conn as never);
  await new Promise(r => setTimeout(r, 30));
  assert.deepEqual(stages.find(s => s.itemId === 9n), { itemId: 9n, stage: 'failed', field: 'pricing' });
  assert.ok(events.some(e => /no photo/.test(e.message)));
});
