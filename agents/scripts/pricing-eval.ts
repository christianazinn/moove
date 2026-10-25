// Pricing accuracy against hand-labeled used prices (fixtures/pricing-eval.json). For each labeled
// query with a committed comps cache it runs the pipeline offline (rule pre-filter, cached Claude
// verdict, cached price prior) and compares three estimators:
//   baseline  the original estimate(): plain median of comps
//   +prior    the comps median shrunk toward Claude's comps-free prior (PRIOR_WEIGHT pseudo-comps)
//   prior     Claude's prior alone
// Usage (from agents/): npm run pricing:eval            offline, cached priors only
//                       npm run pricing:eval -- --fill-priors   asks Claude for missing priors (Sonnet, ~$0.005 each)
import "./env.js";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { filterComps } from "../src/agents/comp-filter.js";
import { estimate, type Estimate } from "../src/agents/pricing.js";
import { pricePrior, priorCacheFile } from "../src/agents/price-prior.js";
import { compsSlug, filterCacheFile, type Comp } from "../src/integrations/apify.js";

const fill = process.argv.includes("--fill-priors");
const labels = JSON.parse(readFileSync(path.join("fixtures", "pricing-eval.json"), "utf8")) as {
  items: Record<string, { usd: number; low: number; high: number; basis?: string }>;
};
const usd = (c: number) => `$${Math.round(c / 100)}`;
const pad = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s.padEnd(n));

type Row = { q: string; web: boolean; truth: number; band: [number, number]; n: number; est: Record<string, Estimate | null> };
const rows: Row[] = [];
for (const [q, label] of Object.entries(labels.items)) {
  const file = path.join("fixtures", "comps", `${compsSlug(q)}.json`);
  if (!existsSync(file)) {
    console.warn(`skip "${q}": no comps cache`);
    continue;
  }
  const raw = JSON.parse(readFileSync(file, "utf8")) as Comp[];
  const it = { name: q, brand: "", category: "", material: "", condition: "", widthM: 0, heightM: 0, depthM: 0 };
  const f = await filterComps(it as never, raw, {
    cacheFile: filterCacheFile(q),
    judge: async () => {
      throw new Error("no cached verdict");
    },
  });
  const p = await pricePrior(it as never, { cacheFile: priorCacheFile(q), cacheOnly: !fill, enabled: true });
  const prior = p.status === "ok" || p.status === "cached" ? p : undefined;
  if (p.status === "failed") console.warn(`prior failed for "${q}": ${p.error}`);
  rows.push({
    q,
    web: /^web/.test(label.basis ?? ""),
    truth: label.usd * 100,
    band: [label.low * 100, label.high * 100],
    n: f.comps.length,
    est: {
      baseline: estimate(f.comps, ""),
      "k=1": prior ? estimate(f.comps, "", { prior, priorWeight: 1 }) : null,
      "+prior": prior ? estimate(f.comps, "", { prior }) : null,
      "k=6": prior ? estimate(f.comps, "", { prior, priorWeight: 6 }) : null,
      prior: prior ? estimate([], "", { prior }) : null,
    },
  });
}

// "+prior" is the production weight (PRIOR_WEIGHT); k=1 and k=6 show the sensitivity.
const METHODS = ["baseline", "k=1", "+prior", "k=6", "prior"];
console.log(`${pad("query", 34)} ${pad("truth", 6)} ${pad("comps", 5)} ${METHODS.map(m => pad(m, 9)).join(" ")}`);
for (const r of rows) {
  console.log(`${pad(r.q, 34)} ${pad(usd(r.truth), 6)} ${pad(String(r.n), 5)} ${METHODS.map(m => pad(r.est[m] ? usd(r.est[m]!.est) : "-", 9)).join(" ")}`);
}

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? (s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2) : NaN;
};
const pct = (x: number) => `${Math.round(x * 100)}%`;
// Only rows every method priced, so the methods are compared on the same items.
const common = rows.filter(r => METHODS.every(m => r.est[m]));
function report(title: string, rs: Row[]) {
  if (!rs.length) return;
  console.log(`\n${title} (${rs.length} items). Lower error is better; "in band" = estimate inside the label's low-high band.`);
  console.log(`${pad("method", 10)} ${pad("mean err", 9)} ${pad("median err", 11)} ${pad("within 30%", 11)} ${pad("in band", 8)} truth in range`);
  for (const m of METHODS) {
    const errs = rs.map(r => Math.abs(r.est[m]!.est - r.truth) / r.truth);
    const inRange = rs.filter(r => r.est[m]!.low <= r.truth && r.truth <= r.est[m]!.high).length;
    const inBand = rs.filter(r => r.band[0] <= r.est[m]!.est && r.est[m]!.est <= r.band[1]).length;
    console.log(`${pad(m, 10)} ${pad(pct(errs.reduce((a, b) => a + b, 0) / errs.length), 9)} ${pad(pct(median(errs)), 11)} ${pad(pct(errs.filter(e => e <= 0.3).length / errs.length), 11)} ${pad(pct(inBand / rs.length), 8)} ${pct(inRange / rs.length)}`);
  }
}
report("All labeled items", common);
// The labels and the prior both come from Claude, so the knowledge-only labels flatter the prior.
// Web-backed labels are the fairer test.
report("Web-backed labels only", common.filter(r => r.web));
report("Knowledge-only labels", common.filter(r => !r.web));
report("Fewer than 5 comps", common.filter(r => r.n < 5));
