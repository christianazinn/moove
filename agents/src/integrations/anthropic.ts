import Anthropic from '@anthropic-ai/sdk';
import { betaZodOutputFormat } from '@anthropic-ai/sdk/helpers/beta/zod';
import { z } from 'zod';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { config } from '../config.js'; // also loads .env.local before the client reads ANTHROPIC_API_KEY
import { loadPhoto, type ImageInput } from './photos.js';

// Credentials resolve from ANTHROPIC_API_KEY (or an `ant auth login` profile).
export const anthropic = new Anthropic();

export type { ImageInput } from './photos.js';

// Loads a photo and base64-encodes it, so the API never needs to reach a localhost/LAN URL itself.
// Never fetches arbitrary URLs (SSRF, #44): our own uploads are read from disk, anything else must be
// https on an ALLOWED_PHOTO_HOSTS host with public addresses. See photos.ts.
export function loadImage(url: string): Promise<ImageInput> {
  return loadPhoto(url, {
    publicUploadBaseUrl: config.publicUploadBaseUrl,
    uploadDir: config.uploadDir,
    allowedHosts: config.allowedPhotoHosts,
  });
}

export class RefusalError extends Error {}

// One structured-output call: images + instructions in, schema-validated object out.
// LLM_REPLAY=record|replay|auto records answers to LLM_REPLAY_DIR (fixtures/llm) and replays them, so tests
// and the E2E run (scripts/e2e.ts) don't spend the API budget; off (default) always calls the API.
// Server-side fallbacks re-run on another model if the request is declined. Haiku has none,
// so pass fallbacks: false for MODEL_FAST calls.
export async function structuredCall<S extends z.ZodType>(opts: {
  model: string;
  system: string;
  text: string;
  images?: ImageInput[];
  schema: S;
  effort?: 'low' | 'medium' | 'high';
  // Thinking counts toward this, so leave room above the answer's size.
  maxTokens?: number;
  fallbacks?: boolean;
}): Promise<z.infer<S>> {
  const mode = replayMode();
  if (mode === 'off') return liveCall(opts);
  const key = replayKey(opts);
  const file = path.join(config.llmReplayDir, `${key}.json`);
  if (mode !== 'record' && existsSync(file)) {
    const saved = JSON.parse(readFileSync(file, 'utf8')) as { output: unknown };
    console.log(`[llm] replayed ${key} (${opts.model})`);
    return opts.schema.parse(saved.output); // a schema change makes a stale recording fail loudly
  }
  if (mode === 'replay') throw new Error(`LLM_REPLAY=replay: no recorded answer ${key} for ${opts.model} (record it with LLM_REPLAY=auto)`);
  const output = await liveCall(opts);
  mkdirSync(config.llmReplayDir, { recursive: true });
  writeFileSync(file, JSON.stringify({ model: opts.model, output }, null, 2) + '\n');
  console.log(`[llm] recorded ${key} (${opts.model})`);
  return output;
}

export type ReplayMode = 'off' | 'record' | 'replay' | 'auto';
export function replayMode(raw = process.env.LLM_REPLAY): ReplayMode {
  const v = (raw ?? '').trim().toLowerCase();
  return v === 'record' || v === 'replay' || v === 'auto' ? v : 'off';
}

/**
 * True when structuredCall(opts) would answer from a recording (LLM_REPLAY=replay|auto and one exists
 * for these exact inputs), i.e. no API spend. Spend caps (homes/budget.ts) skip their slot for these,
 * so rehearsals on recorded answers don't use up the demo's budget.
 */
export function hasRecordedAnswer(opts: { model: string; system: string; text: string; images?: ImageInput[]; schema: z.ZodType }): boolean {
  const mode = replayMode();
  if (mode !== 'replay' && mode !== 'auto') return false;
  return existsSync(path.join(config.llmReplayDir, `${replayKey(opts)}.json`));
}

// Replayed or recorded answers must never reach the live DB (#17): a stale cassette would stand in
// for the model on real users' items. The worker refuses to start with LLM_REPLAY set against maincloud.
export function replayGuardError(mode: ReplayMode, spacetimeUri: string): string | null {
  if (mode === 'off' || !/maincloud\.spacetimedb\.com/i.test(spacetimeUri)) return null;
  return `LLM_REPLAY=${mode} is not allowed against maincloud (${spacetimeUri}): replayed/recorded Claude answers would land on the live DB. Unset LLM_REPLAY (or use a local SpacetimeDB).`;
}

/** Same model, prompts, images and output schema -> same key. */
export function replayKey(opts: { model: string; system: string; text: string; images?: ImageInput[]; schema: z.ZodType }): string {
  const h = createHash('sha256');
  h.update(JSON.stringify([opts.model, opts.system, opts.text, z.toJSONSchema(opts.schema)]));
  for (const img of opts.images ?? []) h.update(createHash('sha256').update(img.data).digest('hex'));
  return h.digest('hex').slice(0, 24);
}

// ---------- daily Claude spend cap ----------
// The API key's balance is small, and a scan now photographs every object, so a runaway loop or a
// big room could drain it mid-demo. Every live call is priced from its token usage (list prices
// per million tokens, input/output) and added to a per-day total in CLAUDE_SPEND_FILE. Past
// CLAUDE_MAX_USD_PER_DAY, live calls are refused (agents log the error; replayed answers are free).
const PRICE_PER_MTOK: Record<string, [number, number]> = {
  'claude-opus-5-5': [4, 20],
  'claude-sonnet-5-5': [2, 10],
  'claude-haiku-5-5': [0.1, 0.5],
  'claude-fable-5-1': [10, 50],
};
export class SpendCapError extends Error {}

export function callCostUsd(model: string, usage: { input_tokens?: number | null; output_tokens?: number | null; cache_read_input_tokens?: number | null; cache_creation_input_tokens?: number | null }): number {
  const [inP, outP] = PRICE_PER_MTOK[model] ?? PRICE_PER_MTOK['claude-opus-5-5']; // unknown model: assume the dearest common tier
  const input = (usage.input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0) * 1.25 + (usage.cache_read_input_tokens ?? 0) * 0.1;
  return (input * inP + (usage.output_tokens ?? 0) * outP) / 1_000_000;
}

type SpendLog = Record<string, { usd: number; calls: number }>;
const day = (d = new Date()) => d.toISOString().slice(0, 10);
function readSpend(): SpendLog {
  try {
    return JSON.parse(readFileSync(config.claudeSpendFile, 'utf8')) as SpendLog;
  } catch {
    return {};
  }
}
export function claudeSpentToday(): { usd: number; calls: number } {
  return readSpend()[day()] ?? { usd: 0, calls: 0 };
}
function addSpend(usd: number): { usd: number; calls: number } {
  const log = readSpend();
  const today = log[day()] ?? { usd: 0, calls: 0 };
  const next = { usd: today.usd + usd, calls: today.calls + 1 };
  try {
    mkdirSync(path.dirname(config.claudeSpendFile), { recursive: true });
    writeFileSync(config.claudeSpendFile, JSON.stringify({ ...log, [day()]: next }, null, 2));
  } catch (err) {
    console.warn(`[llm] couldn't record spend: ${String(err)}`);
  }
  return next;
}

async function liveCall<S extends z.ZodType>(opts: Parameters<typeof structuredCall<S>>[0]): Promise<z.infer<S>> {
  const cap = config.claudeMaxUsdPerDay;
  if (cap > 0) {
    const spent = claudeSpentToday();
    if (spent.usd >= cap) {
      throw new SpendCapError(`Claude spend cap reached: ~$${spent.usd.toFixed(2)} of $${cap.toFixed(2)} today (${spent.calls} calls); raise CLAUDE_MAX_USD_PER_DAY to continue`);
    }
  }
  const response = await anthropic.beta.messages.parse({
    model: opts.model,
    max_tokens: opts.maxTokens ?? 16000,
    ...(opts.fallbacks === false ? {} : { betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' as const }),
    system: opts.system,
    output_config: { format: betaZodOutputFormat(opts.schema), effort: opts.effort ?? 'low' },
    messages: [
      {
        role: 'user',
        content: [
          ...(opts.images ?? []).map(img => ({
            type: 'image' as const,
            source: { type: 'base64' as const, media_type: img.mediaType, data: img.data },
          })),
          { type: 'text' as const, text: opts.text },
        ],
      },
    ],
  });
  if (response.stop_reason === 'refusal') {
    throw new RefusalError(`declined: ${response.stop_details?.category ?? 'unknown'}`);
  }
  if (response.parsed_output == null) throw new Error(`no parsed output (stop_reason=${response.stop_reason})`);
  const total = addSpend(callCostUsd(response.model ?? opts.model, response.usage ?? {}));
  if (cap > 0 && total.usd >= cap * 0.8) console.warn(`[llm] ~$${total.usd.toFixed(2)} of the $${cap.toFixed(2)} daily Claude cap used (${total.calls} calls)`);
  return response.parsed_output;
}
