import { execFileSync } from 'node:child_process';
import type { Conn } from './spacetime.js';
import { config } from './config.js';
import { claudeSpentToday } from './integrations/anthropic.js';
import { apifySpentToday } from './integrations/apify.js';
import { visaCheckoutMode, type VisaEnv } from './integrations/visa.js';

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

export async function announceService(conn: Conn, now = new Date(), env: VisaEnv = process.env): Promise<void> {
  const entries: [string, string][] = [
    ['upload_base_url', config.publicUploadBaseUrl.replace(/\/+$/, '')],
    ['worker_version', workerVersion()],
    ['worker_started_at', now.toISOString()],
    // #191: so purchase approvals can say SIMULATED before anything is paid.
    ['visa_checkout', visaCheckoutMode(env)],
  ];
  for (const [key, value] of entries) {
    try {
      await conn.reducers.setServiceConfig({ key, value });
    } catch (err) {
      // A module older than #191 rejects visa_checkout; the app then just shows no checkout label.
      if (key === 'visa_checkout') console.warn(`[service] module did not accept visa_checkout=${value} (needs the #191 SERVICE_KEYS update): ${String(err)}`);
      else console.warn(`[service] could not set ${key}: ${String(err)}`);
    }
  }
  console.log(`[service] announced upload_base_url=${entries[0][1]} version=${entries[1][1]} visa_checkout=${entries[3][1]}`);
}

// Today's estimated spend against the daily caps (#169, #170), so the app can show the guardrails.
// The UTC day matches the spend files. Cap 0 means no cap.
export function spendToday(now = new Date()): string {
  const c = claudeSpentToday();
  const a = apifySpentToday();
  const r = (n: number) => Math.round(n * 10_000) / 10_000;
  return JSON.stringify({
    day: now.toISOString().slice(0, 10),
    claude: { usd: r(c.usd), calls: c.calls, capUsd: config.claudeMaxUsdPerDay },
    apify: { usd: r(a.usd), runs: a.runs, capUsd: config.apify.maxUsdPerDay },
  });
}

/** Writes spend_today now and whenever it changes (checked every `everyMs`). */
export function announceSpend(conn: Conn, everyMs = 60_000): NodeJS.Timeout {
  let last = '';
  const tick = () => {
    const v = spendToday();
    if (v === last) return;
    last = v;
    conn.reducers.setServiceConfig({ key: 'spend_today', value: v }).catch((err: unknown) => {
      last = '';
      console.warn(`[service] could not set spend_today: ${String(err)}`);
    });
  };
  tick();
  const t = setInterval(tick, everyMs);
  t.unref?.();
  return t;
}
