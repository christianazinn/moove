import { execFileSync } from 'node:child_process';
import type { Conn } from './spacetime.js';
import { config } from './config.js';

// Tells every client where to upload and which worker build is live (service_config table), so a
// new tunnel URL or a second backend needs no app rebuild. A failed write only logs.
export function workerVersion(): string {
  if (process.env.WORKER_VERSION) return process.env.WORKER_VERSION;
  try {
    return execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return 'unknown';
  }
}

export async function announceService(conn: Conn, now = new Date()): Promise<void> {
  const entries: [string, string][] = [
    ['upload_base_url', config.publicUploadBaseUrl.replace(/\/+$/, '')],
    ['worker_version', workerVersion()],
    ['worker_started_at', now.toISOString()],
  ];
  for (const [key, value] of entries) {
    try {
      await conn.reducers.setServiceConfig({ key, value });
    } catch (err) {
      console.warn(`[service] could not set ${key}: ${String(err)}`);
    }
  }
  console.log(`[service] announced upload_base_url=${entries[0][1]} version=${entries[1][1]}`);
}
