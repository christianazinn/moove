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
  // What phones/the worker use to fetch uploads; set to your LAN IP for devices.
  publicUploadBaseUrl: env('PUBLIC_UPLOAD_BASE_URL', 'http://localhost:8787'),
  models: {
    vision: env('MODEL_VISION', 'claude-sonnet-5-5'),
    fast: env('MODEL_FAST', 'claude-haiku-5-5'),
    agent: env('MODEL_AGENT', 'claude-opus-5-5'),
  },
};
