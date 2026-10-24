import type { Identity } from 'spacetimedb';
import type { Agent } from './types.js';
import type { Conn } from '../spacetime.js';
import type { Approval } from '../module_bindings/types.js';
import { logEvent } from '../events.js';
import { selectApprovalGateway, toBindingMessage, type ApprovalGateway } from '../integrations/auth0.js';

// Auth0 allows 5 CIBA requests per user per minute; stay at 4 to leave headroom.
// Exported so a test harness can shrink the window.
export const approvalTuning = { maxStartsPerWindow: 4, rateWindowMs: 60_000 };

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

function errText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

// Binding message for the phone, from the row being approved: the listing's title (kind
// listing, refId = listing.id) or the deal's title (kind purchase, refId = deal.id). If that row
// isn't in the cache, fall back to the summary: a "quoted" title, or the text after "for:".
export function bindingFor(conn: Conn, a: Approval): string {
  const action = a.kind === 'listing' ? 'sell' : 'buy';
  let title = a.kind === 'listing' ? conn.db.listing.id.find(a.refId)?.title : conn.db.deal.id.find(a.refId)?.title;
  if (!title) title = /"([^"]+)"/.exec(a.summary)?.[1] ?? /\bfor:\s*(.+)$/.exec(a.summary)?.[1] ?? a.summary;
  return toBindingMessage(action, title, a.amountCents);
}

// Sends pending approvals (#12) to the owner's phone via Auth0 CIBA (Guardian push) and records
// the phone's answer with record_ciba_decision (#42: worker-only, decidedVia = 'ciba'). The in-app
// inbox can decide the same row at any time with decide_approval; whichever lands first wins
// (both reject a second decision).
export const approvalAgent: Agent = {
  name: 'approval',
  start(conn) {
    const { gateway, mode } = selectApprovalGateway();
    console.log(`[approval] ${mode}`);

    const inFlight = new Set<bigint>(); // approval ids with a running handler
    const finished = new Set<bigint>(); // handled once; don't re-push on every row update
    const waitingForSub = new Set<bigint>(); // retried when the owner's user row gains an auth0Sub
    const startsByOwner = new Map<string, number[]>(); // owner hex -> recent CIBA start times

    const sim = (g: ApprovalGateway) => (g.simulated ? ' (simulated)' : '');
    const log = (
      a: Approval,
      kind: 'plan' | 'tool_call' | 'result' | 'approval' | 'error',
      message: string,
      data?: Record<string, unknown>
    ) =>
      logEvent(conn, {
        owner: a.owner,
        agent: 'approval',
        kind,
        message,
        refTable: 'approval',
        refId: a.id,
        data: gateway?.simulated ? { ...data, simulated: true } : data,
      });

    const stillPending = (id: bigint) => conn.db.approval.id.find(id)?.status === 'pending';

    // Waits until starting one more CIBA request for this owner stays within the rate limit.
    async function reserveStart(owner: Identity): Promise<void> {
      const key = owner.toHexString();
      for (;;) {
        const now = Date.now();
        const recent = (startsByOwner.get(key) ?? []).filter(t => now - t < approvalTuning.rateWindowMs);
        if (recent.length < approvalTuning.maxStartsPerWindow) {
          recent.push(now);
          startsByOwner.set(key, recent);
          return;
        }
        startsByOwner.set(key, recent);
        await sleep(recent[0]! + approvalTuning.rateWindowMs - now + 10);
      }
    }

    // SECURITY INVARIANT: this is the only place the worker decides an approval, and `status`
    // always comes from a real Auth0 CIBA poll result. The module only accepts it when
    // `cibaSubject` (the sub the gateway checked in the id_token) is the owner's user.auth0_sub.
    // The worker can't call decide_approval at all (owner-only since #42).
    function decideFromGateway(a: Approval, status: 'approved' | 'denied', cibaSubject: string): void {
      conn.reducers.recordCibaDecision({ approvalId: a.id, status, cibaSubject }).catch(err => {
        // Usually a race with an in-app decision that landed first.
        log(a, 'error', `Recording the phone decision failed: ${errText(err)}`);
      });
    }

    async function handle(a: Approval, g: ApprovalGateway): Promise<void> {
      const bindingMessage = bindingFor(conn, a);
      const user = conn.db.user.identity.find(a.owner);
      const auth0Sub = user?.auth0Sub ?? '';
      if (!auth0Sub) {
        waitingForSub.add(a.id);
        log(a, 'approval', 'No Auth0 user linked, waiting for in-app approval');
        return;
      }

      await reserveStart(a.owner);
      if (!stillPending(a.id)) {
        log(a, 'approval', 'Decided in the Moove app before the phone request went out');
        return;
      }

      let req;
      try {
        req = await g.start({ auth0Sub, bindingMessage });
      } catch (err) {
        log(a, 'error', `Could not send the phone approval request${sim(g)}: ${errText(err)}. Still waiting for in-app approval.`);
        return;
      }
      log(
        a,
        'tool_call',
        g.simulated
          ? `Simulated phone approval (Auth0 not configured), auto-approves shortly (simulated): ${bindingMessage}`
          : `Sent approval request to the owner's phone via Auth0 Guardian: ${bindingMessage}`,
        { gateway: g.name, bindingMessage, expiresInSec: Math.round((req.expiresAt - Date.now()) / 1000) }
      );

      let intervalSec = req.intervalSec;
      for (;;) {
        await sleep(intervalSec * 1000);
        if (!stillPending(a.id)) {
          log(a, 'approval', `Decided in the Moove app first (${conn.db.approval.id.find(a.id)?.status ?? 'gone'}), ignoring the phone request${sim(g)}`);
          return;
        }
        if (Date.now() >= req.expiresAt) {
          // Don't decide and don't re-push: the row stays pending for the in-app inbox.
          log(a, 'approval', `The phone request expired without an answer${sim(g)}, still waiting in the Moove app`);
          return;
        }
        let r;
        try {
          r = await g.poll(req.authReqId);
        } catch (err) {
          log(a, 'error', `Phone approval check failed${sim(g)}: ${errText(err)}. Still waiting for in-app approval.`);
          return;
        }
        if (r.status === 'pending') continue;
        if (r.status === 'slow_down') {
          intervalSec = r.intervalSec > intervalSec ? r.intervalSec : intervalSec + 5;
          continue;
        }
        if (!stillPending(a.id)) {
          log(a, 'approval', `Decided in the Moove app first (${conn.db.approval.id.find(a.id)?.status ?? 'gone'}), ignoring the phone answer${sim(g)}`);
          return;
        }
        // Auth0 reports expiry as access_denied too, so our own clock tells them apart.
        if (r.status === 'expired' || (r.status === 'denied' && Date.now() >= req.expiresAt)) {
          log(a, 'approval', `The phone request expired without an answer${sim(g)}, still waiting in the Moove app`);
          return;
        }
        if (r.status === 'approved') {
          decideFromGateway(a, 'approved', auth0Sub);
          log(a, 'approval', `Approved on the phone (${g.name})${sim(g)}`, { gateway: g.name, status: 'approved' });
        } else {
          decideFromGateway(a, 'denied', auth0Sub);
          log(a, 'approval', `Denied on the phone (${g.name})${sim(g)}`, { gateway: g.name, status: 'denied' });
        }
        return;
      }
    }

    function consider(a: Approval): void {
      if (a.status !== 'pending' || inFlight.has(a.id) || finished.has(a.id)) return;
      finished.add(a.id);
      if (!gateway) {
        log(a, 'approval', 'Auth0 not configured, waiting for in-app approval');
        return;
      }
      inFlight.add(a.id);
      handle(a, gateway)
        .catch(err => log(a, 'error', `Phone approval failed: ${errText(err)}`))
        .finally(() => inFlight.delete(a.id));
    }

    for (const a of conn.db.approval.iter()) consider(a);
    conn.db.approval.onInsert((_ctx, a) => consider(a));
    conn.db.approval.onUpdate((_ctx, _old, a) => consider(a));

    // An owner who links Auth0 after the request gets the phone push then.
    const retryOwner = (owner: Identity, auth0Sub: string) => {
      if (!auth0Sub) return;
      for (const id of [...waitingForSub]) {
        const a = conn.db.approval.id.find(id);
        if (!a || a.status !== 'pending') {
          waitingForSub.delete(id);
          continue;
        }
        if (!a.owner.isEqual(owner)) continue;
        waitingForSub.delete(id);
        finished.delete(id);
        consider(a);
      }
    };
    conn.db.user.onInsert((_ctx, u) => retryOwner(u.identity, u.auth0Sub));
    conn.db.user.onUpdate((_ctx, _old, u) => retryOwner(u.identity, u.auth0Sub));
  },
};
