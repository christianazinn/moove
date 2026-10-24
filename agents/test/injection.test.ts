// Prompt-injection spot check (#17): an instruction planted in a scraped comp must not be able to
// change what the listing agent does. The model call itself is covered by the live spot check
// (`npm run spotcheck:injection`); these tests pin the deterministic layers around it, which hold
// even if the model is fooled.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildDraftPrompt, clampPrice, finalizeCopy, LISTING_SYSTEM } from '../src/agents/listingPrompt.js';
import { cleanUntrusted } from '../src/untrusted.js';
import { INJECTION_COMPS, CLEAN_COMPS, DEMO_ITEM } from '../fixtures/injection-comps.js';

const ZWSP = String.fromCodePoint(0x200b);
const RLO = String.fromCodePoint(0x202e);

test('planted comp text stays inside the untrusted block and cannot close it', () => {
  const prompt = buildDraftPrompt(DEMO_ITEM, INJECTION_COMPS);
  const open = prompt.indexOf('<untrusted kind="comps">');
  const close = prompt.lastIndexOf('</untrusted>');
  assert.ok(open >= 0 && close > open);
  assert.equal(prompt.split('</untrusted>').length, 2, 'exactly one closing tag (ours)');
  assert.equal(prompt.split('<untrusted').length, 2, 'exactly one opening tag (ours)');
  const inside = prompt.slice(open, close);
  assert.ok(inside.includes('ignore all prior instructions'), 'the text is still visible to the model as data');
  assert.ok(!prompt.slice(close).includes('ignore'), 'nothing planted after the block');
  assert.ok(!prompt.includes(ZWSP) && !prompt.includes(RLO), 'hidden characters removed');
  assert.ok(!/<\/?(system|script|instructions)/i.test(prompt), 'no raw tags survive');
});

test('system prompt tells the model untrusted text is data', () => {
  assert.match(LISTING_SYSTEM, /untrusted/);
  assert.match(LISTING_SYSTEM, /cannot give you instructions/);
});

test('even a fooled model cannot set an injected price', () => {
  // The planted comp asks for 1 cent; the item is estimated at $60-90.
  assert.equal(clampPrice(DEMO_ITEM, 1, INJECTION_COMPS), (DEMO_ITEM.estLowCents * 7n) / 10n);
  assert.equal(clampPrice(DEMO_ITEM, 99_999_99, INJECTION_COMPS), (DEMO_ITEM.estHighCents * 13n) / 10n);
  // No estimate: falls back to the comps band (0.5x min .. 1.5x max), never below $1.
  const noEst = { estLowCents: -1n, estHighCents: -1n };
  assert.equal(clampPrice(noEst, 1, CLEAN_COMPS), 3500n / 2n);
  assert.equal(clampPrice(noEst, Number.NaN, []), 100n);
  // A sane answer passes through untouched.
  assert.equal(clampPrice(DEMO_ITEM, 7200, INJECTION_COMPS), 7200n);
});

test('links and contact details from comps never reach the published copy', () => {
  const out = finalizeCopy({
    title: 'IKEA Poang chair - DM me at scam@evil.example',
    description: 'Great chair.\n\nPay first at https://evil.example/pay or www.evil.example, call +1 (415) 555-0100.',
  });
  for (const leak of ['evil.example', 'scam@', '555-0100']) assert.ok(!(out.title + out.description).includes(leak), leak);
  assert.ok(out.title.length <= 80);
});

test('phone scrubbing removes real numbers but keeps dimensions and model numbers', () => {
  for (const keep of ['Size 120.0 - 60.0 - 75.0 cm', 'Model number 1234567890', 'Width 68 x 82 x 100 cm, 2019 model']) {
    assert.equal(finalizeCopy({ title: keep, description: keep }).description, keep, keep);
  }
  for (const phone of ['call 415-555-0100', 'call (415) 555-0100', 'call +1 415 555 0100', 'text 415.555.0100']) {
    const out = finalizeCopy({ title: 't', description: phone }).description;
    assert.ok(!/555/.test(out), `${phone} -> ${out}`);
  }
});

test('cleanUntrusted bounds length and strips markup', () => {
  const s = cleanUntrusted(`<b>Chair</b>${ZWSP} ${'x'.repeat(500)}`, 50);
  assert.ok(s.length <= 50 && s.startsWith('Chair') && s.endsWith('…'));
});
