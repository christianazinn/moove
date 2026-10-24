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
  models: {
    vision: env('MODEL_VISION', 'claude-sonnet-5-5'),
    fast: env('MODEL_FAST', 'claude-haiku-5-5'),
    agent: env('MODEL_AGENT', 'claude-opus-5-5'),
  },
};
