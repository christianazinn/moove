import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";
import { keptItems, ruleBasedList } from "../src/agents/shopping.js";

// The shopping list subtracts what the user keeps. A shared room's items belong to its owner, so a
// member (a judge who joined the demo room) must still count them, as the app's new-home layout does.

const id = (hex: string) => ({ toHexString: () => hex, isEqual: (o: { toHexString(): string }) => o.toHexString() === hex });
const seed = id("seed");
const judge = id("judge");
const other = id("other");

const item = (n: number, owner: unknown, roomId: bigint, name: string, category: string, disposition = "keep") => ({ id: BigInt(n), owner, roomId, name, category, disposition });
const rows = {
  item: [
    item(1, seed, 10n, "Full size metal bed frame", "bed"),
    item(2, seed, 10n, "Floor lamp", "lamp"),
    item(3, seed, 10n, "Mini fridge", "appliance", "sell"),
    item(4, judge, 20n, "IKEA Micke desk", "desk"),
    item(5, other, 30n, "Sofa", "sofa"), // someone else's room the judge never joined
    item(6, other, 40n, "Area rug", "rug"), // in a room the judge owns, added by a member
  ],
  workerRoom: [
    { id: 10n, owner: seed },
    { id: 20n, owner: judge },
    { id: 30n, owner: other },
    { id: 40n, owner: judge },
  ],
  roomMember: [
    { id: 1n, roomId: 10n, member: judge },
    { id: 2n, roomId: 30n, member: seed },
  ],
};
const table = <T>(r: T[]) => ({ iter: () => r[Symbol.iterator]() });
const conn = { db: { item: table(rows.item), workerRoom: table(rows.workerRoom), roomMember: table(rows.roomMember) } } as unknown as Conn;

test("kept items include rooms the user owns or joined, not other people's rooms", () => {
  const names = keptItems(conn, judge as never).map(k => k.name).sort();
  assert.deepEqual(names, ["Area rug", "Floor lamp", "Full size metal bed frame", "IKEA Micke desk"]);
});

test("a room member's shopping list doesn't ask for what the shared room keeps", () => {
  const list = ruleBasedList([{ name: "Bedroom", kind: "bedroom" }, { name: "Living room", kind: "living" }], keptItems(conn, judge as never)).map(i => i.name);
  assert.ok(!list.includes("Bed frame"), "the kept bed frame covers the bedroom");
  assert.ok(!list.includes("Floor lamp"), "the kept lamp covers the living room");
  assert.ok(list.includes("Mattress"));
});

test("a user with no rooms keeps only their own items", () => {
  const loner = id("loner");
  assert.deepEqual(keptItems(conn, loner as never), []);
});
