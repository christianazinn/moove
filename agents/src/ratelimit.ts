import { readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import type { IncomingMessage } from 'node:http';

// Abuse limits for the public upload port (the tunnel makes it reachable by anyone, and POST has
// no auth until #1). Per-client sliding window, plus a cap on the upload directory's total size.

/** At most `perMin` hits per key in any 60 s window. 0 = unlimited. */
export function rateLimiter(perMin: number) {
  const hits = new Map<string, number[]>();
  return (key: string, nowMs = Date.now()): boolean => {
    if (perMin <= 0) return true;
    const recent = (hits.get(key) ?? []).filter(t => nowMs - t < 60_000);
    if (recent.length >= perMin) {
      hits.set(key, recent);
      return false;
    }
    recent.push(nowMs);
    hits.set(key, recent);
    if (hits.size > 10_000) for (const [k, v] of hits) if (!v.some(t => nowMs - t < 60_000)) hits.delete(k);
    return true;
  };
}

/** The caller's address. Behind cloudflared every request comes from loopback, so there (and only
 * there) the tunnel's CF-Connecting-IP header names the real client. */
export function clientKey(req: IncomingMessage): string {
  const remote = req.socket.remoteAddress ?? '';
  const loopback = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
  const cf = req.headers['cf-connecting-ip'];
  return loopback && typeof cf === 'string' && cf ? cf : remote;
}

/** Total bytes stored under `dir`, counted once at start and then kept up to date by `add`. */
export function diskQuota(dir: string, maxBytes: number) {
  let used = 0;
  try {
    for (const f of readdirSync(dir)) used += statSync(path.join(dir, f)).size;
  } catch {
    // a missing dir is empty
  }
  return {
    fits: (n: number) => maxBytes <= 0 || used + n <= maxBytes,
    add: (n: number) => void (used += n),
    used: () => used,
  };
}
