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
