import type { Identity } from 'spacetimedb';
import type { Conn } from './spacetime.js';
import type { Payment } from './module_bindings/types.js';
import { logEvent } from './events.js';
import { createVisaCheckout, type VisaCheckout, type VisaSink } from './integrations/visa.js';

// Reducers don't return ids, so find the payment row we just inserted by its unique tx id.
function waitForPayment(conn: Conn, match: (p: Payment) => boolean, timeoutMs = 15_000): Promise<bigint> {
  return new Promise((resolve, reject) => {
    for (const p of conn.db.payment.iter()) if (match(p)) return resolve(p.id);
    const timer = setTimeout(() => {
      conn.db.payment.removeOnInsert(cb);
      reject(new Error('payment row did not appear'));
    }, timeoutMs);
    const cb = (_ctx: unknown, p: Payment) => {
      if (!match(p)) return;
      clearTimeout(timer);
      conn.db.payment.removeOnInsert(cb);
      resolve(p.id);
    };
    conn.db.payment.onInsert(cb);
  });
}

// Writes Visa payments and their steps through record_payment / update_payment / log_agent_event.
export function visaSink(conn: Conn): VisaSink {
  return {
    async recordPayment(p) {
      const owner = p.owner as Identity;
      const match = (r: Payment) =>
        r.rail === 'visa' && r.txHash === p.txHash && r.refTable === p.refTable && r.refId === p.refId && r.owner.isEqual(owner);
      const id = waitForPayment(conn, match);
      id.catch(() => undefined); // handled by the await below; avoids an unhandled rejection if the reducer throws
      await conn.reducers.recordPayment({ ...p, owner });
      return id;
    },
    async updatePayment(paymentId, status, txHash) {
      await conn.reducers.updatePayment({ paymentId, status, txHash });
    },
    async logAgentEvent(e) {
      logEvent(conn, { owner: e.owner as Identity, agent: e.agent, kind: e.kind, message: e.message, refTable: e.refTable, refId: e.refId, data: e.data });
    },
  };
}

let checkout: VisaCheckout | undefined;

// One shared checkout per worker process, so the card budget spans every buy-agent run.
export function visaCheckout(conn: Conn): VisaCheckout {
  if (!checkout) {
    checkout = createVisaCheckout(visaSink(conn));
    // The card budget is per process; count the last 24h of pending/settled card payments so a
    // restart doesn't hand the agents a fresh cap. Simulated rows never count, so rehearsals don't use
    // up the demo budget (same idea as x402's seeding). VISA_SEED_BUDGETS=0 turns this off.
    const since = Date.now() - 24 * 3600 * 1000;
    const prior = new Map<string, bigint>();
    for (const p of process.env.VISA_SEED_BUDGETS === '0' ? [] : conn.db.payment.iter()) {
      if (p.rail === 'visa' && !p.simulated && (p.status === 'pending' || p.status === 'settled') && p.createdAt.toMillis() >= since) {
        prior.set(p.agent, (prior.get(p.agent) ?? 0n) + p.amountUsdMicros / 10_000n);
      }
    }
    for (const [agent, cents] of prior) checkout.seedSpent(agent, cents);
    console.log(`[visa] checkout ready (${checkout.simulated ? 'SIMULATED' : checkout.provider})`);
  }
  return checkout;
}
