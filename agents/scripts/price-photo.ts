// Prices one item from local photos with the real pipeline, for eyeballing what the agents would guess:
//   npm run price:photo -- <img1.jpg> [img2.png ...] [--live-comps] [--name "override"]
// All photos are of ONE item. Steps: the vision agent's own identify() (same model, prompt and schema,
// MODEL_VISION) -> pricePrior() -> comps (exact cache in fixtures/comps/, else the most similar cached
// query, or a live Apify lookup with --live-comps) -> filterComps() -> estimate(). Nothing is written to
// SpacetimeDB: the vision agent runs against an in-memory stand-in connection that records reducer calls
// and events and drops them. Claude answers for the prior and the comp filter are cached under
// .cache/price-photo/ (seeded from any committed fixtures/comps/ cache), never in fixtures/.
import './env.js';
import { randomUUID } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, openSync, readSync, closeSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AGENTS_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const USER_CWD = process.env.INIT_CWD ?? process.cwd(); // npm run sets cwd to agents/; resolve photos from where the user ran it

function usage(msg?: string): never {
  if (msg) console.error(`error: ${msg}\n`);
  console.error('usage: npm run price:photo -- <img1.jpg> [img2.png ...] [--live-comps] [--name "override"]');
  console.error('  photos: JPEG, PNG or WebP of ONE item (the vision agent looks at the last 4)');
  console.error('  --live-comps  run a real Apify comps lookup on a cache miss (~$0.05-0.10, counts toward APIFY_MAX_USD_PER_DAY)');
  console.error('  --name        price under this name instead of the one vision gives (brand, condition etc. still from vision)');
  process.exit(2);
}

// ---------- args ----------
const args = process.argv.slice(2);
let liveComps = false;
let nameOverride = '';
const photos: string[] = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--live-comps') liveComps = true;
  else if (a === '--name') nameOverride = (args[++i] ?? usage('--name needs a value')).trim();
  else if (a.startsWith('--name=')) nameOverride = a.slice('--name='.length).trim();
  else if (a === '-h' || a === '--help') usage();
  else if (a.startsWith('--')) usage(`unknown flag ${a}`);
  else photos.push(path.resolve(USER_CWD, a));
}
if (photos.length === 0) usage('give at least one photo');

// ---------- photo checks (by content, not just extension) ----------
type Kind = 'jpg' | 'png' | 'webp' | 'heic' | 'unknown';
function sniff(file: string): Kind {
  const fd = openSync(file, 'r');
  const b = Buffer.alloc(16);
  readSync(fd, b, 0, 16, 0);
  closeSync(fd);
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpg';
  if (b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return 'png';
  if (b.toString('latin1', 0, 4) === 'RIFF' && b.toString('latin1', 8, 12) === 'WEBP') return 'webp';
  if (b.toString('latin1', 4, 8) === 'ftyp' && /^(heic|heix|hevc|heim|heis|mif1|msf1)$/.test(b.toString('latin1', 8, 12))) return 'heic';
  return 'unknown';
}
const MAX_BYTES = 15 * 1024 * 1024; // photos.ts MAX_PHOTO_BYTES
const kinds: Kind[] = [];
for (const f of photos) {
  if (!existsSync(f)) usage(`no such file: ${f}`);
  const k = sniff(f);
  if (k === 'heic' || /\.(heic|heif)$/i.test(f)) {
    const out = f.replace(/\.(heic|heif)$/i, '') + '.jpg';
    usage(`${path.basename(f)} is HEIC, which the Claude API doesn't take. Convert it first:\n  sips -s format jpeg "${f}" --out "${out}"`);
  }
  if (k === 'unknown') usage(`${path.basename(f)} is not a JPEG, PNG or WebP image`);
  if (statSync(f).size > MAX_BYTES) usage(`${path.basename(f)} is over 15 MB; shrink it (sips -Z 2048 in.jpg --out small.jpg)`);
  kinds.push(k);
}
if (photos.length > 4) console.warn(`note: the vision agent only looks at the last 4 photos; ${photos.length - 4} will be ignored`);

// The vision agent loads photos through loadImage(), which reads our own uploads straight from UPLOAD_DIR.
// Point it at a temp dir holding copies named like the upload server's, before config.ts is evaluated
// (env already set wins over .env.local). Lens needs public https photos, so it can't run here; say so.
const uploadDir = mkdtempSync(path.join(os.tmpdir(), 'price-photo-'));
const BASE = 'http://price-photo.invalid';
process.env.UPLOAD_DIR = uploadDir;
process.env.PUBLIC_UPLOAD_BASE_URL = BASE;
process.env.VISION_LENS = '0';
const photoUrls = photos.map((f, i) => {
  const name = `${randomUUID()}.${kinds[i]}`;
  copyFileSync(f, path.join(uploadDir, name));
  return `${BASE}/files/${name}`;
});
process.chdir(AGENTS_DIR); // fixtures/ and .cache/ paths are relative to agents/

// ---------- pipeline modules (dynamic, so the env above is in place first) ----------
const { config } = await import('../src/config.js');
const { visionAgent } = await import('../src/agents/vision.js');
const { pricePrior, priorCacheFile } = await import('../src/agents/price-prior.js');
const { estimate, queryFor } = await import('../src/agents/pricing.js');
const { filterComps, describeItem } = await import('../src/agents/comp-filter.js');
const { cachedComps, similarCachedComps, lookupComps, cacheFile, filterCacheFile, apifySpentToday } = await import('../src/integrations/apify.js');
const { claudeSpentToday, replayMode } = await import('../src/integrations/anthropic.js');
type Item = import('../src/module_bindings/types.js').Item;
type Comp = import('../src/integrations/apify.js').Comp;

const usd = (cents: number) => `$${(cents / 100).toFixed(0)}`;
const hr = (title: string) => console.log(`\n== ${title} ${'='.repeat(Math.max(0, 60 - title.length))}`);
const claudeBefore = claudeSpentToday();
const steps: string[] = []; // Claude calls, for the summary

// ---------- 1. vision: the real identify(), on a stand-in connection ----------
type Details = { name: string; category: string; material: string; brand: string; condition: string; fragile: boolean; maybeSentimental: boolean; notes: string; identifyConfidence: string; closeupHint: string };
async function runVision(): Promise<Details> {
  // A photo-only item, as if RoomPlan had seen something it couldn't name (no box: 0 x 0 x 0 m).
  const item = { id: 1n, owner: {}, name: 'other', category: 'other', widthM: 0, depthM: 0, heightM: 0, photoUrls, detailsStatus: 'pending' } as unknown as Item;
  return new Promise<Details>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('vision timed out after 180 s')), 180_000);
    const done = (fn: () => void) => {
      clearTimeout(timer);
      fn();
    };
    // Every reducer is a no-op that only watches for vision's final event. Nothing leaves this process.
    const reducers = new Proxy({} as Record<string, (a: any) => Promise<void>>, {
      get: (_t, name: string) => (a: any) => {
        if (name === 'logAgentEvent' && a.agent === 'vision') {
          const data = a.dataJson ? JSON.parse(a.dataJson) : {};
          if (a.kind === 'result' && data && 'identifyConfidence' in data) done(() => resolve(data as Details));
          if (a.kind === 'error') done(() => reject(new Error(a.message)));
        }
        return Promise.resolve();
      },
    });
    const conn = {
      reducers,
      db: { item: { iter: () => [item][Symbol.iterator](), id: { find: () => item }, onInsert: () => {}, onUpdate: () => {} } },
    };
    visionAgent.start(conn as any);
  });
}

// Claude caches for the prior and comp filter live in .cache/price-photo/, seeded from any committed
// fixtures/comps/ cache so a demo item replays for free, and never written back into fixtures/.
function stagedCache(fixtureFile: string): string {
  const local = path.join('.cache', 'price-photo', path.basename(fixtureFile));
  const read = (f: string) => {
    try {
      return existsSync(f) ? (JSON.parse(readFileSync(f, 'utf8')) as Record<string, unknown>) : {};
    } catch {
      return {};
    }
  };
  if (existsSync(fixtureFile)) {
    mkdirSync(path.dirname(local), { recursive: true });
    writeFileSync(local, JSON.stringify({ ...read(local), ...read(fixtureFile) }, null, 2));
  }
  return local;
}

try {
  hr('Vision');
  console.log(`${photos.length} photo(s): ${photos.map(p => path.basename(p)).join(', ')}`);
  console.log(`model ${config.models.vision}${replayMode() !== 'off' ? ` (LLM_REPLAY=${replayMode()})` : ''}; Google Lens skipped (needs a public https photo)`);
  const d = await runVision();
  steps.push(`vision: ${config.models.vision} identify (live unless LLM_REPLAY replayed it)`);
  console.log(`  name:       ${d.name}`);
  console.log(`  brand:      ${d.brand || '(none)'}`);
  console.log(`  category:   ${d.category}`);
  console.log(`  material:   ${d.material || '(unclear)'}`);
  console.log(`  condition:  ${d.condition}`);
  console.log(`  confidence: ${d.identifyConfidence}${d.closeupHint ? ` (a close-up of "${d.closeupHint}" would help)` : ''}`);
  console.log(`  flags:      fragile=${d.fragile} maybeSentimental=${d.maybeSentimental}`);
  console.log(`  notes:      ${d.notes}`);
  console.log(`  dims:       none (vision doesn't measure; the app gets them from the LiDAR scan)`);

  const priced = { ...(d as object), name: nameOverride || d.name, widthM: 0, heightM: 0, depthM: 0 } as unknown as Item;
  const q = queryFor(priced);
  hr('Query');
  console.log(`"${q}"${nameOverride ? `  (--name override; vision said "${d.name}")` : ''}`);
  console.log(`item for the filter/prior: ${describeItem(priced)}`);

  // ---------- 2. prior (runs alongside the comps lookup, like pricing.ts) ----------
  // The guess sees the latest photo, as in pricing.ts.
  const last = photos.length - 1;
  const photo = { mediaType: `image/${kinds[last] === 'jpg' ? 'jpeg' : kinds[last]}`, data: readFileSync(photos[last]).toString('base64') } as import('../src/integrations/photos.js').ImageInput;
  const priorP = pricePrior(priced, { cacheFile: stagedCache(priorCacheFile(q)), photo }).catch(err => ({ status: 'failed' as const, error: String(err) }));

  // ---------- 3. comps ----------
  hr('Comps');
  let raw: Comp[] = [];
  let label = '';
  const exact = cachedComps(q);
  if (exact) {
    raw = exact;
    label = `[REPLAYED] exact cache ${cacheFile(q)}`;
  } else if (liveComps) {
    const n = config.apify.sources.length;
    const spent = apifySpentToday();
    console.log(`No cache for this query. Live Apify lookup: ${n} actor run(s) (${config.apify.sources.join(', ')}), about $0.05-0.10 total, at most $${(n * config.apify.maxUsdPerRun).toFixed(2)} (APIFY_MAX_USD_PER_RUN $${config.apify.maxUsdPerRun} each).`);
    console.log(`Apify spend today so far: ~$${spent.usd.toFixed(2)} of $${config.apify.maxUsdPerDay} (APIFY_MAX_USD_PER_DAY). Result is cached to ${cacheFile(q)}.`);
    const r = await lookupComps(q);
    raw = r.comps;
    label = r.replayed ? `[REPLAYED] ${cacheFile(q)}` : `LIVE Apify (${config.apify.sources.join(' + ')}), ~$${(apifySpentToday().usd - spent.usd).toFixed(3)}`;
  } else {
    const sim = similarCachedComps(q, priced.category);
    if (sim) {
      raw = sim.comps;
      label = `[REPLAYED, similar item "${sim.query}"] no cache for this query; cached real comps of the closest one (score ${sim.score.toFixed(2)}). Use --live-comps for real ones.`;
    } else {
      label = 'none: no exact or similar cache (use --live-comps for a real lookup)';
    }
  }
  console.log(`source: ${label}`);
  console.log(`raw comps: ${raw.length}`);

  const f = await filterComps(priced, raw, { cacheFile: stagedCache(filterCacheFile(q)) });
  if (raw.length) {
    const fLabel = { ok: `${config.models.fast} (live)`, cached: `${config.models.fast} [REPLAYED verdict]`, failed: `Claude failed (${f.error}), rule-filtered comps used`, skipped: 'Claude skipped' }[f.claude];
    if (f.claude === 'ok') steps.push(`comp filter: ${config.models.fast} judged ${Math.min(raw.length - f.droppedByRules.length, 40)} titles`);
    if (f.claude === 'cached') steps.push('comp filter: [REPLAYED] cached verdict, no call');
    console.log(`filter (${f.mode}): kept ${f.comps.length} of ${raw.length}; dropped ${f.droppedByRules.length} by rules, ${f.droppedByClaude.length} by ${fLabel}${f.reason ? `: ${f.reason}` : ''}`);
    const sources = Object.entries(f.comps.reduce<Record<string, number>>((m, c) => ((m[c.source] = (m[c.source] ?? 0) + 1), m), {}));
    console.log(`kept by source: ${sources.map(([s, n]) => `${s} ${n}`).join(', ') || '-'}`);
    for (const c of f.comps.slice(0, 6)) console.log(`  + ${usd(c.priceCents).padStart(6)}  ${c.title.slice(0, 80)}`);
    if (f.comps.length > 6) console.log(`  ... ${f.comps.length - 6} more`);
    for (const x of [...f.droppedByRules, ...f.droppedByClaude].slice(0, 4)) console.log(`  - ${usd(x.comp.priceCents).padStart(6)}  ${x.comp.title.slice(0, 60)}  (dropped: ${x.why.slice(0, 50)})`);
  }

  // ---------- 4. prior ----------
  hr('Prior (Claude, no comps)');
  const prior = await priorP;
  let priorR: { cents: number; lowCents: number; highCents: number } | undefined;
  if (prior.status === 'ok' || prior.status === 'cached') {
    priorR = prior;
    steps.push(prior.status === 'ok' ? `price prior: ${config.models.estimate} (live)` : 'price prior: [REPLAYED] cached answer, no call');
    console.log(`${prior.status === 'cached' ? '[REPLAYED] ' : ''}~${usd(prior.cents)} (${usd(prior.lowCents)}-${usd(prior.highCents)}) used, condition "${d.condition}", from the photo: ${prior.reason}`);
  } else {
    console.log(prior.status === 'failed' ? `failed: ${prior.error}` : `${prior.status} (PRICING_PRIOR=0?)`);
  }

  // ---------- 5. estimate ----------
  hr('Estimate');
  const tag = label.startsWith('[REPLAYED, similar') ? '[similar item] ' : label.startsWith('[REPLAYED]') ? '[REPLAYED] ' : '';
  const fmt = (e: ReturnType<typeof estimate>) => (e ? `${usd(e.est)}  (${usd(e.low)}-${usd(e.high)})` : '-');
  const final = estimate(f.comps, d.condition, { prior: priorR, borrowed: label.startsWith('[REPLAYED, similar') });
  const compsOnly = estimate(f.comps, d.condition);
  const priorOnly = priorR ? estimate([], d.condition, { prior: priorR }) : null;
  console.log(`FINAL:       ${tag}${fmt(final)}  ${final ? (final.n === 0 ? "from Claude's guess alone" : `from ${final.n} comps${final.fromPrior ? " + Claude's guess" : ''}`) : 'no comps and no prior'}`);
  console.log(`comps only:  ${tag}${fmt(compsOnly)}${compsOnly ? `  (${compsOnly.n} comps after 3x-median trim)` : ''}`);
  console.log(`prior only:  ${fmt(priorOnly)}  (Claude's guess for condition "${d.condition}", with its range)`);

  // ---------- 6. Claude calls ----------
  hr('Claude calls');
  const after = claudeSpentToday();
  for (const s of steps) console.log(`  ${s}`);
  console.log(`live calls this run: ${after.calls - claudeBefore.calls}, ~$${(after.usd - claudeBefore.usd).toFixed(4)}; today ~$${after.usd.toFixed(2)} of $${config.claudeMaxUsdPerDay} (CLAUDE_MAX_USD_PER_DAY)`);
  console.log('SpacetimeDB: not contacted (vision ran on an in-memory stand-in connection).');
} catch (err) {
  console.error(`\nfailed: ${err instanceof Error ? err.message : String(err)}`);
  process.exitCode = 1;
} finally {
  rmSync(uploadDir, { recursive: true, force: true });
}
