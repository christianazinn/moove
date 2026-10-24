import { test } from "node:test";
import assert from "node:assert/strict";
import type { Item } from "../src/module_bindings/types.js";
import { createX402Rail, type AgentEventRecord, type PaymentRecord, type PaymentSink } from "../src/integrations/x402.js";
import { createPaidCompsSource, pricingPaysX402, startCompsPaywall, type PaidCompsDeps } from "../src/integrations/paid-comps.js";
import type { CompsLookup } from "../src/paywall.js";

const COMPS = [{ source: "ebay", title: "IKEA Poang chair", priceCents: 4500, url: "https://example.com/1" }];
const item = { id: 7n, owner: "owner-1" } as unknown as Item;

function memorySink() {
  const payments: PaymentRecord[] = [];
  const events: AgentEventRecord[] = [];
  const sink: PaymentSink = {
    recordPayment: async (p) => void payments.push(p),
    logAgentEvent: async (e) => void events.push(e),
  };
  return { sink, payments, events };
}

function stubLookup() {
  const calls: string[] = [];
  const lookup: CompsLookup = async (q) => {
    calls.push(q);
    return { comps: COMPS, replayed: false };
  };
  return { lookup, calls };
}

function setup(railEnv: Record<string, string> = {}) {
  const { sink, payments, events } = memorySink();
  const direct = stubLookup();
  const logged: Parameters<PaidCompsDeps["log"]>[0][] = [];
  const deps: PaidCompsDeps = { rail: createX402Rail(sink, railEnv), lookup: direct.lookup, log: (e) => void logged.push(e) };
  return { deps, payments, events, direct, logged };
}

test("a pricing lookup pays once (simulated) and returns the comps", async (t) => {
  const served = stubLookup();
  const paywall = await startCompsPaywall({ lookup: served.lookup, port: 0, env: {} });
  t.after(() => paywall.server.close());
  assert.equal(paywall.paywalled, false);

  const { deps, payments, direct, logged } = setup();
  const res = await createPaidCompsSource(deps, paywall.baseUrl)("IKEA Poang chair", item);

  assert.deepEqual(res, { comps: COMPS, replayed: false });
  assert.equal(payments.length, 1);
  const p = payments[0];
  assert.equal(p.simulated, true);
  assert.equal(p.agent, "pricing");
  assert.equal(p.amountUsdMicros, 10_000n);
  assert.equal(p.refTable, "item");
  assert.equal(p.refId, 7n);
  assert.equal(p.purpose, "comps for 'IKEA Poang chair'");
  assert.deepEqual(served.calls, ["IKEA Poang chair"]);
  assert.equal(direct.calls.length, 0);
  assert.equal(logged.length, 0);
});

test("a refusal falls back to a direct lookup without double-logging the refusal", async () => {
  // Cap below the $0.01 quote, so the rail refuses (and logs the refusal itself).
  const { deps, payments, events, direct, logged } = setup({ AGENT_SPEND_CAP_USDC: "0.001" });
  const res = await createPaidCompsSource(deps, "http://127.0.0.1:1")("lamp", item);

  assert.deepEqual(res, { comps: COMPS, replayed: false });
  assert.equal(payments.length, 0);
  assert.deepEqual(direct.calls, ["lamp"]);
  assert.equal(events.filter((e) => e.message.startsWith("Refused")).length, 1);
  assert.equal(logged.length, 1);
  assert.equal(logged[0].kind, "tool_call");
  assert.match(logged[0].message, /directly \(unpaid\)/);
  assert.equal((logged[0].data as { refused: boolean }).refused, true);
});

test("an HTTP failure falls back to a direct lookup", async (t) => {
  const failing: CompsLookup = async () => {
    throw new Error("apify down");
  };
  const paywall = await startCompsPaywall({ lookup: failing, port: 0, env: {} });
  t.after(() => paywall.server.close());

  const { deps, payments, direct, logged } = setup();
  const res = await createPaidCompsSource(deps, paywall.baseUrl)("desk", item);

  assert.deepEqual(res, { comps: COMPS, replayed: false });
  assert.deepEqual(direct.calls, ["desk"]);
  // The rail (#45) records the 502 as a failed simulated payment and refunds the budget.
  assert.equal(payments.length, 1);
  assert.equal(payments[0].status, "failed");
  assert.equal(payments[0].simulated, true);
  const rail = await deps.rail;
  assert.equal(rail.remaining("pricing"), 5_000_000n);
  assert.equal(logged.length, 1);
  assert.equal(logged[0].kind, "error");
  assert.match(logged[0].message, /HTTP 502/);
});

test("an unreachable paywall falls back to a direct lookup", async () => {
  const { deps, payments, direct, logged } = setup();
  const res = await createPaidCompsSource(deps, "http://127.0.0.1:1")("rug", item);
  assert.deepEqual(res, { comps: COMPS, replayed: false });
  assert.deepEqual(direct.calls, ["rug"]);
  // A thrown fetch writes no payment row and refunds the reservation.
  assert.equal(payments.length, 0);
  assert.equal((await deps.rail).remaining("pricing"), 5_000_000n);
  assert.equal(logged.length, 1);
});

test("PRICING_PAY_X402 gate: on by default, 0 bypasses", () => {
  assert.equal(pricingPaysX402({}), true);
  assert.equal(pricingPaysX402({ PRICING_PAY_X402: "1" }), true);
  assert.equal(pricingPaysX402({ PRICING_PAY_X402: "0" }), false);
  assert.equal(pricingPaysX402({ PRICING_PAY_X402: "false" }), false);
});
