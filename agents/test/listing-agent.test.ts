import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { Conn } from "../src/spacetime.js";
import type { Approval, Item, Listing, User } from "../src/module_bindings/types.js";

// The listing agent's loop (#11, #12) against a fake connection: approval thresholds, idempotency
// across a worker restart, and reducer failures. Own file so the env is set before listing.ts reads
// it: simulated eBay only (no EBAY_* keys, whatever .env.local says), Claude answers replayed.
const tmp = mkdtempSync(path.join(tmpdir(), "listing-agent-"));
for (const k of ["EBAY_CLIENT_ID", "EBAY_CLIENT_SECRET", "EBAY_REFRESH_TOKEN"]) process.env[k] = "";
process.env.UPLOAD_DIR = tmp;
process.env.LLM_REPLAY = "replay";
process.env.LLM_REPLAY_DIR = tmp;
process.env.LISTING_SIM_SOLD_AFTER_SEC = "0";
process.env.APPROVAL_THRESHOLD_CENTS_DEFAULT = "10000";
const { listingAgent, ListingDraft } = await import("../src/agents/listing.js");
const { buildDraftPrompt, LISTING_SYSTEM } = await import("../src/agents/listingPrompt.js");
const { replayKey } = await import("../src/integrations/anthropic.js");
const { config } = await import("../src/config.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => "owner", isEqual: () => true };

type Opts = { threshold?: bigint; failRequestApproval?: boolean; failCreateDraft?: boolean };

function fakeConn(o: Opts = {}) {
  const listings = new Map<bigint, Listing>();
  const approvals = new Map<bigint, Approval>();
  const items = new Map<bigint, Item>();
  const cbs: Record<string, ((...a: unknown[]) => void)[]> = {};
  const on = (k: string) => (cb: (...a: unknown[]) => void) => void (cbs[k] ??= []).push(cb);
  const fire = (k: string, ...a: unknown[]) => (cbs[k] ?? []).forEach(cb => cb({}, ...a));
  const calls: { reducer: string; args: Record<string, unknown> }[] = [];
  const events: { kind: string; message: string; refId: bigint }[] = [];
  let nextApproval = 1n;
  let nextListing = 500n;
  const user = o.threshold === undefined ? undefined : ({ identity: owner, auth0Sub: "", approvalThresholdCents: o.threshold } as unknown as User);
  const conn = {
    db: {
      listing: { iter: () => listings.values(), id: { find: (id: bigint) => listings.get(id) }, onInsert: on("listing.insert"), onUpdate: on("listing.update") },
      approval: { iter: () => approvals.values(), onInsert: on("approval.insert"), onUpdate: on("approval.update") },
      item: { iter: () => items.values(), id: { find: (id: bigint) => items.get(id) }, onInsert: on("item.insert"), onUpdate: on("item.update") },
      comp: { iter: () => [][Symbol.iterator]() },
      user: { identity: { find: () => user } },
    },
    reducers: {
      requestApproval: async (a: { owner: unknown; kind: string; refId: bigint; amountCents: bigint; summary: string }) => {
        calls.push({ reducer: "requestApproval", args: a });
        await sleep(1);
        if (o.failRequestApproval) throw new Error("SenderError: not connected");
        const row = { id: nextApproval++, owner, kind: a.kind, refId: a.refId, amountCents: a.amountCents, summary: a.summary, status: "pending" } as unknown as Approval;
        approvals.set(row.id, row);
        fire("approval.insert", row);
      },
      updateListing: async (a: { listingId: bigint; status: string; externalId: string; url: string; priceCents: bigint }) => {
        calls.push({ reducer: "updateListing", args: a });
        await sleep(1);
        const old = listings.get(a.listingId)!;
        const l = { ...old, status: a.status, externalId: a.externalId || old.externalId, url: a.url || old.url };
        listings.set(l.id, l);
        fire("listing.update", old, l);
      },
      createListingDraft: async (a: { itemId: bigint; title: string; description: string; priceCents: bigint; simulated: boolean }) => {
        calls.push({ reducer: "createListingDraft", args: a });
        await sleep(1);
        if (o.failCreateDraft) throw new Error("SenderError: no item");
        const l = { id: nextListing++, owner, itemId: a.itemId, title: a.title, description: a.description, priceCents: a.priceCents, status: "draft", externalId: "", url: "", simulated: a.simulated } as unknown as Listing;
        listings.set(l.id, l);
        fire("listing.insert", l);
      },
      logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e),
    },
  };
  const listing = (id: bigint, priceCents: bigint, status = "draft") => {
    const l = { id, owner, itemId: id * 10n, title: `Thing ${id}`, description: "desc", priceCents, status, externalId: "", url: "", simulated: true } as unknown as Listing;
    listings.set(id, l);
    return l;
  };
  const approval = (refId: bigint, amountCents: bigint, status = "pending") => {
    const a = { id: nextApproval++, owner, kind: "listing", refId, amountCents, summary: "s", status } as unknown as Approval;
    approvals.set(a.id, a);
    return a;
  };
  const decide = (id: bigint, status: string) => {
    const old = approvals.get(id)!;
    const a = { ...old, status };
    approvals.set(id, a);
    fire("approval.update", old, a);
  };
  const item = (id: bigint) => {
    const it = { id, owner, name: "Oak desk", category: "table", brand: "", material: "oak", condition: "good", widthM: 1, depthM: 0.5, heightM: 0.75, estValueCents: 20000n, estLowCents: 15000n, estHighCents: 25000n, disposition: "sell", detailsStatus: "done", pricingStatus: "done", photoUrls: [] } as unknown as Item;
    items.set(id, it);
    return it;
  };
  const named = (r: string) => calls.filter(c => c.reducer === r);
  return { conn: conn as unknown as Conn, listings, approvals, listing, approval, decide, item, calls, named, events };
}

test("listing agent: a draft already asked about before a restart isn't asked about again", async () => {
  const f = fakeConn({ threshold: 10000n });
  f.listing(1n, 20000n);
  f.approval(1n, 20000n); // request_approval landed, then the worker died before update_listing
  listingAgent.start(f.conn);
  await sleep(30);
  assert.equal(f.named("requestApproval").length, 0, "no duplicate approval row");
  assert.equal(f.listings.get(1n)!.status, "awaiting_approval");
});

test("listing agent: awaiting_approval with no approval row asks for one instead of hanging", async () => {
  const f = fakeConn({ threshold: 10000n });
  f.listing(2n, 20000n, "awaiting_approval"); // the status update landed, the approval didn't
  listingAgent.start(f.conn);
  await sleep(30);
  assert.equal(f.named("requestApproval").length, 1);
  assert.equal(f.approvals.size, 1);
});

test("listing agent: a rejected request_approval logs an error and leaves the listing a draft", async () => {
  const f = fakeConn({ threshold: 10000n, failRequestApproval: true });
  f.listing(3n, 20000n);
  listingAgent.start(f.conn);
  await sleep(30);
  assert.equal(f.listings.get(3n)!.status, "draft", "not parked in awaiting_approval with no approval row");
  assert.equal(f.named("updateListing").length, 0);
  assert.ok(f.events.some(e => e.kind === "error" && e.refId === 3n && /approval/i.test(e.message)));
});

test("listing agent: thresholds -1 and 0 always ask, a price over the threshold asks", async () => {
  for (const [id, threshold, price] of [[4n, -1n, 100n], [5n, 0n, 100n], [6n, 10000n, 10001n]] as const) {
    const f = fakeConn({ threshold });
    f.listing(id, price);
    listingAgent.start(f.conn);
    await sleep(30);
    assert.equal(f.named("requestApproval").length, 1, `threshold ${threshold}, price ${price}`);
    assert.equal(f.listings.get(id)!.status, "awaiting_approval");
  }
});

test("listing agent: exactly at the threshold posts right away (no user row: default threshold)", async () => {
  const f = fakeConn(); // no user row -> APPROVAL_THRESHOLD_CENTS_DEFAULT = 10000
  f.listing(7n, 10000n);
  listingAgent.start(f.conn);
  await sleep(6000); // simulated eBay walks three steps with latency
  assert.equal(f.named("requestApproval").length, 0);
  assert.equal(f.listings.get(7n)!.status, "posted");
  assert.ok(f.listings.get(7n)!.url.endsWith("/files/listing-7.html"));
});

test("listing agent: denied, or approved for a different amount, is rejected, never posted", async () => {
  const f = fakeConn({ threshold: 10000n });
  f.listing(8n, 20000n, "awaiting_approval");
  f.listing(9n, 20000n, "awaiting_approval");
  const a8 = f.approval(8n, 20000n);
  const a9 = f.approval(9n, 15000n); // approved at an older price
  listingAgent.start(f.conn);
  f.decide(a8.id, "denied");
  f.decide(a9.id, "approved");
  await sleep(30);
  assert.equal(f.listings.get(8n)!.status, "rejected");
  assert.equal(f.listings.get(9n)!.status, "rejected");
  assert.ok(f.events.some(e => e.refId === 9n && /price changed after approval/.test(e.message)));
});

test("listing agent: a decided approval found on restart is acted on once", async () => {
  const f = fakeConn({ threshold: 10000n });
  f.listing(10n, 20000n, "awaiting_approval");
  f.approval(10n, 20000n, "approved");
  listingAgent.start(f.conn);
  await sleep(6000);
  assert.equal(f.listings.get(10n)!.status, "posted");
  assert.equal(f.named("updateListing").filter(c => c.args.status === "posted").length, 1);
});

test("listing agent: a rejected create_listing_draft logs an error, not a Drafted result", async () => {
  const f = fakeConn({ failCreateDraft: true });
  const it = f.item(11n);
  const out = { title: "Oak desk, good condition", description: "Solid oak desk.", priceCents: 18000, priceReason: "Below the comps median." };
  writeFileSync(path.join(tmp, `${replayKey({ model: config.models.agent, system: LISTING_SYSTEM, text: buildDraftPrompt(it, []), schema: ListingDraft })}.json`), JSON.stringify({ output: out }));
  listingAgent.start(f.conn);
  await sleep(50);
  assert.equal(f.named("createListingDraft").length, 1);
  assert.ok(f.events.some(e => e.kind === "error" && e.refId === 11n && /Drafting failed/.test(e.message)));
  assert.ok(!f.events.some(e => e.kind === "result" && e.refId === 11n), "no result event for a draft that never landed");
});
