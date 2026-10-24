import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { IncomingMessage } from "node:http";
import { clientKey, diskQuota, rateLimiter } from "../src/ratelimit.js";

test("rateLimiter allows perMin hits per key per minute, then recovers", () => {
  const ok = rateLimiter(3);
  assert.deepEqual([1, 2, 3, 4].map(() => ok("a", 1000)), [true, true, true, false]);
  assert.equal(ok("b", 1000), true, "keys are independent");
  assert.equal(ok("a", 61_001), true, "the window slides");
  assert.equal(rateLimiter(0)("a"), true, "0 = unlimited");
});

test("clientKey trusts CF-Connecting-IP only from loopback (the tunnel)", () => {
  const req = (remoteAddress: string, cf?: string) => ({ socket: { remoteAddress }, headers: cf ? { "cf-connecting-ip": cf } : {} }) as unknown as IncomingMessage;
  assert.equal(clientKey(req("127.0.0.1", "203.0.113.7")), "203.0.113.7");
  assert.equal(clientKey(req("::1", "203.0.113.7")), "203.0.113.7");
  assert.equal(clientKey(req("192.168.1.20", "203.0.113.7")), "192.168.1.20", "a LAN client can't spoof the header");
  assert.equal(clientKey(req("127.0.0.1")), "127.0.0.1");
});

test("diskQuota counts existing files and refuses past the cap", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "quota-"));
  try {
    writeFileSync(path.join(dir, "a.jpg"), Buffer.alloc(600));
    const q = diskQuota(dir, 1000);
    assert.equal(q.used(), 600);
    assert.equal(q.fits(400), true);
    q.add(400);
    assert.equal(q.fits(1), false);
    assert.equal(diskQuota(dir, 0).fits(1e12), true, "0 = off");
    assert.equal(diskQuota(path.join(dir, "missing"), 10).used(), 0);
  } finally {
    rmSync(dir, { recursive: true });
  }
});
