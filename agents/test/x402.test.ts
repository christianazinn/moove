import { test } from "node:test";
import assert from "node:assert/strict";
import { encodePaymentRequiredHeader, encodePaymentResponseHeader } from "@x402/core/http";
import type { PaymentPayload, PaymentRequired } from "@x402/core/types";
import {
  BASE_SEPOLIA,
  SpendLedger,
  SpendRefusedError,
  USDC_BASE_SEPOLIA,
  X402Rail,
  createX402Rail,
  usdToMicros,
  type AgentEventRecord,
  type PaymentRecord,
  type PaymentSink,
} from "../src/integrations/x402.js";
import { COMPS_ROUTE, createCompsPaywall } from "../src/paywall.js";

const PAY_TO = "0x1111111111111111111111111111111111111111";
const TX = "0xabc123";

function memorySink() {
  const payments: PaymentRecord[] = [];
  const events: AgentEventRecord[] = [];
  const sink: PaymentSink = {
    recordPayment: async (p) => void payments.push(p),
    logAgentEvent: async (e) => void events.push(e),
  };
  return { sink, payments, events };
}

function paymentRequired(amountAtomic: string, network = BASE_SEPOLIA, asset = USDC_BASE_SEPOLIA): PaymentRequired {
  return {
    x402Version: 2,
    resource: { url: "https://paid.example/comps", description: "comps", mimeType: "application/json" },
    accepts: [{ scheme: "exact", network, asset, amount: amountAtomic, payTo: PAY_TO, maxTimeoutSeconds: 60, extra: {} }],
  } as PaymentRequired;
}

/** A fake x402 server: 402 without a payment header, 200 + settlement with one. */
function fakeX402Server(pr: PaymentRequired, settle: { success: boolean } = { success: true }) {
  const seen: Request[] = [];
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    seen.push(req);
    if (!req.headers.get("PAYMENT-SIGNATURE")) {
      return new Response("{}", { status: 402, headers: { "PAYMENT-REQUIRED": encodePaymentRequiredHeader(pr) } });
    }
    const header = encodePaymentResponseHeader({
      success: settle.success,
      transaction: settle.success ? TX : "",
      network: BASE_SEPOLIA,
      payer: "0xpayer",
      ...(settle.success ? {} : { errorReason: "insufficient_funds" }),
    });
    return new Response(JSON.stringify({ comps: [] }), {
      status: settle.success ? 200 : 402,
      headers: { "PAYMENT-RESPONSE": header, "content-type": "application/json" },
    });
  }) as typeof globalThis.fetch;
  return { fetch, seen };
}

const fakeSigner = {
  signed: [] as PaymentRequired[],
  async createPaymentPayload(pr: PaymentRequired): Promise<PaymentPayload> {
    this.signed.push(pr);
    return { x402Version: 2, accepted: pr.accepts[0], payload: { signature: "0xsig" } };
  },
};

const ctx = { owner: "user-1", agent: "pricing", purpose: "comps for 'IKEA Poang chair'", refTable: "item", refId: 7n };

test("pays a 402, retries with a signature, and records a settled payment with the tx hash", async () => {
  const { sink, payments, events } = memorySink();
  const server = fakeX402Server(paymentRequired("10000")); // $0.01
  fakeSigner.signed = [];
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(1), usdToMicros(0.1)), signer: fakeSigner, fetch: server.fetch });

  const { response, payment } = await rail.paidFetch(ctx, "https://paid.example/comps?q=chair");

  assert.equal(response.status, 200);
  assert.equal(server.seen.length, 2);
  assert.ok(server.seen[1].headers.get("PAYMENT-SIGNATURE"));
  assert.equal(fakeSigner.signed.length, 1);
  assert.deepEqual(payment, {
    owner: "user-1",
    agent: "pricing",
    rail: "x402",
    purpose: ctx.purpose,
    payee: PAY_TO,
    amountUsdMicros: 10_000n,
    txHash: TX,
    status: "settled",
    simulated: false,
    refTable: "item",
    refId: 7n,
  });
  assert.equal(payments.length, 1);
  assert.deepEqual(events.map((e) => e.kind), ["tool_call", "payment"]);
  assert.match(JSON.parse(events[1].dataJson).explorer, /sepolia\.basescan\.org\/tx\/0xabc123$/);
  assert.equal(rail.remaining("pricing"), usdToMicros(1) - 10_000n);
});

test("does not pay when the server returns no 402", async () => {
  const { sink, payments, events } = memorySink();
  const fetch = (async () => new Response("ok")) as typeof globalThis.fetch;
  const rail = new X402Rail({ sink, ledger: new SpendLedger(1_000_000n, 100_000n), signer: fakeSigner, fetch });
  const { payment } = await rail.paidFetch(ctx, "https://free.example/");
  assert.equal(payment, undefined);
  assert.equal(payments.length + events.length, 0);
});

test("refuses a call over the per-call max, signs nothing, and logs the refusal", async () => {
  const { sink, payments, events } = memorySink();
  const server = fakeX402Server(paymentRequired("500000")); // $0.50
  fakeSigner.signed = [];
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(5), usdToMicros(0.1)), signer: fakeSigner, fetch: server.fetch });

  await assert.rejects(rail.paidFetch(ctx, "https://paid.example/comps"), SpendRefusedError);
  assert.equal(fakeSigner.signed.length, 0);
  assert.equal(server.seen.length, 1);
  assert.equal(payments.length, 0);
  assert.equal(events.length, 1);
  assert.equal(events[0].kind, "error");
  assert.match(events[0].message, /^Refused x402 payment.*per-call max/);
  assert.equal(JSON.parse(events[0].dataJson).refused, true);
});

test("refuses once the agent's budget is used up", async () => {
  const { sink, events } = memorySink();
  const server = fakeX402Server(paymentRequired("40000")); // $0.04 each, $0.10 budget
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(0.1), usdToMicros(0.1)), signer: fakeSigner, fetch: server.fetch });

  await rail.paidFetch(ctx, "https://paid.example/comps");
  await rail.paidFetch(ctx, "https://paid.example/comps");
  await assert.rejects(rail.paidFetch(ctx, "https://paid.example/comps"), /would exceed the pricing budget/);
  assert.equal(events.at(-1)!.kind, "error");
  // Budgets are per agent.
  await rail.paidFetch({ ...ctx, agent: "buy" }, "https://paid.example/comps");
});

test("concurrent calls from one agent cannot overspend the budget", async () => {
  const { sink, payments } = memorySink();
  const server = fakeX402Server(paymentRequired("40000"));
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(0.1), usdToMicros(0.1)), signer: fakeSigner, fetch: server.fetch });
  const results = await Promise.allSettled([1, 2, 3, 4].map(() => rail.paidFetch(ctx, "https://paid.example/comps")));
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 2);
  assert.equal(payments.length, 2);
});

test("refuses servers that don't take Base Sepolia USDC", async () => {
  const { sink } = memorySink();
  const server = fakeX402Server(paymentRequired("10000", "eip155:8453")); // Base mainnet
  fakeSigner.signed = [];
  const rail = new X402Rail({ sink, ledger: new SpendLedger(1_000_000n, 100_000n), signer: fakeSigner, fetch: server.fetch });
  await assert.rejects(rail.paidFetch(ctx, "https://paid.example/comps"), /Base Sepolia USDC/);
  assert.equal(fakeSigner.signed.length, 0);
});

test("a failed settlement is recorded as failed and refunds the budget", async () => {
  const { sink, payments, events } = memorySink();
  const server = fakeX402Server(paymentRequired("10000"), { success: false });
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(1), usdToMicros(0.1)), signer: fakeSigner, fetch: server.fetch });
  const { payment } = await rail.paidFetch(ctx, "https://paid.example/comps");
  assert.equal(payment!.status, "failed");
  assert.equal(payments[0].status, "failed");
  assert.equal(events.at(-1)!.kind, "error");
  assert.match(events.at(-1)!.message, /insufficient_funds/);
  assert.equal(rail.remaining("pricing"), usdToMicros(1));
});

test("simulated rail labels every payment and event as simulated", async () => {
  const { sink, payments, events } = memorySink();
  const fetch = (async () => new Response("{}")) as typeof globalThis.fetch;
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(1), usdToMicros(0.1)), fetch });
  assert.equal(rail.simulated, true);
  const { payment } = await rail.paidFetch({ ...ctx, quotedUsdMicros: 10_000n }, "https://paid.example/comps");
  assert.equal(payment!.simulated, true);
  assert.equal(payment!.txHash, "");
  assert.equal(payments[0].simulated, true);
  assert.match(events.at(-1)!.message, /^\[SIMULATED\]/);
});

test("simulated rail still enforces budgets", async () => {
  const { sink } = memorySink();
  const fetch = (async () => new Response("{}")) as typeof globalThis.fetch;
  const rail = new X402Rail({ sink, ledger: new SpendLedger(usdToMicros(1), usdToMicros(0.1)), fetch });
  await assert.rejects(rail.paidFetch({ ...ctx, quotedUsdMicros: usdToMicros(0.5) }, "https://x/"), SpendRefusedError);
});

test("createX402Rail is simulated without CDP keys or with X402_SIMULATE=1", async () => {
  const { sink } = memorySink();
  assert.equal((await createX402Rail(sink, {})).simulated, true);
  assert.equal(
    (await createX402Rail(sink, { CDP_API_KEY_ID: "a", CDP_API_KEY_SECRET: "b", CDP_WALLET_SECRET: "c", X402_SIMULATE: "1" })).simulated,
    true,
  );
});

test("comps endpoint (simulated, unpaywalled) end to end through the simulated rail", async () => {
  const paywall = await createCompsPaywall(async (q) => ({
    comps: [{ source: "fixture", title: `${q} (fixture)`, priceCents: 4500, url: "https://example.com/1" }],
    replayed: true,
  }), {});
  assert.equal(paywall.paywalled, false);
  const server = paywall.app.listen(0);
  try {
    const port = (server.address() as { port: number }).port;
    const { sink, payments } = memorySink();
    const rail = await createX402Rail(sink, {});
    const { response } = await rail.paidFetch({ ...ctx, quotedUsdMicros: 10_000n }, `http://127.0.0.1:${port}${COMPS_ROUTE}?q=chair`);
    const body = await response.json();
    assert.equal(body.comps[0].title, "chair (fixture)");
    assert.equal(body.paywalled, false);
    assert.equal(payments[0].simulated, true);

    const missing = await fetch(`http://127.0.0.1:${port}${COMPS_ROUTE}`);
    assert.equal(missing.status, 400);
  } finally {
    server.close();
  }
});
