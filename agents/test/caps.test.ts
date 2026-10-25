import { test } from "node:test";
import assert from "node:assert/strict";
import { checkSpendCaps, resetCapWarnings, SPEND_CAP_DEFAULTS, usdCapFromEnv } from "../src/integrations/caps.js";
import { createX402Rail, type PaymentSink } from "../src/integrations/x402.js";
import { createVisaCheckout, type VisaSink } from "../src/integrations/visa.js";

// Spend caps from env: a non-numeric or negative value used to break the x402 rail (BigInt(NaN)) or
// refuse every call, so pricing quietly ran on unpaid lookups. Now: loud warning + default, no crash.

const collect = () => {
  const msgs: string[] = [];
  return { msgs, warn: (m: string) => void msgs.push(m) };
};

async function quietly<T>(fn: () => T | Promise<T>): Promise<{ value: T; warnings: string[] }> {
  const { warn } = console;
  const warnings: string[] = [];
  console.warn = (...a: unknown[]) => void warnings.push(a.map(String).join(" "));
  try {
    return { value: await fn(), warnings };
  } finally {
    console.warn = warn;
  }
}

const x402Sink: PaymentSink = { recordPayment: async () => {}, logAgentEvent: async () => {} };
const visaSink: VisaSink = { recordPayment: async () => 1n, updatePayment: async () => {}, logAgentEvent: async () => {} };

test("usdCapFromEnv: valid values (including 0) are used, unset/empty means the default, quietly", () => {
  resetCapWarnings();
  const w = collect();
  assert.equal(usdCapFromEnv({ AGENT_SPEND_CAP_USDC: "2.5" }, "AGENT_SPEND_CAP_USDC", w.warn), 2.5);
  assert.equal(usdCapFromEnv({ AGENT_SPEND_CAP_USDC: " 3 " }, "AGENT_SPEND_CAP_USDC", w.warn), 3);
  assert.equal(usdCapFromEnv({ VISA_SPEND_CAP_USD: "0" }, "VISA_SPEND_CAP_USD", w.warn), 0);
  assert.equal(usdCapFromEnv({}, "X402_MAX_PER_CALL_USDC", w.warn), 0.1);
  assert.equal(usdCapFromEnv({ VISA_MAX_PER_PURCHASE_USD: "  " }, "VISA_MAX_PER_PURCHASE_USD", w.warn), 750);
  assert.deepEqual(w.msgs, []);
});

test("usdCapFromEnv: non-numeric, negative, NaN and Infinity warn loudly (once per value) and use the default", () => {
  resetCapWarnings();
  const w = collect();
  for (const bad of ["5usd", "-1", "NaN", "Infinity", "$5", "abc"]) {
    assert.equal(usdCapFromEnv({ AGENT_SPEND_CAP_USDC: bad }, "AGENT_SPEND_CAP_USDC", w.warn), SPEND_CAP_DEFAULTS.AGENT_SPEND_CAP_USDC, bad);
  }
  assert.equal(w.msgs.length, 6);
  assert.match(w.msgs[1], /WARNING: AGENT_SPEND_CAP_USDC="-1" is not a number >= 0; using the default 5/);
  usdCapFromEnv({ AGENT_SPEND_CAP_USDC: "-1" }, "AGENT_SPEND_CAP_USDC", w.warn);
  assert.equal(w.msgs.length, 6, "the same bad value isn't warned about twice (startup check + rail)");
});

test("checkSpendCaps at startup: every cap resolved, one warning per bad cap, never throws", () => {
  resetCapWarnings();
  const w = collect();
  const caps = checkSpendCaps({ AGENT_SPEND_CAP_USDC: "five", X402_MAX_PER_CALL_USDC: "-0.1", VISA_SPEND_CAP_USD: "200", VISA_MAX_PER_PURCHASE_USD: "lots" }, w.warn);
  assert.deepEqual(caps, { AGENT_SPEND_CAP_USDC: 5, X402_MAX_PER_CALL_USDC: 0.1, VISA_SPEND_CAP_USD: 200, VISA_MAX_PER_PURCHASE_USD: 750 });
  assert.equal(w.msgs.length, 3);
  for (const k of ["AGENT_SPEND_CAP_USDC", "X402_MAX_PER_CALL_USDC", "VISA_MAX_PER_PURCHASE_USD"]) assert.ok(w.msgs.some((m) => m.includes(k)), k);
});

test("createX402Rail with a non-numeric or negative cap builds with the defaults instead of failing", async () => {
  resetCapWarnings();
  const { value: rail, warnings } = await quietly(() =>
    createX402Rail(x402Sink, { X402_SIMULATE: "1", AGENT_SPEND_CAP_USDC: "5usd", X402_MAX_PER_CALL_USDC: "-1" }),
  );
  assert.equal(rail.simulated, true);
  assert.equal(rail.remaining("pricing"), 5_000_000n);
  assert.equal((rail as unknown as { ledger: { maxPerCallMicros: bigint } }).ledger.maxPerCallMicros, 100_000n);
  assert.equal(warnings.filter((w) => /WARNING/.test(w)).length, 2);
  // A $0.01 comps call is allowed again (it used to be refused or never get a rail at all).
  const zero = await quietly(() => createX402Rail(x402Sink, { X402_SIMULATE: "1", AGENT_SPEND_CAP_USDC: "0" }));
  assert.equal(zero.value.remaining("pricing"), 0n, "an explicit 0 still means no x402 spend");
  assert.deepEqual(zero.warnings, []);
});

test("createVisaCheckout with a negative or non-numeric cap uses the default caps, with a warning", async () => {
  resetCapWarnings();
  const { value: visa, warnings } = await quietly(() =>
    createVisaCheckout(visaSink, { VISA_SPEND_CAP_USD: "-50", VISA_MAX_PER_PURCHASE_USD: "750usd", VISA_SIM_DELAY_MS: "0" }),
  );
  assert.equal(visa.remaining("buy", "user-1"), 150_000n);
  assert.equal(visa.spendBlocker("buy", "user-1", 75_000n), undefined);
  assert.match(visa.spendBlocker("buy", "user-1", 75_001n)!, /per-purchase max/);
  assert.equal(warnings.filter((w) => /WARNING/.test(w)).length, 2);
});
