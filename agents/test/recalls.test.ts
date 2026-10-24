import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { encodePaymentRequiredHeader, encodePaymentResponseHeader } from "@x402/core/http";
import type { PaymentPayload, PaymentRequired } from "@x402/core/types";
import type { Item } from "../src/module_bindings/types.js";
import {
  BASE_SEPOLIA,
  SpendLedger,
  USDC_BASE_SEPOLIA,
  X402Rail,
  pickRequirements,
  usdToMicros,
  type AgentEventRecord,
  type PaymentRecord,
} from "../src/integrations/x402.js";
import {
  RECALLS_PAYEE,
  createRecallChecker,
  parseRecallResponse,
  probableMatches,
  recallCheckEnabled,
  recallQuery,
} from "../src/integrations/recalls.js";

// The CPSC recall check (integrations/recalls.ts) against a fake copy of the third-party x402 service.

const INVOICE = "1792877642-dea8f66491b142c0-d1596-e8d5246e49b9911e3dddef6c";

/** The service's real `accepts` shape: Base mainnet, XRPL mainnet, Base Sepolia, XRPL testnet. */
function mixedPaymentRequired(): PaymentRequired {
  return {
    x402Version: 2,
    resource: { url: "https://api.stablecoingateways.com/v1/recalls?q=x&source=cpsc", description: "Product recall check (US)", mimeType: "application/json" },
    accepts: [
      { amount: "2000", asset: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", extra: { invoiceId: INVOICE, name: "USD Coin", version: "2" }, maxTimeoutSeconds: 600, network: "eip155:8453", payTo: "0x39BF4378b74f9E19c5113b00b01f57d94537bad1", scheme: "exact" },
      { amount: "1596", asset: "XRP", extra: { invoiceId: INVOICE, sourceTag: 26100009 }, maxTimeoutSeconds: 600, network: "xrpl:0", payTo: "r3BsahzSMtF4HiJuL8HMf1se6T1JtMB6hg", scheme: "exact" },
      { amount: "2000", asset: USDC_BASE_SEPOLIA, extra: { invoiceId: INVOICE, name: "USDC", version: "2" }, maxTimeoutSeconds: 600, network: "eip155:84532", payTo: RECALLS_PAYEE, scheme: "exact" },
      { amount: "1596", asset: "XRP", extra: { invoiceId: INVOICE, sourceTag: 26100009 }, maxTimeoutSeconds: 600, network: "xrpl:1", payTo: "rDbkEYdqLHcnWAHAVFwhH6KM6puCPbXNgs", scheme: "exact" },
    ],
  } as PaymentRequired;
}

/** Shaped like the Bazaar example output. */
const MALM_BODY = {
  data: {
    cpsc: [
      { date: "2016-06-28", description: "This recall involves IKEA MALM 3- and 6-drawer chests and dressers...", recall_number: "16221", source: "CPSC", title: "IKEA Recalls MALM and Other Models of Chests and Dressers Due to Serious Tip-Over Hazard", products: [{ name: "IKEA MALM chests and dressers", model: null, units: "About 29 million" }], hazards: ["The chests and dressers can tip over."], remedies: [], url: "https://www.cpsc.gov/Recalls/2016/IKEA-Recalls-MALM" },
      { date: "2026-07-23", description: "Peony Design baby bibs and stroller bags.", recall_number: "26639", source: "CPSC", title: "Peony Design Recalls Personalized Baby Bibs and Stroller Bags" },
    ],
    fda: [],
    partial_errors: [],
    query: "IKEA Malm dresser",
    retrieved_at: "2026-10-24T10:32:46.327Z",
    source: "cpsc",
    sources: ["U.S. CPSC Recalls API (saferproducts.gov), public"],
  },
  receipt: { v: 1, tx_hash: "0x.." },
};

const TX = "0x" + "ab".repeat(32);

/** Fake service: 402 + PAYMENT-REQUIRED without a signature, 200 + PAYMENT-RESPONSE with one. */
function fakeService(opts: { body?: unknown; status?: number; raw?: string } = {}) {
  const seen: Request[] = [];
  const fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    seen.push(req);
    if (!req.headers.get("PAYMENT-SIGNATURE")) {
      return new Response(JSON.stringify({ x402Version: 2, error: "PAYMENT-SIGNATURE header is required" }), {
        status: 402,
        headers: { "PAYMENT-REQUIRED": encodePaymentRequiredHeader(mixedPaymentRequired()), "content-type": "application/json" },
      });
    }
    const status = opts.status ?? 200;
    const header = encodePaymentResponseHeader({ success: status === 200, transaction: status === 200 ? TX : "", network: BASE_SEPOLIA, payer: "0xpayer" });
    return new Response(opts.raw ?? JSON.stringify(opts.body ?? MALM_BODY), { status, headers: { "PAYMENT-RESPONSE": header, "content-type": "application/json" } });
  }) as typeof globalThis.fetch;
  return { fetch, seen, paid: () => seen.filter((r) => r.headers.get("PAYMENT-SIGNATURE")).length };
}

function fakeSigner() {
  const signed: PaymentRequired[] = [];
  return {
    signed,
    async createPaymentPayload(pr: PaymentRequired): Promise<PaymentPayload> {
      signed.push(pr);
      return { x402Version: 2, accepted: pr.accepts[0], payload: { signature: "0xsig" } };
    },
  };
}

function setup(o: { fetch: typeof globalThis.fetch; cap?: number; allowedPayees?: string[]; gate?: string; cacheDir?: string | null }) {
  const payments: PaymentRecord[] = [];
  const railEvents: AgentEventRecord[] = [];
  const logs: { agent: string; kind: string; message: string; data?: unknown }[] = [];
  const signer = fakeSigner();
  const rail = new X402Rail({
    sink: { recordPayment: async (p) => void payments.push(p), logAgentEvent: async (e) => void railEvents.push(e) },
    ledger: new SpendLedger(usdToMicros(o.cap ?? 1), usdToMicros(0.1)),
    signer,
    fetch: o.fetch,
    allowedPayees: o.allowedPayees,
  });
  const checker = createRecallChecker({
    rail,
    log: (e) => void logs.push(e),
    env: { RECALL_CHECK_X402: o.gate ?? "1" },
    cacheDir: o.cacheDir === undefined ? null : o.cacheDir,
  });
  return { checker, payments, railEvents, logs, signer, rail };
}

const item = (o: Partial<Item> = {}): Item =>
  ({ id: 42n, owner: "user-1", brand: "IKEA", name: "Malm dresser", category: "storage", ...o }) as unknown as Item;

test("recalls: parses the Bazaar example shape and rejects a body with no CPSC list", () => {
  const { recalls, retrievedAt } = parseRecallResponse(MALM_BODY);
  assert.equal(recalls.length, 2);
  assert.deepEqual(recalls[0], {
    title: "IKEA Recalls MALM and Other Models of Chests and Dressers Due to Serious Tip-Over Hazard",
    recallNumber: "16221",
    date: "2016-06-28",
    description: "This recall involves IKEA MALM 3- and 6-drawer chests and dressers...",
    products: "IKEA MALM chests and dressers",
    hazard: "The chests and dressers can tip over.",
    url: "https://www.cpsc.gov/Recalls/2016/IKEA-Recalls-MALM",
  });
  assert.equal(retrievedAt, "2026-10-24T10:32:46.327Z");
  assert.equal(parseRecallResponse({ data: { cpsc: [] } }).recalls.length, 0);
  // A top-level list and junk entries are tolerated.
  assert.equal(parseRecallResponse({ cpsc: [null, 3, { title: "X Recalls Y", recall_number: 1 }] }).recalls[0].recallNumber, "1");
  assert.throws(() => parseRecallResponse({ data: { fda: [] } }), /no CPSC list/);
  assert.throws(() => parseRecallResponse("nope"), /no CPSC list/);
});

test("recalls: a probable match needs the brand and a word of the name (plurals ignored)", () => {
  const { recalls } = parseRecallResponse(MALM_BODY);
  assert.deepEqual(probableMatches(recalls, { brand: "IKEA", name: "Malm dresser" }).map((r) => r.recallNumber), ["16221"]);
  assert.equal(probableMatches(recalls, { brand: "IKEA", name: "Poang chair" }).length, 0);
  assert.equal(probableMatches(recalls, { brand: "Graco", name: "stroller" }).length, 0);
  assert.equal(probableMatches(recalls, { brand: "", name: "stroller" }).length, 0, "no brand, no match");
});

test("recalls: only branded, non-generic items are checked; the gate is off by default", () => {
  assert.equal(recallQuery(item()), "IKEA", "the brand is searched; the name is matched locally");
  assert.equal(recallQuery(item({ brand: "" })), null);
  assert.equal(recallQuery(item({ brand: "", name: "other" })), null);
  assert.equal(recallQuery(item({ brand: "x".repeat(200) }))!.length, 80);
  assert.equal(recallCheckEnabled({}), false);
  assert.equal(recallCheckEnabled({ RECALL_CHECK_X402: "0" }), false);
  assert.equal(recallCheckEnabled({ RECALL_CHECK_X402: "1" }), true);
});

test("recalls: picks Base Sepolia USDC from the service's mixed accepts, never mainnet or XRPL", async () => {
  const pick = pickRequirements(mixedPaymentRequired())!;
  assert.equal(pick.network, BASE_SEPOLIA);
  assert.equal(pick.asset, USDC_BASE_SEPOLIA);
  assert.equal(pick.payTo, RECALLS_PAYEE);
  assert.equal(pick.amount, "2000");
  assert.deepEqual(pick.extra, { invoiceId: INVOICE, name: "USDC", version: "2" });

  // Through the rail: the signer only ever sees the Base Sepolia option.
  const svc = fakeService();
  const s = setup({ fetch: svc.fetch });
  const out = await s.checker.check(item());
  assert.equal(out.status, "checked");
  assert.equal(s.signer.signed.length, 1);
  assert.deepEqual(s.signer.signed[0].accepts.map((a) => a.network), [BASE_SEPOLIA]);
  assert.equal(s.payments[0].payee, RECALLS_PAYEE);
  assert.equal(s.payments[0].amountUsdMicros, 2000n);
  assert.equal(s.payments[0].agent, "safety");
  assert.equal(s.payments[0].status, "settled");
  assert.equal(s.payments[0].txHash, TX);
  assert.equal(new URL(svc.seen[0].url).searchParams.get("q"), "IKEA");
  assert.equal(new URL(svc.seen[0].url).searchParams.get("source"), "cpsc");
  if (out.status === "checked") {
    assert.equal(out.txHash, TX);
    assert.equal(out.matches.length, 1);
  }
  const result = s.logs.find((l) => l.kind === "result")!;
  assert.match(result.message, /^Possible CPSC recall for "IKEA Malm dresser": IKEA Recalls MALM .* \(#16221\)$/);
  assert.equal((result.data as { txHash: string }).txHash, TX);
});

test("recalls: gate off means no fetch and no payment", async () => {
  const svc = fakeService();
  const s = setup({ fetch: svc.fetch, gate: "" });
  assert.deepEqual(await s.checker.check(item()), { status: "skipped", reason: "RECALL_CHECK_X402 is off" });
  assert.equal(s.checker.cached(item()), undefined);
  assert.equal(svc.seen.length, 0);
  assert.equal(s.payments.length + s.railEvents.length + s.logs.length, 0);
});

test("recalls: an unbranded item is skipped without a fetch", async () => {
  const svc = fakeService();
  const s = setup({ fetch: svc.fetch });
  assert.equal((await s.checker.check(item({ brand: "" }))).status, "skipped");
  assert.equal(svc.seen.length, 0);
});

test("recalls: a payee not on X402_ALLOWED_PAYEES is refused, then falls back cleanly", async () => {
  const svc = fakeService();
  const s = setup({ fetch: svc.fetch, allowedPayees: ["0x1111111111111111111111111111111111111111"] });
  const out = await s.checker.check(item());
  assert.deepEqual(out, { status: "unavailable", reason: `payee ${RECALLS_PAYEE} is not allowed`, refused: true });
  assert.equal(svc.paid(), 0, "nothing signed or paid");
  assert.equal(s.signer.signed.length, 0);
  assert.equal(s.payments.length, 0);
  assert.ok(s.railEvents.some((e) => JSON.parse(e.dataJson).outcome === "refused"));
  const fb = s.logs.find((l) => l.kind === "tool_call")!;
  assert.match(fb.message, /^Recall check for "IKEA" refused .* listing goes ahead without it$/);
  // Allowlisting the service's payee (any case) lets it through.
  const ok = setup({ fetch: fakeService().fetch, allowedPayees: [RECALLS_PAYEE.toLowerCase()] });
  assert.equal((await ok.checker.check(item())).status, "checked");
});

test("recalls: over the safety budget is refused before signing and falls back", async () => {
  const svc = fakeService();
  const s = setup({ fetch: svc.fetch, cap: 0.001 }); // $0.001 < $0.002
  const out = await s.checker.check(item());
  assert.equal(out.status, "unavailable");
  assert.equal(out.status === "unavailable" && out.refused, true);
  assert.equal(s.signer.signed.length, 0);
  assert.equal(s.payments.length, 0);
});

test("recalls: a non-2xx answer or bad JSON logs one fallback and never throws", async () => {
  const bad = setup({ fetch: fakeService({ status: 500 }).fetch });
  const o1 = await bad.checker.check(item());
  assert.equal(o1.status, "unavailable");
  assert.equal(bad.logs.filter((l) => l.kind === "tool_call").length, 1);
  assert.equal(bad.rail.remaining("safety"), usdToMicros(1), "failed payment refunded");

  const junk = setup({ fetch: fakeService({ raw: "<html>oops" }).fetch });
  const o2 = await junk.checker.check(item());
  assert.deepEqual(o2, { status: "unavailable", reason: "recall service returned bad JSON", refused: false });

  const shape = setup({ fetch: fakeService({ body: { hello: 1 } }).fetch });
  assert.equal((await shape.checker.check(item())).status, "unavailable");

  const offline = setup({ fetch: (async () => { throw new Error("The operation was aborted due to timeout"); }) as typeof fetch });
  const o3 = await offline.checker.check(item());
  assert.equal(o3.status, "unavailable");
  assert.match(offline.logs[0].message, /timeout/);
});

test("recalls: one paid call per query (sequential, concurrent, and across a restart via the disk cache)", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "recalls-"));
  const svc = fakeService();
  const s = setup({ fetch: svc.fetch, cacheDir: dir });
  const [a, b] = await Promise.all([s.checker.check(item()), s.checker.check(item({ id: 43n }))]);
  const c = await s.checker.check(item({ id: 44n }));
  assert.equal(svc.paid(), 1);
  assert.equal(s.payments.length, 1);
  assert.deepEqual([a, b, c].map((o) => o.status === "checked" && o.replayed), [false, true, true]);
  assert.equal(s.logs.filter((l) => l.kind === "result").length, 3, "each item still gets its event");
  assert.ok(s.logs.filter((l) => l.kind === "result").slice(1).every((l) => l.message.startsWith("[REPLAYED] ")));
  assert.equal(s.checker.cached(item())?.[0].recallNumber, "16221");
  assert.equal(s.checker.cached(item({ name: "Poang chair" }))?.length, 0, "same brand report, matched per item");

  // A new worker (fresh checker, same cache dir) reads the report instead of paying again.
  const svc2 = fakeService();
  const s2 = setup({ fetch: svc2.fetch, cacheDir: dir });
  assert.equal(s2.checker.cached(item())?.length, 1);
  assert.equal((await s2.checker.check(item())).status, "checked");
  assert.equal(svc2.seen.length, 0);

  // A failure isn't cached: a later check tries (and pays) again.
  let fail = true;
  const svc3 = fakeService();
  const flaky = (async (i: RequestInfo | URL, init?: RequestInit) => (fail ? new Response("x", { status: 503 }) : svc3.fetch(i, init))) as typeof fetch;
  const s3 = setup({ fetch: flaky });
  assert.equal((await s3.checker.check(item())).status, "unavailable");
  fail = false;
  assert.equal((await s3.checker.check(item())).status, "checked");
  assert.equal(svc3.paid(), 1);
});

test("recalls: on the simulated rail the service's 402 is a labeled, refunded failure", async () => {
  const svc = fakeService();
  const payments: PaymentRecord[] = [];
  const logs: { message: string; data?: unknown }[] = [];
  const rail = new X402Rail({
    sink: { recordPayment: async (p) => void payments.push(p), logAgentEvent: async () => {} },
    ledger: new SpendLedger(usdToMicros(1), usdToMicros(0.1)),
    fetch: svc.fetch,
  });
  const checker = createRecallChecker({ rail, log: (e) => void logs.push(e), env: { RECALL_CHECK_X402: "1" }, cacheDir: null });
  const out = await checker.check(item());
  assert.equal(out.status, "unavailable");
  assert.equal(payments[0].simulated, true);
  assert.equal(payments[0].amountUsdMicros, 2000n);
  assert.equal(payments[0].status, "failed");
  assert.equal(rail.remaining("safety"), usdToMicros(1));
  assert.match(logs[0].message, /^\[SIMULATED\] Recall check for "IKEA" unavailable \(recall service answered HTTP 402\)/);
});

test("recalls: real records (paid run for 'Peloton', 2026-10-24) match a Peloton bike, not a treadmill", () => {
  // Trimmed from the real response: same fields and values, descriptions and remedies dropped.
  const body = {
    data: {
      query: "Peloton",
      source: "cpsc",
      cpsc: [
        { source: "CPSC", recall_number: "26067", date: "2025-11-06", title: "Peloton Recalls Original Series Bike+ Exercise Bikes Due to Fall and Injury Hazards", products: [{ name: "Peloton Original Series Bike+ Model PL02", model: null }], url: "https://www.cpsc.gov/Recalls/2026/Peloton-Recalls-Original-Series-Bike-Exercise-Bikes-Due-to-Fall-and-Injury-Hazards" },
        { source: "CPSC", recall_number: "23201", date: "2023-05-11", title: "Peloton Recalls Two Million Exercise Bikes Due to Fall and Injury Hazards", products: [{ name: "Peloton Bikes Model PL01", model: null }], url: "https://www.cpsc.gov/Recalls/2023/Peloton-Recalls-Two-Million-Exercise-Bikes-Due-to-Fall-and-Injury-Hazards" },
        { source: "CPSC", recall_number: "21702", date: "2020-10-15", title: "Peloton Recalls PR70P Bike Pedals Due to Laceration Hazard (Recall Alert)", products: [{ name: "PR70P Clip-In Pedals fitted on Peloton bikes (sold between July 2013 and May 2016)", model: null }] },
      ],
      fda: [],
      partial_errors: [],
      retrieved_at: "2026-10-24T21:31:37.178Z",
    },
    receipt: {},
  };
  const { recalls } = parseRecallResponse(body);
  assert.equal(recalls.length, 3);
  assert.equal(recalls[0].products, "Peloton Original Series Bike+ Model PL02");
  assert.deepEqual(probableMatches(recalls, { brand: "Peloton", name: "exercise bike" }).map((r) => r.recallNumber), ["26067", "23201", "21702"]);
  assert.deepEqual(probableMatches(recalls, { brand: "Peloton", name: "PR70P pedals" }).map((r) => r.recallNumber), ["21702"]);
  assert.equal(probableMatches(recalls, { brand: "Peloton", name: "Tread treadmill" }).length, 0);
});
