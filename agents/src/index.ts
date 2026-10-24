// Safety net: a stray rejected promise (e.g. a reducer call nobody awaited) must not kill the worker.
process.on('unhandledRejection', (err) => console.error('[agents] UNHANDLED REJECTION (worker kept alive):', err));
import { connect } from './spacetime.js';
import { startUploadServer } from './upload.js';
import { visionAgent } from './agents/vision.js';
import { pricingAgent, setCompsSource } from './agents/pricing.js';
import { installPaidComps, paidCompsSource, pricingPaysX402, startCompsPaywall } from './integrations/paid-comps.js';
import { listingAgent } from './agents/listing.js';
import { approvalAgent } from './agents/approval.js';
import type { Agent } from './agents/types.js';

// Register agents here as they land (vision, pricing, sort, listing, buy, fraud, ...).
const agents: Agent[] = [visionAgent, pricingAgent, listingAgent, approvalAgent];

startUploadServer();

const { conn } = await connect();
console.log(`[agents] cache ready: ${conn.db.item.count()} items`);
// #7: pricing buys its comps over x402 (PRICING_PAY_X402=0 keeps direct Apify lookups).
if (pricingPaysX402()) await installPaidComps({ start: () => startCompsPaywall(), install: url => setCompsSource(paidCompsSource(conn, url)) });
for (const a of agents) {
  await a.start(conn);
  console.log(`[agents] started ${a.name}`);
}
