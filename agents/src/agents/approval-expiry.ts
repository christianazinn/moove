import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Approval } from '../module_bindings/types.js';
import { logEvent } from '../events.js';

// #186: pending approvals nobody answers expire after APPROVAL_EXPIRE_HOURS, through the worker-only
// `expire_approval` reducer (#199, module side). The listing and buy agents then ask again while the
// listing/purchase still applies, at most APPROVAL_MAX_REASKS times per listing or deal.

// The module refuses to expire an approval younger than 15 minutes, so shorter settings are raised.
export const MIN_EXPIRE_MS = 15 * 60_000;

function numEnv(v: string | undefined, fallback: number): number {
  if (v === undefined || v.trim() === '') return fallback;
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/** Milliseconds until a pending approval expires; 0 = expiry off. */
export function expireAfterMs(hours: number): number {
  if (!(hours > 0)) return 0;
  return Math.max(MIN_EXPIRE_MS, Math.round(hours * 3_600_000));
}

// Read once at startup. Exported (mutable) so tests can change them.
export const approvalExpiry = {
  expireMs: expireAfterMs(numEnv(process.env.APPROVAL_EXPIRE_HOURS, 12)),
  maxReasks: Math.floor(numEnv(process.env.APPROVAL_MAX_REASKS, 2)),
};

type ApprovalLike = Pick<Approval, 'id' | 'kind' | 'refId' | 'status'>;

/** Pending and at least `expireMs` old (the boundary itself counts as stale). */
export function isStale(a: Pick<Approval, 'status' | 'requestedAt'>, nowMs: number, expireMs: number): boolean {
  if (expireMs <= 0 || a.status !== 'pending') return false;
  return nowMs - Number(a.requestedAt.toMillis()) >= expireMs;
}

/**
 * What to do about a listing or deal whose latest approval is `latest`, after an expiry. Counted from
 * the approval rows, not memory, so a restart can't ask more often: once the re-ask lands, the latest
 * row is pending again and this says 'none'.
 */
export function afterExpiry(
  approvals: Iterable<ApprovalLike>,
  kind: string,
  refId: bigint,
  maxReasks: number
): { action: 'none' } | { action: 'reask'; expired: bigint; attempt: number } | { action: 'give_up'; expiredCount: number } {
  let latest: ApprovalLike | undefined;
  let expiredCount = 0;
  for (const a of approvals) {
    if (a.kind !== kind || a.refId !== refId) continue;
    if (a.status === 'expired') expiredCount++;
    if (!latest || a.id > latest.id) latest = a;
  }
  if (latest?.status !== 'expired') return { action: 'none' };
  if (expiredCount > maxReasks) return { action: 'give_up', expiredCount };
  return { action: 'reask', expired: latest.id, attempt: expiredCount };
}

type ExpireFn = (args: { approvalId: bigint }) => Promise<void>;

/** The `expire_approval` reducer if these bindings have it (they do once #199 is in). */
export function expireReducer(conn: Conn): ExpireFn | undefined {
  const fn = (conn.reducers as unknown as { expireApproval?: ExpireFn }).expireApproval;
  return typeof fn === 'function' ? fn.bind(conn.reducers) : undefined;
}

// The bindings have the reducer but the running module doesn't (not republished yet).
export function isMissingReducer(err: unknown): boolean {
  return /no such reducer|reducer[^]*not found|unknown reducer|expire_approval[^]*(does not exist|not exist)/i.test(String(err instanceof Error ? err.message : err));
}

export interface ExpirySweeper {
  /** Expires every stale pending approval once. Resolves to how many expired. */
  sweep(): Promise<number>;
  readonly enabled: boolean;
}

/** One sweep loop's state. `now` and `expire` are injectable for tests (fake clock, fake reducer). */
export function createExpirySweeper(o: {
  conn: Conn;
  expireMs: number;
  now?: () => number;
  expire?: ExpireFn;
  say?: (line: string) => void;
}): ExpirySweeper {
  const { conn, expireMs } = o;
  const now = o.now ?? Date.now;
  const say = o.say ?? ((line: string) => console.log(`[approval-expiry] ${line}`));
  let expire = o.expire ?? expireReducer(conn);
  const inFlight = new Set<bigint>();
  const complained = new Set<bigint>(); // ids whose failure was logged; retried quietly on later sweeps

  if (expireMs <= 0) {
    say('off (APPROVAL_EXPIRE_HOURS=0)');
    expire = undefined;
  } else if (!expire) {
    say('off: this build has no expire_approval reducer yet (#199); pending approvals wait until decided');
  } else {
    say(`on: pending approvals expire after ${+(expireMs / 3_600_000).toFixed(2)} h`);
  }

  async function expireOne(a: Approval, fn: ExpireFn): Promise<boolean> {
    inFlight.add(a.id);
    try {
      await fn({ approvalId: a.id });
      const hours = +(expireMs / 3_600_000).toFixed(2);
      logEvent(conn, {
        owner: a.owner,
        agent: 'approval',
        kind: 'approval',
        message: `Expired after ${hours} h with no answer${a.kind === 'listing' ? ', the listing agent asks again if it still applies' : ', the buy agent asks again if it still applies'}`,
        refTable: 'approval',
        refId: a.id,
        data: { expireHours: hours, kind: a.kind, refId: a.refId },
      });
      return true;
    } catch (err) {
      if (isMissingReducer(err)) {
        expire = undefined;
        say('off: the running module has no expire_approval reducer yet (republish with #199); pending approvals wait until decided');
        return false;
      }
      // Usually a decision that landed first, or clock skew against the module's 15-minute floor.
      if (!complained.has(a.id)) {
        complained.add(a.id);
        logEvent(conn, { owner: a.owner, agent: 'approval', kind: 'error', message: `Could not expire the stale approval: ${String(err)}`, refTable: 'approval', refId: a.id });
      }
      return false;
    } finally {
      inFlight.delete(a.id);
    }
  }

  return {
    get enabled() {
      return !!expire;
    },
    async sweep() {
      let n = 0;
      const t = now();
      for (const a of [...conn.db.approval.iter()]) {
        const fn = expire;
        if (!fn) break;
        if (inFlight.has(a.id) || !isStale(a, t, expireMs)) continue;
        if (await expireOne(a, fn)) n++;
      }
      return n;
    },
  };
}

// Sweeps on start and then every quarter of the expiry window (at most every 5 minutes).
export const approvalExpiryAgent: Agent = {
  name: 'approval-expiry',
  start(conn) {
    const sweeper = createExpirySweeper({ conn, expireMs: approvalExpiry.expireMs });
    if (!sweeper.enabled) return;
    const run = () =>
      void sweeper.sweep().catch(err => console.warn(`[approval-expiry] sweep failed: ${String(err)}`));
    run();
    const every = Math.min(5 * 60_000, Math.max(60_000, Math.floor(approvalExpiry.expireMs / 4)));
    setInterval(() => {
      if (sweeper.enabled) run();
    }, every).unref?.();
  },
};
