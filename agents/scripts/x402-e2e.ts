// End-to-end check of the x402 -> SpacetimeDB path (#7): connects as the worker, makes one paid comps
// call through the shared payment rail, and prints the `payment` + `agent_event` rows that landed in the
// database (what the iOS spending log subscribes to). Then checks that a non-worker identity can't call
// `record_payment`.
//
// Needs a running SpacetimeDB with the module published (see root CLAUDE.md). Real Base Sepolia payment
// when CDP keys are in .env.local; X402_SIMULATE=1 for a simulated one.
// Usage: npm run x402:e2e [-- "<item description>"]
import "./env.js";
import { DbConnection } from "../src/module_bindings/index.js";
import { config } from "../src/config.js";
import { connect } from "../src/spacetime.js";
import { paymentRail } from "../src/payments.js";
import { EXPLORER_TX_URL } from "../src/integrations/x402.js";
import { COMPS_ROUTE, createCompsPaywall } from "../src/paywall.js";

const query = process.argv[2] ?? "IKEA Poang armchair";
const short = (hex: string) => `${hex.slice(0, 8)}..${hex.slice(-4)}`;
const show = (row: object) =>
  JSON.stringify(row, (_k, v) => {
    if (typeof v === "bigint") return v.toString();
    if (v && typeof v === "object" && typeof v.toHexString === "function") return short(v.toHexString());
    if (v && typeof v === "object" && typeof v.toDate === "function") return v.toDate().toISOString();
    return v;
  });

async function waitFor(what: string, done: () => boolean, timeoutMs = 15_000): Promise<void> {
  const start = Date.now();
  while (!done()) {
    if (Date.now() - start > timeoutMs) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 100));
  }
}

const { conn, identity } = await connect();
const maxId = (rows: Iterable<{ id: bigint }>) => [...rows].reduce((m, r) => (r.id > m ? r.id : m), 0n);
const paymentsBefore = maxId(conn.db.payment.iter());
const eventsBefore = maxId(conn.db.agentEvent.iter());

const paywall = await createCompsPaywall(async (q) => ({
  comps: [
    { source: "fixture", title: `${q}, good condition`, priceCents: 6000, url: "https://example.com/fixture/1" },
    { source: "fixture", title: `${q}, used`, priceCents: 4500, url: "https://example.com/fixture/2" },
  ],
  replayed: true,
}));
const server = paywall.app.listen(0);
const port = (server.address() as { port: number }).port;
console.log(`comps endpoint on :${port} (${paywall.paywalled ? `x402 paywall, paying to ${paywall.payTo}` : "unpaywalled, simulated"})`);

let failed = false;
try {
  const rail = await paymentRail(conn);
  // The worker's own identity stands in for a user here.
  const { response, payment } = await rail.paidFetch(
    { owner: identity, agent: "pricing", purpose: `comps for '${query}'`, refTable: "item", refId: 0n, quotedUsdMicros: 10_000n },
    `http://127.0.0.1:${port}${COMPS_ROUTE}?q=${encodeURIComponent(query)}`,
  );
  console.log(`HTTP ${response.status}`);

  const newPayments = () => [...conn.db.payment.iter()].filter((p) => p.id > paymentsBefore);
  const newEvents = () => [...conn.db.agentEvent.iter()].filter((e) => e.id > eventsBefore);
  // One payment row, plus the tool_call and payment/error events.
  await waitFor("payment + agent_event rows", () => newPayments().length >= 1 && newEvents().length >= 2);

  console.log("\npayment rows (client cache):");
  for (const p of newPayments()) console.log(" ", show(p));
  console.log("agent_event rows (client cache):");
  for (const e of newEvents()) console.log(" ", show(e));
  if (payment?.txHash) console.log(`\non-chain: ${EXPLORER_TX_URL}${payment.txHash}`);

  const row = newPayments()[0];
  if (row.status !== "settled" || row.simulated !== rail.simulated || (!rail.simulated && !row.txHash)) {
    console.error(`FAIL: unexpected payment row (status=${row.status}, simulated=${row.simulated}, txHash=${row.txHash || "none"})`);
    failed = true;
  }

  // Authorization: a fresh anonymous identity must not be able to write payment rows.
  const outsider = await new Promise<DbConnection>((resolve, reject) => {
    DbConnection.builder()
      .withUri(config.spacetimeUri)
      .withDatabaseName(config.spacetimeDb)
      .onConnect((c) => resolve(c))
      .onConnectError((_ctx, err) => reject(err))
      .build();
  });
  try {
    await outsider.reducers.recordPayment({
      owner: identity, agent: "pricing", rail: "x402", purpose: "forged", payee: "0xforged",
      amountUsdMicros: 1n, txHash: "0xforged", status: "settled", simulated: false, refTable: "", refId: 0n,
    });
    console.error(`FAIL: non-worker ${short(outsider.identity!.toHexString())} was allowed to call record_payment`);
    failed = true;
  } catch (err) {
    console.log(`\nauth check: non-worker ${short(outsider.identity!.toHexString())} record_payment rejected: ${(err as Error).message ?? err}`);
  } finally {
    outsider.disconnect();
  }
} catch (err) {
  console.error("FAIL:", err);
  failed = true;
} finally {
  server.close();
  conn.disconnect();
}
console.log(failed ? "\nx402 e2e: FAIL" : "\nx402 e2e: PASS");
// The CDP clients keep sockets open, so exit explicitly.
process.exit(failed ? 1 : 0);
