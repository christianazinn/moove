// Spend caps read from env (x402 + Visa). A typo like AGENT_SPEND_CAP_USDC=5usd or a negative value
// used to turn into NaN / a negative budget: the x402 rail failed to build (BigInt(NaN)) or refused
// every call, and pricing quietly fell back to unpaid lookups for the whole run. Now a bad value logs a
// loud warning and the default is used; the worker never crashes over it. Unset/empty = default,
// and an explicit 0 still means "no spending on this rail".

export const SPEND_CAP_DEFAULTS = {
  AGENT_SPEND_CAP_USDC: 5,
  X402_MAX_PER_CALL_USDC: 0.1,
  VISA_SPEND_CAP_USD: 1500,
  VISA_MAX_PER_PURCHASE_USD: 750,
} as const;
export type SpendCapKey = keyof typeof SPEND_CAP_DEFAULTS;
export type SpendCapEnv = { [K in SpendCapKey]?: string };

type Warn = (msg: string) => void;
const warned = new Set<string>();

/** Dollars for `key`: the env value if it is a finite number >= 0, else the default (with a warning). */
export function usdCapFromEnv(env: SpendCapEnv, key: SpendCapKey, warn: Warn = console.warn): number {
  const d = SPEND_CAP_DEFAULTS[key];
  const raw = env[key];
  if (raw === undefined || raw.trim() === '') return d;
  const n = Number(raw);
  if (Number.isFinite(n) && n >= 0) return n;
  // Once per key+value per process: the startup check and the rail/checkout constructors share this.
  const seen = `${key}=${raw}`;
  if (!warned.has(seen)) {
    warned.add(seen);
    warn(`[caps] WARNING: ${key}=${JSON.stringify(raw)} is not a number >= 0; using the default ${d}. Fix it in .env.local.`);
  }
  return d;
}

/** Startup check (index.ts): warns about every bad cap at boot instead of at the first payment. */
export function checkSpendCaps(env: SpendCapEnv = process.env, warn: Warn = console.warn): Record<SpendCapKey, number> {
  const out = {} as Record<SpendCapKey, number>;
  for (const key of Object.keys(SPEND_CAP_DEFAULTS) as SpendCapKey[]) out[key] = usdCapFromEnv(env, key, warn);
  return out;
}

/** Test hook: forget which bad values were already warned about. */
export function resetCapWarnings(): void {
  warned.clear();
}
