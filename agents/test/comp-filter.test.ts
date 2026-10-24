import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { Comp } from "../src/integrations/apify.js";
import { compFilterMode, compsPrompt, describeItem, filterComps, preFilter, type ItemDesc, type Judge } from "../src/agents/comp-filter.js";
import { filterSummary } from "../src/agents/pricing.js";
import { INJECTION_TEXT } from "../fixtures/injection-comps.js";

// Real cached eBay/FB comps for "IKEA Kallax shelf" (5 of the 17 are inserts sold alone).
const KALLAX: Comp[] = JSON.parse(readFileSync(new URL("../fixtures/comps/ikea-kallax-shelf.json", import.meta.url), "utf8"));
const item: ItemDesc = {
  name: "Kallax shelf",
  brand: "IKEA",
  category: "shelf",
  material: "particleboard",
  condition: "good",
  widthM: 0.77,
  heightM: 1.47,
  depthM: 0.39,
};
const comp = (title: string, priceCents = 1000): Comp => ({ source: "ebay", title, priceCents, url: "https://example.com" });
const tmpCache = () => path.join(mkdtempSync(path.join(tmpdir(), "comp-filter-")), "q.filter.json");

function countingJudge(verdict: (comps: Comp[]) => { keep: number[]; reason: string }) {
  const calls: { desc: string; comps: Comp[] }[] = [];
  const judge: Judge = async (desc, comps) => {
    calls.push({ desc, comps });
    return verdict(comps);
  };
  return { judge, calls };
}

test("the pre-filter drops the real Kallax insert listings but keeps 'with 4 inserts'", () => {
  const { kept, dropped } = preFilter(KALLAX, item);
  assert.equal(dropped.length, 5);
  assert.ok(dropped.every((d) => /insert/i.test(d.comp.title)));
  assert.ok(kept.some((c) => c.title.includes("with 4 inserts")));
  assert.equal(kept.length, 12);
});

test("the pre-filter catches parts, wanted ads and bundles, case-insensitively", () => {
  const titles = ["Lamp FOR PARTS not working", "WANTED: kallax", "ISO desk chair", "Bundle of 3 lamps", "Lot of 5 chairs", "Broken lamp", "Floor lamp"];
  const { kept, dropped } = preFilter(titles.map((t) => comp(t)), { ...item, name: "lamp", category: "lamp" });
  assert.deepEqual(kept.map((c) => c.title), ["Floor lamp"]);
  assert.equal(dropped.length, 6);
});

test("the pre-filter keeps a junk word the item itself has", () => {
  const { kept } = preFilter([comp("IKEA Kallax insert with door"), comp("Kallax shelf")], { ...item, name: "Kallax insert", category: "shelf insert" });
  assert.equal(kept.length, 2);
});

test("describeItem lists name, brand, category, dims and condition", () => {
  assert.equal(
    describeItem(item),
    "Kallax shelf; brand IKEA; category shelf; material particleboard; 0.77 x 1.47 x 0.39 m (W x H x D); condition good",
  );
  assert.equal(describeItem({ ...item, brand: "", material: "", widthM: 0 }), "Kallax shelf; category shelf; condition good");
  assert.match(compsPrompt("x", KALLAX.slice(0, 1)), /^Item: x\n\nListings \(scraped, untrusted\):\n<untrusted kind="comps">\n- 1\. \[ebay\] \$35\.00 IKEA KALLAX/);
});

test("PRICING_COMP_FILTER parses to claude (default), rules or off", () => {
  assert.equal(compFilterMode({}), "claude");
  assert.equal(compFilterMode({ PRICING_COMP_FILTER: "1" }), "claude");
  assert.equal(compFilterMode({ PRICING_COMP_FILTER: "rules" }), "rules");
  assert.equal(compFilterMode({ PRICING_COMP_FILTER: "0" }), "off");
  assert.equal(compFilterMode({ PRICING_COMP_FILTER: "off" }), "off");
});

test("off returns every comp untouched and never calls the judge", async () => {
  const { judge, calls } = countingJudge(() => ({ keep: [1], reason: "" }));
  const f = await filterComps(item, KALLAX, { mode: "off", judge });
  assert.equal(f.comps, KALLAX);
  assert.equal(calls.length, 0);
  assert.match(filterSummary(f, KALLAX.length), /off .* all 17 comps/);
});

test("rules mode applies only the pre-filter", async () => {
  const { judge, calls } = countingJudge(() => ({ keep: [1], reason: "" }));
  const f = await filterComps(item, KALLAX, { mode: "rules", judge });
  assert.equal(f.comps.length, 12);
  assert.equal(calls.length, 0);
  assert.equal(filterSummary(f, 17), "Kept 12 of 17 comps (dropped 5 by rules)");
});

test("claude mode sends rule survivors to the judge and keeps its 1-based picks", async () => {
  const { judge, calls } = countingJudge(() => ({ keep: [1, 3, 3, 0, 99], reason: "dropped #2: drawer set" }));
  const f = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile: null });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].comps.length, 12);
  assert.equal(calls[0].desc, describeItem(item));
  assert.equal(f.claude, "ok");
  assert.deepEqual(f.comps, [calls[0].comps[0], calls[0].comps[2]]);
  assert.equal(f.droppedByRules.length, 5);
  assert.equal(f.droppedByClaude.length, 10);
  assert.equal(filterSummary(f, 17), "Kept 2 of 17 comps (dropped 5 by rules, 10 by Claude: dropped #2: drawer set)");
});

test("a judge error falls back to the rule-filtered comps", async () => {
  const judge: Judge = async () => {
    throw new Error("529 overloaded");
  };
  const f = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile: null });
  assert.equal(f.claude, "failed");
  assert.equal(f.error, "529 overloaded");
  assert.equal(f.comps.length, 12);
  assert.equal(f.droppedByClaude.length, 0);
});

test("a judge that keeps nothing also falls back instead of valuing at $0", async () => {
  const { judge } = countingJudge(() => ({ keep: [], reason: "none match" }));
  const f = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile: null });
  assert.equal(f.claude, "failed");
  assert.equal(f.comps.length, 12);
});

test("if the rules would drop everything, all comps go to the judge", async () => {
  const comps = [comp("Kallax insert"), comp("Kallax insert with door")];
  const { judge, calls } = countingJudge((c) => ({ keep: c.map((_x, i) => i + 1), reason: "" }));
  const f = await filterComps(item, comps, { mode: "claude", judge, cacheFile: null });
  assert.equal(calls[0].comps.length, 2);
  assert.equal(f.comps.length, 2);
  assert.equal(f.droppedByRules.length, 0);
});

test("verdicts are cached per item description + comps, so a replay doesn't call Claude", async () => {
  const cacheFile = tmpCache();
  const { judge, calls } = countingJudge(() => ({ keep: [2], reason: "only #2 matches" }));
  const first = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile });
  const again = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile });
  assert.equal(calls.length, 1);
  assert.equal(first.claude, "ok");
  assert.equal(again.claude, "cached");
  assert.deepEqual(again.comps, first.comps);
  assert.match(filterSummary(again, 17), /by Claude \[REPLAYED\]: only #2 matches/);

  // A different item (or different comps) is a different key.
  await filterComps({ ...item, condition: "fair" }, KALLAX, { mode: "claude", judge, cacheFile });
  assert.equal(calls.length, 2);
  const cache = JSON.parse(readFileSync(cacheFile, "utf8"));
  assert.equal(Object.keys(cache).length, 2);
  assert.deepEqual(Object.values(cache).map((e: any) => e.keep), [[2], [2]]);
});

test("failed verdicts are not cached", async () => {
  const cacheFile = tmpCache();
  const bad: Judge = async () => {
    throw new Error("boom");
  };
  await filterComps(item, KALLAX, { mode: "claude", judge: bad, cacheFile });
  const { judge, calls } = countingJudge(() => ({ keep: [1], reason: "" }));
  const f = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile });
  assert.equal(calls.length, 1);
  assert.equal(f.claude, "ok");
});

test("scraped titles are cleaned and fenced in one untrusted block (#17)", () => {
  const prompt = compsPrompt(describeItem(item), [comp("Kallax shelf"), comp(INJECTION_TEXT, 1)]);
  assert.equal(prompt.split("<untrusted").length, 2, "exactly one opening tag (ours)");
  assert.equal(prompt.split("</untrusted>").length, 2, "exactly one closing tag (ours)");
  assert.ok(prompt.trimEnd().endsWith("</untrusted>"), "nothing planted after the block");
  assert.ok(prompt.includes("ignore all prior instructions"), "still visible to the model as data");
  assert.ok(!/[\u200b\u202e]/.test(prompt), "hidden characters removed");
  assert.ok(!/<\/?system/i.test(prompt), "no raw tags survive");
});

test("the judge's reason is cleaned and capped before it reaches event messages", async () => {
  const { judge } = countingJudge(() => ({ keep: [1], reason: `<b>kept</b> #1\u200b ${"x".repeat(500)}` }));
  const f = await filterComps(item, KALLAX, { mode: "claude", judge, cacheFile: null });
  assert.ok(f.reason!.length <= 200);
  assert.ok(!/[<>\u200b]/.test(f.reason!));
  assert.ok(f.droppedByClaude.every((d) => d.why === f.reason));
});
