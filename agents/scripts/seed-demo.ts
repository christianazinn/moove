// Demo safety net: seeds a realistic college-student bedroom (scripts/demo-room.ts) through the same
// app reducers the iOS app calls (register_user, import_scan, set_sentimental), connected as a NORMAL
// user, not the worker. A running worker then prices every item from the committed comps caches
// ([REPLAYED], no Apify calls). Items have no photos, so vision (Claude) never runs on them.
//
// Skips if this user already has a "Bedroom" (prints its join code) unless --force, which imports another.
// --wait[=SEC] waits (default 90s) for the worker to price the items and prints the estimates.
// The user's token lives in .user-token.<db> (SEED_USER_TOKEN_FILE overrides), so re-runs are the same user.
// Refuses a maincloud URI unless --maincloud is passed.
// Usage (from agents/): npm run seed:demo [-- --force] [-- --wait] [-- --maincloud]
import "./env.js";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import type { Identity } from "spacetimedb";
import { DbConnection, tables } from "../src/module_bindings/index.js";
import type { Item, Room } from "../src/module_bindings/types.js";
import { config } from "../src/config.js";
import { DEMO_HOME, DEMO_OBJECTS, DEMO_ROOM_NAME, demoQuery } from "./demo-room.js";

const force = process.argv.includes("--force");
const waitArg = process.argv.find((a) => a === "--wait" || a.startsWith("--wait="));
const waitSec = waitArg ? Number(waitArg.split("=")[1] ?? 90) : 0;
if (!Number.isFinite(waitSec) || waitSec < 0) {
  console.error(`bad ${waitArg}: use --wait or --wait=SEC`);
  process.exit(1);
}
// .env.example points SPACETIME_URI at maincloud, so a bare run from a copied .env.local would write the
// live demo database. Seeding it takes an explicit --maincloud.
if (/maincloud/i.test(config.spacetimeUri) && !process.argv.includes("--maincloud")) {
  console.error(`refusing to seed ${config.spacetimeUri} without --maincloud (set SPACETIME_URI=ws://localhost:3000 for a local DB)`);
  process.exit(1);
}
const tokenFile = process.env.SEED_USER_TOKEN_FILE || `.user-token.${config.spacetimeDb}`;
const dollars = (c: bigint) => `$${(Number(c) / 100).toFixed(0)}`;

async function waitFor<T>(what: string, get: () => T | undefined, timeoutMs = 15_000): Promise<T> {
  const start = Date.now();
  for (;;) {
    const v = get();
    if (v !== undefined) return v;
    if (Date.now() - start > timeoutMs) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 200));
  }
}

const { conn, identity } = await new Promise<{ conn: DbConnection; identity: Identity }>((resolve, reject) => {
  DbConnection.builder()
    .withUri(config.spacetimeUri)
    .withDatabaseName(config.spacetimeDb)
    .withToken(existsSync(tokenFile) ? readFileSync(tokenFile, "utf8").trim() : undefined)
    .onConnect((conn, identity, token) => {
      writeFileSync(tokenFile, token);
      conn
        .subscriptionBuilder()
        .onApplied(() => resolve({ conn, identity }))
        .onError((ctx) => reject(ctx.event ?? new Error("subscription failed")))
        .subscribe([tables.room, tables.item, tables.user]);
    })
    .onConnectError((_ctx, err) => reject(err))
    .build();
});
console.log(`connected to ${config.spacetimeUri} / ${config.spacetimeDb} as user ${identity.toHexString()} (token: agents/${tokenFile})`);

const myBedrooms = () => [...conn.db.room.iter()].filter((r) => r.owner.isEqual(identity) && r.name === DEMO_ROOM_NAME && r.home === DEMO_HOME);
const itemsIn = (room: Room) => [...conn.db.item.iter()].filter((it) => it.roomId === room.id);

function printItems(room: Room): void {
  for (const it of itemsIn(room).sort((a, b) => Number(a.id - b.id))) {
    const price = it.pricingStatus === "done" ? `${dollars(it.estValueCents)} (${dollars(it.estLowCents)}-${dollars(it.estHighCents)})` : it.pricingStatus;
    console.log(`  #${it.id} ${it.name.padEnd(26)} ${it.category.padEnd(12)} ${price}${it.maybeSentimental ? "  [sentimental]" : ""}`);
  }
}

let failed = false;
try {
  const existing = myBedrooms();
  let room: Room;
  if (existing.length && !force) {
    room = existing.reduce((a, b) => (b.id > a.id ? b : a)); // newest; iter() order isn't by id
    console.log(`\nAlready seeded: "${room.name}" (room #${room.id}, ${itemsIn(room).length} items). Use --force to import another.`);
  } else {
    if (!conn.db.user.identity.find(identity)) await conn.reducers.registerUser({ auth0Sub: "", name: "Demo Student", email: "demo@moove.app" });
    const before = new Set(existing.map((r) => r.id));
    await conn.reducers.importScan({
      roomName: DEMO_ROOM_NAME,
      home: DEMO_HOME,
      usdzUrl: "",
      capturedRoomJsonUrl: "",
      objects: DEMO_OBJECTS.map(({ sentimental: _s, ...o }) => o),
    });
    room = await waitFor("the new room", () => myBedrooms().find((r) => !before.has(r.id)));
    await waitFor("its items", () => (itemsIn(room).length >= DEMO_OBJECTS.length ? true : undefined));
    for (const o of DEMO_OBJECTS.filter((o) => o.sentimental)) {
      const find = () => itemsIn(room).find((i) => i.scanObjectId === o.scanObjectId);
      // Let a running worker price it first: an update that lands while the item still reads `pending`
      // can make the pricing agent price it twice. No worker within 20s means no race, so flag it anyway.
      await waitFor("pricing before flagging", () => (["done", "failed"].includes(find()?.pricingStatus ?? "") ? true : undefined), 20_000).catch(() => {});
      const it = find();
      if (it) await conn.reducers.setSentimental({ itemId: it.id, value: true });
    }
    console.log(`\nSeeded "${room.name}" (room #${room.id}, home '${room.home}') with ${DEMO_OBJECTS.length} items.`);
  }
  console.log(`Join code: ${room.joinCode}   (in the app: join_room("${room.joinCode}"))`);

  if (waitSec > 0) {
    console.log(`\nWaiting up to ${waitSec}s for the worker to price them...`);
    const settled = (it: Item) => it.pricingStatus === "done" || it.pricingStatus === "failed";
    try {
      await waitFor("pricing", () => (itemsIn(room).every(settled) ? true : undefined), waitSec * 1000);
    } catch {
      console.warn("Not all items priced yet. Is the worker running against this database?");
      failed = true;
    }
  }
  printItems(room);
  if (!waitSec) console.log(`Queries the pricing agent will run: ${DEMO_OBJECTS.map(demoQuery).join(" | ")}`);
} catch (err) {
  console.error("seed failed:", (err as Error).message ?? err);
  failed = true;
} finally {
  conn.disconnect();
}
process.exit(failed ? 1 : 0);
