// Safety net: a stray rejected promise (e.g. a reducer call nobody awaited) must not kill the worker.
process.on('unhandledRejection', (err) => console.error('[agents] UNHANDLED REJECTION (worker kept alive):', err));
import { connect } from './spacetime.js';
import { startUploadServer } from './upload.js';
import { visionAgent } from './agents/vision.js';
import { pricingAgent } from './agents/pricing.js';
import { listingAgent } from './agents/listing.js';
import { approvalAgent } from './agents/approval.js';
import type { Agent } from './agents/types.js';

// Register agents here as they land (vision, pricing, sort, listing, buy, fraud, ...).
const agents: Agent[] = [visionAgent, pricingAgent, listingAgent, approvalAgent];

startUploadServer();

const { conn } = await connect();
console.log(`[agents] cache ready: ${conn.db.item.count()} items`);
for (const a of agents) {
  await a.start(conn);
  console.log(`[agents] started ${a.name}`);
}
