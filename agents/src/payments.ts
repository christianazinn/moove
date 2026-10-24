import type { Identity } from 'spacetimedb';
import type { Conn } from './spacetime.js';
import { logEvent } from './events.js';
import { createX402Rail, type PaymentSink, type X402Rail } from './integrations/x402.js';

// Writes x402 payments and their agent steps through the record_payment / log_agent_event
// reducers, so the app's spending log updates live. Owners are SpacetimeDB identities here.
export function spacetimeSink(conn: Conn): PaymentSink {
  return {
    // Awaited so failures are seen, but swallowed: the rail calls this after the payment already
    // settled on-chain, so a DB write failure must neither crash the worker nor read as a failed payment.
    async recordPayment(p) {
      try {
        await conn.reducers.recordPayment({ ...p, owner: p.owner as Identity });
      } catch (err) {
        const reason = (err as Error)?.message ?? String(err);
        console.warn(
          `[x402] record_payment failed (${reason}); payment NOT in DB: agent=${p.agent} status=${p.status} ` +
            `amountUsdMicros=${p.amountUsdMicros} simulated=${p.simulated} txHash=${p.txHash || '(none)'}`,
        );
        try {
          logEvent(conn, {
            owner: p.owner as Identity,
            agent: p.agent,
            kind: 'error',
            message: `Couldn't record x402 payment for ${p.purpose}: ${reason}`,
            refTable: p.refTable,
            refId: p.refId,
            data: { rail: 'x402', txHash: p.txHash, amountUsdMicros: p.amountUsdMicros, status: p.status, simulated: p.simulated, error: reason },
          });
        } catch (logErr) {
          console.warn('[x402] logging the record_payment failure also failed:', logErr);
        }
      }
    },
    async logAgentEvent(e) {
      logEvent(conn, {
        owner: e.owner as Identity,
        agent: e.agent,
        kind: e.kind,
        message: e.message,
        refTable: e.refTable,
        refId: e.refId,
        data: JSON.parse(e.dataJson),
      });
    },
  };
}

let rail: Promise<X402Rail> | undefined;

// One shared rail per worker process, so per-agent budgets span every agent run.
export function paymentRail(conn: Conn): Promise<X402Rail> {
  rail ??= createX402Rail(spacetimeSink(conn)).then((r) => {
    console.log(`[x402] rail ready (${r.simulated ? 'SIMULATED' : 'Base Sepolia'})`);
    return r;
  });
  return rail;
}
