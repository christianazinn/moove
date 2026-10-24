import { createServer, type Server } from 'node:http';
import { createReadStream, existsSync, mkdirSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { config } from './config.js';
import { BadImageError, sanitizeUpload } from './imagemeta.js';

const EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/heic': 'heic',
  'image/webp': 'webp',
  'model/vnd.usdz+zip': 'usdz',
  'application/json': 'json',
};
// html is served (simulated listing pages written by integrations/ebay.ts) but never accepted as an upload.
const TYPE: Record<string, string> = { ...Object.fromEntries(Object.entries(EXT).map(([t, e]) => [e, t])), html: 'text/html; charset=utf-8' };
// Served html is static and escaped; this CSP means even an escaping bug can't run script on this origin.
const HTML_CSP = "default-src 'none'; img-src * data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'";
// One flat name with a known extension: no slashes, traversal, dotfiles or directory listing.
// Uploads are named <uuid v4>.<ext> here, so they can't be guessed.
const FILE_RE = /^\/files\/([A-Za-z0-9][\w-]*\.(\w+))$/;

// Minimal file store for photos, USDZ scans and CapturedRoom JSON (SpacetimeDB isn't a blob store).
//   POST /upload[?name=...]  raw body, Content-Type header  -> 201 { "url": "<public url>" }
//   GET  /files/<name>                                       -> the file
//   GET  /healthz                                            -> 200 { "ok": true } (platform health checks)
// Hardening (#17): type allowlist + magic-byte check, size cap, EXIF/GPS stripped from JPEG/PNG,
// random UUID names (the client's ?name is ignored), no directory listing, nosniff + CSP.
// Not yet: auth on POST (needs Auth0 login from #1; the iOS uploader already sends a Bearer token
// when it has one). See docs/security.md.
export function startUploadServer(port = config.uploadPort): Server {
  mkdirSync(config.uploadDir, { recursive: true });
  return createServer(async (req, res) => {
    res.setHeader('x-content-type-options', 'nosniff');
    try {
      const pathname = new URL(req.url ?? '/', 'http://x').pathname;
      if (req.method === 'GET' && pathname === '/healthz') return send(res, 200, { ok: true });
      if (req.method === 'POST' && pathname === '/upload') {
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
        const name = `${randomUUID()}.${ext}`;
        await writeFile(path.join(config.uploadDir, name), body, { flag: 'wx' });
        return send(res, 201, { url: `${config.publicUploadBaseUrl}/files/${name}` });
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

function send(res: import('node:http').ServerResponse, status: number, body: unknown) {
  if (res.headersSent) return;
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}
