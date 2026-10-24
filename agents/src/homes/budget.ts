// Spend cap for POST /homes/import (#17 follow-up). The endpoint has no caller identity yet (upload
// auth waits on #1), so anyone who can reach the upload port can start imports. Each paid step (an
// Apify Zillow run, the listing-photo classifier, a floor-plan vision read) takes one slot, at most
// HOMES_MAX_PAID_CALLS per HOMES_SPEND_WINDOW_H. Paid steps log a tool_call with `paid: true`, and
// on start the worker re-counts those from agent_event (like sam3d's priorSpendUsd), so a restart
// doesn't reset the cap. Over the cap the step is skipped and the app estimates the plan instead.
// Claude steps answered from an LLM_REPLAY recording cost nothing: they take no slot and log
// `paid: false`, so rehearsals don't use up the demo's budget (hasRecordedAnswer in anthropic.ts).
import { config } from '../config.js';

let stamps: number[] = [];

const windowMs = () => config.homes.spendWindowH * 3600_000;

/** Takes one paid-call slot, or returns false when the window's cap is used up. */
export function takePaidCall(nowMs = Date.now(), max = config.homes.maxPaidCalls): boolean {
  stamps = stamps.filter(t => nowMs - t < windowMs());
  if (stamps.length >= max) return false;
  stamps.push(nowMs);
  return true;
}

export const OVER_CAP_NOTE = 'Skipped: the worker has used its listing-import budget for now (HOMES_MAX_PAID_CALLS).';

/** Thrown by a paid step that was skipped over the cap (the caller turns it into OVER_CAP_NOTE). */
export class OverCapError extends Error {
  constructor() {
    super(OVER_CAP_NOTE);
  }
}

/** Re-counts paid homes steps already logged (agent_event data `{requestId, detail: {paid: true}}`). */
export function seedHomesBudget(
  events: Iterable<{ agent: string; kind: string; dataJson: string; createdAt: { toMillis(): bigint } }>,
  nowMs = Date.now()
): number {
  stamps = [];
  for (const e of events) {
    if (e.agent !== 'homes' || e.kind !== 'tool_call' || !e.dataJson) continue;
    const at = Number(e.createdAt.toMillis());
    if (nowMs - at >= windowMs()) continue;
    try {
      if ((JSON.parse(e.dataJson) as { detail?: { paid?: unknown } }).detail?.paid === true) stamps.push(at);
    } catch {
      // not JSON
    }
  }
  return stamps.length;
}

/** Tests only. */
export function resetHomesBudget(): void {
  stamps = [];
}
