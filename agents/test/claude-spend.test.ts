import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { z } from "zod";

// The daily Claude spend cap. No network: the over-cap call is refused before the API is reached.
const dir = mkdtempSync(path.join(tmpdir(), "claude-spend-"));
const file = path.join(dir, "spend.json");
process.env.CLAUDE_SPEND_FILE = file;
process.env.CLAUDE_MAX_USD_PER_DAY = "1";
delete process.env.LLM_REPLAY;
const { structuredCall, callCostUsd, claudeSpentToday, SpendCapError } = await import("../src/integrations/anthropic.js");

test("cost uses per-model prices, with cache writes at 1.25x and cache reads at 0.1x", () => {
  assert.equal(callCostUsd("claude-sonnet-5-5", { input_tokens: 1_000_000, output_tokens: 0 }), 2);
  assert.equal(callCostUsd("claude-sonnet-5-5", { input_tokens: 0, output_tokens: 100_000 }), 1);
  assert.equal(callCostUsd("claude-haiku-5-5", { input_tokens: 1_000_000, output_tokens: 1_000_000 }), 0.6);
  assert.equal(callCostUsd("claude-sonnet-5-5", { cache_read_input_tokens: 1_000_000 }), 0.2);
  assert.equal(callCostUsd("claude-sonnet-5-5", { cache_creation_input_tokens: 1_000_000 }), 2.5);
  assert.equal(callCostUsd("some-future-model", { input_tokens: 1_000_000 }), 4); // unknown: priced like Opus
});

test("over the daily cap, live calls are refused before reaching the API", async () => {
  const today = new Date().toISOString().slice(0, 10);
  writeFileSync(file, JSON.stringify({ [today]: { usd: 1.2, calls: 40 } }));
  assert.deepEqual(claudeSpentToday(), { usd: 1.2, calls: 40 });
  await assert.rejects(
    structuredCall({ model: "claude-sonnet-5-5", system: "s", text: "t", schema: z.object({ a: z.string() }) }),
    (e: unknown) => e instanceof SpendCapError && /cap reached: ~\$1\.20 of \$1\.00 today \(40 calls\)/.test(String(e)),
  );
});
