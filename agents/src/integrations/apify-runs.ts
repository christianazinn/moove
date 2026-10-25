// One queue for every Apify actor run in this worker: pricing comps, deal search, Google Lens,
// product images and the Zillow import. The free plan allows 5 concurrent runs and 16 GB of run
// memory; when several agents ran at once during a big scan, Apify refused runs with
// "concurrent-runs-limit-exceeded" / "actor-memory-limit-exceeded" (Rio's Oct 24 receipts: 39
// comps purchases "failed" with HTTP 502 that way). Runs above `APIFY_MAX_CONCURRENT_RUNS`
// wait their turn, and a refusal for capacity is retried after a short wait.
type Fetch = typeof fetch;

let active = 0;
const waiting: (() => void)[] = [];

export function apifyMaxRuns(): number {
  return Math.max(1, Number(process.env.APIFY_MAX_CONCURRENT_RUNS ?? 3) || 3);
}

/** Runs waiting for a slot and running now (for tests and logs). */
export function apifyRunState(): { active: number; waiting: number } {
  return { active, waiting: waiting.length };
}

async function acquire(): Promise<void> {
  if (active < apifyMaxRuns()) {
    active++;
    return;
  }
  await new Promise<void>(resolve => waiting.push(resolve));
  active++;
}

function release(): void {
  active--;
  waiting.shift()?.();
}

/** Apify said it's at capacity (too many runs or too much memory in use), not a real failure. */
export function isApifyCapacityError(text: string): boolean {
  return /concurrent-runs-limit|actor-memory-limit|memory limit of \d+MB/i.test(text);
}

const RETRY_MS = (process.env.APIFY_CAPACITY_RETRY_MS ?? '10000,30000').split(',').map(Number).filter(n => n >= 0);

/**
 * `fetch` for an Apify run: waits for a slot, and on a capacity refusal (HTTP 402/429 with a
 * concurrent-runs or memory-limit error) releases the slot, waits and tries again. The final
 * response is returned with its body intact either way.
 */
export async function apifyFetch(url: URL | string, init: RequestInit, fetchImpl: Fetch = fetch): Promise<Response> {
  for (let attempt = 0; ; attempt++) {
    await acquire();
    let res: Response;
    try {
      res = await fetchImpl(url, init);
    } finally {
      release();
    }
    if (res.ok || (res.status !== 402 && res.status !== 429) || attempt >= RETRY_MS.length) return res;
    const text = await res.text();
    const again = new Response(text, { status: res.status, statusText: res.statusText, headers: res.headers });
    if (!isApifyCapacityError(text)) return again;
    console.warn(`[apify] at capacity (${res.status}), retrying in ${RETRY_MS[attempt] / 1000}s`);
    await new Promise(r => setTimeout(r, RETRY_MS[attempt]));
  }
}
