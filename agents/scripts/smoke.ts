// Phone's-eye smoke test of one backend: what a judge's phone would do with a join code.
// It connects as a test user (token in agents/.user-token.smoke.<db>, so re-runs are the same
// member), joins the room by code, then checks:
//   - the room shows up in my_room with its items, and every item is priced and sorted
//   - the worker's announced upload URL accepts a photo and serves it back (tunnel + upload path)
//   - room and user are private (#41): a direct subscription to them is refused
// No Claude, Apify or payments: nothing is added to any item. Prints PASS/FAIL lines and exits
// non-zero on a failure.
// Usage (from agents/): npm run smoke -- <db> <join code> [--uri ws://localhost:3000]
//   e.g. npm run smoke -- moove-demo 4RZ9G8
import "./env.js";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { DbConnection } from "../src/module_bindings/index.js";

const args = process.argv.slice(2);
const uriArg = args.indexOf("--uri");
const URI = uriArg >= 0 ? args[uriArg + 1] : "wss://maincloud.spacetimedb.com";
const [DB, CODE] = args.filter((a, i) => !a.startsWith("--") && args[i - 1] !== "--uri");
if (!DB || !CODE) {
  console.error("usage: npm run smoke -- <db> <join code> [--uri ws://localhost:3000]");
  process.exit(2);
}
const tokenFile = `.user-token.smoke.${DB}`;

let failed = 0;
const report = (ok: boolean, what: string, detail: string) => {
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"} ${what}: ${detail}`);
};
const until = async <T>(fn: () => T | undefined, ms: number): Promise<T | undefined> => {
  for (const end = Date.now() + ms; Date.now() < end; await new Promise(r => setTimeout(r, 250))) {
    const v = fn();
    if (v) return v;
  }
  return undefined;
};

const conn = await new Promise<DbConnection>((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error("connect timed out")), 20_000);
  DbConnection.builder()
    .withUri(URI)
    .withDatabaseName(DB)
    .withToken(existsSync(tokenFile) ? readFileSync(tokenFile, "utf8").trim() : undefined)
    .onConnect((c, identity, token) => {
      writeFileSync(tokenFile, token);
      const me = `0x${identity.toHexString()}`;
      c.subscriptionBuilder()
        .onApplied(() => {
          clearTimeout(timer);
          resolve(c);
        })
        .onError(ctx => reject(ctx.event ?? new Error("subscription failed")))
        .subscribe([
          "SELECT * FROM my_room",
          "SELECT * FROM service_config",
          `SELECT * FROM item WHERE owner = ${me}`,
          `SELECT item.* FROM item JOIN room_member ON item.room_id = room_member.room_id WHERE room_member.member = ${me}`,
        ]);
    })
    .onConnectError((_ctx, err) => reject(err))
    .build();
}).catch((err: unknown) => {
  console.log(`FAIL connect ${URI}/${DB}: ${(err as Error)?.message ?? err}`);
  process.exit(1);
});
console.log(`smoke test of ${URI.replace(/^wss?:\/\//, "")}/${DB} with code ${CODE}`);

// 1. Join by code and see the room and its items.
try {
  await conn.reducers.joinRoom({ code: CODE });
} catch (err) {
  report(false, "join_room", String((err as Error)?.message ?? err));
}
const code = CODE.trim().toUpperCase();
const room = await until(() => [...conn.db.myRoom.iter()].find(r => r.joinCode === code), 15_000);
report(!!room, "join by code", room ? `"${room.name}" (room #${room.id}) is in my_room` : "no room with that code in my_room");
if (room) {
  const items = await until(() => {
    const got = [...conn.db.item.iter()].filter(i => i.roomId === room.id);
    return got.length ? got : undefined;
  }, 15_000) ?? [];
  report(items.length > 0, "items stream in", `${items.length} items`);
  const unpriced = items.filter(i => i.pricingStatus !== "done");
  report(items.length > 0 && unpriced.length === 0, "every item priced", unpriced.length ? `${unpriced.length} not done: ${unpriced.slice(0, 4).map(i => `${i.name} (${i.pricingStatus})`).join(", ")}` : `${items.length}/${items.length}, e.g. ${items[0] ? `${items[0].name} $${(Number(items[0].estValueCents) / 100).toFixed(0)}` : ""}`);
  const unsorted = items.filter(i => !i.disposition);
  const by = new Map<string, number>();
  for (const i of items) by.set(i.disposition || "none", (by.get(i.disposition || "none") ?? 0) + 1);
  report(items.length > 0 && unsorted.length === 0, "every item sorted", [...by].map(([k, n]) => `${n} ${k}`).join(", "));
}

// 2. The upload path the phone uses (worker's announced URL, through the tunnel).
const base = conn.db.serviceConfig.key.find("upload_base_url")?.value ?? "";
if (!base) report(false, "upload", "no upload_base_url in service_config");
else {
  try {
    const png = readFileSync(path.join("fixtures", "e2e", "room.png"));
    const up = await fetch(`${base}/upload`, { method: "POST", headers: { "content-type": "image/png" }, body: new Uint8Array(png), signal: AbortSignal.timeout(20_000) });
    const { url } = (await up.json()) as { url?: string };
    const back = url ? await fetch(url, { signal: AbortSignal.timeout(20_000) }) : undefined;
    report(up.status === 201 && !!back?.ok, "upload round trip", `${base}: POST ${up.status}, GET ${back?.status ?? "-"}`);
  } catch (err) {
    report(false, "upload round trip", `${base}: ${(err as Error)?.message ?? err}`);
  }
}

// 3. Privacy (#41): room and user can't be read directly. Asked over the HTTP SQL API as this
// user, so a still-public table can't trip the SDK's decoders.
const http = URI.replace(/^ws/, "http");
const token = readFileSync(tokenFile, "utf8").trim();
const open: string[] = [];
for (const t of ["room", "user"]) {
  const res = await fetch(`${http}/v1/database/${DB}/sql`, { method: "POST", headers: { authorization: `Bearer ${token}` }, body: `SELECT * FROM ${t}`, signal: AbortSignal.timeout(15_000) }).catch(() => undefined);
  if (res?.ok) open.push(t);
}
report(open.length === 0, "room/user private", open.length ? `a client can read ${open.join(", ")} (module predates #41 step 2?)` : "direct reads refused");

conn.disconnect();
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exit(failed ? 1 : 0);
