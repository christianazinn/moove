import { numberFromEnv } from './integrations/caps.js';
import { parseAllowedHosts } from './integrations/photos.js';

// Loads ../.env.local (repo root) then agents/.env.local if present. See root .env.example.
for (const f of ['../.env.local', '.env.local']) {
  try {
    process.loadEnvFile(f);
  } catch {
    // file is optional
  }
}

const env = (k: string, d = '') => process.env[k] ?? d;

export const config = {
  spacetimeUri: env('SPACETIME_URI', 'ws://localhost:3000'),
  spacetimeDb: env('SPACETIME_DB_NAME', 'moove'),
  // Persisted worker credentials: the first identity to call register_worker owns the
  // worker role, so the same token must be reused across restarts.
  workerTokenFile: env('SPACETIME_WORKER_TOKEN_FILE', '.worker-token'),
  workerToken: env('SPACETIME_WORKER_TOKEN'),
  uploadPort: Number(env('UPLOAD_PORT', '8787')),
  uploadDir: env('UPLOAD_DIR', 'uploads'),
  // Largest accepted upload (USDZ scans are the big ones).
  uploadMaxBytes: Number(env('UPLOAD_MAX_BYTES', String(50 * 1024 * 1024))),
  // Per-client POST limits and a cap on the upload dir's size (src/ratelimit.ts); 0 = off.
  uploadRatePerMin: Number(env('UPLOAD_RATE_PER_MIN', '120')),
  homesRatePerMin: Number(env('HOMES_IMPORT_RATE_PER_MIN', '6')),
  uploadDirMaxBytes: Number(env('UPLOAD_DIR_MAX_MB', '2048')) * 1024 * 1024,
  // What phones/the worker use to fetch uploads; set to your LAN IP for devices.
  publicUploadBaseUrl: env('PUBLIC_UPLOAD_BASE_URL', 'http://localhost:8787'),
  // Extra https hosts the vision agent may fetch photos from (#44, comma-separated, default none).
  // Our own uploads are read from uploadDir on disk and never fetched.
  allowedPhotoHosts: parseAllowedHosts(env('ALLOWED_PHOTO_HOSTS')),
  // Paywalled comps endpoint the pricing agent buys from over x402 (#7); bound to 127.0.0.1.
  x402Port: Number(env('X402_PORT', '8402')),
  apify: {
    token: env('APIFY_TOKEN'),
    // Comma-separated subset of: ebay, fb, craigslist
    sources: env('APIFY_SOURCES', 'ebay,fb').split(',').map(s => s.trim()).filter(Boolean),
    maxUsdPerRun: Number(env('APIFY_MAX_USD_PER_RUN', '0.10')),
    // Daily cap on estimated Apify spend (comps, deals, Lens; 0 = no cap); running total in spendFile.
    maxUsdPerDay: Number(env('APIFY_MAX_USD_PER_DAY', '5')),
    spendFile: env('APIFY_SPEND_FILE', '.cache/apify-spend.json'),
    city: { fb: env('MARKET_CITY_FB', 'sanfrancisco'), craigslist: env('MARKET_CITY_CRAIGSLIST', 'sfbay') },
    // Opt-in Zillow scraper for POST /homes/import (#89, useScraper: true only). See homes/zillowApify.ts.
    zillowActor: env('APIFY_ZILLOW_ACTOR', 'maxcopell~zillow-detail-scraper'),
  },
  // Reverse image search (#292): Google Lens on an item's photo when vision isn't sure of the exact
  // product and the model matters for its price. Off with VISION_LENS=0 or without APIFY_TOKEN.
  lens: {
    enabled: env('VISION_LENS', '1') !== '0',
    maxMatches: Math.max(1, Number(env('LENS_MAX_MATCHES', '8'))),
    // Booked against APIFY_MAX_USD_PER_DAY before each live search: $0.008 search + $0.01 run start.
    maxUsdPerSearch: Number(env('LENS_MAX_USD_PER_SEARCH', '0.02')),
    cacheDir: env('LENS_CACHE_DIR', 'fixtures/lens'),
  },
  // SAM 3D Objects on fal.ai (#65): 3D models of photographed items. Off without FAL_KEY.
  sam3d: {
    enabled: Boolean(env('FAL_KEY')),
    usdPerRun: Number(env('SAM3D_USD_PER_RUN', '0.02')),
    // Per worker run, covering fal + the Claude image pick + image searches (~$0.07 per item).
    maxUsd: Number(env('SAM3D_MAX_USD', '2.00')),
    // The cap covers this many hours (spend logged by earlier worker runs counts too).
    spendWindowH: Number(env('SAM3D_SPEND_WINDOW_H', '24')),
    concurrency: Number(env('SAM3D_CONCURRENCY', '2')),
    // After fal says it can't run (no balance, rate limit, outage), wait this long before retrying.
    retryLaterSec: Number(env('SAM3D_RETRY_LATER_SEC', '600')),
    // SAM 3D tries on one item before giving up (next-best image on each retry).
    maxAttempts: Math.max(1, Number(env('SAM3D_MAX_ATTEMPTS', '2'))),
    // Estimated cost of one Claude image pick (MODEL_VISION, up to ~8 images), for the spend cap.
    selectUsd: Number(env('SAM3D_SELECT_USD', '0.04')),
    // Web product images for items vision identified as a specific product (#84). 0 = photos only.
    webImages: env('SAM3D_WEB_IMAGES', '1') !== '0',
    webImagesMax: Math.max(0, Number(env('SAM3D_WEB_IMAGES_MAX', '6'))),
    // Cap on one Apify image search (maxTotalChargeUsd); cached searches are free.
    imageSearchMaxUsd: Number(env('SAM3D_IMAGE_SEARCH_MAX_USD', '0.03')),
    // Optional allowlist of hosts web images may come from (comma-separated). Empty = any public https host.
    productImageHosts: parseAllowedHosts(env('PRODUCT_IMAGE_HOSTS')),
  },
  // POST /homes/import (#89) spend cap (#17 follow-up): paid steps (Apify Zillow run, photo classifier,
  // floor-plan vision read) per window, re-counted from agent_event on start. See homes/budget.ts.
  // A bad value (e.g. "30x" -> NaN) used to mean no cap at all; now it warns and uses the default.
  homes: {
    maxPaidCalls: Math.floor(numberFromEnv(process.env.HOMES_MAX_PAID_CALLS, 'HOMES_MAX_PAID_CALLS', 30, { min: 0 })),
    spendWindowH: numberFromEnv(process.env.HOMES_SPEND_WINDOW_H, 'HOMES_SPEND_WINDOW_H', 24, { above: 0 }),
  },
  // POST /moves/quotes (moves/quotes.ts): rate-table estimates, plus optional Craigslist listed rates.
  moves: {
    ratePerMin: Number(env('MOVES_QUOTES_RATE_PER_MIN', '20')),
    // Off by default: one Apify run (Craigslist "labor & moving" ads) per uncached request, within APIFY_MAX_USD_PER_DAY.
    apifyMovers: env('APIFY_MOVERS', '0') === '1',
    craigslistCity: env('MARKET_CITY_CRAIGSLIST', 'sfbay').trim() || 'sfbay',
  },
  // Recorded Claude answers for LLM_REPLAY (see integrations/anthropic.ts).
  llmReplayDir: env('LLM_REPLAY_DIR', 'fixtures/llm'),
  // Daily cap on estimated live Claude spend (0 = no cap); the running total lives in claudeSpendFile.
  claudeMaxUsdPerDay: Number(env('CLAUDE_MAX_USD_PER_DAY', '3')),
  claudeSpendFile: env('CLAUDE_SPEND_FILE', '.cache/claude-spend.json'),
  models: {
    vision: env('MODEL_VISION', 'claude-sonnet-5-5'),
    fast: env('MODEL_FAST', 'claude-haiku-5-5'),
    agent: env('MODEL_AGENT', 'claude-opus-5-5'),
  },
};
