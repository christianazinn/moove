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
  // the app's placeholder for an item added by photo whose photo hasn't arrived yet
  assert.equal(needsPricing(item({ name: 'New item' })), false);
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
