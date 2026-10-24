import { test } from "node:test";
import assert from "node:assert/strict";
import { toBindingMessage } from "../src/integrations/auth0.js";
import { bindingFor } from "../src/agents/approval.js";
import type { Conn } from "../src/spacetime.js";
import type { Approval } from "../src/module_bindings/types.js";

const VALID = /^[A-Za-z0-9 +\-_.,:#]{1,64}$/;

test("binding message puts the amount first and fits Auth0's rules", () => {
  const m = toBindingMessage("sell", "Herman Miller Aeron chair", 42_000n);
  assert.equal(m, "Moove: sell 420.00 USD: Herman Miller Aeron chair");
  assert.match(m, VALID);
});

test("long or hostile titles are cleaned and cut, never the amount", () => {
  const m = toBindingMessage("buy", `8" Memory Foam Mattress — Queen, $$ "best" deal!!! ${"x".repeat(80)}`, 17_999n);
  assert.match(m, VALID);
  assert.ok(m.startsWith("Moove: buy 179.99 USD: 8 Memory Foam Mattress"));
});

test("an empty title still gives a valid message", () => {
  assert.equal(toBindingMessage("buy", "$$$", 500n), "Moove: buy 5.00 USD");
});

function conn(rows: { listing?: Record<string, string>; deal?: Record<string, string> }): Conn {
  const table = (byId: Record<string, string> = {}) => ({ id: { find: (id: bigint) => (byId[String(id)] ? { title: byId[String(id)] } : undefined) } });
  return { db: { listing: table(rows.listing), deal: table(rows.deal) } } as unknown as Conn;
}
const approval = (kind: string, refId: bigint, amountCents: bigint, summary: string) => ({ kind, refId, amountCents, summary }) as unknown as Approval;

test("purchase approvals use the deal's title", () => {
  const a = approval("purchase", 9n, 17_999n, "Pay $179.99 to target for: 8 memory foam mattress");
  assert.equal(bindingFor(conn({ deal: { "9": "Queen memory foam mattress, 8in" } }), a), "Moove: buy 179.99 USD: Queen memory foam mattress, 8in");
});

test("purchase approvals fall back to the summary text after 'for:'", () => {
  const a = approval("purchase", 9n, 17_999n, "Pay $179.99 to target for: 8 memory foam mattress");
  assert.equal(bindingFor(conn({}), a), "Moove: buy 179.99 USD: 8 memory foam mattress");
});

test("listing approvals use the listing's title, then a quoted title in the summary", () => {
  const a = approval("listing", 3n, 42_000n, 'Sell "Aeron chair" for $420.00');
  assert.equal(bindingFor(conn({ listing: { "3": "Herman Miller Aeron" } }), a), "Moove: sell 420.00 USD: Herman Miller Aeron");
  assert.equal(bindingFor(conn({}), a), "Moove: sell 420.00 USD: Aeron chair");
});
