import '../config.js'; // loads .env.local before FAL_KEY is read

// Meta SAM 3D Objects on fal.ai (`fal-ai/sam-3/3d-objects`): one photo + a text prompt
// naming the object in, a GLB mesh out. Docs: https://fal.ai/models/fal-ai/sam-3/3d-objects/api
// Uses fal's queue REST API directly (submit, poll status, fetch result), so no SDK.
// The key stays in the worker's env (FAL_KEY); never ship it to the app.

export const SAM3D_MODEL = 'fal-ai/sam-3/3d-objects';
const QUEUE = 'https://queue.fal.run';
const MAX_GLB_BYTES = 50 * 1024 * 1024;

export interface Sam3dRequest {
  /** data: URI or public URL of the photo (fal accepts base64 data URIs). */
  imageUrl: string;
  /** What to segment, e.g. "office chair". */
  prompt: string;
}

export interface Sam3dResult {
  glb: Buffer;
  sourceUrl: string;
  requestId: string;
}

export class Sam3dError extends Error {}

type Fetch = typeof fetch;

/** Pulls the mesh URL out of a SAM 3D result: the single/combined GLB, else the first per-object GLB. */
export function glbUrlFrom(output: unknown): string | undefined {
  const o = output as { model_glb?: { url?: string }; individual_glbs?: { url?: string }[] } | null;
  return o?.model_glb?.url ?? o?.individual_glbs?.find(g => g?.url)?.url;
}

export async function reconstruct(
  req: Sam3dRequest,
  opts: { key?: string; fetch?: Fetch; pollMs?: number; timeoutMs?: number } = {}
): Promise<Sam3dResult> {
  const key = opts.key ?? process.env.FAL_KEY;
  if (!key) throw new Sam3dError('FAL_KEY is not set');
  const f = opts.fetch ?? fetch;
  const headers = { authorization: `Key ${key}`, 'content-type': 'application/json' };
  const deadline = Date.now() + (opts.timeoutMs ?? 5 * 60_000);

  const submit = await f(`${QUEUE}/${SAM3D_MODEL}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ image_url: req.imageUrl, prompt: req.prompt, export_textured_glb: true }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!submit.ok) throw new Sam3dError(`submit: ${submit.status} ${await submit.text()}`);
  const queued = (await submit.json()) as { request_id: string; status_url: string; response_url: string };

  for (;;) {
    if (Date.now() > deadline) throw new Sam3dError(`timed out waiting for ${queued.request_id}`);
    const res = await f(queued.status_url, { headers, signal: AbortSignal.timeout(30_000) });
    if (!res.ok) throw new Sam3dError(`status: ${res.status}`);
    const { status } = (await res.json()) as { status: string };
    if (status === 'COMPLETED') break;
    if (status !== 'IN_QUEUE' && status !== 'IN_PROGRESS') throw new Sam3dError(`status ${status}`);
    await new Promise(r => setTimeout(r, opts.pollMs ?? 3000));
  }

  const result = await f(queued.response_url, { headers, signal: AbortSignal.timeout(30_000) });
  // 422: nothing matching the prompt was segmented; 400: unusable photo.
  if (!result.ok) throw new Sam3dError(`result: ${result.status} ${await result.text()}`);
  const url = glbUrlFrom(await result.json());
  if (!url || !/^https:\/\//i.test(url)) throw new Sam3dError('no GLB in the result');

  const glbRes = await f(url, { signal: AbortSignal.timeout(120_000) });
  if (!glbRes.ok) throw new Sam3dError(`download GLB: ${glbRes.status}`);
  const glb = Buffer.from(await glbRes.arrayBuffer());
  if (glb.length > MAX_GLB_BYTES) throw new Sam3dError(`GLB over ${MAX_GLB_BYTES} bytes`);
  if (glb.subarray(0, 4).toString('latin1') !== 'glTF') throw new Sam3dError('download is not a GLB');
  return { glb, sourceUrl: url, requestId: queued.request_id };
}
