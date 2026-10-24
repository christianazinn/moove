import { test } from "node:test";
import assert from "node:assert/strict";
import { priorSpendUsd } from "../src/agents/sam3d.js";

const H = 3600_000;
const now = 1_800_000_000_000;
const ev = (o: { agent?: string; kind?: string; data?: unknown; raw?: string; agoH?: number }) => ({
  agent: o.agent ?? "sam3d",
  kind: o.kind ?? "tool_call",
  dataJson: o.raw ?? (o.data === undefined ? "" : JSON.stringify(o.data)),
  createdAt: { toMillis: () => BigInt(now - (o.agoH ?? 1) * H) },
});

test("prior SAM 3D spend counts this agent's tool calls inside the window only", () => {
  const events = [
    ev({ data: { costUsd: 0.02 } }), // fal run
    ev({ data: { costUsd: 0.04 } }), // Claude image pick
    ev({ data: { costUsd: 0.0105, replayed: false } }), // image search
    ev({ data: { costUsd: 0.5 }, agoH: 30 }), // outside the 24 h window
    ev({ agent: "pricing", data: { costUsd: 0.01 } }), // another agent
    ev({ kind: "result", data: { costUsd: 9 } }), // results don't spend
    ev({ data: { refused: true } }), // no cost recorded
    ev({ raw: "not json" }),
    ev({ data: { costUsd: -1 } }),
  ];
  assert.equal(Number(priorSpendUsd(events, now, 24 * H).toFixed(4)), 0.0705);
  assert.equal(priorSpendUsd([], now, 24 * H), 0);
});
