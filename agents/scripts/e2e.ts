// End-to-end pipeline test on a LOCAL SpacetimeDB (never maincloud):
//   scan (import_scan_v2) -> room photo sweep -> pricing (x402, simulated rail) -> auto-sort ->
//   listing (+ approval) -> new home -> shopping list -> deals -> fraud -> purchase (+ approval,
//   simulated Visa) -> payments,
// plus the commerce guarantees the demo relies on: x402 calls past the pricing budget are refused
// before paying, the card budget and the fraud block stop a purchase before any approval or charge,
// and every spending-log row is complete and labeled simulated.
// driven through the same reducers the iOS app calls, against a real worker process.
//
// Needs `spacetime start` (local server on :3000, or wherever E2E_URI points). Publishes the current module to a fresh database
// (E2E_DB, default moove-e2e, wiped each run), starts its own worker on spare ports, runs the stages,
// prints a PASS/FAIL table and exits non-zero on any failure.
//
// Safe by default, even with a dev's .env.local loaded (it has real keys on some laptops):
//   - Claude: LLM_REPLAY=replay (recorded answers in fixtures/llm; a miss fails, never calls the API).
//     Opt in with E2E_LLM=auto (a miss calls the API once and records it) or E2E_LLM=record / --live.
//   - x402: X402_SIMULATE=1 for the worker, so CDP keys never sign Base Sepolia payments. Opt in with
//     E2E_REAL_X402=1 (the commerce stages then fail, since they assert simulated rows).
//   - Visa is always the simulated provider; Apify, fal, Pangram, eBay and Auth0 CIBA are never called
//     (their keys are blanked, so listings use the simulated eBay and approvals stay in-app).
// The worker stage and the table header say which modes ran.
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
const LLM_OPT_IN = args.includes("--live") ? "record" : (process.env.E2E_LLM ?? "").trim();
if (LLM_OPT_IN && !["replay", "auto", "record"].includes(LLM_OPT_IN)) {
  console.error(`E2E_LLM must be replay, auto or record (got ${LLM_OPT_IN})`);
  process.exit(2);
}
const LLM_MODE = args.includes("--replay") ? "replay" : LLM_OPT_IN || "replay";
const REAL_X402 = process.env.E2E_REAL_X402 === "1";
const MODES = `LLM_REPLAY=${LLM_MODE}, x402=${REAL_X402 ? "REAL (Base Sepolia, E2E_REAL_X402=1)" : "simulated"}, visa=simulated`;
const DB = process.env.E2E_DB || "moove-e2e";
const URI = process.env.E2E_URI || "ws://localhost:3000";
const PORT = Number(process.env.E2E_UPLOAD_PORT || 8790);
const X402_PORT = Number(process.env.E2E_X402_PORT || 8412);
const LOG_DIR = path.join(".cache", "e2e");
// Commerce limits the worker runs with, tight enough that the guardrail stages below trip them.
// Pricing buys one $0.01 comps report per item over x402 (COMPS_QUOTE_USD_MICROS), so a $0.05 budget
// pays for 5 of the 9 demo items and the rest must be refused (pricing falls back to the direct lookup).
const X402_CAP_USDC = "0.05";
const X402_QUOTE_MICROS = 10_000n;
// The purchase stage's cheapest card deal (~$60) fits in $200; the most expensive card deal doesn't fit in what's left.
const VISA_CAP_USD = "200";
const FRAUD_BLOCK = 0.7; // the buy agent's default BUY_FRAUD_BLOCK, pinned so a dev's env can't change it
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
    // Even if a dev's .env.local has CDP keys: no Base Sepolia payments unless explicitly asked for.
    X402_SIMULATE: REAL_X402 ? "0" : "1",
    AGENT_SPEND_CAP_USDC: X402_CAP_USDC,
    X402_MAX_PER_CALL_USDC: "0.10",
    VISA_SPEND_CAP_USD: VISA_CAP_USD,
    VISA_MAX_PER_PURCHASE_USD: "750",
    BUY_FRAUD_BLOCK: String(FRAUD_BLOCK),
    BUY_AUTO_CHOOSE: "0",
    PANGRAM_URL: "", // no AI-text detector call: fraud scores stay rule-based and deterministic
    PANGRAM_TOKEN: "",
    EBAY_CLIENT_SECRET: "", // listings post to the labeled simulated eBay, never the sandbox
    EBAY_REFRESH_TOKEN: "",
    AUTH0_CIBA_CLIENT_SECRET: "", // no Guardian pushes: approvals are decided in-app by the test
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

// Connects to the test database, optionally with a saved token (the worker's, to plant test data).
function connectAs(token?: string, subscribe = true): Promise<{ conn: DbConnection; identity: Identity }> {
  return new Promise((resolve, reject) => {
    let b = DbConnection.builder().withUri(URI).withDatabaseName(DB);
    if (token) b = b.withToken(token);
    b.onConnect((conn, identity) => {
      if (!subscribe) return resolve({ conn, identity });
      conn.subscriptionBuilder()
        .onApplied(() => resolve({ conn, identity }))
        .onError(ctx => reject(ctx.event ?? new Error("subscription failed")))
        .subscribe(Object.values(tables));
    })
      .onConnectError((_ctx, err) => reject(err))
      .build();
  });
}

const parseData = (json: string): Record<string, unknown> => {
  try {
    return json ? (JSON.parse(json) as Record<string, unknown>) : {};
  } catch {
    return {};
  }
};

let worker: ReturnType<typeof startWorker> | undefined;
let conn: DbConnection | undefined;
let me: Identity | undefined;
// Error events the guardrail stages triggered on purpose; the final agent-log check ignores exactly these.
const expectedErrors = new Set<bigint>();

// ---------- stages ----------
await stage("preflight: local SpacetimeDB", async () => {
  const res = await fetch(URI.replace(/^ws/, "http") + "/v1/ping").catch(() => undefined);
  if (!res || !res.ok) throw new Error(`no SpacetimeDB at ${URI} (run \`spacetime start\`)`);
  return { detail: URI };
});

await stage(`publish module to ${DB} (fresh)`, async () => {
  // Publish to the server E2E_URI points at (not the "local" nickname, which is always :3000).
  const server = URI.replace(/^ws/, "http");
  const r = spawnSync("spacetime", ["publish", "-s", server, "-p", "../spacetime", "--delete-data", "--yes=all", DB], { encoding: "utf8" });
  if (r.status !== 0) throw new Error((r.stderr || r.stdout).split("\n").filter(Boolean).slice(-3).join(" | "));
  return { detail: (r.stdout.match(/(Created|Updated)[^\n]*/) ?? ["published"])[0] };
});

await stage("worker starts against it", async () => {
  worker = startWorker();
  await worker.ready;
  return { detail: `${MODES}, uploads on :${PORT}, log ${worker.log}` };
});

await stage("app user connects + register_user", async () => {
  const c = await connectAs();
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

await stage(`x402 budget: calls past the $${X402_CAP_USDC} pricing cap refused before paying`, async () => {
  const cap = BigInt(Math.round(Number(X402_CAP_USDC) * 1e6));
  const affordable = Number(cap / X402_QUOTE_MICROS);
  const pricingEvents = () =>
    [...conn!.db.agentEvent.iter()].filter(e => me && e.owner.isEqual(me) && e.agent === "pricing").map(e => ({ e, d: parseData(e.dataJson) }));
  const refused = await until(`${DEMO_OBJECTS.length - affordable} x402 refusals`, () => {
    const r = pricingEvents().filter(({ e, d }) => e.kind === "error" && d.rail === "x402" && d.outcome === "refused");
    return r.length >= DEMO_OBJECTS.length - affordable ? r : undefined;
  }, 15_000);
  const pays = [...conn!.db.payment.iter()].filter(p => me && p.owner.isEqual(me) && p.rail === "x402");
  const settled = pays.filter(p => p.status === "settled");
  const total = settled.reduce((a, p) => a + p.amountUsdMicros, 0n);
  if (settled.length !== affordable || total > cap) throw new Error(`${settled.length} settled x402 payments totalling ${total} micros, want ${affordable} within the ${cap}-micro cap`);
  const evs = pricingEvents();
  for (const { e, d } of refused) {
    if (!/^(\[SIMULATED\] )?Refused x402 payment for .*would exceed the pricing budget/.test(e.message)) throw new Error(`unexpected refusal message: ${e.message}`);
    if (d.refused !== true || BigInt(String(d.remainingUsdMicros)) >= X402_QUOTE_MICROS) throw new Error(`refusal data wrong: ${e.dataJson}`);
    // Refused before paying: no "Paying ..." step and no payment row for that item, and it was still priced.
    if (evs.some(x => x.e.refId === e.refId && x.d.outcome === "paying")) throw new Error(`item ${e.refId}: refused, but a "paying" step was logged for it`);
    if (pays.some(p => p.refTable === "item" && p.refId === e.refId)) throw new Error(`item ${e.refId}: refused, but has an x402 payment row`);
    if (!evs.some(x => x.e.refId === e.refId && x.e.kind === "tool_call" && x.d.fallback === true && x.d.refused === true)) throw new Error(`item ${e.refId}: no direct-lookup fallback after the refusal`);
    expectedErrors.add(e.id);
  }
  return { detail: `${settled.length} paid (${total} of ${cap} micros), ${refused.length} refused with no "paying" step or payment row, priced via direct lookup` };
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
  // The planted demo scam (fixtures/deals.json, "planted": true) rides along on "Desk chair".
  const chair = [...conn!.db.shoppingItem.iter()].find(s => me && s.owner.isEqual(me) && s.name.toLowerCase() === "desk chair");
  const planted = chair && deals.find(d => d.shoppingItemId === chair.id && d.sellerInfo.startsWith("Planted demo scam"));
  if (chair && !planted) throw new Error(`no planted demo scam deal on "Desk chair"`);
  if (planted && (!/sample data$/.test(planted.sellerInfo) || planted.fraudScore < FRAUD_BLOCK)) throw new Error(`planted demo scam: ${planted.fraudScore.toFixed(2)}, "${planted.sellerInfo}"`);
  const plantedNote = planted ? `; planted demo scam scored ${planted.fraudScore.toFixed(2)}` : "";
  return { detail: `${deals.length} deals, ${flagged.length} flagged >= 0.3${flagged[0] ? ` (e.g. "${flagged[0].title}": ${flagged[0].fraudReasons.join("; ")})` : ""}${plantedNote}` };
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

// Shared by the two Visa guardrail stages: a refused purchase gets no approval request and no charge.
const myDeals = () => [...conn!.db.deal.iter()].filter(d => me && d.owner.isEqual(me));
const openItems = () => [...conn!.db.shoppingItem.iter()].filter(s => me && s.owner.isEqual(me) && s.status === "found" && s.chosenDealId === 0n);
const cardRemainingCents = () => {
  const spent = [...conn!.db.payment.iter()]
    .filter(p => p.rail === "visa" && p.agent === "buy" && (p.status === "pending" || p.status === "settled"))
    .reduce((a, p) => a + p.amountUsdMicros / 10_000n, 0n);
  return BigInt(Math.round(Number(VISA_CAP_USD) * 100)) - spent;
};
async function expectBlocked(dealId: bigint, why: RegExp): Promise<string> {
  const ev = await until(`buy agent refusing deal ${dealId}`, () =>
    [...conn!.db.agentEvent.iter()].find(e => e.agent === "buy" && e.refTable === "deal" && e.refId === dealId && e.kind === "error" && e.message.startsWith("Not buying")), 30_000);
  if (!why.test(ev.message)) throw new Error(`refused for the wrong reason: ${ev.message}`);
  const ap = [...conn!.db.approval.iter()].find(a => a.kind === "purchase" && a.refId === dealId);
  if (ap) throw new Error(`a purchase approval (${ap.status}) was requested for the refused deal`);
  const pay = [...conn!.db.payment.iter()].find(p => p.rail === "visa" && p.refId === dealId);
  if (pay) throw new Error(`a Visa payment row (${pay.status}) exists for the refused deal`);
  expectedErrors.add(ev.id);
  return ev.message;
}

const capItem = await stage(`visa guardrail: over the $${VISA_CAP_USD} buy card budget -> refused, no approval/charge`, async () => {
  const left = cardRemainingCents();
  const open = new Set(openItems().map(s => s.id));
  const deal = myDeals()
    .filter(d => open.has(d.shoppingItemId) && CARD_CHECKOUT_SOURCES.has(d.source) && d.fraudScore >= 0 && d.fraudScore < FRAUD_BLOCK && d.priceCents > left)
    .sort((a, b) => Number(b.priceCents - a.priceCents))[0];
  if (!deal) throw new Error(`no screened card deal over the remaining $${Number(left) / 100} to test with`);
  await conn!.reducers.chooseDeal({ shoppingItemId: deal.shoppingItemId, dealId: deal.id });
  const msg = await expectBlocked(deal.id, /would exceed the buy card budget/);
  if (cardRemainingCents() !== left) throw new Error(`card budget moved from ${left} to ${cardRemainingCents()} cents`);
  return { detail: `$${Number(left) / 100} left: ${msg.replace(/^Not buying /, "")}`, value: deal.shoppingItemId };
});

await stage(`visa guardrail: fraud-flagged card deal (>= ${FRAUD_BLOCK}) -> refused, no approval/charge`, async () => {
  // No fixture deal scores that high, so plant one with the classic scam script through the worker
  // identity (add_deal is worker-only) and let the real fraud screen score it.
  const token = readFileSync(`.worker-token.${DB}`, "utf8").trim();
  const w = await connectAs(token, false);
  const item = openItems().find(s => s.id !== capItem);
  if (!item) throw new Error("no open shopping item left to plant a deal on");
  const left = cardRemainingCents();
  const priceCents = 4999n;
  if (priceCents > left) throw new Error(`only $${Number(left) / 100} of card budget left, the planted deal would trip the cap instead`);
  const url = `https://example.invalid/e2e-planted-scam/${item.id}`;
  try {
    await w.conn.reducers.addDeal({
      shoppingItemId: item.id, source: "target", title: `${item.name}, brand new in box, Zelle only`,
      priceCents, url, sellerInfo: "Target · new · ships · Visa checkout",
    });
  } finally {
    w.conn.disconnect();
  }
  const deal = await until("planted deal fraud-screened", () => myDeals().find(d => d.url === url && d.fraudScore >= 0), 30_000);
  if (deal.fraudScore < FRAUD_BLOCK) throw new Error(`fraud screen scored the planted scam ${deal.fraudScore.toFixed(2)} (${deal.fraudReasons.join("; ")}), want >= ${FRAUD_BLOCK}`);
  await conn!.reducers.chooseDeal({ shoppingItemId: item.id, dealId: deal.id });
  const msg = await expectBlocked(deal.id, /fraud screen scored it/);
  return { detail: msg.replace(/^Not buying /, "").slice(0, 160) };
});

await stage("spending log: payment rows complete + simulated, [SIMULATED] events", async () => {
  const pays = [...conn!.db.payment.iter()].filter(p => me && p.owner.isEqual(me));
  const rails = new Set(pays.map(p => p.rail));
  if (!rails.has("x402") || !rails.has("visa")) throw new Error(`want both rails in the log, got ${[...rails].join(", ") || "none"}`);
  const bad = pays.filter(p =>
    !p.agent || !p.purpose || !["x402", "visa"].includes(p.rail) || p.amountUsdMicros <= 0n ||
    !["pending", "settled", "failed"].includes(p.status) || p.simulated !== true ||
    (p.rail === "visa" ? !p.txHash.startsWith("sim_") : p.payee !== "simulated"));
  if (bad.length) throw new Error(`${bad.length} bad payment row(s): ${bad.slice(0, 3).map(p => JSON.stringify({ agent: p.agent, rail: p.rail, amount: String(p.amountUsdMicros), status: p.status, simulated: p.simulated, payee: p.payee, txHash: p.txHash })).join(" ")}`);
  if (pays.some(p => p.status === "pending")) throw new Error("a payment is still pending after checkout finished");
  // Every money step on a rail, of any kind: payments, "Paying ..." tool calls, refusals,
  // failures and Visa's "Not charging yet" approval waits.
  const railEvents = [...conn!.db.agentEvent.iter()]
    .filter(e => me && e.owner.isEqual(me))
    .map(e => ({ e, d: parseData(e.dataJson) }))
    .filter(({ d }) => d.rail === "x402" || d.rail === "visa");
  const unlabeled = railEvents.filter(({ e, d }) => d.simulated !== true || !e.message.startsWith("[SIMULATED] "));
  if (unlabeled.length) throw new Error(`${unlabeled.length} rail event(s) not labeled simulated: ${unlabeled.slice(0, 3).map(x => x.e.message).join(" | ")}`);
  const kinds = new Map<string, number>();
  for (const { e } of railEvents) kinds.set(e.kind, (kinds.get(e.kind) ?? 0) + 1);
  if (!railEvents.some(({ e, d }) => d.rail === "x402" && e.kind === "error" && d.refused === true)) throw new Error("no x402 refusal event to check (the budget stage should have made one)");
  const by = (r: string) => pays.filter(p => p.rail === r).map(p => p.status).join("/");
  const kindList = [...kinds].map(([k, n]) => `${n} ${k}`).join(", ");
  return { detail: `${pays.length} rows (x402 ${by("x402")}; visa ${by("visa")}), all simulated; ${railEvents.length} rail events (${kindList}), all "[SIMULATED] ..."` };
});

await stage("share: second phone joins by code, sees items, edits sync back", async () => {
  if (!conn || !me) throw new Error("not connected");
  const myRoom = [...conn.db.myRoom.iter()].find(r => r.name === "E2E Bedroom");
  if (!myRoom) throw new Error("owner's my_room view has no E2E Bedroom");
  const second = await new Promise<{ conn: DbConnection; identity: Identity }>((resolve, reject) => {
    DbConnection.builder()
      .withUri(URI)
      .withDatabaseName(DB)
      .onConnect((c, identity) => {
        c.subscriptionBuilder()
          .onApplied(() => resolve({ conn: c, identity }))
          .onError(ctx => reject(ctx.event ?? new Error("subscription failed")))
          .subscribe([tables.myRoom, tables.item, tables.roomMember]);
      })
      .onConnectError((_ctx, err) => reject(err))
      .build();
  });
  try {
    await second.conn.reducers.joinRoom({ code: myRoom.joinCode.toLowerCase() }); // codes are case-insensitive
    await until("room in the second phone's my_room", () => [...second.conn.db.myRoom.iter()].find(r => r.id === myRoom.id), 15_000);
    const theirs = [...second.conn.db.item.iter()].filter(i => i.roomId === myRoom.id);
    const target = theirs.find(i => i.disposition === "keep");
    if (!target) throw new Error(`second phone sees ${theirs.length} items, none kept`);
    await second.conn.reducers.setDisposition({ itemId: target.id, disposition: "donate" });
    await until("owner sees the member's edit", () => {
      const it = conn!.db.item.id.find(target.id);
      return it && it.disposition === "donate" && it.dispositionSource === "user" ? it : undefined;
    }, 15_000);
    return { detail: `joined with ${myRoom.joinCode}, sees ${theirs.length} items; member set "${target.name}" to donate, owner saw it` };
  } finally {
    second.conn.disconnect();
  }
});

await stage("vision: a photographed item gets identified (Claude, replayed)", async () => {
  if (!conn || !me) throw new Error("not connected");
  const room = [...conn.db.myRoom.iter()].find(r => r.name === "E2E Bedroom")!;
  await conn.reducers.addItem({
    roomId: room.id,
    object: { scanObjectId: "e2e-vision", name: "", category: "table", widthM: 1.2, heightM: 0.75, depthM: 0.6, photoUrl: "" },
  });
  const it = await until("new item", () => items().find(i => i.scanObjectId === "e2e-vision"), 10_000);
  // A user choice, so sort never overrides it and no listing (another Claude call) follows.
  await conn.reducers.setDisposition({ itemId: it.id, disposition: "keep" });
  const res = await fetch(`http://localhost:${PORT}/upload`, { method: "POST", headers: { "content-type": "image/png" }, body: new Uint8Array(roomPhoto()) });
  if (!res.ok) throw new Error(`upload: HTTP ${res.status}`);
  const { url } = (await res.json()) as { url: string };
  await conn.reducers.addItemPhoto({ itemId: it.id, url });
  const done = await until("vision done/failed", () => {
    const x = conn!.db.item.id.find(it.id);
    return x && (x.detailsStatus === "done" || x.detailsStatus === "failed") ? x : undefined;
  }, 90_000);
  if (done.detailsStatus !== "done") {
    const err = [...conn.db.agentEvent.iter()].filter(e => e.agent === "vision" && e.kind === "error" && e.refId === it.id).pop();
    throw new Error(`vision ${done.detailsStatus}: ${err?.message ?? "?"}`);
  }
  // Renamed by vision -> pricing runs again, and the guardrail stage already spent the x402 budget,
  // so its refusal (or "no cached comps") is expected for this item.
  await until("its pricing settled", () => {
    const x = conn!.db.item.id.find(it.id);
    return x && x.pricingStatus !== "pending" && x.pricingStatus !== "running" ? x : undefined;
  }, 30_000).catch(() => undefined);
  for (const e of conn.db.agentEvent.iter()) {
    if (e.refId === it.id && e.agent === "pricing" && e.kind === "error" && /pricing budget|no cached comps/.test(e.message)) expectedErrors.add(e.id);
  }
  return { detail: `"${done.name}" (${done.category}; ${done.material || "no material"}; ${done.condition})` };
});

await stage("agent log: no unexpected errors", async () => {
  const evs = [...conn!.db.agentEvent.iter()].filter(e => me && e.owner.isEqual(me));
  // Expected noise: spend-cap refusals are designed behavior; transient retries recover.
  // No APIFY_TOKEN in a test run, so items the sweep adds or renames have no cached comps: expected.
  // The guardrail stages' refusals are expected too (exactly the events they asserted).
  const errs = evs.filter(e => e.kind === "error" && !expectedErrors.has(e.id) && !/retrying in|Spend cap|APIFY_TOKEN not set and no cached comps/.test(e.message));
  if (errs.length) throw new Error(`${errs.length} error event(s): ${errs.slice(0, 3).map(e => `[${e.agent}] ${e.message.slice(0, 100)}`).join(" | ")}`);
  const agents = [...new Set(evs.map(e => e.agent))].sort();
  return { detail: `${evs.length} events from ${agents.join(", ")}` };
});

// ---------- report ----------
conn?.disconnect();
if (worker && !KEEP) stopWorker(worker.child);
const pad = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s.padEnd(n));
console.log(`\nMoove E2E on ${URI}/${DB} (${MODES}) — ${Math.round((Date.now() - t0) / 1000)}s`);
console.log(`${pad("stage", 62)} ${pad("result", 6)} ${pad("time", 6)} detail`);
for (const r of rows) console.log(`${pad(r.stage, 62)} ${pad(r.ok ? "PASS" : "FAIL", 6)} ${pad(`${(r.ms / 1000).toFixed(1)}s`, 6)} ${r.detail}`);
const failed = rows.filter(r => !r.ok).length;
console.log(`\n${rows.length - failed}/${rows.length} passed${worker ? `; worker log: agents/${worker.log}` : ""}${KEEP ? " (worker left running: --keep)" : ""}`);
process.exit(failed ? 1 : 0);
