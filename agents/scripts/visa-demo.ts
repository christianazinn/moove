// One Visa checkout end to end, without SpacetimeDB: authorize a hold, re-check, capture, and print
// the payment row + every agent_event. Uses the CyberSource sandbox when VISA_ACCEPTANCE_* keys are
// set (test card, no real money), otherwise the labeled simulated backend.
// Usage: npm run visa:demo [-- <amount in dollars>]   e.g. npm run visa:demo -- 89.99
import "./env.js";
import { createVisaCheckout, dollars, type VisaSink } from "../src/integrations/visa.js";

const amountCents = BigInt(Math.round(Number(process.argv[2] ?? "42.50") * 100));
let nextId = 1n;
const sink: VisaSink = {
  recordPayment: async (p) => {
    console.log("payment row:", { ...p, amount: dollars(p.amountUsdMicros / 10_000n) });
    return nextId++;
  },
  updatePayment: async (id, status) => console.log(`payment #${id} -> ${status}`),
  logAgentEvent: async (e) => console.log(`agent_event [${e.kind}] ${e.message}`),
};

const visa = createVisaCheckout(sink);
console.log(`Visa checkout: ${visa.simulated ? "SIMULATED" : visa.provider}`);
const r = await visa.purchase({
  owner: "demo-user",
  agent: "buy",
  purpose: "Demo: MICKE desk",
  merchant: "ikea",
  refTable: "deal",
  refId: 0n,
  amountCents,
  thresholdCents: 100_00n,
  // Pretend the user approved exactly this amount, so amounts over $100 work too.
  currentApproval: () => ({ id: 1n, status: "approved", amountCents }),
  consumerPrompt: `Buy a desk for no more than ${dollars(amountCents)} from IKEA`,
});
console.log("result:", r);
process.exit(r.status === "captured" ? 0 : 1);
