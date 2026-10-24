import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import type { AgentEvent, Approval, User } from "../src/module_bindings/types.js";

// The approval agent's CIBA loop (#12, #42) against a fake connection and a stubbed Auth0 (fetch is
// replaced, nothing leaves the process). Own file so the env is set before the agent reads it.
process.env.AUTH0_DOMAIN = "tenant.us.auth0.com";
process.env.AUTH0_CIBA_CLIENT_ID = "id";
process.env.AUTH0_CIBA_CLIENT_SECRET = "secret";
process.env.AUTH0_AUDIENCE = "";
const { approvalAgent, priorPush } = await import("../src/agents/approval.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const jwt = (payload: object) => `h.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.s`;
const owner = { toHexString: () => "owner", isEqual: () => true };

// Auth0 stub: bc-authorize hands out a request with `expiresIn` / `interval` (seconds), the token
// endpoint answers from `answer()`.
function stubAuth0(o: { expiresIn: number; interval: number; answer: () => object }) {
  const calls = { authorize: 0, token: 0 };
  globalThis.fetch = (async (url: string) => {
    if (String(url).endsWith("/bc-authorize")) {
      calls.authorize++;
      return new Response(JSON.stringify({ auth_req_id: `req-${calls.authorize}`, expires_in: o.expiresIn, interval: o.interval }));
    }
    calls.token++;
    const body = o.answer();
    return new Response(JSON.stringify(body), { status: "error" in body ? 400 : 200 });
  }) as typeof fetch;
  return calls;
}

function fakeConn(rows: { approvals: Approval[]; events?: AgentEvent[] }) {
  const approvals = new Map(rows.approvals.map(a => [a.id, a]));
  const events: AgentEvent[] = rows.events ?? [];
  const decisions: { approvalId: bigint; status: string; cibaSubject: string }[] = [];
  const user = { identity: owner, auth0Sub: "auth0|alice", approvalThresholdCents: 10000n } as unknown as User;
  const noop = () => undefined;
  const conn = {
    db: {
      approval: { iter: () => approvals.values(), id: { find: (id: bigint) => approvals.get(id) }, onInsert: noop, onUpdate: noop },
      workerUser: { iter: () => [user].filter(Boolean).values(), onInsert: noop },
      listing: { id: { find: () => ({ title: "Oak desk" }) } },
      deal: { id: { find: () => undefined } },
      agentEvent: { iter: () => events.values() },
    },
    reducers: {
      recordCibaDecision: async (d: { approvalId: bigint; status: string; cibaSubject: string }) => {
        decisions.push(d);
        approvals.set(d.approvalId, { ...approvals.get(d.approvalId)!, status: d.status });
      },
      logAgentEvent: async (e: Omit<AgentEvent, "id" | "createdAt">) =>
        void events.push({ ...e, id: BigInt(events.length + 1), createdAt: { toMillis: () => BigInt(Date.now()) } } as unknown as AgentEvent),
    },
  };
  return { conn: conn as unknown as Conn, events, decisions };
}

const pending = (id: bigint) => ({ id, owner, kind: "listing", refId: 1n, amountCents: 20000n, summary: 'Sell "Oak desk"', status: "pending" }) as unknown as Approval;
const pushEvent = (approvalId: bigint, sentMsAgo: number, expiresInSec: number) =>
  ({ id: 1n, owner, agent: "approval", kind: "tool_call", message: "Sent approval request", refTable: "approval", refId: approvalId, dataJson: JSON.stringify({ gateway: "Auth0 Guardian", expiresInSec }), createdAt: { toMillis: () => BigInt(Date.now() - sentMsAgo) } }) as unknown as AgentEvent;

test("approval agent: an approval tapped just before expiry is still recorded", async () => {
  const realFetch = globalThis.fetch;
  // The push expires before the first poll is due: the phone answer must still be read once.
  const calls = stubAuth0({ expiresIn: 0.05, interval: 0.1, answer: () => ({ access_token: "a", id_token: jwt({ sub: "auth0|alice" }) }) });
  try {
    const f = fakeConn({ approvals: [pending(1n)] });
    approvalAgent.start(f.conn);
    await sleep(300);
    assert.equal(calls.token, 1);
    assert.deepEqual(f.decisions, [{ approvalId: 1n, status: "approved", cibaSubject: "auth0|alice" }]);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("approval agent: a push still unanswered at expiry stops polling and leaves the row pending", async () => {
  const realFetch = globalThis.fetch;
  const calls = stubAuth0({ expiresIn: 0.15, interval: 0.05, answer: () => ({ error: "authorization_pending" }) });
  try {
    const f = fakeConn({ approvals: [pending(2n)] });
    approvalAgent.start(f.conn);
    await sleep(500);
    const polls = calls.token;
    await sleep(200);
    assert.equal(calls.token, polls, "stopped polling");
    assert.equal(calls.authorize, 1, "never re-pushed");
    assert.equal(f.decisions.length, 0);
    assert.ok(f.events.some(e => /expired without an answer/.test(e.message)));
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("approval agent: after a restart, an approval whose phone push already expired isn't pushed again", async () => {
  const realFetch = globalThis.fetch;
  const calls = stubAuth0({ expiresIn: 300, interval: 5, answer: () => ({ error: "authorization_pending" }) });
  try {
    const f = fakeConn({ approvals: [pending(3n), pending(4n)], events: [pushEvent(3n, 400_000, 300)] });
    approvalAgent.start(f.conn);
    await sleep(50);
    assert.equal(calls.authorize, 1, "only the never-pushed approval 4 gets a push");
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("priorPush: finds this approval's latest push and whether it is still live", () => {
  const now = Date.now();
  assert.equal(priorPush([], 3n, now), "none");
  assert.equal(priorPush([pushEvent(3n, 400_000, 300)], 3n, now), "expired");
  assert.equal(priorPush([pushEvent(3n, 10_000, 300)], 3n, now), "live");
  assert.equal(priorPush([pushEvent(3n, 400_000, 300), pushEvent(3n, 10_000, 300)], 3n, now), "live");
  assert.equal(priorPush([pushEvent(9n, 10_000, 300)], 3n, now), "none", "other approvals don't count");
});
