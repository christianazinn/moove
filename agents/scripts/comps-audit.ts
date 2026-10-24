// Pricing quality check over every committed comps cache (agents/fixtures/comps/*.json). For each
// query it runs the real pipeline offline (rule pre-filter, then the cached Claude verdict when one
// exists, never a live call) and the production estimate(), and flags estimates worth a human look:
// too few comps, a wide spread, or a big swing between raw and filtered estimates.
// Usage (from agents/): npm run comps:audit        Exits non-zero if anything is flagged.
import "./env.js";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { filterComps } from "../src/agents/comp-filter.js";
import { estimate } from "../src/agents/pricing.js";
import { filterCacheFile, type Comp } from "../src/integrations/apify.js";
import { DEMO_OBJECTS, demoQuery } from "./demo-room.js";

const DIR = path.join("fixtures", "comps");
const MIN_COMPS = 5;
const MAX_SPREAD = 1.2; // (high - low) / est
const MAX_SWING = 0.4; // |filtered - raw| / raw

// Demo items carry their scanned size and category; other caches are judged by name alone.
const demo = new Map(DEMO_OBJECTS.map(o => [demoQuery(o), o]));
const usd = (c: number) => `$${(c / 100).toFixed(0)}`;
const pad = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s.padEnd(n));

let flagged = 0;
console.log(`${pad("query", 30)} ${pad("comps", 11)} ${pad("raw", 6)} ${pad("estimate (range)", 22)} filter   flags`);
for (const f of readdirSync(DIR).filter(f => f.endsWith(".json") && !f.endsWith(".filter.json")).sort()) {
  const raw = JSON.parse(readFileSync(path.join(DIR, f), "utf8")) as Comp[];
  const slug = f.replace(/\.json$/, "");
  const o = [...demo.entries()].find(([q]) => q.toLowerCase().replace(/[^a-z0-9]+/g, "-") === slug);
  const query = o ? o[0] : slug.replace(/-/g, " ");
  const it = { name: o ? o[1].name : query, brand: "", category: o ? o[1].category : "", material: "", condition: "", widthM: o?.[1].widthM ?? 0, heightM: o?.[1].heightM ?? 0, depthM: o?.[1].depthM ?? 0 };
  const res = await filterComps(it as never, raw, {
    cacheFile: filterCacheFile(query),
    judge: async () => {
      throw new Error("no cached verdict (audit never calls Claude)");
    },
  });
  const all = estimate(raw, "");
  const e = estimate(res.comps, "");
  const flags: string[] = [];
  if (res.comps.length < MIN_COMPS) flags.push(`only ${res.comps.length} comps`);
  if (e && e.est > 0 && (e.high - e.low) / e.est > MAX_SPREAD) flags.push(`wide spread ${usd(e.low)}-${usd(e.high)}`);
  if (e && all && all.est > 0 && Math.abs(e.est - all.est) / all.est > MAX_SWING) flags.push(`filter moved it ${usd(all.est)} -> ${usd(e.est)}`);
  if (!e) flags.push("no estimate");
  if (flags.length) flagged++;
  const filter = res.claude === "cached" ? "claude" : res.claude === "failed" ? "rules" : res.mode;
  console.log(`${pad(query, 30)} ${pad(`${res.comps.length}/${raw.length}`, 11)} ${pad(all ? usd(all.est) : "-", 6)} ${pad(e ? `${usd(e.est)} (${usd(e.low)}-${usd(e.high)})` : "-", 22)} ${pad(filter, 8)} ${flags.join("; ") || "ok"}`);
}
console.log(`\n${flagged} flagged (comps < ${MIN_COMPS}, spread > ${MAX_SPREAD * 100}% of the estimate, or the filter moved it > ${MAX_SWING * 100}%)`);
process.exit(flagged ? 1 : 0);
