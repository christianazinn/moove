import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import type { Item } from "../src/module_bindings/types.js";
import { createX402Rail, type AgentEventRecord, type PaymentRecord, type PaymentSink } from "../src/integrations/x402.js";
import {
  CompsLookupFailedError,
  createPaidCompsSource,
  installPaidComps,
  pricingPaysX402,
  startCompsPaywall,
  type PaidCompsDeps,
} from "../src/integrations/paid-comps.js";
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
  // Simulated rail: the refusal and the fallback are both labeled.
  assert.equal(events.filter((e) => e.message.startsWith("[SIMULATED] Refused x402 payment")).length, 1);
  assert.equal(logged.length, 1);
  assert.equal(logged[0].kind, "tool_call");
  assert.match(logged[0].message, /^\[SIMULATED\] x402 payment refused, .*directly \(unpaid\)/);
  assert.equal((logged[0].data as { refused: boolean }).refused, true);
});

test("a failed lookup behind the paywall (502) is not re-run directly", async (t) => {
  const failing: CompsLookup = async () => {
    throw new Error("apify down");
  };
  const paywall = await startCompsPaywall({ lookup: failing, port: 0, env: {} });
  t.after(() => paywall.server.close());

  const { deps, payments, direct, logged } = setup();
  await assert.rejects(createPaidCompsSource(deps, paywall.baseUrl)("desk", item), (err: Error) => {
    assert.ok(err instanceof CompsLookupFailedError);
    assert.match(err.message, /^comps lookup failed: apify down/);
    return true;
  });

  // Apify ran once (behind the paywall), not a second time directly; pricing fails the item.
  assert.equal(direct.calls.length, 0);
  assert.equal(logged.length, 0);
  // The rail (#45) records the 502 as a failed simulated payment and refunds the budget.
  assert.equal(payments.length, 1);
  assert.equal(payments[0].status, "failed");
  assert.equal(payments[0].simulated, true);
  assert.equal((await deps.rail).remaining("pricing"), 5_000_000n);
});

async function serveStatus(t: { after: (fn: () => void) => void }, status: number, body: unknown): Promise<string> {
  const server = createServer((_req, res) => {
    res.writeHead(status, { "content-type": "application/json" });
    res.end(JSON.stringify(body));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

for (const [status, body] of [
  [500, { error: "boom" }],
  [502, { error: "bad gateway" }],
] as const) {
  test(`another HTTP ${status} failure falls back to a direct lookup, logged as a tool_call`, async (t) => {
    const baseUrl = await serveStatus(t, status, body);
    const { deps, payments, direct, logged } = setup();
    const res = await createPaidCompsSource(deps, baseUrl)("desk", item);

    assert.deepEqual(res, { comps: COMPS, replayed: false });
    assert.deepEqual(direct.calls, ["desk"]);
    assert.equal(payments.length, 1);
    assert.equal(payments[0].status, "failed");
    assert.equal(logged.length, 1);
    assert.equal(logged[0].kind, "tool_call");
    assert.match(logged[0].message, new RegExp(`HTTP ${status}.*directly \\(unpaid\\)`));
  });
}

test("an unreachable paywall falls back to a direct lookup", async () => {
  const { deps, payments, direct, logged } = setup();
  const res = await createPaidCompsSource(deps, "http://127.0.0.1:1")("rug", item);
  assert.deepEqual(res, { comps: COMPS, replayed: false });
  assert.deepEqual(direct.calls, ["rug"]);
  // A thrown fetch writes no payment row and refunds the reservation.
  assert.equal(payments.length, 0);
  assert.equal((await deps.rail).remaining("pricing"), 5_000_000n);
  assert.equal(logged.length, 1);
  assert.equal(logged[0].kind, "tool_call");
});

test("a paywall that fails to start leaves pricing on direct lookups", async () => {
  const installed: string[] = [];
  const errors: unknown[] = [];
  const ok = await installPaidComps({
    start: async () => {
      throw new Error("CDP outage");
    },
    install: (url) => void installed.push(url),
    logError: (_msg, err) => void errors.push(err),
  });
  assert.equal(ok, false);
  assert.equal(installed.length, 0);
  assert.equal((errors[0] as Error).message, "CDP outage");
});

test("a paywall port already in use (EADDRINUSE) leaves pricing on direct lookups", async (t) => {
  const blocker = createServer();
  await new Promise<void>((resolve) => blocker.listen(0, "127.0.0.1", resolve));
  t.after(() => blocker.close());
  const port = (blocker.address() as AddressInfo).port;

  const installed: string[] = [];
  const errors: unknown[] = [];
  const ok = await installPaidComps({
    start: () => startCompsPaywall({ lookup: stubLookup().lookup, port, env: {} }),
    install: (url) => void installed.push(url),
    logError: (_msg, err) => void errors.push(err),
  });
  assert.equal(ok, false);
  assert.equal(installed.length, 0);
  assert.equal((errors[0] as NodeJS.ErrnoException).code, "EADDRINUSE");
});

test("a paywall that starts installs the paid source", async (t) => {
  const installed: string[] = [];
  const ok = await installPaidComps({
    start: async () => {
      const p = await startCompsPaywall({ lookup: stubLookup().lookup, port: 0, env: {} });
      t.after(() => p.server.close());
      return p;
    },
    install: (url) => void installed.push(url),
  });
  assert.equal(ok, true);
  assert.match(installed[0], /^http:\/\/127\.0\.0\.1:\d+$/);
});

test("PRICING_PAY_X402 gate: on by default, 0 bypasses", () => {
  assert.equal(pricingPaysX402({}), true);
  assert.equal(pricingPaysX402({ PRICING_PAY_X402: "1" }), true);
  assert.equal(pricingPaysX402({ PRICING_PAY_X402: "0" }), false);
  assert.equal(pricingPaysX402({ PRICING_PAY_X402: "false" }), false);
});
