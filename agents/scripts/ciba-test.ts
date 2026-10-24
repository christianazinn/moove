// One real Auth0 CIBA round trip, without SpacetimeDB: send a Guardian push to an Auth0 user, poll
// until they approve or deny (or it expires), and print the result. Uses the same gateway as the
// approval agent, so it needs AUTH0_DOMAIN + AUTH0_CIBA_CLIENT_ID + AUTH0_CIBA_CLIENT_SECRET.
// Usage: npm run auth0:ciba-test -- <auth0 user id> [amount in dollars]
//   e.g. npm run auth0:ciba-test -- 'auth0|abc123' 420
import "./env.js";
import { auth0Config, auth0CibaGateway, toBindingMessage } from "../src/integrations/auth0.js";

const sub = process.argv[2];
if (!sub) {
  console.error("usage: npm run auth0:ciba-test -- <auth0 user id> [amount in dollars]");
  process.exit(2);
}
const cfg = auth0Config();
if (!cfg) {
  console.error("Auth0 CIBA is not configured: set AUTH0_DOMAIN, AUTH0_CIBA_CLIENT_ID and AUTH0_CIBA_CLIENT_SECRET");
  process.exit(2);
}

const amountCents = BigInt(Math.round(Number(process.argv[3] ?? "420") * 100));
const gateway = auth0CibaGateway(cfg);
const bindingMessage = toBindingMessage("sell", "Herman Miller chair", amountCents);
console.log(`tenant ${cfg.domain}, user ${sub}`);
console.log(`push: "${bindingMessage}"`);

const start = await gateway.start({ auth0Sub: sub, bindingMessage });
console.log(`bc-authorize ok, expires in ${Math.round((start.expiresAt - Date.now()) / 1000)}s; approve or deny on the phone`);

let interval = start.intervalSec;
for (;;) {
  await new Promise((r) => setTimeout(r, interval * 1000));
  const p = await gateway.poll(start.authReqId);
  if (p.status === "pending") continue;
  if (p.status === "slow_down") {
    interval = Math.max(interval + 5, p.intervalSec);
    continue;
  }
  // access_denied also covers expiry; tell them apart by our own clock, like the approval agent.
  const status = p.status === "denied" && Date.now() >= start.expiresAt ? "expired" : p.status;
  console.log(`result: ${status}`);
  process.exit(status === "approved" ? 0 : 1);
}
