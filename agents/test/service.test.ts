import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const dir = mkdtempSync(path.join(tmpdir(), "spend-"));
process.env.CLAUDE_SPEND_FILE = path.join(dir, "claude.json");
process.env.APIFY_SPEND_FILE = path.join(dir, "apify.json");
process.env.CLAUDE_MAX_USD_PER_DAY = "3";
process.env.APIFY_MAX_USD_PER_DAY = "2";
const { spendToday, announceSpend } = await import("../src/service.js");

test("spend_today reports today's spend against both caps", () => {
  const s = JSON.parse(spendToday(new Date("2026-10-24T12:00:00Z")));
  assert.deepEqual(s, { day: "2026-10-24", claude: { usd: 0, calls: 0, capUsd: 3 }, apify: { usd: 0, runs: 0, capUsd: 2 } });
});

test("announceSpend writes once and again only when it changes", async () => {
  const writes: { key: string; value: string }[] = [];
  const conn = { reducers: { setServiceConfig: async (a: { key: string; value: string }) => void writes.push(a) } };
  const t = announceSpend(conn as never, 20);
  await new Promise(r => setTimeout(r, 70));
  clearInterval(t);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].key, "spend_today");
  rmSync(dir, { recursive: true });
});
