// Which shopping items get the planted demo scam (fixtures/deals.json, "planted": true). The list
// comes from Claude, so the chair can be named many ways; the planted Aeron must show on any desk or
// office chair, and never on dining chairs, armchairs, chair accessories or other furniture.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fixtureDealSource, hasPlantedDeal, nameWords, plantedMatches } from '../src/integrations/deals.js';
import { createDealSource } from '../src/integrations/deals-apify.js';

const POSITIVE: [string, string][] = [
  ['Desk chair', 'chair'],
  ['desk chair', 'furniture'],
  ['Desk Chair', 'chair'],
  ['DESK CHAIR', 'chair'],
  ['Office chair', 'office chair'],
  ['Ergonomic desk chair', 'chair'],
  ['Ergonomic office chair', 'seating'],
  ['Ergonomic chair', 'chair'],
  ['Task chair', 'chair'],
  ['Computer chair', 'chair'],
  ['Gaming chair', 'chair'],
  ['Mesh office chair', 'chair'],
  ['Swivel desk chair', 'chair'],
  ['Rolling desk chair with arms', 'chair'],
  ['Desk chairs (set of 2)', 'chair'],
  ['Office-chair', 'chair'],
  ['Chair', 'office chair'], // the category says what kind
  ['Seat for the desk nook', 'desk chair'],
];

const NEGATIVE: [string, string][] = [
  ['Dining chairs', 'dining chair'],
  ['Dining chairs (set of 2)', 'chair'],
  ['Dining chair', 'chair'],
  ['Kitchen chairs', 'chair'],
  ['Armchair', 'chair'],
  ['Accent armchair', 'seating'],
  ['Office armchair', 'chair'],
  ['Folding chair', 'chair'],
  ['Rocking chair', 'chair'],
  ['Chair', 'chair'],
  ['Desk', 'desk'],
  ['Office desk', 'desk'],
  ['Standing desk', 'office'],
  ['Desk lamp', 'lamp'],
  ['Office chair mat', 'office'],
  ['Desk chair cushion', 'chair'],
  ['Office chair replacement wheels', 'chair'],
  ['Sofa', 'sofa'],
  ['Chairside table', 'table'],
  ['Highchair', 'chair'],
  ['', ''],
];

test('nameWords: lowercase whole words, punctuation dropped, simple plurals folded', () => {
  assert.deepEqual(nameWords('Desk-Chairs (set of 2)'), ['desk', 'chair', 'set', 'of', '2']);
  assert.deepEqual(nameWords('Glass'), ['glass']);
  assert.deepEqual(nameWords('  '), []);
});

test('planted deal: matches desk/office chairs however Claude names them', () => {
  for (const [name, category] of POSITIVE) assert.ok(hasPlantedDeal({ name, category }), `should match "${name}" [${category}]`);
});

test('planted deal: never dining chairs, armchairs, plain chairs, accessories or other furniture', () => {
  for (const [name, category] of NEGATIVE) assert.ok(!hasPlantedDeal({ name, category }), `should not match "${name}" [${category}]`);
});

test('plantedMatches is data-driven: plantedFor phrases and plantedExcept words', () => {
  const row = { plantedFor: ['bed frame'], plantedExcept: ['slat'] };
  assert.ok(plantedMatches(row, { name: 'Queen Bed Frames', category: 'bed' }));
  assert.ok(!plantedMatches(row, { name: 'Bed frame slats', category: 'bed' }));
  assert.ok(!plantedMatches(row, { name: 'Frame for the bed', category: 'bed' }), 'phrase words must be in order');
  assert.ok(!plantedMatches({}, { name: 'Bed frame', category: 'bed' }), 'no plantedFor, never planted');
});

test('fixture source serves the planted row only on matching items, and only once', async () => {
  const src = fixtureDealSource();
  for (const name of ['Ergonomic desk chair', 'Office chair', 'Gaming chair']) {
    const planted = (await src.search({ name, category: 'chair' })).filter(d => d.planted);
    assert.equal(planted.length, 1, name);
    assert.equal(planted[0].title, 'Herman Miller Aeron, brand new, $95, Zelle only, ship only');
    assert.ok(planted[0].sample);
  }
  for (const name of ['Dining chairs', 'Armchair', 'Sofa']) {
    assert.ok(!(await src.search({ name, category: 'chair' })).some(d => d.planted), name);
  }
});

test('demo path without APIFY_TOKEN: planted row rides along with replayed live chairs and a card deal', async () => {
  // fixtures/deals-live-office-chair.json is a committed replay: the planted row must still come along.
  const found = await createDealSource({}).search({ name: 'Office chair', category: 'office chair' });
  assert.ok(found.some(d => d.replay && !d.sample), 'replayed live listings');
  assert.ok(found.some(d => d.checkout === 'visa'), 'a card-checkout option');
  assert.equal(found.filter(d => d.planted).length, 1);
  // A name with no committed replay falls through to the sample data, planted row included.
  const sample = await createDealSource({}).search({ name: 'Ergonomic gaming chair', category: 'chair' });
  assert.ok(sample.every(d => d.sample) && sample.some(d => d.planted));
});
