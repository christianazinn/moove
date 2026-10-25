import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";

// visaCheckout(conn) seeds the card budget from the last 24h of payment rows, per agent and user, so
// a restart doesn't reset anyone's cap and one user's spend never counts against another's. Own file:
// the checkout is a per-process singleton. Simulated backend, no network.
process.env.VISA_PROVIDER = "simulated";
process.env.VISA_SIM_DELAY_MS = "0";
process.env.VISA_SPEND_CAP_USD = "100";
process.env.VISA_MAX_PER_PURCHASE_USD = "80";
delete process.env.VISA_SEED_BUDGETS;
const { visaCheckout } = await import("../src/checkout.js");

const id = (hex: string) => ({ toHexString: () => hex, isEqual: (o: { toHexString(): string }) => o.toHexString() === hex });
const alice = id("c200aa");
const bob = id("c200bb");
const carol = id("c200cc");
const now = Date.now();
let nextId = 1n;
const pay = (owner: unknown, usd: number, o: Record<string, unknown> = {}) => ({
  id: nextId++,
  owner,
  agent: "buy",
  rail: "visa",
  status: "settled",
  simulated: false, // Visa sandbox rows: the card rail on the hosted worker, so they count
  amountUsdMicros: BigInt(usd * 1_000_000),
  createdAt: { toMillis: () => now - 3600_000 },
  ...o,
});
const payments = [
  pay(alice, 60),
  pay(alice, 30, { status: "pending" }),
  pay(alice, 50, { status: "failed" }), // released, doesn't count
  pay(alice, 50, { createdAt: { toMillis: () => now - 25 * 3600_000 } }), // older than 24h
  pay(bob, 20),
  pay(bob, 70, { simulated: true }), // simulated rehearsal, never counts
  pay(bob, 10, { rail: "x402" }),
];
const conn = { db: { payment: { iter: () => payments[Symbol.iterator]() } }, reducers: {} } as unknown as Conn;

test("seeds each user's own card budget from their pending/settled sandbox payments of the last 24h", () => {
  const visa = visaCheckout(conn);
  assert.equal(visa.remaining("buy", alice), 1_000n);
  assert.equal(visa.remaining("buy", bob), 8_000n);
  assert.equal(visa.remaining("buy", carol), 10_000n, "a user with no payments has the whole cap");
  assert.match(visa.spendBlocker("buy", alice, 2_000n)!, /would exceed the buy card budget/);
  assert.equal(visa.spendBlocker("buy", carol, 8_000n), undefined);
  assert.match(visa.spendBlocker("buy", carol, 8_001n)!, /per-purchase max/);
});
