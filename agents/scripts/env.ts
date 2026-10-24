// Loads the repo-root .env.local (gitignored) for local scripts. The worker gets env from its host.
try {
  process.loadEnvFile(new URL("../../.env.local", import.meta.url));
} catch {
  // no .env.local: fine, scripts fall back to simulated mode
}
