import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { Conn } from "../src/spacetime.js";
import type { Item } from "../src/module_bindings/types.js";

// When Apify can't run, pricing borrows the cached real comps of the most similar item (labeled).
process.env.PRICING_COMP_FILTER = "rules"; // no Claude in tests
const { similarCachedComps, isApifyUnavailable, ApifyCapError } = await import("../src/integrations/apify.js");
const { pricingAgent, setCompsSource } = await import("../src/agents/pricing.js");

const comp = (p: number) => ({ source: "ebay", title: "x", priceCents: p, url: "u" });

test("similarCachedComps matches thing words, not colors, materials or broad categories", () => {
  const dir = mkdtempSync(path.join(tmpdir(), "comps-"));
  try {
    for (const slug of ["black-mesh-back-office-chair", "white-wall-mounted-porcelain-bathroom-sink", "black-floating-wall-shelf", "electronics", "table"]) {
      writeFileSync(path.join(dir, `${slug}.json`), JSON.stringify([comp(1000)]));
    }
    writeFileSync(path.join(dir, "table.filter.json"), "{}");
    const m = (q: string, c: string) => similarCachedComps(q, c, dir)?.query ?? null;
    assert.equal(m("black mesh office chair with patterned seat", "chair"), "black mesh back office chair");
    assert.equal(m("chrome wall-mounted bathroom towel rack shelf", "storage"), "black floating wall shelf");
    assert.equal(m("white wall-mounted hair dryer", "electronics"), null, "no shared thing word, broad category");
    assert.equal(m("workbench", "table"), "table", "specific category counts");
    assert.equal(m("red plush toy", "other"), null);
    assert.equal(similarCachedComps("x", "", path.join(dir, "missing")), null);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("isApifyUnavailable: credit, cap and token errors, not transient ones", () => {
  assert.ok(isApifyUnavailable(new ApifyCapError("Apify daily spend cap reached")));
  assert.ok(isApifyUnavailable(new Error('HTTP 403 {"error":{"type":"platform-feature-disabled","message":"Monthly usage hard limit exceeded"}}')));
  assert.ok(isApifyUnavailable(new Error("APIFY_TOKEN not set and no cached comps for this query")));
  assert.ok(!isApifyUnavailable(new Error("HTTP 429 concurrent-runs-limit")));
});

test("pricing falls back to a similar cached item when Apify is out of credit, and says so", async () => {
  const owner = { toHexString: () => "o", isEqual: () => true };
  // Committed fixture: fixtures/comps/mesh-office-chair.json
  const it = { id: 1n, owner, name: "black mesh office chair", category: "chair", brand: "", condition: "good", photoUrls: [], detailsStatus: "done", pricingStatus: "pending" } as unknown as Item;
  const rows = new Map([[1n, it]]);
  const events: { kind: string; message: string }[] = [];
  let est = -1n;
  const conn = {
    db: { item: { iter: () => [...rows.values()].values(), id: { find: (id: bigint) => rows.get(id) }, onInsert() {}, onUpdate() {} } },
    reducers: {
      setItemStage: async (a: { stage: string }) => void rows.set(1n, { ...rows.get(1n)!, pricingStatus: a.stage } as Item),
      setEstValue: async (a: { estValueCents: bigint }) => {
        est = a.estValueCents;
        rows.set(1n, { ...rows.get(1n)!, pricingStatus: "done" } as Item);
      },
      addComps: async () => {},
      logAgentEvent: async (e: { kind: string; message: string }) => void events.push(e),
    },
  } as unknown as Conn;
  setCompsSource(async () => {
    throw new Error('apify: HTTP 403 {"error":{"type":"platform-feature-disabled","message":"Monthly usage hard limit exceeded"}}');
  });
  const log = console.log;
  console.log = () => {};
  try {
    pricingAgent.start(conn);
    await new Promise(r => setTimeout(r, 200));
  } finally {
    console.log = log;
  }
  assert.ok(est > 0n, "priced from the similar item's comps");
  assert.ok(events.some(e => e.message.startsWith('[REPLAYED] No live comps') && e.message.includes('similar item "mesh office chair"')));
  assert.ok(events.some(e => e.kind === "result" && e.message.startsWith('[REPLAYED, similar item "mesh office chair"]')));
});
