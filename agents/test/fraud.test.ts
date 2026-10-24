import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import {
  WEIGHTS,
  aiTextSignal,
  combine,
  duplicateSignal,
  median,
  newSellerSignal,
  offPlatformSignal,
  priceSignal,
  screenDeal,
  type DealLike,
  type Signal,
  type SignalKey,
} from "../src/agents/fraud.js";
import { chooseAiTextDetector, pangramDetector, parseScore, toRequestBody } from "../src/integrations/aitext.js";

const NOW = new Date("2026-10-24T12:00:00Z");
let nextId = 1n;
const deal = (o: Partial<DealLike> = {}): DealLike => ({
  id: nextId++,
  shoppingItemId: 1n,
  source: "fb",
  title: "Wood bed frame full size, barely used",
  priceCents: 6000,
  url: `https://example.com/item/${nextId}`,
  sellerInfo: "Marketplace seller, Oakland (4.8 stars) · good · 6 mi · message seller · score 0.83",
  ...o,
});
const none: Signal = { score: 0, reasons: [] };
const signals = (o: Partial<Record<SignalKey, Signal>>) => ({ offPlatform: none, price: none, newSeller: none, duplicate: none, aiText: none, ...o });

test("median ignores non-positive prices and averages the middle pair", () => {
  assert.equal(median([]), null);
  assert.equal(median([0, -1]), null);
  assert.equal(median([300, 100, 200]), 200);
  assert.equal(median([100, 200, 300, 400, 0]), 250);
});

test("price: far below the other deals is too good to be true", () => {
  const s = priceSignal(500, [10000, 12000, 9000], []);
  assert.equal(s.score, 1);
  assert.equal(s.basis, "peers");
  assert.deepEqual(s.reasons, ["price $5 is 95% below the other deals (median $100)"]);
});

test("price: a normal used discount vs retail deals is not flagged", () => {
  // $30 used vs ~$100 new retail: ratio 0.3, above the peers band start.
  assert.deepEqual(priceSignal(3000, [10000, 9000], []).reasons, []);
  assert.equal(priceSignal(3000, [10000, 9000], []).score, 0);
});

test("price: small gaps below the reason floor score zero (no unexplained points)", () => {
  // ratio 0.22 vs peers -> raw score ~0.18, under the 0.25 floor.
  assert.equal(priceSignal(2200, [10000, 10000], []).score, 0);
});

test("price: comps are used sold prices, so the bar is higher than vs peers", () => {
  const s = priceSignal(2500, [], [10000, 9000, 11000]);
  assert.equal(s.basis, "comps");
  assert.ok(s.score > 0.5, `score ${s.score}`);
  assert.match(s.reasons[0], /below recent sold prices \(median \$100\)/);
});

test("price: needs enough references, and skips unknown prices", () => {
  assert.equal(priceSignal(100, [10000], []).score, 0); // one peer is not a market
  assert.equal(priceSignal(100, [], [10000, 10000]).score, 0); // two comps either
  assert.equal(priceSignal(0, [10000, 10000, 10000], []).score, 0);
  assert.equal(priceSignal(-1, [10000, 10000, 10000], []).score, 0);
});

test("off-platform: payment asks are caught, each with a reason", () => {
  const cases: [string, RegExp][] = [
    ["Couch, Zelle only", /Zelle/],
    ["pay with cashapp please", /Cash App/],
    ["Venmo only, no lowballers", /Venmo only/],
    ["paypal friends and family", /friends & family/],
    ["wire transfer or western union", /wire/],
    ["accept Apple gift card", /gift cards/],
    ["I take bitcoin", /crypto/],
    ["$40 deposit to hold it for you", /deposit/],
    ["Shipping only, I'm out of state", /shipping only/],
    ["email me for details", /off-platform/],
    ["Text me at (415) 555-0199", /phone number/],
    ["call 4155550199", /phone number/],
    ["reach me at seller@mail.com", /email address/],
    ["WhatsApp me", /off-platform/],
  ];
  for (const [text, re] of cases) {
    const s = offPlatformSignal(text);
    assert.ok(s.score > 0, text);
    assert.ok(s.reasons.some(r => re.test(r)), `${text}: ${s.reasons}`);
  }
});

test("off-platform: ordinary listing text is clean", () => {
  for (const text of [
    "BILLY bookcase, white, 80x28x202 cm",
    "Wireless speaker, works great",
    "Wire shelf rack, 5 tiers",
    "Venmo or cash at pickup",
    "Tall bookshelf, free delivery nearby",
    "IKEA · new · ships · Visa checkout · score 0.71",
    "Queen bed frame w/ headboard - must go",
    "LISABO table, ash veneer, 140x78 cm",
  ]) {
    assert.deepEqual(offPlatformSignal(text), none, text);
  }
});

test("off-platform: several hits stack but stay within 0..1", () => {
  const one = offPlatformSignal("email me");
  const two = offPlatformSignal("email me or text me at 415-555-0199");
  assert.ok(two.score > one.score);
  assert.equal(offPlatformSignal("zelle, cashapp, gift card, wire transfer, bitcoin").score, 1);
});

test("new seller: joined this year, no ratings, new account", () => {
  const joined = newSellerSignal("Marketplace seller, joined 2026", NOW);
  assert.equal(joined.score, 0.8);
  assert.deepEqual(joined.reasons, ["seller account is new (joined 2026)"]);
  assert.match(newSellerSignal("Joined Facebook in 2026", NOW).reasons[0], /joined 2026/);
  assert.equal(newSellerSignal("member since 2025", NOW).score, 0.3);
  assert.equal(newSellerSignal("joined 2019 (4.9 stars)", NOW).score, 0);
  assert.deepEqual(newSellerSignal("0 ratings", NOW).reasons, ["seller has no ratings"]);
  assert.deepEqual(newSellerSignal("No reviews yet", NOW).reasons, ["seller has no ratings"]);
  assert.deepEqual(newSellerSignal("brand new account", NOW).reasons, ["new seller account"]);
  assert.deepEqual(newSellerSignal("account created 3 days ago", NOW).reasons, ["seller account is 3 days old"]);
  assert.deepEqual(newSellerSignal("1 rating", NOW).reasons, ["seller has only 1 rating"]);
});

test("new seller: empty seller info is a mild signal, established sellers are clean", () => {
  assert.deepEqual(newSellerSignal("   ", NOW), { score: 0.4, reasons: ["no seller info"] });
  assert.deepEqual(newSellerSignal("Marketplace seller, Oakland (4.8 stars) · good · 6 mi · message seller · score 0.83", NOW), none);
  assert.deepEqual(newSellerSignal("Target · new · ships · Visa checkout · score 0.75", NOW), none);
  assert.deepEqual(newSellerSignal("Seller with 120 ratings", NOW), none);
});

test("duplicate: same link under a different title", () => {
  const a = deal({ url: "https://x.test/1", title: "Oak dresser, 6 drawers" });
  const b = deal({ url: "https://x.test/1", title: "Leather sectional sofa" });
  assert.deepEqual(duplicateSignal(a, [a, b]).reasons, ["same link is used by a different listing"]);
});

test("duplicate: same title + price on another source / link", () => {
  const a = deal({ source: "fb", title: "Solid walnut bookshelf, 6 shelves", priceCents: 3000 });
  const b = deal({ source: "craigslist", title: "solid walnut BOOKSHELF - 6 shelves", priceCents: 3000n });
  assert.deepEqual(duplicateSignal(a, [a, b]).reasons, ["identical listing posted on fb and craigslist"]);
  const c = deal({ source: "fb", title: a.title, priceCents: 3000 });
  assert.deepEqual(duplicateSignal(a, [a, c]).reasons, ["identical listing posted 2 times"]);
});

test("duplicate: the same listing seen twice, different prices, or short titles are not reuse", () => {
  const a = deal({ url: "https://x.test/9", title: "Solid walnut bookshelf, 6 shelves" });
  const sameListing = deal({ url: "https://x.test/9", title: a.title, shoppingItemId: 2n });
  const otherPrice = deal({ title: a.title, priceCents: 4500 });
  assert.deepEqual(duplicateSignal(a, [a, sameListing, otherPrice]), none);
  const short = deal({ title: "Desk", priceCents: 1000 });
  assert.deepEqual(duplicateSignal(short, [short, deal({ title: "desk", priceCents: 1000 })]), none);
});

test("ai text: -1 and low scores add nothing; higher scores add a reason", () => {
  assert.deepEqual(aiTextSignal(-1), none);
  assert.deepEqual(aiTextSignal(0.3), none);
  assert.deepEqual(aiTextSignal(0.6), { score: 0.6, reasons: ["listing text may be AI-generated (0.60)"] });
  assert.deepEqual(aiTextSignal(0.93), { score: 0.93, reasons: ["listing text likely AI-generated (0.93)"] });
});

test("combine: weighted noisy-OR, strongest reason first", () => {
  assert.deepEqual(combine(signals({})), { fraudScore: 0, reasons: [] });
  assert.equal(combine(signals({ offPlatform: { score: 1, reasons: ["a"] } })).fraudScore, WEIGHTS.offPlatform);
  const both = combine(signals({ price: { score: 1, reasons: ["cheap"] }, newSeller: { score: 1, reasons: ["new"] }, aiText: { score: 0.9, reasons: ["ai"] } }));
  const expected = 1 - (1 - WEIGHTS.price) * (1 - WEIGHTS.newSeller) * (1 - WEIGHTS.aiText * 0.9);
  assert.equal(both.fraudScore, Math.round(expected * 1000) / 1000);
  assert.deepEqual(both.reasons, ["cheap", "new", "ai"]);
  // Everything maxed out never exceeds 1.
  const all = combine(signals(Object.fromEntries(Object.keys(WEIGHTS).map(k => [k, { score: 1, reasons: [] }]))));
  assert.ok(all.fraudScore <= 1 && all.fraudScore > 0.95);
});

test("combine: one payment ask blocks on its own; a cheap price alone does not", () => {
  assert.ok(combine(signals({ offPlatform: { score: 1, reasons: [] } })).fraudScore >= 0.7);
  const cheap = combine(signals({ price: { score: 1, reasons: [] } })).fraudScore;
  assert.ok(cheap >= 0.3 && cheap < 0.7, String(cheap));
});

test("screenDeal: uses peers of the same shopping item only, and passes aiTextScore through", () => {
  const cheap = deal({ priceCents: 300, shoppingItemId: 5n });
  const peers = [deal({ priceCents: 10000, shoppingItemId: 5n }), deal({ priceCents: 12000, shoppingItemId: 5n })];
  const otherItem = [deal({ title: "Other item one", priceCents: 400, shoppingItemId: 6n }), deal({ title: "Other item two", priceCents: 300, shoppingItemId: 6n })];
  const s = screenDeal(cheap, { allDeals: [cheap, ...peers, ...otherItem], aiTextScore: 0.95, now: NOW });
  assert.equal(s.signals.price.score, 1);
  assert.equal(s.aiTextScore, 0.95);
  assert.ok(s.reasons.includes("listing text likely AI-generated (0.95)"));
  assert.ok(s.fraudScore >= 0.7);
  // Without peers there is no price signal and no AI score: -1 stays -1.
  const alone = screenDeal(cheap, { allDeals: [cheap, ...otherItem], now: NOW });
  assert.equal(alone.signals.price.score, 0);
  assert.equal(alone.aiTextScore, -1);
  assert.equal(alone.fraudScore, 0);
});

test("screenDeal: cached comps drive the price check when there are no peers", () => {
  const d = deal({ priceCents: 1000 });
  const s = screenDeal(d, { allDeals: [d], compPrices: [9000, 10000, 11000], now: NOW });
  assert.equal(s.signals.price.score, 1);
  assert.match(s.reasons[0], /recent sold prices/);
});

// The planted answer key (fixtures/fraud-deals.json): every scam caught with the right reasons,
// no legit deal flagged.
test("planted fixture set: scams flagged with the right reasons, legit deals clean", () => {
  type Row = { item: string; source: string; title: string; priceCents: number; url: string; sellerInfo: string; scam: boolean; block?: boolean; expect?: string[] };
  const rows: Row[] = JSON.parse(readFileSync(new URL("../fixtures/fraud-deals.json", import.meta.url), "utf8")).deals;
  const items = [...new Set(rows.map(r => r.item))];
  const deals = rows.map((r, i) => ({ ...r, id: BigInt(i + 1), shoppingItemId: BigInt(items.indexOf(r.item) + 1) }));
  let caught = 0;
  let falsePositives = 0;
  for (const d of deals) {
    const s = screenDeal(d, { allDeals: deals, now: NOW });
    const label = `${d.title}: ${s.fraudScore} [${s.reasons.join("; ")}]`;
    if (d.scam) {
      assert.ok(s.fraudScore >= 0.3, `missed scam ${label}`);
      if (d.block) assert.ok(s.fraudScore >= 0.7, `scam not blocked ${label}`);
      for (const e of d.expect ?? []) assert.ok(s.reasons.some(r => r.includes(e)), `missing reason "${e}" for ${label}`);
      caught++;
    } else {
      if (s.fraudScore >= 0.3 || s.reasons.length) falsePositives++;
      assert.ok(s.fraudScore < 0.3 && s.reasons.length === 0, `false positive ${label}`);
    }
  }
  assert.equal(caught, deals.filter(d => d.scam).length);
  assert.ok(caught >= 6);
  assert.equal(falsePositives, 0);
});

test("aitext: request body and tolerant score parsing", () => {
  assert.deepEqual(toRequestBody("hello"), { text: "hello" });
  assert.equal(parseScore({ score: 0.93 }), 0.93);
  assert.equal(parseScore({ ai_score: 0.2 }), 0.2);
  assert.equal(parseScore({ fraction_ai: 0 }), 0);
  assert.equal(parseScore(0.5), 0.5);
  assert.equal(parseScore("0.7"), 0.7);
  assert.equal(parseScore([{ score: 0.4 }]), 0.4);
  for (const bad of [{}, { score: 1.5 }, { score: -0.1 }, { score: "nope" }, null, { label: "AI" }]) {
    assert.throws(() => parseScore(bad), /no 0..1 score/, JSON.stringify(bad));
  }
});

test("aitext: no detector without PANGRAM_URL", () => {
  assert.equal(chooseAiTextDetector({}), null);
  assert.equal(chooseAiTextDetector({ PANGRAM_URL: "  " }), null);
  assert.equal(chooseAiTextDetector({ PANGRAM_URL: "http://127.0.0.1:1/score" })?.name, "pangram");
});

test("aitext: pangramDetector POSTs {text} (with optional bearer token) and reads {score}", async (t) => {
  const seen: { body: unknown; auth?: string; type?: string }[] = [];
  const server = createServer((req, res) => {
    let raw = "";
    req.on("data", c => (raw += c));
    req.on("end", () => {
      seen.push({ body: JSON.parse(raw), auth: req.headers.authorization, type: req.headers["content-type"] });
      if (raw.includes("boom")) {
        res.writeHead(500).end("model not loaded");
        return;
      }
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ score: 0.87 }));
    });
  });
  await new Promise<void>(r => server.listen(0, "127.0.0.1", r));
  t.after(() => server.close());
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}/score`;

  const det = pangramDetector({ url, token: "tok" });
  assert.equal(await det.score("Stunning mid-century credenza, a timeless statement piece"), 0.87);
  assert.deepEqual(seen[0], { body: { text: "Stunning mid-century credenza, a timeless statement piece" }, auth: "Bearer tok", type: "application/json" });
  await assert.rejects(det.score("boom"), /HTTP 500 model not loaded/);
  assert.equal(seen[1].auth, "Bearer tok");
  const anon = pangramDetector({ url });
  await anon.score("no token here");
  assert.equal(seen[2].auth, undefined);
});
