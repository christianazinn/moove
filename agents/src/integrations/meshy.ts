import '../config.js'; // loads .env.local before MESHY_API_KEY is read

// Meshy image-to-3D: one photo in, a textured USDZ out (RealityKit loads it natively).
// Docs: https://docs.meshy.ai/en/api/image-to-3d
//   POST /openapi/v1/image-to-3d      { image_url (URL or data URI), target_formats: ['usdz'], ... } -> { result: <task id> }
//   GET  /openapi/v1/image-to-3d/:id  -> task { status: PENDING|IN_PROGRESS|SUCCEEDED|FAILED|CANCELED,
//                                              model_urls: { usdz }, task_error: { message }, consumed_credits }
// Plain REST, so no SDK. The key stays in the worker's env (MESHY_API_KEY); never ship it to the app.
// Cost: 30 credits per textured meshy-7.1 task (https://docs.meshy.ai/en/api/pricing); failed tasks are refunded.

export const MESHY_MODEL = 'meshy-7.1';
const API = 'https://api.meshy.ai/openapi/v1/image-to-3d';
const DEFAULT_MAX_BYTES = 50 * 1024 * 1024;
const ZIP_MAGIC = Buffer.from([0x50, 0x4b, 0x03, 0x04]); // PK\x03\x04: USDZ is an uncompressed zip

export interface MeshyRequest {
  /** data: URI or public URL of the photo (Meshy accepts base64 data URIs, JPG/PNG/WebP, 20 MB). */
  imageUrl: string;
}

export interface MeshyResult {
  usdz: Buffer;
  sourceUrl: string;
  taskId: string;
  credits: number;
}

export class MeshyError extends Error {}

type Fetch = typeof fetch;

interface MeshyTask {
  status?: string;
  model_urls?: { usdz?: string };
  task_error?: { message?: string };
  consumed_credits?: number;
}

/** True if the buffer starts like a zip (local file header), which every USDZ is. */
export function isZip(b: Buffer): boolean {
  return b.length >= 4 && b.subarray(0, 4).equals(ZIP_MAGIC);
}

export async function generateModel(
  req: MeshyRequest,
  opts: { key?: string; fetch?: Fetch; pollMs?: number; timeoutMs?: number; maxBytes?: number } = {}
): Promise<MeshyResult> {
  const key = opts.key ?? process.env.MESHY_API_KEY;
  if (!key) throw new MeshyError('MESHY_API_KEY is not set');
  const f = opts.fetch ?? fetch;
  const maxBytes = opts.maxBytes ?? DEFAULT_MAX_BYTES;
  const headers = { authorization: `Bearer ${key}`, 'content-type': 'application/json' };
  const deadline = Date.now() + (opts.timeoutMs ?? 10 * 60_000);

  const submit = await f(API, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      image_url: req.imageUrl,
      ai_model: MESHY_MODEL,
      should_texture: true,
      target_formats: ['usdz'], // only what the app loads; Meshy builds just the listed formats
      moderation: true,
    }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!submit.ok) throw new MeshyError(`submit: ${submit.status} ${await submit.text()}`);
  const taskId = ((await submit.json()) as { result?: string }).result;
  if (!taskId || !/^[\w-]+$/.test(taskId)) throw new MeshyError('submit: no task id');

  let task: MeshyTask;
  for (;;) {
    if (Date.now() > deadline) throw new MeshyError(`timed out waiting for ${taskId}`);
    const res = await f(`${API}/${taskId}`, { headers, signal: AbortSignal.timeout(30_000) });
    if (!res.ok) throw new MeshyError(`status: ${res.status}`);
    task = (await res.json()) as MeshyTask;
    if (task.status === 'SUCCEEDED') break;
    if (task.status !== 'PENDING' && task.status !== 'IN_PROGRESS') {
      throw new MeshyError(`task ${task.status ?? 'unknown'}${task.task_error?.message ? `: ${task.task_error.message}` : ''}`);
    }
    await new Promise(r => setTimeout(r, opts.pollMs ?? 5000));
  }

  const url = task.model_urls?.usdz;
  if (!url || !/^https:\/\//i.test(url)) throw new MeshyError('no USDZ in the result');
  const dl = await f(url, { signal: AbortSignal.timeout(120_000) });
  if (!dl.ok) throw new MeshyError(`download USDZ: ${dl.status}`);
  if (Number(dl.headers.get('content-length') ?? '0') > maxBytes) throw new MeshyError(`USDZ over ${maxBytes} bytes`);
  const usdz = Buffer.from(await dl.arrayBuffer());
  if (usdz.length > maxBytes) throw new MeshyError(`USDZ over ${maxBytes} bytes`);
  if (!isZip(usdz)) throw new MeshyError('download is not a USDZ (zip)');
  return { usdz, sourceUrl: url, taskId, credits: task.consumed_credits ?? 0 };
}

// ---------- simulated mode (MESHY_SIMULATED=1): a fixture USDZ built here, no network ----------

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(b: Buffer): number {
  let c = 0xffffffff;
  for (const byte of b) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

const FIXTURE_USDA = `#usda 1.0
(
    defaultPrim = "Model"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "Model"
{
    def Cube "Box"
    {
        double size = 0.5
    }
}
`;

/** A tiny valid USDZ: an uncompressed zip holding one .usda, with its data 64-byte aligned
 *  as the USDZ spec asks. Stands in for a Meshy result in simulated mode. */
export function fixtureUsdz(): Buffer {
  const name = Buffer.from('model.usda');
  const data = Buffer.from(FIXTURE_USDA);
  const crc = crc32(data);
  const pad = (64 - ((30 + name.length + 4) % 64)) % 64; // extra field = 4-byte header + padding
  const extra = Buffer.alloc(4 + pad);
  extra.writeUInt16LE(0x1986, 0); // private "padding" extra field id
  extra.writeUInt16LE(pad, 2);

  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4); // version needed
  local.writeUInt16LE(0, 6); // flags
  local.writeUInt16LE(0, 8); // stored
  local.writeUInt32LE(0, 10); // dos time/date
  local.writeUInt32LE(crc, 14);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(data.length, 22);
  local.writeUInt16LE(name.length, 26);
  local.writeUInt16LE(extra.length, 28);

  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(20, 4); // version made by
  central.writeUInt16LE(20, 6); // version needed
  central.writeUInt32LE(crc, 16);
  central.writeUInt32LE(data.length, 20);
  central.writeUInt32LE(data.length, 24);
  central.writeUInt16LE(name.length, 28);
  central.writeUInt32LE(0, 42); // local header offset

  const body = Buffer.concat([local, name, extra, data]);
  const dir = Buffer.concat([central, name]);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(dir.length, 12);
  end.writeUInt32LE(body.length, 16);
  return Buffer.concat([body, dir, end]);
}
