import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { z } from "zod";

// LLM record/replay (no network: every case here is a hit or a refused miss).
const dir = mkdtempSync(path.join(tmpdir(), "llm-replay-"));
process.env.LLM_REPLAY_DIR = dir;
const { structuredCall, replayKey, replayMode } = await import("../src/integrations/anthropic.js");

const schema = z.object({ name: z.string(), n: z.number() });
const base = { model: "claude-sonnet-5-5", system: "sys", text: "hello", schema };

test("replayMode parses the env value and defaults to off", () => {
  assert.equal(replayMode(undefined), "off");
  assert.equal(replayMode(" Replay "), "replay");
  assert.equal(replayMode("auto"), "auto");
  assert.equal(replayMode("yes"), "off");
});

test("keys change with model, prompt, images and schema", () => {
  const k = replayKey(base);
  assert.equal(k, replayKey({ ...base }));
  assert.notEqual(k, replayKey({ ...base, model: "claude-haiku-5-5" }));
  assert.notEqual(k, replayKey({ ...base, text: "hello!" }));
  assert.notEqual(k, replayKey({ ...base, images: [{ mediaType: "image/png", data: "AAAA" }] }));
  assert.notEqual(k, replayKey({ ...base, schema: z.object({ name: z.string() }) }));
});

test("replay returns the recorded answer, misses fail loudly, stale recordings fail validation", async () => {
  process.env.LLM_REPLAY = "replay";
  writeFileSync(path.join(dir, `${replayKey(base)}.json`), JSON.stringify({ output: { name: "chair", n: 2 } }));
  assert.deepEqual(await structuredCall(base), { name: "chair", n: 2 });
  await assert.rejects(structuredCall({ ...base, text: "never recorded" }), /no recorded answer/);
  const stale = { ...base, text: "stale" };
  writeFileSync(path.join(dir, `${replayKey(stale)}.json`), JSON.stringify({ output: { name: "chair" } }));
  await assert.rejects(structuredCall(stale));
  delete process.env.LLM_REPLAY;
});
