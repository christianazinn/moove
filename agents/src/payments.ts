import type { Identity } from 'spacetimedb';
import type { Conn } from './spacetime.js';
import { logEvent } from './events.js';
import { createX402Rail, type PaymentSink, type X402Rail } from './integrations/x402.js';

// Writes x402 payments and their agent steps through the record_payment / log_agent_event
// reducers, so the app's spending log updates live. Owners are SpacetimeDB identities here.
export function spacetimeSink(conn: Conn): PaymentSink {
  return {
    async recordPayment(p) {
      conn.reducers.recordPayment({ ...p, owner: p.owner as Identity });
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
