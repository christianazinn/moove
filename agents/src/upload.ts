import { createServer } from 'node:http';
import { createReadStream, existsSync, mkdirSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { config } from './config.js';

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

// Minimal file store for photos, USDZ scans and CapturedRoom JSON (SpacetimeDB isn't a blob store).
//   POST /upload   raw body, Content-Type header  -> 201 { "url": "<public url>" }
//   GET  /files/<name>                             -> the file
export function startUploadServer(): void {
  mkdirSync(config.uploadDir, { recursive: true });
  createServer(async (req, res) => {
    try {
      if (req.method === 'POST' && req.url === '/upload') {
        const type = (req.headers['content-type'] ?? '').split(';')[0];
        const ext = EXT[type];
        if (!ext) return send(res, 415, { error: `unsupported content-type ${type}` });
        const chunks: Buffer[] = [];
        for await (const c of req) chunks.push(c as Buffer);
        const name = `${randomUUID()}.${ext}`;
        await writeFile(path.join(config.uploadDir, name), Buffer.concat(chunks));
        return send(res, 201, { url: `${config.publicUploadBaseUrl}/files/${name}` });
      }
      const m = req.method === 'GET' && req.url?.match(/^\/files\/([\w-]+\.(\w+))$/);
      if (m && existsSync(path.join(config.uploadDir, m[1]))) {
        res.writeHead(200, { 'content-type': TYPE[m[2]] ?? 'application/octet-stream' });
        return void createReadStream(path.join(config.uploadDir, m[1])).pipe(res);
      }
      send(res, 404, { error: 'not found' });
    } catch (err) {
      send(res, 500, { error: String(err) });
    }
  }).listen(config.uploadPort, () => console.log(`[upload] listening on :${config.uploadPort}`));
}

function send(res: import('node:http').ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}
