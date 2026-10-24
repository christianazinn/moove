// Health check for every Moove backend in one command. Connects to each database as an anonymous
// client (only public tables are read), then checks the worker the database says is live:
//   service_config (upload URL, worker version, start time), worker registration, row counts, the
//   newest agent_event, and GET <upload_base_url>/healthz.
// Usage (from agents/): npm run status [-- moove moove-demo] [-- --uri ws://localhost:3000]
// Defaults: maincloud, databases moove and moove-demo. Exits non-zero if any backend looks down.
import "./env.js";
import { DbConnection, tables } from "../src/module_bindings/index.js";

const args = process.argv.slice(2);
const uriArg = args.indexOf("--uri");
const URI = uriArg >= 0 ? args[uriArg + 1] : "wss://maincloud.spacetimedb.com";
const dbs = args.filter((a, i) => !a.startsWith("--") && args[i - 1] !== "--uri");
const DBS = dbs.length ? dbs : ["moove", "moove-demo"];

type Report = { db: string; ok: boolean; lines: string[] };

function ago(ms: number): string {
  const s = Math.round(ms / 1000);
  return s < 120 ? `${s}s ago` : s < 7200 ? `${Math.round(s / 60)}m ago` : `${Math.round(s / 3600)}h ago`;
}

async function check(db: string): Promise<Report> {
  const lines: string[] = [];
  let ok = true;
  const conn = await new Promise<DbConnection>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("connect timed out")), 20_000);
    DbConnection.builder()
      .withUri(URI)
      .withDatabaseName(db)
      .onConnect(c => {
        c.subscriptionBuilder()
          .onApplied(() => {
            clearTimeout(timer);
            resolve(c);
          })
          .onError(ctx => reject(ctx.event ?? new Error("subscription failed")))
          .subscribe([tables.serviceConfig, tables.worker, tables.item, tables.room, tables.agentEvent, tables.payment, tables.listing]);
      })
      .onConnectError((_ctx, err) => reject(err))
      .build();
  }).catch((err: unknown) => err as Error);
  if (conn instanceof Error) return { db, ok: false, lines: [`cannot connect: ${conn.message}`] };

  const cfg = (k: string) => conn.db.serviceConfig.key.find(k)?.value ?? "";
  const url = cfg("upload_base_url");
  const started = cfg("worker_started_at");
  lines.push(`worker: version ${cfg("worker_version") || "?"}, started ${started ? ago(Date.now() - Date.parse(started)) : "?"}; ${conn.db.worker.count()} registered`);
  if (!url) {
    ok = false;
    lines.push("upload_base_url: not announced (worker never started on this database, or it predates service_config)");
  } else {
    const t = Date.now();
    const res = await fetch(`${url}/healthz`, { signal: AbortSignal.timeout(15_000) }).catch((e: unknown) => e as Error);
    if (res instanceof Error || !res.ok) {
      ok = false;
      lines.push(`upload ${url}: DOWN (${res instanceof Error ? res.message : `HTTP ${res.status}`})`);
    } else lines.push(`upload ${url}: healthy (${Date.now() - t} ms)`);
  }
  const events = [...conn.db.agentEvent.iter()];
  const newest = events.reduce((m, e) => Math.max(m, Number(e.createdAt.toMillis())), 0);
  const errors = events.filter(e => e.kind === "error" && Date.now() - Number(e.createdAt.toMillis()) < 3600_000).length;
  lines.push(
    `data: ${conn.db.room.count()} rooms, ${conn.db.item.count()} items, ${conn.db.listing.count()} listings, ${conn.db.payment.count()} payments, ` +
      `${events.length} agent events (newest ${newest ? ago(Date.now() - newest) : "never"}, ${errors} errors in the last hour)`
  );
  conn.disconnect();
  return { db, ok, lines };
}

let down = 0;
for (const db of DBS) {
  const r = await check(db);
  if (!r.ok) down++;
  console.log(`${r.ok ? "UP  " : "DOWN"} ${URI.replace(/^wss?:\/\//, "")}/${db}`);
  for (const l of r.lines) console.log(`     ${l}`);
}
process.exit(down ? 1 : 0);
