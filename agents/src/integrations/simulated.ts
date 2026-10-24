// Track rule: anything simulated is visibly labeled. Payment rails run every agent_event message
// through this when the rail/provider is simulated; real-mode messages are left as they are.
export const SIMULATED_PREFIX = '[SIMULATED] ';

/** Prefixes `[SIMULATED] ` unless the message already has it. */
export function simulatedLabel(message: string): string {
  return message.startsWith(SIMULATED_PREFIX) ? message : SIMULATED_PREFIX + message;
}
