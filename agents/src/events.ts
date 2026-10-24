import type { Identity } from 'spacetimedb';
import type { Conn } from './spacetime.js';

export type EventKind = 'plan' | 'tool_call' | 'result' | 'payment' | 'approval' | 'error';

// Every agent step should go through this so the app can show what agents did.
export function logEvent(
  conn: Conn,
  e: {
    owner: Identity;
    agent: string;
    kind: EventKind;
    message: string;
    refTable?: string;
    refId?: bigint;
    data?: unknown;
  }
): void {
  const dataJson = e.data === undefined ? '' : JSON.stringify(e.data, (_k, v) => (typeof v === 'bigint' ? v.toString() : v));
  conn.reducers
    .logAgentEvent({ owner: e.owner, agent: e.agent, kind: e.kind, message: e.message, refTable: e.refTable ?? '', refId: e.refId ?? 0n, dataJson })
    // A failed log write (e.g. while reconnecting) must never crash the worker.
    .catch(err => console.warn(`[${e.agent}] could not log event: ${String(err)}`));
  console.log(`[${e.agent}] ${e.kind}: ${e.message}`);
}
