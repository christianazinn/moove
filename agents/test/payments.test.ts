import { test } from "node:test";
import assert from "node:assert/strict";
import { spacetimeSink } from "../src/payments.js";
import type { Conn } from "../src/spacetime.js";
import type { PaymentRecord } from "../src/integrations/x402.js";

const payment: PaymentRecord = {
  owner: "owner-identity",
  agent: "pricing",
  rail: "x402",
  purpose: "comps for 'chair'",
  payee: "0x1111111111111111111111111111111111111111",
  amountUsdMicros: 10_000n,
  txHash: "0xdeadbeef",
  status: "settled",
  simulated: false,
  refTable: "item",
  refId: 7n,
};

/** A fake SpacetimeDB connection: only the reducers the sink touches. */
function fakeConn(opts: { recordPayment: () => Promise<void>; logAgentEvent?: () => Promise<void> }) {
  const events: any[] = [];
  const conn = {
    reducers: {
      recordPayment: opts.recordPayment,
      logAgentEvent: (e: unknown) => {
        events.push(e);
        return opts.logAgentEvent ? opts.logAgentEvent() : Promise.resolve();
      },
    },
  } as unknown as Conn;
  return { conn, events };
}

/** Silences console.warn/log for the duration and returns what warn printed. */
async function quietly(fn: () => Promise<void>): Promise<string[]> {
  const lines: string[] = [];
  const { warn, log } = console;
  console.warn = (...args: unknown[]) => void lines.push(args.map(String).join(" "));
  console.log = () => {};
  try {
    await fn();
  } finally {
    console.warn = warn;
    console.log = log;
  }
  return lines;
}

test("recordPayment resolves after the reducer resolves", async () => {
  let called = 0;
  const { conn, events } = fakeConn({ recordPayment: async () => void called++ });
  await spacetimeSink(conn).recordPayment(payment);
  assert.equal(called, 1);
  assert.equal(events.length, 0);
});

test("a rejected record_payment is awaited, swallowed, and logged with the tx hash", async () => {
  const { conn, events } = fakeConn({
    recordPayment: () => Promise.reject(new Error("caller is not the registered worker")),
  });
  const warned = await quietly(() => assert.doesNotReject(spacetimeSink(conn).recordPayment(payment)));
  assert.ok(warned.some((l) => l.includes("0xdeadbeef") && l.includes("caller is not the registered worker")));
  assert.equal(events.length, 1);
  assert.equal(events[0].kind, "error");
  assert.equal(events[0].agent, "pricing");
  assert.equal(events[0].refId, 7n);
  assert.match(events[0].dataJson, /0xdeadbeef/);
});

test("recordPayment still resolves when the error event can't be written either", async () => {
  const { conn } = fakeConn({
    recordPayment: () => Promise.reject(new Error("db down")),
    logAgentEvent: () => {
      throw new Error("still down");
    },
  });
  const warned = await quietly(() => assert.doesNotReject(spacetimeSink(conn).recordPayment(payment)));
  assert.ok(warned.some((l) => l.includes("0xdeadbeef")));
});
