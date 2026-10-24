import { test } from "node:test";
import assert from "node:assert/strict";
import type { Conn } from "../src/spacetime.js";

// #145: rows a dead worker left `running` go back to `pending` on start; nothing else is touched.
process.env.FAL_KEY = "";
const { visionAgent } = await import("../src/agents/vision.js");
const { sam3dAgent } = await import("../src/agents/sam3d.js");
const { sweepAgent } = await import("../src/agents/sweep.js");

const STATUSES = ["pending", "running", "done", "failed"];

function fakeConn() {
  const items = STATUSES.map((s, i) => ({ id: BigInt(i + 1), detailsStatus: s, modelStatus: s, photoUrls: [] }));
  // No `pending` scan: its settle timer would start a real sweep against this fake.
  const scans = ["none", "running", "done", "failed"].map((s, i) => ({ id: BigInt(i + 1), sweepStatus: s }));
  const stages: { itemId: bigint; stage: string; field: string }[] = [];
  const sweeps: { scanId: bigint; status: string }[] = [];
  const conn = {
    db: {
      item: { iter: () => items.values(), id: { find: (id: bigint) => items.find((i) => i.id === id) }, onInsert() {}, onUpdate() {} },
      scan: { iter: () => scans.values(), id: { find: (id: bigint) => scans.find((s) => s.id === id) }, onUpdate() {} },
      scanPhoto: { iter: () => [].values(), onInsert() {} },
      agentEvent: { iter: () => [].values() },
    },
    reducers: {
      setItemStage: (a: (typeof stages)[number]) => void stages.push(a),
      setSweepStatus: async (a: (typeof sweeps)[number]) => void sweeps.push(a),
    },
  } as unknown as Conn;
  return { conn, stages, sweeps };
}

test("vision re-queues an item left details_status=running", () => {
  const { conn, stages } = fakeConn();
  visionAgent.start(conn);
  assert.deepEqual(stages, [{ itemId: 2n, stage: "pending", field: "details" }]);
});

test("sam3d re-queues an item left model_status=running, even with the agent off", () => {
  const { conn, stages } = fakeConn();
  sam3dAgent.start(conn);
  assert.deepEqual(stages, [{ itemId: 2n, stage: "pending", field: "model" }]);
});

test("sweep re-queues a scan left sweep_status=running", () => {
  const { conn, sweeps } = fakeConn();
  sweepAgent.start(conn);
  assert.deepEqual(sweeps, [{ scanId: 2n, status: "pending" }]);
});
