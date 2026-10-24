import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { Conn } from "../src/spacetime.js";
import type { Approval, Item, Listing } from "../src/module_bindings/types.js";

// #186: stale pending approvals expire (fake clock, fake expire_approval), and the listing agent
// asks again once per expiry, also across a restart. Own file so the env is set before the agents
// read it: simulated eBay only, Claude answers replayed, defaults for expiry.
const tmp = mkdtempSync(path.join(tmpdir(), "approval-expiry-"));
for (const k of ["EBAY_CLIENT_ID", "EBAY_CLIENT_SECRET", "EBAY_REFRESH_TOKEN"]) process.env[k] = "";
process.env.UPLOAD_DIR = tmp;
process.env.LLM_REPLAY = "replay";
process.env.LLM_REPLAY_DIR = tmp;
process.env.LISTING_SIM_SOLD_AFTER_SEC = "0";
process.env.APPROVAL_THRESHOLD_CENTS_DEFAULT = "10000";
delete process.env.APPROVAL_EXPIRE_HOURS;
delete process.env.APPROVAL_MAX_REASKS;
const { afterExpiry, approvalExpiry, createExpirySweeper, expireAfterMs, isStale, MIN_EXPIRE_MS } = await import("../src/agents/approval-expiry.js");
const { listingAgent } = await import("../src/agents/listing.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const owner = { toHexString: () => "owner", isEqual: () => true };
const HOUR = 3_600_000;
const T0 = Date.UTC(2026, 9, 24, 0, 0, 0);
const at = (ms: number) => ({ toMillis: () => BigInt(ms) });

function approvalRow(id: bigint, status: string, requestedAtMs = T0, o: Partial<{ kind: string; refId: bigint; amountCents: bigint }> = {}) {
  return { id, owner, kind: o.kind ?? "listing", refId: o.refId ?? 1n, amountCents: o.amountCents ?? 20000n, summary: "s", status, requestedAt: at(requestedAtMs), updatedAt: at(requestedAtMs), decidedVia: "", cibaSubject: "" } as unknown as Approval;
}

// Approvals + events, an optional fake expire_approval that behaves like the module (#199).
function sweepConn(rows: Approval[], o: { withReducer?: boolean; moduleHasIt?: boolean } = {}) {
  const approvals = new Map(rows.map(a => [a.id, a]));
  const events: { kind: string; message: string; refId: bigint }[] = [];
  const expireCalls: bigint[] = [];
  const reducers: Record<string, unknown> = {
    logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e),
  };
  if (o.withReducer !== false) {
    reducers.expireApproval = async ({ approvalId }: { approvalId: bigint }) => {
      expireCalls.push(approvalId);
      if (o.moduleHasIt === false) throw new Error("No such reducer `expire_approval`");
      const a = approvals.get(approvalId)!;
      if (a.status !== "pending") throw new Error(`approval already ${a.status}`);
      approvals.set(approvalId, { ...a, status: "expired", decidedVia: "expired" } as Approval);
    };
  }
  const conn = { db: { approval: { iter: () => approvals.values() } }, reducers } as unknown as Conn;
  return { conn, approvals, events, expireCalls };
}

test("expiry settings: default 12 h, 0 = off, never under the module's 15-minute floor", () => {
  assert.equal(approvalExpiry.expireMs, 12 * HOUR);
  assert.equal(approvalExpiry.maxReasks, 2);
  assert.equal(expireAfterMs(0), 0);
  assert.equal(expireAfterMs(-1), 0);
  assert.equal(expireAfterMs(0.01), MIN_EXPIRE_MS);
  assert.equal(expireAfterMs(1.5), 1.5 * HOUR);
});

test("expiry: a pending approval expires exactly at the boundary, not a millisecond before", async () => {
  let now = T0 + 12 * HOUR - 1;
  const lines: string[] = [];
  const f = sweepConn([approvalRow(1n, "pending")]);
  const sweeper = createExpirySweeper({ conn: f.conn, expireMs: 12 * HOUR, now: () => now, say: l => lines.push(l) });
  assert.equal(await sweeper.sweep(), 0);
  assert.equal(f.approvals.get(1n)!.status, "pending");
  assert.deepEqual(f.expireCalls, []);
  now = T0 + 12 * HOUR;
  assert.equal(await sweeper.sweep(), 1);
  assert.equal(f.approvals.get(1n)!.status, "expired");
  const ev = f.events.filter(e => e.refId === 1n);
  assert.equal(ev.length, 1);
  assert.equal(ev[0]!.kind, "approval");
  assert.match(ev[0]!.message, /^Expired after 12 h with no answer/);
  // Already expired: a later sweep leaves it alone.
  now += HOUR;
  assert.equal(await sweeper.sweep(), 0);
  assert.deepEqual(f.expireCalls, [1n]);
  assert.equal(lines.length, 1, "one startup line");
});

test("expiry: decided approvals are never expired, however old", async () => {
  const old = T0 - 100 * HOUR;
  const f = sweepConn([approvalRow(1n, "approved", old), approvalRow(2n, "denied", old), approvalRow(3n, "expired", old), approvalRow(4n, "pending", T0)]);
  const sweeper = createExpirySweeper({ conn: f.conn, expireMs: 12 * HOUR, now: () => T0 + HOUR, say: () => undefined });
  assert.equal(await sweeper.sweep(), 0);
  assert.deepEqual(f.expireCalls, []);
  assert.deepEqual([1n, 2n, 3n, 4n].map(id => f.approvals.get(id)!.status), ["approved", "denied", "expired", "pending"]);
  assert.equal(isStale(approvalRow(5n, "approved", old), T0, 12 * HOUR), false);
  assert.equal(isStale(approvalRow(6n, "pending", old), T0, 0), false, "0 = off");
});

test("expiry: a no-op with one log line when the bindings or the running module lack expire_approval", async () => {
  const lines: string[] = [];
  const noBindings = sweepConn([approvalRow(1n, "pending", T0 - 100 * HOUR)], { withReducer: false });
  const a = createExpirySweeper({ conn: noBindings.conn, expireMs: 12 * HOUR, now: () => T0, say: l => lines.push(l) });
  assert.equal(a.enabled, false);
  assert.equal(await a.sweep(), 0);
  assert.equal(noBindings.approvals.get(1n)!.status, "pending");
  assert.deepEqual(lines.length, 1);
  assert.match(lines[0]!, /off: .*no expire_approval/);

  lines.length = 0;
  const oldModule = sweepConn([approvalRow(1n, "pending", T0 - 100 * HOUR), approvalRow(2n, "pending", T0 - 100 * HOUR)], { moduleHasIt: false });
  const b = createExpirySweeper({ conn: oldModule.conn, expireMs: 12 * HOUR, now: () => T0, say: l => lines.push(l) });
  assert.equal(b.enabled, true);
  assert.equal(await b.sweep(), 0);
  assert.equal(await b.sweep(), 0);
  assert.equal(b.enabled, false);
  assert.deepEqual(oldModule.expireCalls, [1n], "stops after the first 'no such reducer'");
  assert.equal(oldModule.events.length, 0, "not an error event per approval");
  assert.equal(lines.filter(l => /off: the running module/.test(l)).length, 1);
});

test("expiry: a refused expire (e.g. decided first) logs one error and is retried quietly", async () => {
  const f = sweepConn([approvalRow(1n, "pending", T0 - 13 * HOUR)]);
  let fail = true;
  const sweeper = createExpirySweeper({
    conn: f.conn,
    expireMs: 12 * HOUR,
    now: () => T0,
    say: () => undefined,
    expire: async ({ approvalId }) => {
      if (fail) throw new Error("approval is less than 15 minutes old");
      f.approvals.set(approvalId, { ...f.approvals.get(approvalId)!, status: "expired" } as Approval);
    },
  });
  await sweeper.sweep();
  await sweeper.sweep();
  assert.equal(f.events.filter(e => e.kind === "error").length, 1);
  fail = false;
  assert.equal(await sweeper.sweep(), 1);
});

test("afterExpiry: re-ask while under the cap, give up past it, nothing once the re-ask landed", () => {
  const exp = (id: bigint) => approvalRow(id, "expired");
  assert.deepEqual(afterExpiry([approvalRow(1n, "pending")], "listing", 1n, 2), { action: "none" });
  assert.deepEqual(afterExpiry([exp(1n)], "listing", 1n, 2), { action: "reask", expired: 1n, attempt: 1 });
  assert.deepEqual(afterExpiry([exp(1n), approvalRow(2n, "pending")], "listing", 1n, 2), { action: "none" }, "restart after the re-ask landed");
  assert.deepEqual(afterExpiry([exp(1n), exp(2n)], "listing", 1n, 2), { action: "reask", expired: 2n, attempt: 2 });
  assert.deepEqual(afterExpiry([exp(1n), exp(2n), exp(3n)], "listing", 1n, 2), { action: "give_up", expiredCount: 3 });
  assert.deepEqual(afterExpiry([exp(1n)], "listing", 1n, 0), { action: "give_up", expiredCount: 1 });
  assert.deepEqual(afterExpiry([exp(1n)], "purchase", 1n, 2), { action: "none" }, "other kind");
  assert.deepEqual(afterExpiry([exp(1n)], "listing", 9n, 2), { action: "none" }, "other listing");
});

// ---- listing agent: re-ask after expiry ----

// Approval ids are unique across the file, as in the DB (the agent remembers re-asked ids per process).
let nextApproval = 1000n;

function listingConn() {
  const listings = new Map<bigint, Listing>();
  const approvals = new Map<bigint, Approval>();
  const items = new Map<bigint, Item>();
  const cbs: Record<string, ((...a: unknown[]) => void)[]> = {};
  const on = (k: string) => (cb: (...a: unknown[]) => void) => void (cbs[k] ??= []).push(cb);
  const fire = (k: string, ...a: unknown[]) => (cbs[k] ?? []).forEach(cb => cb({}, ...a));
  const requests: bigint[] = [];
  const statuses: string[] = [];
  const events: { kind: string; message: string; refId: bigint }[] = [];
  const conn = {
    db: {
      listing: { iter: () => listings.values(), id: { find: (id: bigint) => listings.get(id) }, onInsert: on("listing.insert"), onUpdate: on("listing.update") },
      approval: { iter: () => approvals.values(), onInsert: on("approval.insert"), onUpdate: on("approval.update") },
      item: { iter: () => [][Symbol.iterator](), id: { find: (id: bigint) => items.get(id) }, onInsert: on("item.insert"), onUpdate: on("item.update") },
      comp: { iter: () => [][Symbol.iterator]() },
      user: { identity: { find: () => undefined } },
    },
    reducers: {
      requestApproval: async (a: { refId: bigint; amountCents: bigint; kind: string }) => {
        requests.push(a.refId);
        await sleep(1);
        const row = approvalRow(nextApproval++, "pending", Date.now(), { refId: a.refId, amountCents: a.amountCents });
        approvals.set(row.id, row);
        fire("approval.insert", row);
      },
      updateListing: async (a: { listingId: bigint; status: string }) => {
        statuses.push(a.status);
        await sleep(1);
        const old = listings.get(a.listingId)!;
        const l = { ...old, status: a.status };
        listings.set(l.id, l);
        fire("listing.update", old, l);
      },
      logAgentEvent: async (e: { kind: string; message: string; refId: bigint }) => void events.push(e),
    },
  };
  const listing = (id: bigint, disposition = "sell") => {
    items.set(id * 10n, { id: id * 10n, owner, disposition } as unknown as Item);
    const l = { id, owner, itemId: id * 10n, title: `Thing ${id}`, description: "d", priceCents: 20000n, status: "awaiting_approval", externalId: "", url: "", simulated: true } as unknown as Listing;
    listings.set(id, l);
    return l;
  };
  const approval = (refId: bigint, status: string) => {
    const a = approvalRow(nextApproval++, status, T0, { refId });
    approvals.set(a.id, a);
    return a;
  };
  const expire = (id: bigint) => {
    const old = approvals.get(id)!;
    const a = { ...old, status: "expired" } as Approval;
    approvals.set(id, a);
    fire("approval.update", old, a);
  };
  return { conn: conn as unknown as Conn, listings, approvals, listing, approval, expire, requests, statuses, events };
}

test("listing agent: an expired approval is asked again once, even when updates arrive twice", async () => {
  const f = listingConn();
  f.listing(101n);
  const a = f.approval(101n, "pending");
  listingAgent.start(f.conn);
  await sleep(20);
  assert.deepEqual(f.requests, [], "still waiting on the pending one");
  f.expire(a.id);
  f.expire(a.id); // a duplicate update before the new row lands
  await sleep(30);
  assert.deepEqual(f.requests, [101n]);
  assert.equal(f.listings.get(101n)!.status, "awaiting_approval", "not rejected");
  assert.ok(f.events.some(e => e.kind === "approval" && e.refId === 101n && /expired without an answer, asking again \(1 of 2\)/.test(e.message)));
});

test("listing agent: a restart after the re-ask landed doesn't ask a second time", async () => {
  const f = listingConn();
  f.listing(102n);
  f.approval(102n, "expired");
  f.approval(102n, "pending"); // the re-ask from the previous worker run
  listingAgent.start(f.conn);
  await sleep(30);
  assert.deepEqual(f.requests, []);
  assert.equal(f.listings.get(102n)!.status, "awaiting_approval");
});

test("listing agent: a restart between the expiry and the re-ask asks exactly once", async () => {
  const f = listingConn();
  f.listing(103n);
  f.approval(103n, "expired"); // the previous run expired it and died before asking again
  listingAgent.start(f.conn);
  listingAgent.start(f.conn); // and a second start in the same process registers more callbacks
  await sleep(30);
  assert.deepEqual(f.requests, [103n]);
});

test("listing agent: gives up after APPROVAL_MAX_REASKS expiries, or when the item is no longer for sale", async () => {
  const f = listingConn();
  f.listing(104n);
  for (let i = 0; i < 3; i++) f.approval(104n, "expired");
  f.listing(105n, "keep");
  f.approval(105n, "expired");
  listingAgent.start(f.conn);
  await sleep(30);
  assert.deepEqual(f.requests, []);
  assert.equal(f.listings.get(104n)!.status, "rejected");
  assert.equal(f.listings.get(105n)!.status, "rejected");
  assert.ok(f.events.some(e => e.refId === 104n && /expired 3 times/.test(e.message)));
  assert.ok(f.events.some(e => e.refId === 105n && /no longer sorted to sell/.test(e.message)));
});
