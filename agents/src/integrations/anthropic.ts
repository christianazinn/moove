import Anthropic from '@anthropic-ai/sdk';
import { betaZodOutputFormat } from '@anthropic-ai/sdk/helpers/beta/zod';
import type { z } from 'zod';

// Credentials resolve from ANTHROPIC_API_KEY (or an `ant auth login` profile).
export const anthropic = new Anthropic();

export type ImageInput = { mediaType: 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp'; data: string };

// Fetches an image (from our upload server or anywhere) and base64-encodes it, so the API
// never needs to reach a localhost/LAN URL itself.
export async function loadImage(url: string): Promise<ImageInput> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url}: ${res.status}`);
  const type = (res.headers.get('content-type') ?? '').split(';')[0];
  const mediaType = (['image/jpeg', 'image/png', 'image/gif', 'image/webp'] as const).find(t => t === type) ?? 'image/jpeg';
  return { mediaType, data: Buffer.from(await res.arrayBuffer()).toString('base64') };
}

export class RefusalError extends Error {}

// One structured-output call: images + instructions in, schema-validated object out.
// Server-side fallbacks re-run on another model if the request is declined.
export async function structuredCall<S extends z.ZodType>(opts: {
  model: string;
  system: string;
  text: string;
  images?: ImageInput[];
  schema: S;
  effort?: 'low' | 'medium' | 'high';
}): Promise<z.infer<S>> {
  const response = await anthropic.beta.messages.parse({
    model: opts.model,
    max_tokens: 16000,
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
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
