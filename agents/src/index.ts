import { connect } from './spacetime.js';
import { startUploadServer } from './upload.js';
import { visionAgent } from './agents/vision.js';
import { listingAgent } from './agents/listing.js';
import type { Agent } from './agents/types.js';

// Register agents here as they land (vision, pricing, sort, listing, buy, fraud, ...).
const agents: Agent[] = [visionAgent, listingAgent];

startUploadServer();

const { conn } = await connect();
console.log(`[agents] cache ready: ${conn.db.item.count()} items`);
for (const a of agents) {
  await a.start(conn);
  console.log(`[agents] started ${a.name}`);
}
