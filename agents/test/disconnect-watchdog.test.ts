import { test } from "node:test";
import assert from "node:assert/strict";
import { disconnectWatchdog, exitAfterReconnect } from "../src/spacetime.js";

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

test("exits only if the connection stays down past the limit", async () => {
  let exits = 0;
  const w = disconnectWatchdog(() => exits++, 0.05);
  w.down();
  await sleep(20);
  w.up(); // reconnected in time
  await sleep(60);
  assert.equal(exits, 0);
  w.down();
  w.down(); // repeated disconnect events don't stack timers
  await sleep(80);
  assert.equal(exits, 1);
});

test("an automatic reconnect exits on the next tick so the startup recovery reruns", async () => {
  let exits = 0;
  const { warn } = console;
  console.warn = () => {};
  try {
    exitAfterReconnect(() => exits++);
    assert.equal(exits, 0); // the reconnect callback returns (token saved) first
    await sleep(5);
    assert.equal(exits, 1);
  } finally {
    console.warn = warn;
  }
});

test("a limit of 0 disables it", async () => {
  let exits = 0;
  const w = disconnectWatchdog(() => exits++, 0);
  w.down();
  await sleep(20);
  assert.equal(exits, 0);
});
