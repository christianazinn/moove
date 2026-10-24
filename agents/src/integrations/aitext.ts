// AI-generated text detection (#18): scores listing copy 0 (human) .. 1 (AI-written) so the fraud
// screen can flag templated / generated scam listings. Backed by Christian's open-source Pangram
// replication, reached over plain HTTP:
//
//   POST ${PANGRAM_URL}   Content-Type: application/json   [Authorization: Bearer ${PANGRAM_TOKEN}]
//   request:  {"text": "<listing text>"}
//   response: {"score": 0.93}      (0..1, higher = more likely AI-generated)
//
// If the service's shape differs, change only toRequestBody() / parseScore() below. parseScore
// already accepts a few common alternatives ({ai_score}, {probability}, {fraction_ai}, a bare
// number, or [{score}]). With PANGRAM_URL unset there is no detector and deals get ai_text_score -1.

export interface AiTextDetector {
  name: string;
  // 0..1 likelihood the text is AI-generated. Throws on transport / shape errors.
  score(text: string): Promise<number>;
}

export function toRequestBody(text: string): unknown {
  return { text };
}

const SCORE_KEYS = ['score', 'ai_score', 'aiScore', 'probability', 'prob_ai', 'fraction_ai', 'ai_likelihood'];

export function parseScore(body: unknown): number {
  let v: unknown = body;
  if (Array.isArray(v)) v = v[0];
  if (v && typeof v === 'object') {
    const o = v as Record<string, unknown>;
    v = SCORE_KEYS.map(k => o[k]).find(x => x !== undefined);
  }
  const n = typeof v === 'string' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n > 1) {
    throw new Error(`AI-text detector returned no 0..1 score: ${JSON.stringify(body).slice(0, 200)}`);
  }
  return n;
}

export function pangramDetector(opts: {
  url: string;
  token?: string;
  timeoutMs?: number;
  fetch?: typeof fetch;
}): AiTextDetector {
  const doFetch = opts.fetch ?? fetch;
  return {
    name: 'pangram',
    async score(text) {
      const headers: Record<string, string> = { 'content-type': 'application/json' };
      if (opts.token) headers.authorization = `Bearer ${opts.token}`;
      const res = await doFetch(opts.url, {
        method: 'POST',
        headers,
        body: JSON.stringify(toRequestBody(text)),
        signal: AbortSignal.timeout(opts.timeoutMs ?? 8000),
      });
      if (!res.ok) throw new Error(`AI-text detector: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`);
      return parseScore(await res.json());
    },
  };
}

// The configured detector, or null when PANGRAM_URL is unset (ai_text_score stays -1).
export function chooseAiTextDetector(env: Record<string, string | undefined> = process.env): AiTextDetector | null {
  const url = env.PANGRAM_URL?.trim();
  if (!url) return null;
  return pangramDetector({ url, token: env.PANGRAM_TOKEN || undefined, timeoutMs: Number(env.PANGRAM_TIMEOUT_MS) || 8000 });
}
