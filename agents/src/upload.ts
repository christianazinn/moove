import { createServer, type Server } from 'node:http';
import { createReadStream, existsSync, mkdirSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { config } from './config.js';
import { BadImageError, sanitizeUpload } from './imagemeta.js';
import { importHome, ImportInputError } from './homes/listing.js';
import { clientKey, diskQuota, rateLimiter } from './ratelimit.js';

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/heic': 'heic',
  'image/webp': 'webp',
  'model/vnd.usdz+zip': 'usdz',
  'application/json': 'json',
};
// html (simulated listing pages written by integrations/ebay.ts) and glb (SAM 3D models written
// by agents/sam3d.ts) are served but never accepted as uploads.
const TYPE: Record<string, string> = { ...Object.fromEntries(Object.entries(EXT).map(([t, e]) => [e, t])), html: 'text/html; charset=utf-8', glb: 'model/gltf-binary' };
// Served html is static and escaped; this CSP means even an escaping bug can't run script on this origin.
const HTML_CSP = "default-src 'none'; img-src * data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'";
// One flat name with a known extension: no slashes, traversal, dotfiles or directory listing.
// Uploads are named <uuid v4>.<ext> here, so they can't be guessed.
const FILE_RE = /^\/files\/([A-Za-z0-9][\w-]*\.(\w+))$/;

// Minimal file store for photos, USDZ scans and CapturedRoom JSON (SpacetimeDB isn't a blob store).
//   POST /upload[?name=...]  raw body, Content-Type header  -> 201 { "url": "<public url>" }
//   GET  /files/<name>                                       -> the file
//   GET  /healthz                                            -> 200 { "ok": true } (platform health checks)
//   POST /homes/import  JSON {url?, address?, beds?, ...}     -> 200 new-home draft (#89, homes/listing.ts)
// Hardening (#17): type allowlist + magic-byte check, size cap, EXIF/GPS stripped from JPEG/PNG,
// random UUID names (the client's ?name is ignored), no directory listing, nosniff + CSP, per-client
// rate limits on POST (429) and a cap on the upload dir's total size (507), see ratelimit.ts.
// Not yet: auth on POST (needs Auth0 login from #1; the iOS uploader already sends a Bearer token
// when it has one). See docs/security.md.
export function startUploadServer(port = config.uploadPort): Server {
  mkdirSync(config.uploadDir, { recursive: true });
  const uploadLimit = rateLimiter(config.uploadRatePerMin);
  const homesLimit = rateLimiter(config.homesRatePerMin);
  const quota = diskQuota(config.uploadDir, config.uploadDirMaxBytes);
  return createServer(async (req, res) => {
    res.setHeader('x-content-type-options', 'nosniff');
    try {
      const pathname = new URL(req.url ?? '/', 'http://x').pathname;
      if (req.method === 'GET' && pathname === '/healthz') return send(res, 200, { ok: true });
      if (req.method === 'POST' && pathname === '/upload') {
        if (!uploadLimit(clientKey(req))) return send(res, 429, { error: `over ${config.uploadRatePerMin} uploads a minute; try again shortly` });
        const type = (req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
        // HEIC can carry EXIF/GPS we can't strip cheaply, so it's refused rather than stored as-is.
        if (type === 'image/heic') return send(res, 415, { error: 'HEIC is not accepted (location metadata can\'t be stripped); send image/jpeg' });
        const ext = EXT[type];
        if (!ext) return send(res, 415, { error: `unsupported content-type ${type}` });
        const declared = Number(req.headers['content-length'] ?? '0');
        if (declared > config.uploadMaxBytes) return send(res, 413, { error: `over ${config.uploadMaxBytes} bytes` });
        const chunks: Buffer[] = [];
        let size = 0;
        for await (const c of req) {
          size += (c as Buffer).length;
          if (size > config.uploadMaxBytes) {
            res.setHeader('connection', 'close');
            send(res, 413, { error: `over ${config.uploadMaxBytes} bytes` });
            res.once('finish', () => req.destroy()); // let the 413 flush before dropping the socket
            return;
          }
          chunks.push(c as Buffer);
        }
        if (size === 0) return send(res, 400, { error: 'empty body' });
        const body = sanitizeUpload(type, Buffer.concat(chunks));
        if (!quota.fits(body.length)) return send(res, 507, { error: 'upload storage is full (UPLOAD_DIR_MAX_MB)' });
        const name = `${randomUUID()}.${ext}`;
        await writeFile(path.join(config.uploadDir, name), body, { flag: 'wx' });
        quota.add(body.length);
        return send(res, 201, { url: `${config.publicUploadBaseUrl}/files/${name}` });
      }
      if (req.method === 'POST' && pathname === '/homes/import') {
        if (!homesLimit(clientKey(req))) return send(res, 429, { error: `over ${config.homesRatePerMin} imports a minute; try again shortly` });
        return await homesImport(req, res);
      }
      const m = req.method === 'GET' && pathname.match(FILE_RE);
      if (m && TYPE[m[2]] && existsSync(path.join(config.uploadDir, m[1]))) {
        const headers: Record<string, string> = { 'content-type': TYPE[m[2]] };
        if (m[2] === 'html') headers['content-security-policy'] = HTML_CSP;
        res.writeHead(200, headers);
        return void createReadStream(path.join(config.uploadDir, m[1])).pipe(res);
      }
      send(res, 404, { error: 'not found' });
    } catch (err) {
      if (err instanceof BadImageError) return send(res, 422, { error: err.message });
      console.error('[upload]', err);
      send(res, 500, { error: 'internal error' }); // no paths or stack traces to clients
    }
  }).listen(port, () => console.log(`[upload] listening on :${port}`));
}

// Import a new home from a listing link / address / floor-plan images (#89). Small JSON body only.
const HOMES_IMPORT_MAX_BYTES = 64 * 1024;
async function homesImport(req: import('node:http').IncomingMessage, res: import('node:http').ServerResponse) {
  const type = (req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/json') return send(res, 415, { error: 'send Content-Type: application/json' });
  if (Number(req.headers['content-length'] ?? '0') > HOMES_IMPORT_MAX_BYTES) return send(res, 413, { error: `over ${HOMES_IMPORT_MAX_BYTES} bytes` });
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const c of req) {
    size += (c as Buffer).length;
    if (size > HOMES_IMPORT_MAX_BYTES) {
      res.setHeader('connection', 'close');
      send(res, 413, { error: `over ${HOMES_IMPORT_MAX_BYTES} bytes` });
      res.once('finish', () => req.destroy());
      return;
    }
    chunks.push(c as Buffer);
  }
  let body: unknown;
  try {
    body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return send(res, 400, { error: 'body is not valid JSON' });
  }
  try {
    send(res, 200, await importHome(body));
  } catch (err) {
    if (err instanceof ImportInputError) return send(res, 400, { error: err.message });
    console.error('[homes] import failed', err);
    send(res, 500, { error: `home import failed: ${(err instanceof Error ? err.message : String(err)).slice(0, 200)}` });
  }
}

function send(res: import('node:http').ServerResponse, status: number, body: unknown) {
  if (res.headersSent) return;
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}
