import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import {
  CYBERSOURCE_SANDBOX_HOST,
  CardSpendLedger,
  VisaApiError,
  VisaCheckout,
  approvalGate,
  createAcceptanceBackend,
  createSimulatedBackend,
  createVisaCheckout,
  cybersourceSignedHeaders,
  selectBackend,
  type ApprovalView,
  type CheckoutBackend,
  type PurchaseContext,
  type VisaEventRecord,
  type VisaPaymentRecord,
  type VisaSink,
} from "../src/integrations/visa.js";

const NOW = new Date("2026-10-24T18:30:00.000Z");
const SECRET = Buffer.from("not-a-real-shared-secret-0123456789").toString("base64");
const CFG = { merchantId: "moove_test", keyId: "11111111-2222-3333-4444-555555555555", secret: SECRET };
const ENV_KEYS = { VISA_ACCEPTANCE_MERCHANT_ID: "m", VISA_ACCEPTANCE_KEY_ID: "k", VISA_ACCEPTANCE_SECRET: SECRET };

function memorySink() {
  const payments: (VisaPaymentRecord & { id: bigint })[] = [];
  const updates: { paymentId: bigint; status: string }[] = [];
  const events: VisaEventRecord[] = [];
  let next = 1n;
  const sink: VisaSink = {
    async recordPayment(p) {
      const id = next++;
      payments.push({ ...p, id });
      return id;
    },
    async updatePayment(paymentId, status) {
      updates.push({ paymentId, status });
      const row = payments.find((p) => p.id === paymentId);
      if (row) row.status = status;
    },
    logAgentEvent: async (e) => void events.push(e),
  };
  return { sink, payments, updates, events };
}

type Reply = { status: number; body: unknown };
/** A fake CyberSource REST server. `routes` maps an endpoint kind to a reply (or a queue of replies). */
function fakeCybersource(routes: Partial<Record<"authorize" | "capture" | "reverse", Reply | Reply[]>> = {}) {
  const seen: { url: string; path: string; headers: Headers; body: any; kind: string }[] = [];
  const defaults: Record<string, Reply> = {
    authorize: { status: 201, body: { id: "7000000000000000000001", status: "AUTHORIZED" } },
    capture: { status: 201, body: { id: "7000000000000000000002", status: "PENDING" } },
    reverse: { status: 201, body: { id: "7000000000000000000003", status: "REVERSED" } },
  };
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input));
    const kind = url.pathname.endsWith("/captures") ? "capture" : url.pathname.endsWith("/reversals") ? "reverse" : "authorize";
    seen.push({ url: url.href, path: url.pathname, headers: new Headers(init?.headers), body: JSON.parse(String(init?.body)), kind });
    const r = routes[kind as keyof typeof routes];
    const reply = Array.isArray(r) ? (r.length > 1 ? r.shift()! : r[0]) : (r ?? defaults[kind]);
    return new Response(JSON.stringify(reply.body), { status: reply.status, headers: { "content-type": "application/hal+json" } });
  }) as typeof globalThis.fetch;
  return { fetch, seen };
}

/** Wraps a backend and counts calls. */
function spy(inner: CheckoutBackend) {
  const calls = { authorize: 0, capture: 0, void: 0 };
  const backend: CheckoutBackend = {
    ...inner,
    authorize: (req) => (calls.authorize++, inner.authorize(req)),
    capture: (...a) => (calls.capture++, inner.capture(...a)),
    void: (...a) => (calls.void++, inner.void(...a)),
  };
  return { backend, calls };
}

const approved = (amountCents: bigint, status = "approved"): ApprovalView => ({ id: 9n, status, amountCents });

function ctx(over: Partial<PurchaseContext> = {}): PurchaseContext {
  return {
    owner: "user-1",
    agent: "buy",
    purpose: "Twin bed frame from IKEA",
    merchant: "IKEA",
    refTable: "deal",
    refId: 12n,
    amountCents: 12_345n,
    thresholdCents: 20_000n,
    currentApproval: () => undefined,
    consumerPrompt: "a twin bed frame under $150",
    ...over,
  };
}

const ledger = (cap = 50_000n, max = 30_000n) => new CardSpendLedger(cap, max);

// ---------- signing ----------

test("cybersourceSignedHeaders matches an independently computed HTTP Signature", () => {
  const body = JSON.stringify({ hello: "world", amount: "1.00" });
  const path = "/pts/v2/payments";
  const h = cybersourceSignedHeaders({ ...CFG, host: CYBERSOURCE_SANDBOX_HOST }, "POST", path, body, NOW);

  const digest = "SHA-256=" + crypto.createHash("sha256").update(body).digest("base64");
  const date = "Sat, 24 Oct 2026 18:30:00 GMT";
  const signingString = [
    `host: ${CYBERSOURCE_SANDBOX_HOST}`,
    `date: ${date}`,
    `request-target: post ${path}`,
    `digest: ${digest}`,
    `v-c-merchant-id: ${CFG.merchantId}`,
  ].join("\n");
  const sig = crypto.createHmac("sha256", Buffer.from(SECRET, "base64")).update(signingString).digest("base64");

  assert.equal(h.date, date);
  assert.equal(h.digest, digest);
  assert.equal(h["v-c-merchant-id"], CFG.merchantId);
  assert.equal(
    h.signature,
    `keyid="${CFG.keyId}", algorithm="HmacSHA256", headers="host date request-target digest v-c-merchant-id", signature="${sig}"`,
  );
});

test("GET signatures omit the digest", () => {
  const h = cybersourceSignedHeaders({ ...CFG, host: CYBERSOURCE_SANDBOX_HOST }, "GET", "/x", "", NOW);
  assert.equal(h.digest, undefined);
  assert.match(h.signature, /headers="host date request-target v-c-merchant-id"/);
});

// ---------- acceptance backend ----------

test("acceptance authorize posts a sandbox auth-only request on the test card", async () => {
  const server = fakeCybersource();
  const b = createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW });
  assert.equal(b.simulated, false);
  assert.equal(b.sandbox, true);

  const r = await b.authorize({ reference: "moove-deal-12", amountCents: 12_345n, currency: "USD", description: "bed" });
  assert.deepEqual(r, { id: "7000000000000000000001", status: "authorized", processorStatus: "AUTHORIZED", reason: undefined, httpStatus: 201 });
  const req = server.seen[0];
  assert.equal(req.url, "https://apitest.cybersource.com/pts/v2/payments");
  assert.equal(req.body.processingInformation.capture, false);
  assert.equal(req.body.paymentInformation.card.number, "4111111111111111");
  assert.equal(req.body.orderInformation.amountDetails.totalAmount, "123.45");
  assert.equal(req.body.orderInformation.amountDetails.currency, "USD");
  assert.equal(req.body.clientReferenceInformation.code, "moove-deal-12");
  // The signed digest covers exactly the body that was sent.
  const sent = JSON.stringify(req.body);
  assert.equal(req.headers.get("digest"), "SHA-256=" + crypto.createHash("sha256").update(sent).digest("base64"));
  assert.match(req.headers.get("signature")!, /^keyid="11111111-/);
});

test("acceptance formats cent amounts", async () => {
  const server = fakeCybersource();
  const b = createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW });
  for (const c of [500n, 7n, 100n, 99_999n]) await b.authorize({ reference: "r", amountCents: c, currency: "USD", description: "d" });
  assert.deepEqual(
    server.seen.map((s) => s.body.orderInformation.amountDetails.totalAmount),
    ["5.00", "0.07", "1.00", "999.99"],
  );
});

test("acceptance capture and reversal hit the right endpoints and map statuses", async () => {
  const server = fakeCybersource();
  const b = createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW });
  const cap = await b.capture("auth/1", 500n, "moove-deal-12");
  assert.equal(cap.status, "captured");
  assert.equal(cap.processorStatus, "PENDING");
  assert.equal(server.seen[0].path, "/pts/v2/payments/auth%2F1/captures");
  assert.equal(server.seen[0].body.orderInformation.amountDetails.totalAmount, "5.00");

  const rev = await b.void("A1", 500n, "moove-deal-12", "user picked another deal");
  assert.equal(rev.status, "voided");
  assert.equal(rev.processorStatus, "REVERSED");
  assert.equal(server.seen[1].path, "/pts/v2/payments/A1/reversals");
  assert.equal(server.seen[1].body.reversalInformation.amountDetails.totalAmount, "5.00");
  assert.equal(server.seen[1].body.reversalInformation.reason, "user picked another deal");
});

test("acceptance maps a 201 DECLINED to declined instead of throwing", async () => {
  const server = fakeCybersource({
    authorize: { status: 201, body: { id: "D1", status: "DECLINED", errorInformation: { reason: "INSUFFICIENT_FUND", message: "Decline" } } },
  });
  const b = createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW });
  const r = await b.authorize({ reference: "r", amountCents: 100n, currency: "USD", description: "d" });
  assert.equal(r.status, "declined");
  assert.equal(r.reason, "INSUFFICIENT_FUND: Decline");
});

test("acceptance throws VisaApiError on 401", async () => {
  const server = fakeCybersource({ authorize: { status: 401, body: { response: { rmsg: "Authentication Failed" } } } });
  const b = createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW });
  await assert.rejects(b.authorize({ reference: "r", amountCents: 100n, currency: "USD", description: "d" }), (e: unknown) => {
    assert.ok(e instanceof VisaApiError);
    assert.equal(e.httpStatus, 401);
    assert.match(e.message, /Authentication Failed/);
    return true;
  });
});

test("acceptance refuses any non-sandbox host", () => {
  assert.throws(() => createAcceptanceBackend({ ...CFG, host: "api.cybersource.com" }), /sandbox only/);
});

// ---------- purchase flow ----------

test("simulated purchase records pending -> settled, labeled simulated everywhere", async () => {
  const { sink, payments, updates, events } = memorySink();
  const co = new VisaCheckout({ sink, backend: createSimulatedBackend(), ledger: ledger() });
  const r = await co.purchase(ctx());

  assert.equal(r.status, "captured");
  assert.equal(r.simulated, true);
  assert.equal(r.provider, "simulated");
  assert.match(r.captureId!, /^sim_/);
  assert.equal(payments.length, 1);
  const p = payments[0];
  assert.equal(p.rail, "visa");
  assert.equal(p.simulated, true);
  assert.equal(p.amountUsdMicros, 12_345n * 10_000n);
  assert.match(p.txHash, /^sim_auth_[0-9a-f-]{36}$/);
  assert.deepEqual(updates, [{ paymentId: p.id, status: "settled" }]);
  assert.equal(p.status, "settled");
  assert.ok(events.length >= 4);
  for (const e of events) {
    assert.equal(e.data.simulated, true, e.message);
    assert.match(e.message, /^\[SIMULATED\]/);
    assert.equal(e.data.rail, "visa");
  }
  assert.deepEqual(events.map((e) => e.kind), ["tool_call", "payment", "tool_call", "payment"]);
  assert.equal(co.remaining("buy"), 50_000n - 12_345n);
});

test("simulated ids are unique across backend instances (worker restarts)", async () => {
  const req = { reference: "r", amountCents: 1n, currency: "USD" as const, description: "d" };
  const a = await createSimulatedBackend().authorize(req);
  const b = await createSimulatedBackend().authorize(req);
  assert.notEqual(a.id, b.id);
  assert.match(a.id, /^sim_auth_/);
});

test("sandbox purchase is labeled simulated: false with sandbox notes", async () => {
  const { sink, payments, events } = memorySink();
  const server = fakeCybersource();
  const co = new VisaCheckout({ sink, backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }), ledger: ledger() });
  const r = await co.purchase(ctx());
  assert.equal(r.status, "captured");
  assert.equal(r.simulated, false);
  assert.equal(payments[0].simulated, false);
  assert.equal(payments[0].txHash, "7000000000000000000001");
  assert.match(payments[0].payee, /sandbox merchant \(for IKEA\)/);
  for (const e of events) {
    assert.match(e.message, /^\[VISA SANDBOX\]/);
    assert.equal(e.data.sandbox, true);
    assert.equal(e.data.simulated, false);
  }
  assert.deepEqual(server.seen.map((s) => s.kind), ["authorize", "capture"]);
});

// ---------- approval gate ----------

test("approvalGate rules", () => {
  assert.deepEqual(approvalGate(100n, 100n, undefined), { ok: true });
  assert.equal(approvalGate(101n, 100n, undefined).ok, false);
  assert.deepEqual(approvalGate(1n, -1n, approved(1n)), { ok: true, approvalId: 9n });
  assert.equal(approvalGate(1n, -1n, undefined).ok, false);
  assert.equal(approvalGate(500n, 100n, approved(400n)).ok, false);
});

test("above the threshold with no approval: needs_approval and nothing is authorized", async () => {
  const { sink, payments, events } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const r = await co.purchase(ctx({ amountCents: 25_000n }));
  assert.equal(r.status, "needs_approval");
  assert.equal(s.calls.authorize, 0);
  assert.equal(payments.length, 0);
  assert.deepEqual(events.map((e) => e.kind), ["approval"]);
  assert.equal(co.remaining("buy"), 50_000n);
});

test("pending approval waits, denied and mismatched approvals refuse, none authorize", async () => {
  const { sink } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const amt = 25_000n;
  assert.equal((await co.purchase(ctx({ amountCents: amt, currentApproval: () => approved(amt, "pending") }))).status, "waiting");
  assert.equal((await co.purchase(ctx({ amountCents: amt, currentApproval: () => approved(amt, "denied") }))).status, "refused");
  const mismatch = await co.purchase(ctx({ amountCents: amt, currentApproval: () => approved(24_000n) }));
  assert.equal(mismatch.status, "refused");
  assert.match(mismatch.reason!, /approved \$240\.00 but the amount is now \$250\.00/);
  assert.equal(s.calls.authorize, 0);
});

test("threshold -1 always asks, even for small amounts", async () => {
  const { sink } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  assert.equal((await co.purchase(ctx({ amountCents: 1n, thresholdCents: -1n }))).status, "needs_approval");
  assert.equal(s.calls.authorize, 0);
  const ok = await co.purchase(ctx({ amountCents: 1n, thresholdCents: -1n, currentApproval: () => approved(1n) }));
  assert.equal(ok.status, "captured");
});

test("an approval denied while the hold is in flight voids it and never captures", async () => {
  const { sink, payments, events } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const amt = 25_000n;
  let n = 0;
  const r = await co.purchase(ctx({ amountCents: amt, currentApproval: () => (n++ === 0 ? approved(amt) : approved(amt, "denied")) }));
  assert.equal(r.status, "voided");
  assert.match(r.reason!, /approval denied/);
  assert.equal(s.calls.authorize, 1);
  assert.equal(s.calls.capture, 0);
  assert.equal(s.calls.void, 1);
  assert.equal(payments[0].status, "failed");
  assert.equal(events.at(-1)!.data.voided, true);
  assert.equal(co.remaining("buy"), 50_000n);
});

test("stillValid returning a reason voids the hold", async () => {
  const { sink, payments } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const r = await co.purchase(ctx({ stillValid: () => "user picked another deal" }));
  assert.equal(r.status, "voided");
  assert.equal(r.reason, "user picked another deal");
  assert.equal(s.calls.capture, 0);
  assert.equal(payments[0].status, "failed");
});

test("calling capture() directly still enforces the approval gate", async () => {
  const { sink, payments } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const c = ctx({ amountCents: 25_000n });
  const hold = await co.authorize(c); // authorize() itself has no gate; capture must
  await assert.rejects(co.capture(c, hold), /not captured: .*threshold/);
  assert.equal(s.calls.capture, 0);
  assert.equal(s.calls.void, 1);
  assert.equal(payments[0].status, "failed");
  assert.equal(co.remaining("buy"), 50_000n);
});

test("a hold can be closed only once: no double release, no release after capture", async () => {
  const { sink } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const c = ctx({ amountCents: 1_000n });

  const h1 = await co.authorize(c);
  await co.void(c, h1, "first");
  await assert.rejects(co.void(c, h1, "second"), /already captured or voided/);
  await assert.rejects(co.capture(c, h1), /already captured or voided/);
  assert.equal(co.remaining("buy"), 50_000n);

  const h2 = await co.authorize(c);
  await co.capture(c, h2);
  await assert.rejects(co.void(c, h2, "late"), /already captured or voided/);
  await assert.rejects(co.capture(c, h2), /already captured or voided/);
  assert.equal(co.remaining("buy"), 49_000n);
  assert.equal(s.calls.capture, 1);
  assert.equal(s.calls.void, 1);

  await assert.rejects(co.capture(c, { ...h2, authId: "forged" }), /unknown hold/);
});

test("a reversal the processor does not confirm is logged as an error, not as released", async () => {
  const { sink, events } = memorySink();
  const server = fakeCybersource({ reverse: { status: 201, body: { id: "R1", status: "DECLINED" } } });
  const co = new VisaCheckout({ sink, backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }), ledger: ledger() });
  const r = await co.purchase(ctx({ stillValid: () => "changed mind" }));
  assert.equal(r.status, "voided");
  assert.equal(events.at(-1)!.kind, "error");
  assert.match(events.at(-1)!.message, /Could not release the hold/);
});

test("a capture decline voids the hold and releases budget", async () => {
  const { sink, payments } = memorySink();
  const server = fakeCybersource({ capture: { status: 201, body: { id: "C1", status: "DECLINED" } } });
  const co = new VisaCheckout({ sink, backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }), ledger: ledger() });
  const r = await co.purchase(ctx());
  assert.equal(r.status, "declined");
  assert.deepEqual(server.seen.map((s) => s.kind), ["authorize", "capture", "reverse"]);
  assert.equal(payments[0].status, "failed");
  assert.equal(co.remaining("buy"), 50_000n);
});

// ---------- ledger ----------

test("over the per-purchase max or the cap: refused, no authorize, error event", async () => {
  const { sink, payments, events } = memorySink();
  const s = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: s.backend, ledger: ledger(20_000n, 15_000n) });

  const big = await co.purchase(ctx({ amountCents: 16_000n }));
  assert.equal(big.status, "refused");
  assert.match(big.reason!, /per-purchase max of \$150\.00/);
  assert.equal(events.at(-1)!.kind, "error");
  assert.equal(events.at(-1)!.data.refused, true);

  assert.equal((await co.purchase(ctx({ amountCents: 15_000n }))).status, "captured");
  const over = await co.purchase(ctx({ amountCents: 6_000n }));
  assert.equal(over.status, "refused");
  assert.match(over.reason!, /would exceed the buy card budget/);
  assert.equal(s.calls.authorize, 1);
  assert.equal(payments.length, 1);
});

test("budget is released after a void or a decline so a later purchase fits", async () => {
  const { sink } = memorySink();
  const co = new VisaCheckout({ sink, backend: createSimulatedBackend({ declineOverCents: 9_000n }), ledger: ledger(10_000n, 10_000n) });
  assert.equal((await co.purchase(ctx({ amountCents: 9_500n }))).status, "declined");
  assert.equal(co.remaining("buy"), 10_000n);
  assert.equal((await co.purchase(ctx({ amountCents: 9_000n, stillValid: () => "nope" }))).status, "voided");
  assert.equal(co.remaining("buy"), 10_000n);
  assert.equal((await co.purchase(ctx({ amountCents: 9_000n }))).status, "captured");
  assert.equal(co.remaining("buy"), 1_000n);
});

test("concurrent purchases cannot overspend the cap", async () => {
  const { sink } = memorySink();
  const co = new VisaCheckout({ sink, backend: createSimulatedBackend({ delayMs: 5 }), ledger: ledger(10_000n, 10_000n) });
  const rs = await Promise.all([1, 2, 3, 4].map(() => co.purchase(ctx({ amountCents: 4_000n }))));
  assert.equal(rs.filter((r) => r.status === "captured").length, 2);
  assert.equal(co.remaining("buy"), 2_000n);
});

// ---------- fallback ----------

test("a 500 from CyberSource falls back to the simulated checkout for that purchase only", async () => {
  const { sink, payments, events } = memorySink();
  const server = fakeCybersource({ authorize: [{ status: 500, body: { message: "down" } }, { status: 201, body: { id: "A2", status: "AUTHORIZED" } }] });
  const co = new VisaCheckout({
    sink,
    backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }),
    fallback: createSimulatedBackend(),
    ledger: ledger(),
  });

  const r1 = await co.purchase(ctx());
  assert.equal(r1.status, "captured");
  assert.equal(r1.simulated, true);
  assert.equal(payments[0].simulated, true);
  const fb = events.find((e) => e.kind === "error")!;
  assert.match(fb.message, /^\[VISA SANDBOX\] CyberSource 500.*falling back to the simulated checkout/);
  assert.equal(fb.data.fallback, "simulated");
  // Everything after the switch is labeled simulated.
  const after = events.slice(events.indexOf(fb) + 1);
  assert.ok(after.length > 0);
  for (const e of after) assert.equal(e.data.simulated, true, e.message);
  assert.deepEqual(server.seen.map((s) => s.kind), ["authorize"]); // the simulated hold was not captured on CyberSource

  // The next purchase tries the sandbox again and is captured there.
  assert.equal(co.simulated, false);
  const r2 = await co.purchase(ctx({ refId: 13n }));
  assert.equal(r2.status, "captured");
  assert.equal(r2.simulated, false);
  assert.equal(payments[1].simulated, false);
  assert.deepEqual(server.seen.map((s) => s.kind), ["authorize", "authorize", "capture"]);
  assert.equal(server.seen[2].path, "/pts/v2/payments/A2/captures");
});

test("a sandbox hold placed before another purchase falls back is still captured on the sandbox", async () => {
  const { sink } = memorySink();
  const server = fakeCybersource({ authorize: [{ status: 201, body: { id: "A1", status: "AUTHORIZED" } }, { status: 502, body: {} }] });
  const sim = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }), fallback: sim.backend, ledger: ledger() });
  const c1 = ctx();
  const h1 = await co.authorize(c1);
  const h2 = await co.authorize(ctx({ refId: 13n, amountCents: 100n }));
  assert.equal(h1.simulated, false);
  assert.equal(h2.simulated, true);
  await co.capture(c1, h1);
  assert.equal(server.seen.at(-1)!.path, "/pts/v2/payments/A1/captures");
  assert.equal(sim.calls.capture, 0);
});

test("a decline does not fall back", async () => {
  const { sink } = memorySink();
  const server = fakeCybersource({ authorize: { status: 400, body: { id: "D", status: "DECLINED", errorInformation: { reason: "PROCESSOR_DECLINED" } } } });
  const sim = spy(createSimulatedBackend());
  const co = new VisaCheckout({ sink, backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }), fallback: sim.backend, ledger: ledger() });
  const r = await co.purchase(ctx());
  assert.equal(r.status, "declined");
  assert.equal(r.simulated, false);
  assert.match(r.reason!, /PROCESSOR_DECLINED/);
  assert.equal(sim.calls.authorize, 0);
  assert.equal(co.remaining("buy"), 50_000n);
});

test("a 401 without a fallback is a declined purchase with budget released", async () => {
  const { sink, payments } = memorySink();
  const server = fakeCybersource({ authorize: { status: 401, body: {} } });
  const co = new VisaCheckout({ sink, backend: createAcceptanceBackend({ ...CFG, fetch: server.fetch, now: () => NOW }), ledger: ledger() });
  const r = await co.purchase(ctx());
  assert.equal(r.status, "declined");
  assert.equal(payments.length, 0);
  assert.equal(co.remaining("buy"), 50_000n);
});

// ---------- env wiring ----------

test("selectBackend picks the backend from env", () => {
  assert.equal(selectBackend({}).backend.provider, "simulated");
  assert.equal(selectBackend({}).note, undefined);

  const acc = selectBackend(ENV_KEYS);
  assert.equal(acc.backend.provider, "acceptance");
  assert.equal(acc.backend.simulated, false);

  const vic = selectBackend({ ...ENV_KEYS, VISA_PROVIDER: "vic" });
  assert.equal(vic.backend.simulated, true);
  assert.match(vic.note!, /vic is not implemented/);

  const missing = selectBackend({ VISA_PROVIDER: "acceptance" });
  assert.equal(missing.backend.simulated, true);
  assert.match(missing.note!, /keys are missing/);

  const badHost = selectBackend({ ...ENV_KEYS, VISA_ACCEPTANCE_HOST: "api.cybersource.com" });
  assert.equal(badHost.backend.simulated, true);
  assert.match(badHost.note!, /sandbox only/);

  assert.equal(selectBackend({ ...ENV_KEYS, VISA_PROVIDER: "simulated" }).backend.simulated, true);
  assert.match(selectBackend({ VISA_PROVIDER: "paypal" }).note!, /unknown VISA_PROVIDER/);
});

test("createVisaCheckout budgets: defaults, and an explicit 0 cap means no spending", async () => {
  const { sink } = memorySink();
  assert.equal(createVisaCheckout(sink, {}).remaining("buy"), 150_000n);
  const zero = createVisaCheckout(sink, { VISA_SPEND_CAP_USD: "0", VISA_SIM_DELAY_MS: "0" });
  assert.equal(zero.remaining("buy"), 0n);
  assert.equal((await zero.purchase(ctx({ amountCents: 100n }))).status, "refused");
});

// ---------- review fixes ----------

test("a denied approval blocks the purchase even after the threshold is raised above the price", async () => {
  const { sink } = memorySink();
  const s = spy(createSimulatedBackend());
  const visa = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  const r = await visa.purchase(ctx({ thresholdCents: 50_000n, currentApproval: () => approved(12_345n, "denied") }));
  assert.equal(r.status, "refused");
  assert.equal(s.calls.authorize, 0);
  assert.deepEqual(approvalGate(100n, 1_000n, approved(100n, "expired")), { ok: false, needsApproval: false, reason: "approval expired" });
});

test("the threshold is read fresh at the pre-capture re-check", async () => {
  const { sink, payments } = memorySink();
  const s = spy(createSimulatedBackend());
  const visa = new VisaCheckout({ sink, backend: s.backend, ledger: ledger() });
  let threshold = 20_000n; // under it at first, then the user switches to "always ask" mid-flight
  const r = await visa.purchase(
    ctx({
      thresholdCents: () => {
        const t = threshold;
        threshold = -1n;
        return t;
      },
    }),
  );
  assert.equal(r.status, "voided");
  assert.equal(s.calls.capture, 0);
  assert.equal(payments[0].status, "failed");
});

test("a capture that fails in transit stays pending, keeps the budget and is not voided", async () => {
  const { sink, payments } = memorySink();
  const inner = createSimulatedBackend();
  const s = spy({
    ...inner,
    capture: async () => {
      throw new VisaApiError("socket hang up", 0, {});
    },
  });
  const l = ledger(20_000n);
  const visa = new VisaCheckout({ sink, backend: s.backend, ledger: l });
  const r = await visa.purchase(ctx());
  assert.equal(r.status, "unknown");
  assert.equal(s.calls.void, 0);
  assert.equal(payments[0].status, "pending");
  assert.equal(l.spentBy("buy"), 12_345n);
});

test("a reversal that fails keeps the hold counted against the budget", async () => {
  const { sink } = memorySink();
  const inner = createSimulatedBackend();
  const backend: CheckoutBackend = { ...inner, void: async () => ({ id: "", status: "declined", processorStatus: "DECLINED", reason: "nope" }) };
  const l = ledger();
  const visa = new VisaCheckout({ sink, backend, ledger: l });
  const r = await visa.purchase(ctx({ stillValid: () => "user picked another deal" }));
  assert.equal(r.status, "voided");
  assert.equal(l.spentBy("buy"), 12_345n);
});

test("seeded spend from earlier runs counts toward the cap", async () => {
  const { sink } = memorySink();
  const s = spy(createSimulatedBackend());
  const visa = new VisaCheckout({ sink, backend: s.backend, ledger: ledger(20_000n) });
  visa.seedSpent("buy", 10_000n);
  const r = await visa.purchase(ctx());
  assert.equal(r.status, "refused");
  assert.equal(s.calls.authorize, 0);
});
