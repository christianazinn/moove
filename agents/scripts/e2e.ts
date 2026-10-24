// End-to-end pipeline test on a LOCAL SpacetimeDB (never maincloud):
//   scan (import_scan_v2) -> room photo sweep -> pricing (x402, simulated rail) -> auto-sort ->
//   listing (+ approval) -> new home -> shopping list -> deals -> fraud -> purchase (+ approval,
//   simulated Visa) -> payments,
// driven through the same reducers the iOS app calls, against a real worker process.
//
// Needs `spacetime start` (local server on :3000). Publishes the current module to a fresh database
// (E2E_DB, default moove-e2e, wiped each run), starts its own worker on spare ports, runs the stages,
// prints a PASS/FAIL table and exits non-zero on any failure.
//
// Claude calls go through LLM_REPLAY (default auto: recorded answers in fixtures/llm are replayed;
// a miss calls the API once and records it). --replay forbids live calls (CI-style); --live always calls.
// Apify is never called: the demo items have committed comps caches, deals come from fixtures.
//
// Usage (from agents/): npm run e2e [-- --replay | --live] [-- --keep]   (--keep leaves the worker running)
import "./env.js";
import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { deflateSync, crc32 } from "node:zlib";
import path from "node:path";
import type { Identity } from "spacetimedb";
import { DbConnection, tables } from "../src/module_bindings/index.js";
import { CARD_CHECKOUT_SOURCES } from "../src/integrations/deals.js";
import { DEMO_OBJECTS } from "./demo-room.js";

const args = process.argv.slice(2);
const KEEP = args.includes("--keep");
const LLM_MODE = args.includes("--replay") ? "replay" : args.includes("--live") ? "record" : "auto";
const DB = process.env.E2E_DB || "moove-e2e";
const URI = process.env.E2E_URI || "ws://localhost:3000";
const PORT = Number(process.env.E2E_UPLOAD_PORT || 8790);
const X402_PORT = Number(process.env.E2E_X402_PORT || 8412);
const LOG_DIR = path.join(".cache", "e2e");
if (!/localhost|127\.0\.0\.1/.test(URI)) {
  console.error(`e2e only runs against a local SpacetimeDB (got ${URI})`);
  process.exit(2);
}

type Row = { stage: string; ok: boolean; detail: string; ms: number };
const rows: Row[] = [];
const t0 = Date.now();
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

async function stage<T>(name: string, fn: () => Promise<{ detail: string; value?: T }>): Promise<T | undefined> {
  const start = Date.now();
  try {
    const { detail, value } = await fn();
    rows.push({ stage: name, ok: true, detail, ms: Date.now() - start });
    console.log(`PASS ${name}: ${detail}`);
    return value;
  } catch (err) {
    rows.push({ stage: name, ok: false, detail: String(err instanceof Error ? err.message : err).slice(0, 300), ms: Date.now() - start });
    console.log(`FAIL ${name}: ${String(err)}`);
    return undefined;
  }
}

async function until<T>(what: string, get: () => T | undefined | false | null, timeoutMs: number): Promise<T> {
  const start = Date.now();
  for (;;) {
    const v = get();
    if (v !== undefined && v !== false && v !== null) return v as T;
    if (Date.now() - start > timeoutMs) throw new Error(`timed out after ${Math.round(timeoutMs / 1000)}s waiting for ${what}`);
    await sleep(250);
  }
}

// The sweep's "room photo" is a committed file: its bytes are part of the recorded answer's key, and
// zlib output differs between Node versions, so it must not be regenerated per run.
const ROOM_PNG = path.join("fixtures", "e2e", "room.png");
function roomPhoto(): Buffer {
  if (!existsSync(ROOM_PNG)) {
    mkdirSync(path.dirname(ROOM_PNG), { recursive: true });
    writeFileSync(ROOM_PNG, generateRoomPng());
  }
  return readFileSync(ROOM_PNG);
}

// A 96x64 PNG: a brown desk and a dark floor lamp on a light wall.
function generateRoomPng(): Buffer {
  const w = 96, h = 64;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 3 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const o = y * (w * 3 + 1) + 1 + x * 3;
      const desk = y > 30 && y < 36 && x > 10 && x < 60; // a "desk" top
      const leg = y >= 36 && y < 60 && (x === 14 || x === 56);
      const lamp = x > 75 && x < 79 && y > 10 && y < 60;
      const c = desk || leg ? [120, 72, 40] : lamp ? [30, 30, 30] : y > 58 ? [180, 160, 120] : [235, 232, 225];
      raw[o] = c[0]; raw[o + 1] = c[1]; raw[o + 2] = c[2];
    }
  }
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

function startWorker(): { child: ChildProcess; log: string; ready: Promise<void> } {
  mkdirSync(LOG_DIR, { recursive: true });
  const log = path.join(LOG_DIR, "worker.log");
  const out = createWriteStream(log);
  const tokenFile = `.worker-token.${DB}`;
  rmSync(tokenFile, { force: true }); // fresh DB -> fresh worker identity (first caller wins locally)
  const env = {
    ...process.env,
    SPACETIME_URI: URI,
    SPACETIME_DB_NAME: DB,
    SPACETIME_WORKER_TOKEN_FILE: tokenFile,
    SPACETIME_WORKER_TOKEN: "",
    UPLOAD_PORT: String(PORT),
    PUBLIC_UPLOAD_BASE_URL: `http://localhost:${PORT}`,
    UPLOAD_DIR: path.join(LOG_DIR, "uploads"),
    X402_PORT: String(X402_PORT),
    LLM_REPLAY: LLM_MODE,
    VISA_PROVIDER: "simulated",
    X402_SEED_BUDGETS: "0",
    VISA_SEED_BUDGETS: "0",
    FAL_KEY: "",
    APIFY_TOKEN: "", // never scrape from a test run: every demo query has a committed cache
    SWEEP_SETTLE_MS: "1500",
    FRAUD_SETTLE_MS: "1500",
    PRICING_RETRY_BASE_MS: "2000",
  };
  const child = spawn("npx", ["tsx", "src/index.ts"], { env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  let buf = "";
  const ready = new Promise<void>((resolve, reject) => {
    const onData = (d: Buffer) => {
      out.write(d);
      buf += d.toString();
      if (/\[agents\] started fraud/.test(buf)) resolve();
    };
    child.stdout!.on("data", onData);
    child.stderr!.on("data", onData);
    child.on("exit", code => reject(new Error(`worker exited early (code ${code}); see ${log}`)));
    setTimeout(() => reject(new Error(`worker not ready after 90s; see ${log}`)), 90_000).unref();
  });
  return { child, log, ready };
}

function stopWorker(child: ChildProcess): void {
  try {
    process.kill(-child.pid!, "SIGTERM"); // the whole group: npx -> tsx -> node
  } catch {
    // already gone
  }
}

let worker: ReturnType<typeof startWorker> | undefined;
let conn: DbConnection | undefined;
let me: Identity | undefined;

// ---------- stages ----------
await stage("preflight: local SpacetimeDB", async () => {
  const res = await fetch(URI.replace(/^ws/, "http") + "/v1/ping").catch(() => undefined);
  if (!res || !res.ok) throw new Error(`no SpacetimeDB at ${URI} (run \`spacetime start\`)`);
  return { detail: URI };
});

await stage(`publish module to ${DB} (fresh)`, async () => {
  const r = spawnSync("spacetime", ["publish", "-s", "local", "-p", "../spacetime", "--delete-data", "--yes=all", DB], { encoding: "utf8" });
  if (r.status !== 0) throw new Error((r.stderr || r.stdout).split("\n").filter(Boolean).slice(-3).join(" | "));
  return { detail: (r.stdout.match(/(Created|Updated)[^\n]*/) ?? ["published"])[0] };
});

await stage("worker starts against it", async () => {
  worker = startWorker();
  await worker.ready;
  return { detail: `LLM_REPLAY=${LLM_MODE}, uploads on :${PORT}, log ${worker.log}` };
});

await stage("app user connects + register_user", async () => {
  const c = await new Promise<{ conn: DbConnection; identity: Identity }>((resolve, reject) => {
    DbConnection.builder()
      .withUri(URI)
      .withDatabaseName(DB)
      .onConnect((conn, identity) => {
        conn.subscriptionBuilder()
          .onApplied(() => resolve({ conn, identity }))
          .onError(ctx => reject(ctx.event ?? new Error("subscription failed")))
          .subscribe(Object.values(tables));
      })
      .onConnectError((_ctx, err) => reject(err))
      .build();
  });
  conn = c.conn;
  me = c.identity;
  await conn.reducers.registerUser({ auth0Sub: "", name: "E2E Tester", email: "e2e@example.invalid" });
  // -1 = ask for approval on everything, so the approval path runs for listings and purchases
  await conn.reducers.setApprovalThreshold({ cents: -1n });
  await until("user row", () => conn!.db.user.identity.find(me!), 10_000);
  return { detail: `user ${me.toHexString().slice(0, 12)}…, approval threshold -1 (always ask)` };
});

await stage("service_config: worker announced its upload URL", async () => {
  const want = `http://localhost:${PORT}`;
  const row = await until("upload_base_url", () => conn!.db.serviceConfig.key.find("upload_base_url"), 15_000);
  if (row.value !== want) throw new Error(`upload_base_url=${row.value}, want ${want}`);
  const v = conn!.db.serviceConfig.key.find("worker_version");
  return { detail: `upload_base_url=${row.value}, worker_version=${v?.value ?? "?"}` };
});

const items = () => (conn ? [...conn.db.item.iter()].filter(it => me && it.owner.isEqual(me)) : []);

const scanId = await stage("scan: import_scan_v2 (9 demo objects + RoomPlan attributes)", async () => {
  if (!conn) throw new Error("not connected");
  await conn.reducers.importScanV2({
    roomName: "E2E Bedroom",
    home: "old",
    usdzUrl: "",
    capturedRoomJsonUrl: "",
    objects: DEMO_OBJECTS.map(o => ({
      scanObjectId: o.scanObjectId, name: o.name, category: o.category,
      widthM: o.widthM, heightM: o.heightM, depthM: o.depthM, photoUrl: "",
      attributes: o.category === "chair" ? ["ChairType.swivel", "ChairArmType.existing"] : [],
    })),
  });
  const its = await until("9 items", () => (items().length === DEMO_OBJECTS.length ? items() : undefined), 15_000);
  const chair = its.find(i => i.category === "chair");
  if (!chair || !chair.attributesJson.includes("ChairType.swivel")) throw new Error(`chair attributes not stored: ${chair?.attributesJson}`);
  for (const o of DEMO_OBJECTS.filter(o => o.sentimental)) {
    const it = its.find(i => i.scanObjectId === o.scanObjectId)!;
    await conn.reducers.setSentimental({ itemId: it.id, value: true });
  }
  const scan = [...conn.db.scan.iter()].find(s => me && s.owner.isEqual(me));
  return { detail: `${its.length} items, chair attributes ${chair.attributesJson}`, value: scan?.id };
});

await stage("pricing: every item priced from cached comps (x402 simulated)", async () => {
  const done = await until("all items priced", () => {
    const its = items();
    return its.length && its.every(i => i.pricingStatus === "done" || i.pricingStatus === "failed") ? its : undefined;
  }, 90_000);
  const failed = done.filter(i => i.pricingStatus === "failed").map(i => i.name);
  if (failed.length) throw new Error(`pricing failed for ${failed.join(", ")}`);
  const pays = [...conn!.db.payment.iter()].filter(p => p.rail === "x402");
  const est = done.map(i => `${i.name.split(" ").slice(-1)[0]} $${Number(i.estValueCents) / 100}`).join(", ");
  return { detail: `${done.length} priced; ${pays.length} x402 payment rows (simulated: ${pays.every(p => p.simulated)}); ${est}` };
});

await stage("sort: keep/sell/donate/trash, sentimental left to the user", async () => {
  const its = await until("dispositions", () => {
    const xs = items();
    return xs.every(i => i.maybeSentimental ? i.disposition === "undecided" : i.disposition !== "undecided") ? xs : undefined;
  }, 30_000);
  const by: Record<string, number> = {};
  for (const i of its) by[i.disposition] = (by[i.disposition] ?? 0) + 1;
  if (!its.some(i => i.disposition === "sell")) throw new Error(`no item sorted to sell (${JSON.stringify(by)}), so listing can't be tested`);
  return { detail: JSON.stringify(by) };
});

await stage("sweep: room photo -> named/added items", async () => {
  if (!conn || scanId === undefined) throw new Error("no scan");
  const res = await fetch(`http://localhost:${PORT}/upload`, { method: "POST", headers: { "content-type": "image/png" }, body: new Uint8Array(roomPhoto()) });
  if (!res.ok) throw new Error(`upload: HTTP ${res.status} ${await res.text()}`);
  const { url } = (await res.json()) as { url: string };
  await conn.reducers.addScanPhoto({ scanId, url });
  const s = await until("sweep done/failed", () => {
    const sc = conn!.db.scan.id.find(scanId);
    return sc && (sc.sweepStatus === "done" || sc.sweepStatus === "failed") ? sc : undefined;
  }, 120_000);
  if (s.sweepStatus !== "done") {
    const err = [...conn.db.agentEvent.iter()].filter(e => e.agent === "sweep" && e.kind === "error").pop();
    throw new Error(`sweep ${s.sweepStatus}: ${err?.message ?? "?"}`);
  }
  const added = items().filter(i => i.scanObjectId.startsWith("photo:")).map(i => i.name);
  const result = [...conn.db.agentEvent.iter()].filter(e => e.agent === "sweep" && e.kind === "result").pop();
  return { detail: `${result?.message ?? "done"}${added.length ? ` [added: ${added.join(", ")}]` : ""}` };
});

await stage("listing: sell items drafted, approval requested (threshold -1)", async () => {
  const sells = () => items().filter(i => i.disposition === "sell");
  const appr = await until("listing approvals", () => {
    const ls = [...conn!.db.listing.iter()].filter(l => me && l.owner.isEqual(me));
    const ap = [...conn!.db.approval.iter()].filter(a => me && a.owner.isEqual(me) && a.kind === "listing" && a.status === "pending");
    return sells().every(i => ls.some(l => l.itemId === i.id)) && ap.length >= sells().length ? ap : undefined;
  }, 120_000);
  return { detail: `${sells().length} sell item(s) -> ${appr.length} pending listing approval(s)`, value: appr };
});

await stage("approval: owner approves -> listing posted (simulated eBay)", async () => {
  const pending = [...conn!.db.approval.iter()].filter(a => me && a.owner.isEqual(me) && a.kind === "listing" && a.status === "pending");
  for (const a of pending) await conn!.reducers.decideApproval({ approvalId: a.id, status: "approved" });
  const posted = await until("listings posted", () => {
    const ls = [...conn!.db.listing.iter()].filter(l => me && l.owner.isEqual(me));
    return ls.length && ls.every(l => l.status === "posted") ? ls : undefined;
  }, 60_000);
  const decided = [...conn!.db.approval.iter()].filter(a => pending.some(p => p.id === a.id));
  if (!decided.every(a => a.decidedVia === "app")) throw new Error(`decided_via not 'app': ${decided.map(a => a.decidedVia)}`);
  return { detail: `${posted.length} posted (simulated: ${posted.every(l => l.simulated)}); decided_via=app` };
});

await stage("new home -> shopping list (Claude, replayed)", async () => {
  const plan = { rooms: [{ name: "Bedroom", kind: "bedroom" }, { name: "Living room", kind: "living" }, { name: "Kitchen", kind: "kitchen" }] };
  await conn!.reducers.createNewHome({ name: "E2E house", source: "demo", floorPlanJson: JSON.stringify(plan) });
  const list = await until("shopping items", () => {
    const xs = [...conn!.db.shoppingItem.iter()].filter(s => me && s.owner.isEqual(me));
    return xs.length ? xs : undefined;
  }, 90_000);
  return { detail: `${list.length} items: ${list.slice(0, 6).map(s => s.name).join(", ")}${list.length > 6 ? ", …" : ""}` };
});

await stage("buy: deals found and fraud-screened", async () => {
  const deals = await until("screened deals", () => {
    const ds = [...conn!.db.deal.iter()].filter(d => me && d.owner.isEqual(me));
    return ds.length && ds.every(d => d.fraudScore >= 0) ? ds : undefined;
  }, 120_000);
  const flagged = deals.filter(d => d.fraudScore >= 0.3);
  return { detail: `${deals.length} deals, ${flagged.length} flagged >= 0.3${flagged[0] ? ` (e.g. "${flagged[0].title}": ${flagged[0].fraudReasons.join("; ")})` : ""}` };
});

await stage("purchase: choose card deal -> approve -> simulated Visa payment", async () => {
  const card = [...conn!.db.deal.iter()]
    .filter(d => me && d.owner.isEqual(me) && CARD_CHECKOUT_SOURCES.has(d.source) && d.fraudScore < 0.5)
    .sort((a, b) => Number(a.priceCents - b.priceCents))[0];
  if (!card) throw new Error("no card-checkout deal to buy");
  await conn!.reducers.chooseDeal({ shoppingItemId: card.shoppingItemId, dealId: card.id });
  const ap = await until("purchase approval", () =>
    [...conn!.db.approval.iter()].find(a => a.kind === "purchase" && a.refId === card.id && a.status === "pending"), 60_000);
  await conn!.reducers.decideApproval({ approvalId: ap.id, status: "approved" });
  const pay = await until("settled Visa payment", () =>
    [...conn!.db.payment.iter()].find(p => p.rail === "visa" && p.refId === card.id && p.status !== "pending"), 60_000);
  if (pay.status !== "settled") throw new Error(`Visa payment ${pay.status}`);
  return { detail: `"${card.title}" (${card.source}) $${Number(card.priceCents) / 100}: payment ${pay.status}, simulated: ${pay.simulated}` };
});

await stage("agent log: no unexpected errors", async () => {
  const evs = [...conn!.db.agentEvent.iter()].filter(e => me && e.owner.isEqual(me));
  // Expected noise: spend-cap refusals are designed behavior; transient retries recover.
  // No APIFY_TOKEN in a test run, so items the sweep adds or renames have no cached comps: expected.
  const errs = evs.filter(e => e.kind === "error" && !/retrying in|Spend cap|APIFY_TOKEN not set and no cached comps/.test(e.message));
  if (errs.length) throw new Error(`${errs.length} error event(s): ${errs.slice(0, 3).map(e => `[${e.agent}] ${e.message.slice(0, 100)}`).join(" | ")}`);
  const agents = [...new Set(evs.map(e => e.agent))].sort();
  return { detail: `${evs.length} events from ${agents.join(", ")}` };
});

// ---------- report ----------
conn?.disconnect();
if (worker && !KEEP) stopWorker(worker.child);
const pad = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s.padEnd(n));
console.log(`\nMoove E2E on ${URI}/${DB} (LLM_REPLAY=${LLM_MODE}) — ${Math.round((Date.now() - t0) / 1000)}s`);
console.log(`${pad("stage", 62)} ${pad("result", 6)} ${pad("time", 6)} detail`);
for (const r of rows) console.log(`${pad(r.stage, 62)} ${pad(r.ok ? "PASS" : "FAIL", 6)} ${pad(`${(r.ms / 1000).toFixed(1)}s`, 6)} ${r.detail}`);
const failed = rows.filter(r => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed${worker ? `; worker log: agents/${worker.log}` : ""}${KEEP ? " (worker left running: --keep)" : ""}`);
process.exit(failed ? 1 : 0);
