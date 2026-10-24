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

/** Meshy runs only when explicitly enabled AND it has a key (or is simulated). */
export function meshyEnabled(e: Record<string, string | undefined> = process.env): boolean {
  return e.MOOVE_MESHY_ENABLED === '1' && (Boolean(e.MESHY_API_KEY) || e.MESHY_SIMULATED === '1');
}

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
    city: { fb: env('MARKET_CITY_FB', 'sanfrancisco'), craigslist: env('MARKET_CITY_CRAIGSLIST', 'sfbay') },
  },
  // SAM 3D Objects on fal.ai (#65): 3D models of photographed items. Off without FAL_KEY.
  sam3d: {
    enabled: Boolean(env('FAL_KEY')),
    usdPerRun: Number(env('SAM3D_USD_PER_RUN', '0.02')),
    maxUsd: Number(env('SAM3D_MAX_USD', '1.00')), // per worker run, about 50 items
    concurrency: Number(env('SAM3D_CONCURRENCY', '2')),
  },
  // Meshy image-to-3D (#65): USDZ models of photographed items. Off by default: runs only with
  // MOOVE_MESHY_ENABLED=1 plus MESHY_API_KEY (or MESHY_SIMULATED=1, a fixture USDZ, no network).
  // While it runs, the SAM 3D agent stands down so no item is built twice.
  meshy: {
    enabled: meshyEnabled(),
    simulated: env('MESHY_SIMULATED') === '1',
    // 30 credits per textured meshy-7.1 task; USD per credit depends on the plan (~$0.02 assumed).
    usdPerRun: Number(env('MESHY_USD_PER_RUN', '0.60')),
    maxUsd: Number(env('MESHY_MAX_USD', '2.00')), // per worker run, about 3 items
    concurrency: Number(env('MESHY_CONCURRENCY', '1')),
    maxBytes: Number(env('MESHY_MAX_BYTES', String(50 * 1024 * 1024))),
  },
  models: {
    vision: env('MODEL_VISION', 'claude-sonnet-5-5'),
    fast: env('MODEL_FAST', 'claude-haiku-5-5'),
    agent: env('MODEL_AGENT', 'claude-opus-5-5'),
  },
};
