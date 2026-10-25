import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";

// The buy agent's checkout loop (#15) against a fake connection, with the simulated Visa backend
// (no network). Own file so the env is set before buy.ts / checkout.ts read it, and one shared fake
// connection because the card checkout is a per-process singleton bound to the first connection.
process.env.VISA_PROVIDER = "simulated";
process.env.VISA_SIM_DELAY_MS = "0";
process.env.VISA_SEED_BUDGETS = "0";
process.env.DEALS_SOURCE = "fixtures";
process.env.BUY_RETRY_DELAY_MS = "20";
process.env.BUY_FRAUD_BLOCK = "0.7";
delete process.env.BUY_REQUIRE_FRAUD_SCORE;
delete process.env.BUY_AUTO_CHOOSE;
const { buyAgent, pickDealsToWrite } = await import("../src/agents/buy.js");
const { createDealSource } = await import("../src/integrations/deals-apify.js");
const { rankDeals, sellerInfo } = await import("../src/integrations/deals.js");
const { cachedCompPrices, screenDeal } = await import("../src/agents/fraud.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { isEqual: (o: unknown) => o === owner, toHexString: () => "owner" };

type Row = { id: bigint; [k: string]: any };
function table() {
  const rows = new Map<bigint, Row>();
  const ins: ((ctx: unknown, r: Row) => void)[] = [];
  const upd: ((ctx: unknown, old: Row, r: Row) => void)[] = [];
  return {
    rows,
    iter: () => [...rows.values()][Symbol.iterator](),
    id: { find: (id: bigint) => rows.get(id) },
    onInsert: (cb: (ctx: unknown, r: Row) => void) => void ins.push(cb),
    removeOnInsert: (cb: (ctx: unknown, r: Row) => void) => void ins.splice(ins.indexOf(cb), 1),
    onUpdate: (cb: (ctx: unknown, old: Row, r: Row) => void) => void upd.push(cb),
    insert(r: Row) {
      rows.set(r.id, r);
      for (const cb of [...ins]) cb({}, r);
      return r;
    },
    update(r: Row) {
      const old = rows.get(r.id)!;
      rows.set(r.id, r);
      for (const cb of [...upd]) cb({}, old, r);
      return r;
    },
  };
}

const db = { shoppingItem: table(), deal: table(), approval: table(), payment: table(), workerUser: { iter: () => [].values() } };
const events: { kind: string; message: string; refId: bigint }[] = [];
const failStatusFor = new Set<bigint>(); // shopping item ids whose next set_shopping_status throws
let nextId = 1000n;
const conn = {
  db,
  reducers: {
    logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e),
    setShoppingStatus: async ({ shoppingItemId, status }: { shoppingItemId: bigint; status: string }) => {
      if (failStatusFor.delete(shoppingItemId)) throw new Error("disconnected");
      db.shoppingItem.update({ ...db.shoppingItem.rows.get(shoppingItemId)!, status });
    },
    requestApproval: async (a: { refId: bigint; amountCents: bigint }) =>
      void db.approval.insert({ id: nextId++, owner, kind: "purchase", refId: a.refId, amountCents: a.amountCents, status: "pending" }),
    recordPayment: async (p: Row) => void db.payment.insert({ ...p, id: nextId++, createdAt: { toMillis: () => Date.now() } }),
    updatePayment: async ({ paymentId, status }: { paymentId: bigint; status: string }) =>
      void db.payment.update({ ...db.payment.rows.get(paymentId)!, status }),
    addDeal: async (d: Row & { shoppingItemId: bigint }) => {
      db.deal.insert({ ...d, id: nextId++, owner, fraudScore: -1, aiTextScore: -1, fraudReasons: [] });
      const s = db.shoppingItem.rows.get(d.shoppingItemId)!;
      if (s.status === "open" || s.status === "searching") db.shoppingItem.update({ ...s, status: "found" });
    },
  },
} as unknown as Conn;
buyAgent.start(conn);

/** A shopping item with one chosen card-checkout deal. */
function chosenDeal(o: { fraudScore?: number; priceCents?: bigint } = {}) {
  const itemId = nextId++;
  const deal = { id: nextId++, owner, shoppingItemId: itemId, source: "ikea", title: `Desk ${itemId}`, priceCents: o.priceCents ?? 5_000n, url: `https://example.com/${itemId}`, sellerInfo: "", fraudScore: o.fraudScore ?? -1, aiTextScore: -1, fraudReasons: [] as string[] };
  db.deal.rows.set(deal.id, deal);
  const item = { id: itemId, owner, name: "Desk", category: "desk", reason: "Office: needs a desk", status: "found", chosenDealId: deal.id };
  return { deal, item, insert: () => db.shoppingItem.insert(item) };
}
const paymentsFor = (dealId: bigint) => [...db.payment.rows.values()].filter(p => p.refId === dealId);
const eventsFor = (dealId: bigint) => events.filter(e => e.refId === dealId);

test("a chosen deal is never paid before the fraud screen scores it, and not at all when it scores high", async () => {
  const { deal, insert } = chosenDeal({ fraudScore: -1 });
  insert(); // e.g. BUY_AUTO_CHOOSE picked it inside the fraud agent's settle window
  await sleep(50);
  assert.deepEqual(paymentsFor(deal.id), [], "no hold or charge on an unscreened deal");
  assert.ok(eventsFor(deal.id).some(e => /fraud screen/i.test(e.message)), "says it is waiting for the fraud screen");
  db.deal.update({ ...deal, fraudScore: 0.9, fraudReasons: ["asks for Zelle"] });
  await sleep(50);
  assert.deepEqual(paymentsFor(deal.id), []);
  assert.ok(eventsFor(deal.id).some(e => e.kind === "error" && /Not buying .*0\.90/.test(e.message)));
});

test("an unscreened deal is bought once the fraud screen clears it", async () => {
  const { deal, item, insert } = chosenDeal({ fraudScore: -1 });
  insert();
  await sleep(30);
  assert.deepEqual(paymentsFor(deal.id), []);
  db.deal.update({ ...deal, fraudScore: 0.1 });
  await sleep(50);
  assert.deepEqual(paymentsFor(deal.id).map(p => p.status), ["settled"]);
  assert.equal(db.shoppingItem.rows.get(item.id)!.status, "bought");
});

test("a hold left pending by an earlier run is reversed, not left hanging or charged", async () => {
  const { deal, insert } = chosenDeal({ fraudScore: 0.1 });
  // The worker crashed between authorize and capture: a pending row, and no hold in this process.
  db.payment.rows.set(1n, { id: 1n, owner, agent: "buy", rail: "visa", purpose: "Desk", payee: "ikea", amountUsdMicros: deal.priceCents * 10_000n, txHash: "sim_auth_from_earlier_run", status: "pending", simulated: true, refTable: "deal", refId: deal.id, createdAt: { toMillis: () => Date.now() - 60_000 } });
  insert();
  await sleep(50);
  assert.deepEqual(paymentsFor(deal.id).map(p => p.status), ["failed"], "the stale hold is released and nothing new is charged");
  assert.ok(eventsFor(deal.id).some(e => e.kind === "payment" && /Released .*earlier run/.test(e.message)));
});

test("a capture that went through is reported as bought even if marking the item bought fails", async () => {
  const { deal, item, insert } = chosenDeal({ fraudScore: 0.1 });
  failStatusFor.add(item.id);
  insert();
  await sleep(80);
  assert.deepEqual(paymentsFor(deal.id).map(p => p.status), ["settled"], "charged exactly once");
  assert.ok(eventsFor(deal.id).some(e => e.kind === "result" && /^Bought /.test(e.message)));
  assert.ok(!eventsFor(deal.id).some(e => /will try again/.test(e.message)), "no misleading retry after a capture");
});

test("a purchase exactly at the approval threshold goes through without asking; one cent over asks", async () => {
  const at = chosenDeal({ fraudScore: 0.1, priceCents: 10_000n }); // default threshold $100.00
  at.insert();
  const over = chosenDeal({ fraudScore: 0.1, priceCents: 10_001n });
  over.insert();
  await sleep(60);
  assert.deepEqual(paymentsFor(at.deal.id).map(p => p.status), ["settled"]);
  assert.deepEqual(paymentsFor(over.deal.id), []);
  const asked = [...db.approval.rows.values()].filter(a => a.refId === over.deal.id);
  assert.equal(asked.length, 1);
  // A denial sticks: no charge, and no second request.
  db.approval.update({ ...asked[0], status: "denied" });
  await sleep(40);
  assert.deepEqual(paymentsFor(over.deal.id), []);
  assert.equal([...db.approval.rows.values()].filter(a => a.refId === over.deal.id).length, 1);
  assert.ok(eventsFor(over.deal.id).some(e => /approval denied/.test(e.message)));
});

test("#186: an expired purchase approval is asked again once; after a restart with the re-ask on file, not again", async () => {
  const { deal, insert } = chosenDeal({ fraudScore: 0.1, priceCents: 15_000n });
  insert();
  await sleep(40);
  const forDeal = () => [...db.approval.rows.values()].filter(a => a.refId === deal.id);
  assert.equal(forDeal().length, 1);
  // The worker's expiry sweep expires it; duplicate updates must not ask twice.
  const first = forDeal()[0]!;
  db.approval.update({ ...first, status: "expired" });
  db.approval.update({ ...first, status: "expired" });
  await sleep(40);
  assert.deepEqual(forDeal().map(a => a.status), ["expired", "pending"]);
  assert.deepEqual(paymentsFor(deal.id), [], "nothing charged on an expired approval");
  assert.ok(eventsFor(deal.id).some(e => /expired without an answer, asking again \(1 of 2\)/.test(e.message)));
  // Another pass, as after a restart: the latest row is the pending re-ask, so nothing new is asked.
  db.shoppingItem.update({ ...db.shoppingItem.rows.get(deal.shoppingItemId)! });
  await sleep(40);
  assert.equal(forDeal().length, 2);
  // Approving the re-ask buys it.
  const second = forDeal()[1]!;
  db.approval.update({ ...second, status: "approved" });
  await sleep(60);
  assert.deepEqual(paymentsFor(deal.id).map(p => p.status), ["settled"]);
});

test("#186: a purchase whose approval expired past APPROVAL_MAX_REASKS stops without paying", async () => {
  const { deal, insert } = chosenDeal({ fraudScore: 0.1, priceCents: 15_000n });
  for (let i = 0; i < 3; i++) db.approval.rows.set(nextId, { id: nextId++, owner, kind: "purchase", refId: deal.id, amountCents: deal.priceCents, status: "expired" });
  insert();
  await sleep(40);
  assert.equal([...db.approval.rows.values()].filter(a => a.refId === deal.id).length, 3, "no new ask");
  assert.deepEqual(paymentsFor(deal.id), []);
  assert.ok(eventsFor(deal.id).some(e => /expired 3 times/.test(e.message)));
});

test("an approval for a different amount never pays", async () => {
  const { deal, insert } = chosenDeal({ fraudScore: 0.1, priceCents: 20_000n });
  db.approval.rows.set(nextId, { id: nextId++, owner, kind: "purchase", refId: deal.id, amountCents: 19_000n, status: "approved" });
  insert();
  await sleep(40);
  assert.deepEqual(paymentsFor(deal.id), []);
});

test("the planted demo scam on Desk chair is written, labeled sample data, scored >= 0.7 by the real fraud rules, and never paid", async () => {
  // The demo path with no APIFY_TOKEN: committed live replay + sample retail rows + the planted scam.
  const found = await createDealSource({}).search({ name: "Desk chair", category: "chair" });
  const live = found.filter(d => !d.sample);
  assert.ok(live.length >= 3 && live.every(d => d.replay && !d.planted), "the planted deal is not one of the 3+ replayed live deals");
  const written = pickDealsToWrite(rankDeals(found), 5);
  const planted = written.find(d => d.planted);
  assert.ok(planted, "the planted deal always makes the written top 5");
  assert.ok(written.some(d => d.checkout === "visa"), "and the card-checkout deal still does");
  assert.equal(planted.title, "Herman Miller Aeron, brand new, $95, Zelle only, ship only");
  assert.ok(planted.sample);
  assert.match(sellerInfo(planted), /^Planted demo scam \(not a real listing\) · .*sample data$/);
  assert.doesNotMatch(sellerInfo(planted), /score/, "no rank score that could be read as the fraud score");
  assert.ok(written.filter(d => !d.planted).every(d => /score \d\.\d\d/.test(sellerInfo(d))), "other deals keep their rank score");
  assert.equal(planted.checkout, "seller_message");
  assert.ok((await createDealSource({}).search({ name: "Office chair", category: "chair" })).some(d => d.planted), "also planted for Office chair (replayed live search)");
  assert.ok(!(await createDealSource({}).search({ name: "Dining chairs", category: "dining chair" })).some(d => d.planted), "never for dining chairs");

  // Score it the way the fraud agent does: against the other written deals and cached comps.
  const itemId = nextId++;
  const rows = written.map(d => ({ id: nextId++, owner, shoppingItemId: itemId, source: d.source, title: d.title, priceCents: d.priceCents, url: d.url, sellerInfo: sellerInfo(d), fraudScore: -1, aiTextScore: -1, fraudReasons: [] as string[] }));
  const row = rows[written.indexOf(planted)];
  const screen = screenDeal(row, { allDeals: rows, compPrices: cachedCompPrices("Desk chair") });
  assert.ok(screen.fraudScore >= 0.7, `scored ${screen.fraudScore}`);
  assert.ok(screen.reasons.includes("asks for payment by Zelle"), screen.reasons.join("; "));

  // The user chooses it anyway: the buy agent refuses, with no approval request and no payment.
  for (const r of rows) db.deal.rows.set(r.id, r);
  db.deal.rows.set(row.id, { ...row, fraudScore: screen.fraudScore, fraudReasons: screen.reasons });
  db.shoppingItem.insert({ id: itemId, owner, name: "Desk chair", category: "chair", reason: "Desk nook: needs a chair", status: "found", chosenDealId: row.id });
  await sleep(50);
  assert.deepEqual(paymentsFor(row.id), []);
  assert.equal([...db.approval.rows.values()].filter(a => a.refId === row.id).length, 0);
  assert.ok(eventsFor(row.id).some(e => e.kind === "error" && /^Not buying "Herman Miller Aeron, brand new.*fraud screen scored it 0\.\d\d \(asks for payment by Zelle/.test(e.message)));
});

test("an item an earlier run left 'searching' with no deals is searched again, once", async () => {
  // The worker restarted between set_shopping_status('searching') and add_deal.
  const itemId = nextId++;
  const before = events.length;
  db.shoppingItem.insert({ id: itemId, owner, name: "Desk", category: "desk", reason: "Office: needs a desk", status: "searching", chosenDealId: 0n });
  await sleep(80);
  const deals = [...db.deal.rows.values()].filter(d => d.shoppingItemId === itemId);
  assert.ok(deals.length > 0, "deals were written");
  assert.equal(db.shoppingItem.rows.get(itemId)!.status, "found");
  const searches = events.slice(before).filter(e => e.refId === itemId && /^Looking for deals/.test(e.message));
  assert.equal(searches.length, 1, "our own 'searching' write doesn't start a second search");
});

test("pickDealsToWrite keeps the card deal and the planted deal when both are outside the top n", () => {
  const d = (title: string, extra: Record<string, unknown> = {}) => ({ source: "fb", title, priceCents: 1000n, url: `https://x/${title}`, seller: "", condition: "good", distanceMiles: 1, checkout: "seller_message", replay: true, score: 1, why: "", ...extra }) as any;
  const ranked = [d("a"), d("b"), d("c"), d("card", { checkout: "visa", source: "ikea" }), d("scam", { planted: true, sample: true })];
  assert.deepEqual(pickDealsToWrite(ranked, 3).map(x => x.title), ["a", "scam", "card"]);
  assert.deepEqual(pickDealsToWrite(ranked.slice(0, 2).concat(ranked[4]), 5).map(x => x.title), ["a", "b", "scam"]);
});
