import { test } from "node:test";
import assert from "node:assert/strict";
import { auth0CibaGateway } from "../src/integrations/auth0.js";

const jwt = (payload: object) => `h.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.s`;

// Stubs fetch: bc-authorize hands out req-1, the token endpoint answers with `tokenBody`.
async function approvalWith(tokenBody: object): Promise<unknown> {
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string) =>
    String(url).endsWith("/bc-authorize")
      ? new Response(JSON.stringify({ auth_req_id: "req-1", expires_in: 300, interval: 5 }))
      : new Response(JSON.stringify(tokenBody))) as typeof fetch;
  try {
    const g = auth0CibaGateway({ domain: "tenant.us.auth0.com", clientId: "id", clientSecret: "secret", audience: "" });
    await g.start({ auth0Sub: "auth0|alice", bindingMessage: "Moove: buy 1.00 USD: lamp" });
    return await g.poll("req-1");
  } finally {
    globalThis.fetch = realFetch;
  }
}

test("approves when the id_token is for the requested user", async () => {
  assert.deepEqual(await approvalWith({ access_token: "a", id_token: jwt({ sub: "auth0|alice" }) }), { status: "approved" });
});

test("rejects an approval for a different user", async () => {
  await assert.rejects(approvalWith({ access_token: "a", id_token: jwt({ sub: "auth0|mallory" }) }), /different user/);
});

test("fails closed when a success response has no id_token", async () => {
  await assert.rejects(approvalWith({ access_token: "a" }), /without a readable id_token/);
});

test("fails closed when the id_token can't be decoded", async () => {
  await assert.rejects(approvalWith({ access_token: "a", id_token: "not-a-jwt" }), /without a readable id_token/);
});
