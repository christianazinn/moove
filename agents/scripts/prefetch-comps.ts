// Fills fixtures/comps/ with real comps for every demo-room item (scripts/demo-room.ts), so pricing the
// seeded room replays caches instead of calling Apify during the demo. Cached queries cost nothing;
// each missing one runs the APIFY_SOURCES actors once (capped by APIFY_MAX_USD_PER_RUN per actor).
// No Claude calls. Commit the new fixtures/comps/*.json (real data only).
// Usage (from agents/): npm run comps:prefetch [-- --dry]   (--dry lists what's missing, spends nothing)
import "./env.js";
import { existsSync } from "node:fs";
import { cacheFile, lookupComps } from "../src/integrations/apify.js";
import { estimate } from "../src/agents/pricing.js";
import { DEMO_OBJECTS, demoQuery } from "./demo-room.js";

const dry = process.argv.includes("--dry");
const queries = [...new Set(DEMO_OBJECTS.map(demoQuery))];
let failed = 0;
for (const q of queries) {
  const file = cacheFile(q);
  if (dry) {
    console.log(`${existsSync(file) ? "cached " : "MISSING"}  "${q}"  ${file}`);
    continue;
  }
  try {
    const { comps, replayed } = await lookupComps(q);
    const e = estimate(comps, "");
    const est = e ? `~$${e.est / 100} ($${e.low / 100}-$${e.high / 100})` : "no estimate";
    const bySource = Object.entries(comps.reduce<Record<string, number>>((m, c) => ((m[c.source] = (m[c.source] ?? 0) + 1), m), {}))
      .map(([s, n]) => `${s}:${n}`)
      .join(" ");
    console.log(`${replayed ? "cached " : "fetched"}  "${q}": ${comps.length} comps (${bySource || "none"}), ${est}`);
    if (comps.length === 0) {
      console.warn(`  WARNING: empty cache written to ${file}; delete it and pick a better item name`);
      failed++;
    }
  } catch (err) {
    console.error(`FAILED   "${q}": ${(err as Error).message ?? err}`);
    failed++;
  }
}
process.exit(failed ? 1 : 0);
