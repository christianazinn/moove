// Benchmark the pricing pipeline against an external dataset of real sold prices (JSONL rows:
// {id, name, brand, category, condition, priceUsd}). Not committed data: point it at a local file.
//   prior on every row (one MODEL_ESTIMATE call each, cached)
//   full pipeline (live comps -> comp filter -> estimate with and without the prior) on --full N rows
// Live comps are written under --work (default .cache/bench/), never fixtures/. Apify spend is bounded
// up front by APIFY_MAX_USD_PER_RUN x 2 actors x N; the script refuses if that passes --max-apify-usd.
// Usage (from agents/): npx tsx scripts/pricing-bench.ts <rows.jsonl> [--full 25] [--max-apify-usd 3] [--work dir]
import { config } from "../src/config.js"; // loads ../.env.local relative to agents/, so import before chdir
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const opt = (k: string, d: string) => (args.includes(k) ? args[args.indexOf(k) + 1] : d);
const file = path.resolve(args.find(a => !a.startsWith("--") && !/^\d/.test(a)) ?? "");
const FULL = Number(opt("--full", "0"));
const MAX_APIFY = Number(opt("--max-apify-usd", "3"));
const work = path.resolve(opt("--work", ".cache/bench"));
const sources = config.apify.sources.length;
const bound = FULL * sources * config.apify.maxUsdPerRun;
if (FULL && bound > MAX_APIFY + 1e-9) {
  console.error(`Refusing: ${FULL} items x ${sources} actors x $${config.apify.maxUsdPerRun}/run = $${bound.toFixed(2)} > --max-apify-usd ${MAX_APIFY}`);
  process.exit(2);
}
mkdirSync(path.join(work, "fixtures", "comps"), { recursive: true });
process.chdir(work); // fixtures/comps/ (live comps, filter verdicts) and .cache/ now live here
const { estimate, queryFor } = await import("../src/agents/pricing.js");
const { pricePrior } = await import("../src/agents/price-prior.js");
const { filterComps } = await import("../src/agents/comp-filter.js");
const { lookupComps, filterCacheFile } = await import("../src/integrations/apify.js");

type Row = { id: string; name: string; brand: string; category: string; condition: string; priceUsd: number };
const rows = readFileSync(file, "utf8").split("\n").filter(Boolean).map(l => JSON.parse(l) as Row);
const itemOf = (r: Row) => ({ name: r.name, brand: r.brand ?? "", category: r.category.split(" > ").pop() ?? "", material: "", condition: r.condition, widthM: 0, heightM: 0, depthM: 0 });

// Full-pipeline rows: used items (the app prices used things) spread across top-level categories.
const top = (r: Row) => r.category.split(" > ")[0];
const used = rows.filter(r => r.condition !== "new");
const byTop = new Map<string, Row[]>();
for (const r of used) byTop.set(top(r), [...(byTop.get(top(r)) ?? []), r]);
const fullRows: Row[] = [];
for (let i = 0; fullRows.length < FULL && i < 50; i++) for (const g of byTop.values()) if (g[i] && fullRows.length < FULL) fullRows.push(g[i]);
const fullIds = new Set(fullRows.map(r => r.id));

type Out = { id: string; name: string; cat: string; cond: string; truth: number; prior?: number; comps?: number; nComps?: number; blend?: number; error?: string };
const out: Out[] = [];
const priorFile = path.join(".cache", "priors.json");
let i = 0;
for (const r of rows) {
  i++;
  const it = itemOf(r);
  const o: Out = { id: r.id, name: r.name, cat: top(r), cond: r.condition, truth: Math.round(r.priceUsd * 100) };
  const p = await pricePrior(it as never, { cacheFile: priorFile, enabled: true });
  if (p.status === "ok" || p.status === "cached") o.prior = estimate([], r.condition, { priorCents: p.cents })!.est;
  else if (p.status === "failed") o.error = `prior: ${p.error}`;
  if (fullIds.has(r.id)) {
    const q = queryFor({ ...it } as never);
    try {
      const { comps: raw } = await lookupComps(q);
      const f = await filterComps(it as never, raw, { cacheFile: filterCacheFile(q) });
      o.nComps = f.comps.length;
      o.comps = estimate(f.comps, r.condition)?.est;
      if (p.status === "ok" || p.status === "cached") o.blend = estimate(f.comps, r.condition, { priorCents: p.cents })?.est;
    } catch (err) {
      o.error = `comps: ${String(err).slice(0, 160)}`;
    }
    console.log(`[full ${fullRows.findIndex(x => x.id === r.id) + 1}/${FULL}] ${q.slice(0, 50)}: truth $${r.priceUsd} comps ${o.comps != null ? `$${o.comps / 100}` : "-"} (${o.nComps ?? 0}) blend ${o.blend != null ? `$${o.blend / 100}` : "-"} prior ${o.prior != null ? `$${o.prior / 100}` : "-"}`);
  } else if (i % 50 === 0) console.log(`[prior] ${i}/${rows.length}`);
  out.push(o);
}
writeFileSync("results.json", JSON.stringify(out, null, 2));

const pct = (x: number) => `${Math.round(x * 100)}%`;
const med = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : NaN;
};
function report(title: string, rs: Out[], keys: (keyof Out)[]) {
  const ok = rs.filter(r => keys.every(k => typeof r[k] === "number" && (r[k] as number) > 0));
  console.log(`\n${title}: ${ok.length} rows`);
  console.log("method    median err  mean err  within 30%  within 2x  bias (median est/truth)");
  for (const k of keys) {
    const ratio = ok.map(r => (r[k] as number) / r.truth);
    const err = ratio.map(x => Math.abs(x - 1));
    console.log(`${String(k).padEnd(9)} ${pct(med(err)).padEnd(11)} ${pct(err.reduce((a, b) => a + b, 0) / err.length).padEnd(9)} ${pct(err.filter(e => e <= 0.3).length / err.length).padEnd(11)} ${pct(ratio.filter(x => x >= 0.5 && x <= 2).length / ratio.length).padEnd(10)} ${med(ratio).toFixed(2)}x`);
  }
}
report("Prior only, all rows", out, ["prior"]);
for (const c of ["new", "like_new", "good"]) report(`  prior, condition ${c}`, out.filter(r => r.cond === c), ["prior"]);
for (const t of [...new Set(out.map(r => r.cat))]) {
  const rs = out.filter(r => r.cat === t);
  if (rs.length >= 15) report(`  prior, ${t}`, rs, ["prior"]);
}
if (FULL) report("Full pipeline rows (used items, live comps)", out.filter(r => fullIds.has(r.id)), ["comps", "blend", "prior"]);
console.log(`\nClaude priors cached in ${path.join(work, priorFile)}, per-row results in ${path.join(work, "results.json")}`);
