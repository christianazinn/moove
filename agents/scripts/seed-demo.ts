// Demo safety net: seeds a realistic college-student bedroom (scripts/demo-room.ts) through the same
// app reducers the iOS app calls (register_user, import_scan, set_sentimental), connected as a NORMAL
// user, not the worker. A running worker then prices every item from the committed comps caches
// ([REPLAYED], no Apify calls). Items have no photos, so vision (Claude) never runs on them.
//
// SEED_COMMERCE=1 also seeds the commerce story (DEMO_COMMERCE_OBJECTS: a Herman Miller chair set to sell,
// which the listing agent drafts over the $100 threshold and asks approval for). On an already-seeded
// Bedroom it adds just the missing commerce items, so the join code stays the same. Off by default: the
// listing draft is a live Claude call on a maincloud worker.
//
// --reset-commerce (implies SEED_COMMERCE=1) makes the commerce story single-use-proof: it denies the
// chair's pending listing approval, deletes the chair and seeds it again, so the listing agent drafts a
// fresh listing that waits for approval. It waits for that approval and prints its id. The join code
// doesn't change. COST: one live Claude listing draft (MODEL_AGENT, Opus) per reset on a maincloud worker,
// since the worker refuses LLM_REPLAY there. A user can't re-open the old listing (see planCommerceReset).
//
// Skips if this user already has a "Bedroom" (prints its join code) unless --force, which imports another.
// --wait[=SEC] waits (default 90s) for the worker to price the items and prints the estimates.
// The user's token lives in .user-token.<db> (SEED_USER_TOKEN_FILE overrides), so re-runs are the same user.
// Refuses a maincloud URI unless --maincloud is passed.
// Usage (from agents/): npm run seed:demo [-- --force] [-- --wait] [-- --maincloud] [-- --reset-commerce] [-- --help]
import "./env.js";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import type { Identity } from "spacetimedb";
import { DbConnection, tables } from "../src/module_bindings/index.js";
import type { Item, Room } from "../src/module_bindings/types.js";
import { config } from "../src/config.js";
import { DEMO_COMMERCE_OBJECTS, DEMO_HOME, DEMO_OBJECTS, DEMO_ROOM_NAME, demoQuery, freshCommerceApproval, planCommerceReset } from "./demo-room.js";

const HELP = `npm run seed:demo -- [options]   (from agents/; SPACETIME_URI + SPACETIME_DB_NAME pick the DB)
  --maincloud        required for a maincloud URI (the live demo DB)
  --wait[=SEC]       wait for the worker to price the items (default 90 s) and print the estimates
  --force            import another Bedroom (NEW join code: every doc that quotes it breaks)
  --reset-commerce   re-arm the Herman Miller chair's approval beat in the existing Bedroom, same join code:
                     denies its pending listing approval, deletes the chair, adds it back and taps Sell, then
                     waits (--wait or 180 s) for the fresh pending approval and prints its id.
                     COST: one live Claude listing draft (MODEL_AGENT, ~1 Opus call, a few cents) per reset
                     on maincloud, counted in CLAUDE_MAX_USD_PER_DAY. Pricing replays (no Apify).
  SEED_COMMERCE=1    also seed the chair (one live Claude listing draft on maincloud)
  e.g. SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_DB_NAME=moove-demo npm run seed:demo -- --maincloud --reset-commerce`;
if (process.argv.includes("--help") || process.argv.includes("-h")) {
  console.log(HELP);
  process.exit(0);
}

const force = process.argv.includes("--force");
const resetCommerce = process.argv.includes("--reset-commerce");
if (force && resetCommerce) {
  console.error("--reset-commerce keeps the existing room and join code; don't combine it with --force");
  process.exit(1);
}
const commerce = process.env.SEED_COMMERCE === "1" || resetCommerce;
const objects = commerce ? [...DEMO_OBJECTS, ...DEMO_COMMERCE_OBJECTS] : DEMO_OBJECTS;
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
        .subscribe([tables.myRoom, tables.item, tables.myUser, tables.listing, tables.approval]);
    })
    .onConnectError((_ctx, err) => reject(err))
    .build();
});
console.log(`connected to ${config.spacetimeUri} / ${config.spacetimeDb} as user ${identity.toHexString()} (token: agents/${tokenFile})`);

const myBedrooms = () => [...conn.db.myRoom.iter()].filter((r) => r.owner.isEqual(identity) && r.name === DEMO_ROOM_NAME && r.home === DEMO_HOME);
const itemsIn = (room: Room) => [...conn.db.item.iter()].filter((it) => it.roomId === room.id);

function printItems(room: Room): void {
  for (const it of itemsIn(room).sort((a, b) => Number(a.id - b.id))) {
    const price = it.pricingStatus === "done" ? `${dollars(it.estValueCents)} (${dollars(it.estLowCents)}-${dollars(it.estHighCents)})` : it.pricingStatus;
    console.log(`  #${it.id} ${it.name.padEnd(26)} ${it.category.padEnd(12)} ${price.padEnd(16)} ${it.disposition}${it.maybeSentimental ? "  [sentimental]" : ""}`);
    for (const l of conn.db.listing.iter()) {
      if (l.itemId !== it.id) continue;
      const appr = [...conn.db.approval.iter()].filter((a) => a.kind === "listing" && a.refId === l.id).map((a) => a.status);
      console.log(`      listing #${l.id} "${l.title}" ${dollars(l.priceCents)} ${l.status}${appr.length ? ` (approval ${appr.join(", ")})` : ""}`);
    }
  }
}

// What the seed does as the user once an object is imported: flag it sentimental, or tap Sell.
async function applyUserEdits(room: Room, objs: typeof objects): Promise<void> {
  for (const o of objs.filter((o) => o.sentimental || o.sell)) {
    const find = () => itemsIn(room).find((i) => i.scanObjectId === o.scanObjectId);
    // Let a running worker price it first: an update that lands while the item still reads `pending`
    // can make the pricing agent price it twice. No worker within 20s means no race, so edit it anyway.
    await waitFor("pricing before editing", () => (["done", "failed"].includes(find()?.pricingStatus ?? "") ? true : undefined), 20_000).catch(() => {});
    const it = find();
    if (!it) continue;
    if (o.sentimental) await conn.reducers.setSentimental({ itemId: it.id, value: true });
    if (o.sell) await conn.reducers.setDisposition({ itemId: it.id, disposition: "sell" });
  }
}

let failed = false;
let resetDeleted: bigint[] = [];
try {
  const existing = myBedrooms();
  let room: Room;
  // A reset that found no room would import a new one with a new join code: exactly what it's meant to avoid.
  if (resetCommerce && !existing.length) throw new Error(`no "${DEMO_ROOM_NAME}" for this seed user (agents/${tokenFile}) to reset; seed it first`);
  if (existing.length && !force) {
    room = existing.reduce((a, b) => (b.id > a.id ? b : a)); // newest; iter() order isn't by id
    console.log(`\nAlready seeded: "${room.name}" (room #${room.id}, ${itemsIn(room).length} items). Use --force to import another.`);
    if (resetCommerce) {
      const plan = planCommerceReset(room.id, identity.toHexString(), conn.db.item.iter(), conn.db.listing.iter(), conn.db.approval.iter());
      for (const approvalId of plan.deny) {
        await conn.reducers.decideApproval({ approvalId, status: "denied" });
        console.log(`Reset: denied pending listing approval #${approvalId}`);
      }
      if (plan.inFlight.length) console.warn(`Reset: listing(s) ${plan.inFlight.map((id) => `#${id}`).join(", ")} are mid-post; they finish posting (simulated) on their own.`);
      for (const itemId of plan.deleteItemIds) {
        const name = conn.db.item.id.find(itemId)?.name ?? "(commerce item)";
        await conn.reducers.deleteItem({ itemId });
        console.log(`Reset: deleted #${itemId} ${name}`);
      }
      resetDeleted = plan.deleteItemIds;
      await waitFor("the reset", () => (itemsIn(room).some((i) => resetDeleted.includes(i.id)) ? undefined : true));
    }
    const missing = commerce ? DEMO_COMMERCE_OBJECTS.filter((o) => !itemsIn(room).some((i) => i.scanObjectId === o.scanObjectId)) : [];
    for (const { sentimental: _s, sell: _sell, ...o } of missing) await conn.reducers.addItem({ roomId: room.id, object: o });
    if (missing.length) {
      await waitFor("the commerce items", () => (missing.every((o) => itemsIn(room).some((i) => i.scanObjectId === o.scanObjectId)) ? true : undefined));
      await applyUserEdits(room, missing);
      console.log(`Added ${missing.length} commerce item(s) (SEED_COMMERCE=1): ${missing.map((o) => o.name).join(", ")}`);
    }
  } else {
    if (conn.db.myUser.count() === 0n) await conn.reducers.registerUser({ auth0Sub: "", name: "Demo Student", email: "demo@moove.app" });
    const before = new Set(existing.map((r) => r.id));
    await conn.reducers.importScan({
      roomName: DEMO_ROOM_NAME,
      home: DEMO_HOME,
      usdzUrl: "",
      capturedRoomJsonUrl: "",
      objects: objects.map(({ sentimental: _s, sell: _sell, ...o }) => o),
    });
    room = await waitFor("the new room", () => myBedrooms().find((r) => !before.has(r.id)));
    await waitFor("its items", () => (itemsIn(room).length >= objects.length ? true : undefined));
    await applyUserEdits(room, objects);
    console.log(`\nSeeded "${room.name}" (room #${room.id}, home '${room.home}') with ${objects.length} items${commerce ? " (incl. SEED_COMMERCE=1)" : ""}.`);
  }
  console.log(`Join code: ${room.joinCode}   (in the app: join_room("${room.joinCode}"))`);

  if (resetCommerce) {
    // The worker prices the new chair (replay), the listing agent drafts it (one live Claude call on
    // maincloud) and, over the $100 threshold, asks for approval.
    const sec = waitSec || 180;
    console.log(`\nWaiting up to ${sec}s for the listing agent to draft the chair and ask for approval (one Claude call)...`);
    const fresh = () => freshCommerceApproval(room.id, identity.toHexString(), resetDeleted, conn.db.item.iter(), conn.db.listing.iter(), conn.db.approval.iter());
    try {
      const a = await waitFor("a fresh listing approval", fresh, sec * 1000);
      console.log(`Reset done: approval #${a.id} pending (${a.summary}). Join code ${room.joinCode} (unchanged).`);
    } catch {
      console.warn("No fresh pending approval yet. Is the worker running? Check its log for the listing draft (a Claude error, or CLAUDE_MAX_USD_PER_DAY).");
      failed = true;
    }
  }

  if (waitSec > 0) {
    console.log(`\nWaiting up to ${waitSec}s for the worker to price them...`);
    const settled = (it: Item) => it.pricingStatus === "done" || it.pricingStatus === "failed";
    try {
      await waitFor("pricing", () => (itemsIn(room).every(settled) ? true : undefined), waitSec * 1000);
    } catch {
      console.warn("Not all items priced yet. Is the worker running against this database?");
      failed = true;
    }
    if (commerce) {
      // The listing agent drafts each sell item (a Claude call), then asks approval above the threshold.
      const sells = itemsIn(room).filter((it) => DEMO_COMMERCE_OBJECTS.some((o) => o.sell && o.scanObjectId === it.scanObjectId));
      const listed = (it: Item) => [...conn.db.listing.iter()].some((l) => l.itemId === it.id && l.status !== "draft");
      await waitFor("listings", () => (sells.every(listed) ? true : undefined), waitSec * 1000).catch(() => {
        console.warn("The commerce item has no listing past draft yet (the listing agent needs Claude; check the worker log).");
        failed = true;
      });
    }
  }
  printItems(room);
  if (!waitSec) console.log(`Queries the pricing agent will run: ${objects.map(demoQuery).join(" | ")}`);
} catch (err) {
  console.error("seed failed:", (err as Error).message ?? err);
  failed = true;
} finally {
  conn.disconnect();
}
process.exit(failed ? 1 : 0);
