// One paid CPSC recall check against the third-party x402 service (api.stablecoingateways.com),
// through the same rail and budget checks the worker uses. Prints the tx hash, the basescan link and
// what came back. Writes nothing to SpacetimeDB (console sink), and never caches, so each run pays.
// Simulated without CDP keys (the service then answers 402 and nothing is paid).
// The service is searched for the brand; the name is matched against the recalls locally.
// Usage: npm run x402:recall -- "IKEA Malm dresser"   (first word is taken as the brand)
//        npm run x402:recall -- --brand "Herman Miller" "Aeron chair"
import "./env.js";
import type { Item } from "../src/module_bindings/types.js";
import { createRecallChecker, describeMatch, recallQuery, recallUrl, RECALLS_URL } from "../src/integrations/recalls.js";
import { createX402Rail, EXPLORER_TX_URL, formatUsd, type PaymentSink } from "../src/integrations/x402.js";

const args = process.argv.slice(2);
const b = args.indexOf("--brand");
let brand = b >= 0 ? (args.splice(b, 2)[1] ?? "") : "";
let name = args.join(" ").trim() || "IKEA Malm dresser";
if (!brand) [brand, name] = [name.split(/\s+/)[0], name.split(/\s+/).slice(1).join(" ")];

const sink: PaymentSink = {
  recordPayment: async (p) => console.log("payment row (not written):", { ...p, amount: formatUsd(p.amountUsdMicros) }),
  logAgentEvent: async (e) => console.log(`agent_event [${e.agent}/${e.kind}] ${e.message}`),
};

// RECALL_SHOW_BODY=1 prints the paid response body as it came back (first 4000 chars).
if (process.env.RECALL_SHOW_BODY === "1") {
  const real = globalThis.fetch;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const res = await real(input, init);
    const url = input instanceof Request ? input.url : String(input);
    if (url.startsWith(RECALLS_URL) && res.status !== 402) console.log(`raw body (HTTP ${res.status}):`, (await res.clone().text()).slice(0, 4000));
    return res;
  }) as typeof fetch;
}
const rail = await createX402Rail(sink);
console.log(`Rail: ${rail.simulated ? "SIMULATED (no CDP keys or X402_SIMULATE=1)" : "Base Sepolia (CDP wallet moove-agents)"}`);
const item = { id: 0n, owner: "x402-recall-script", brand, name, category: name } as unknown as Item;
const checker = createRecallChecker({
  rail,
  cacheDir: null,
  env: { RECALL_CHECK_X402: "1", RECALL_CHECK_TIMEOUT_MS: process.env.RECALL_CHECK_TIMEOUT_MS },
  log: (e) => console.log(`agent_event [${e.agent}/${e.kind}] ${e.message}`),
});
const q = [brand, name].filter(Boolean).join(" ");
console.log(`GET ${recallUrl(recallQuery(item) ?? q)}`);
const out = await checker.check(item);
if (out.status !== "checked") {
  console.log(`Not checked (${out.status}): ${out.reason}`);
  process.exit(1);
}
const { report, matches, txHash } = out;
console.log(`\n${report.recalls.length} CPSC result(s) for "${report.query}", ${matches.length} probable match(es) for "${q}"${report.retrievedAt ? `, retrieved ${report.retrievedAt}` : ""}`);
for (const r of report.recalls.slice(0, 15)) console.log(`  ${matches.includes(r) ? "MATCH" : "     "} ${r.date} ${describeMatch(r)}`);
console.log(`\ntx: ${txHash ?? "(none)"}`);
if (txHash) console.log(`On-chain: ${EXPLORER_TX_URL}${txHash}`);
console.log(`safety budget left: ${formatUsd(rail.remaining("safety"))}`);
