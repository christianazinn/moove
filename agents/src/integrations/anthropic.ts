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

/** Same model, prompts, images and output schema -> same key. */
export function replayKey(opts: { model: string; system: string; text: string; images?: ImageInput[]; schema: z.ZodType }): string {
  const h = createHash('sha256');
  h.update(JSON.stringify([opts.model, opts.system, opts.text, z.toJSONSchema(opts.schema)]));
  for (const img of opts.images ?? []) h.update(createHash('sha256').update(img.data).digest('hex'));
  return h.digest('hex').slice(0, 24);
}

async function liveCall<S extends z.ZodType>(opts: Parameters<typeof structuredCall<S>>[0]): Promise<z.infer<S>> {
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
  return response.parsed_output;
}
