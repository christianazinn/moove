// One paid comps call end to end: starts the paywalled comps endpoint locally, pays it from the agent
// wallet over x402, and prints the payment row + explorer link. Simulated without CDP keys.
// Usage: npm run x402:demo [-- "<item description>"]
import "./env.js";
import { createX402Rail, EXPLORER_TX_URL, formatUsd, type PaymentSink } from "../src/integrations/x402.js";
import { COMPS_ROUTE, createCompsPaywall } from "../src/paywall.js";

const query = process.argv[2] ?? "IKEA Poang armchair";

// Fixture lookup until #6's Apify client lands.
const paywall = await createCompsPaywall(async (q) => ({
  comps: [
    { source: "fixture", title: `${q}, good condition`, priceCents: 6000, url: "https://example.com/fixture/1" },
    { source: "fixture", title: `${q}, used`, priceCents: 4500, url: "https://example.com/fixture/2" },
  ],
  replayed: true,
}));
const server = paywall.app.listen(0);
const port = (server.address() as { port: number }).port;
console.log(`Comps endpoint on :${port} (${paywall.paywalled ? `x402 paywall, paying to ${paywall.payTo}` : "UNPAYWALLED, simulated mode"})`);

// Console sink until the worker's SpacetimeDB client lands.
const sink: PaymentSink = {
  recordPayment: async (p) => console.log("payment row:", { ...p, amount: formatUsd(p.amountUsdMicros) }),
  logAgentEvent: async (e) => console.log(`agent_event [${e.kind}] ${e.message}`),
};

try {
  const rail = await createX402Rail(sink);
  const { response, payment } = await rail.paidFetch(
    { owner: "demo", agent: "pricing", purpose: `comps for '${query}'`, quotedUsdMicros: 10_000n },
    `http://127.0.0.1:${port}${COMPS_ROUTE}?q=${encodeURIComponent(query)}`,
  );
  console.log(`HTTP ${response.status}`, await response.json());
  if (payment?.txHash) console.log(`On-chain: ${EXPLORER_TX_URL}${payment.txHash}`);
  console.log(`pricing budget left: ${formatUsd(rail.remaining("pricing"))}`);
} finally {
  server.close();
}
