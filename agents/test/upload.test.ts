import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { sanitizeUpload, stripJpeg, stripPng, stripWebp, BadImageError } from '../src/imagemeta.js';

// ---------- fixtures ----------
const seg = (marker: number, payload: Buffer) => {
  const h = Buffer.alloc(4);
  h[0] = 0xff;
  h[1] = marker;
  h.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([h, payload]);
};

// EXIF (little-endian) with Orientation=6 and a fake GPS IFD pointer, plus a GPS-looking string.
function exifApp1(orientation: number): Buffer {
  const tiff = Buffer.alloc(8 + 2 + 2 * 12 + 4 + 32);
  tiff.write('II', 0, 'latin1');
  tiff.writeUInt16LE(42, 2);
  tiff.writeUInt32LE(8, 4);
  tiff.writeUInt16LE(2, 8);
  tiff.writeUInt16LE(0x0112, 10); // Orientation
  tiff.writeUInt16LE(3, 12);
  tiff.writeUInt32LE(1, 14);
  tiff.writeUInt16LE(orientation, 18);
  tiff.writeUInt16LE(0x8825, 22); // GPSInfo IFD pointer
  tiff.writeUInt16LE(4, 24);
  tiff.writeUInt32LE(1, 26);
  tiff.writeUInt32LE(38, 30);
  tiff.write('GPS 37.8719N 122.2585W HOME', 38, 'latin1');
  return seg(0xe1, Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), tiff]));
}

const SCAN = Buffer.from([0x12, 0x34, 0xff, 0x00, 0x56, 0xff, 0xd0, 0x78]); // stuffed FF + restart marker
function jpeg(extra: Buffer[] = [], trailer = Buffer.alloc(0)): Buffer {
  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    seg(0xe0, Buffer.from('JFIF\0\x01\x01\0\0\x01\0\x01\0\0', 'latin1')),
    ...extra,
    seg(0xfe, Buffer.from('shot at 123 Main St', 'latin1')),
    seg(0xdb, Buffer.alloc(65, 1)), // DQT
    seg(0xc0, Buffer.from([8, 0, 1, 0, 1, 1, 1, 0x11, 0])), // SOF0
    seg(0xda, Buffer.from([1, 1, 0, 0, 0x3f, 0])), // SOS
    SCAN,
    Buffer.from([0xff, 0xd9]),
    trailer,
  ]);
}

// ---------- metadata stripping ----------
test('JPEG: EXIF/GPS, XMP, IPTC, comments and trailing data are removed', () => {
  const xmp = seg(0xe1, Buffer.from('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>GPSLatitude</x:xmpmeta>', 'latin1'));
  const iptc = seg(0xed, Buffer.from('Photoshop 3.0\0 Sublocation: Berkeley', 'latin1'));
  const trailer = Buffer.concat([Buffer.from([0xff, 0xd8]), exifApp1(1), Buffer.from([0xff, 0xd9])]); // MPF-style embedded image
  const out = stripJpeg(jpeg([exifApp1(6), xmp, iptc], trailer)).toString('latin1');
  for (const leak of ['GPS', '37.8719', 'Main St', 'xmpmeta', 'Berkeley', 'Photoshop']) {
    assert.ok(!out.includes(leak), `still contains ${leak}`);
  }
  assert.ok(out.includes('JFIF'), 'JFIF kept');
  assert.ok(out.endsWith(SCAN.toString('latin1') + '\xff\xd9'), 'scan data intact, ends at EOI');
});

test('JPEG: orientation survives so photos are not rotated', () => {
  const out = stripJpeg(jpeg([exifApp1(6)]));
  const i = out.indexOf(Buffer.from('Exif\0\0', 'latin1'));
  assert.ok(i > 0, 'minimal EXIF present');
  // big-endian TIFF, single IFD0 entry: 0x0112 SHORT 1 -> value 6
  assert.equal(out.readUInt16BE(i + 6 + 10), 0x0112);
  assert.equal(out.readUInt16BE(i + 6 + 18), 6);
  // No EXIF at all when orientation is the default.
  assert.equal(stripJpeg(jpeg([exifApp1(1)])).indexOf(Buffer.from('Exif', 'latin1')), -1);
});

test('PNG: eXIf and text chunks are removed', () => {
  const chunk = (type: string, data: Buffer) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    return Buffer.concat([len, Buffer.from(type, 'latin1'), data, Buffer.alloc(4)]);
  };
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', Buffer.alloc(13)),
    chunk('tEXt', Buffer.from('Location\x00 123 Main St', 'latin1')),
    chunk('eXIf', Buffer.from('GPS', 'latin1')),
    chunk('IDAT', Buffer.from('pixels', 'latin1')),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  const out = stripPng(png).toString('latin1');
  assert.ok(!out.includes('Main St') && !out.includes('GPS'));
  assert.ok(out.includes('IHDR') && out.includes('pixels') && out.includes('IEND'));
});

test('WebP: EXIF and XMP chunks are removed, flags and RIFF size fixed', () => {
  const chunk = (fourcc: string, data: Buffer) => {
    const h = Buffer.alloc(8);
    h.write(fourcc, 0, 'latin1');
    h.writeUInt32LE(data.length, 4);
    return Buffer.concat([h, data, data.length & 1 ? Buffer.alloc(1) : Buffer.alloc(0)]);
  };
  const vp8x = Buffer.alloc(10);
  vp8x[0] = 0x08 | 0x04 | 0x10; // EXIF + XMP + alpha
  const body = Buffer.concat([
    chunk('VP8X', vp8x),
    chunk('VP8L', Buffer.from('pixels!', 'latin1')), // odd length -> padded
    chunk('EXIF', Buffer.from('GPS 37.8719N 122.2585W', 'latin1')),
    chunk('XMP ', Buffer.from('<x:xmpmeta>Berkeley</x:xmpmeta>', 'latin1')),
  ]);
  const head = Buffer.alloc(12);
  head.write('RIFF', 0, 'latin1');
  head.writeUInt32LE(4 + body.length, 4);
  head.write('WEBP', 8, 'latin1');
  const out = stripWebp(Buffer.concat([head, body]));
  const str = out.toString('latin1');
  assert.ok(!str.includes('GPS') && !str.includes('Berkeley') && !str.includes('EXIF'));
  assert.ok(str.includes('pixels!'));
  assert.equal(out.readUInt32LE(4), out.length - 8, 'RIFF size matches');
  assert.equal(out[12 + 8], 0x10, 'only the alpha flag is left in VP8X');
  assert.deepEqual(sanitizeUpload('image/webp', Buffer.concat([head, body])), out);
});

test('declared type must match the bytes', () => {
  assert.throws(() => sanitizeUpload('image/jpeg', Buffer.from('<html><script>alert(1)</script>')), BadImageError);
  assert.throws(() => sanitizeUpload('image/png', jpeg()), BadImageError);
  assert.throws(() => sanitizeUpload('application/json', Buffer.from('{nope')), BadImageError);
  assert.doesNotThrow(() => sanitizeUpload('application/json', Buffer.from('{"rooms":[]}')));
  assert.doesNotThrow(() => sanitizeUpload('application/json', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('{"rooms":[]}')])));
});

// ---------- upload server ----------
let server: Server;
let base: string;
let dir: string;

before(async () => {
  dir = mkdtempSync(path.join(tmpdir(), 'moove-upload-'));
  process.env.UPLOAD_DIR = dir;
  process.env.UPLOAD_MAX_BYTES = '4096';
  process.env.PUBLIC_UPLOAD_BASE_URL = 'http://public.example';
  const { startUploadServer } = await import('../src/upload.js');
  server = startUploadServer(0);
  await new Promise(r => server.once('listening', r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(() => {
  server?.close();
  rmSync(dir, { recursive: true, force: true });
});

const post = (body: Buffer, type: string, query = '') =>
  fetch(`${base}/upload${query}`, { method: 'POST', headers: { 'content-type': type }, body: new Uint8Array(body) });

test('upload: stored under a random name with metadata stripped (client ?name ignored)', async () => {
  const res = await post(jpeg([exifApp1(6)]), 'image/jpeg', '?name=../../etc/passwd');
  assert.equal(res.status, 201);
  const { url } = (await res.json()) as { url: string };
  const name = url.replace('http://public.example/files/', '');
  assert.match(name, /^[0-9a-f-]{36}\.jpg$/);
  assert.ok(!readFileSync(path.join(dir, name)).toString('latin1').includes('GPS'));
  const got = await fetch(`${base}/files/${name}`);
  assert.equal(got.status, 200);
  assert.equal(got.headers.get('content-type'), 'image/jpeg');
  assert.equal(got.headers.get('x-content-type-options'), 'nosniff');
});

test('upload: rejects bad types, mismatched bytes, html and oversize bodies', async () => {
  assert.equal((await post(Buffer.from('<h1>hi</h1>'), 'text/html')).status, 415);
  const heic = await post(Buffer.from('\0\0\0\x18ftypheic\0\0\0\0', 'latin1'), 'image/heic');
  assert.equal(heic.status, 415);
  assert.match(((await heic.json()) as { error: string }).error, /image\/jpeg/);
  assert.equal((await post(Buffer.from('<h1>hi</h1>'), 'image/jpeg')).status, 422);
  assert.equal((await post(Buffer.alloc(0), 'image/jpeg')).status, 400);
  const big = await post(Buffer.alloc(5000, 1), 'application/json').catch(() => undefined);
  assert.ok(!big || big.status === 413, `oversize got ${big?.status}`);
  assert.equal(readdirSync(dir).length, 1, 'only the one good upload was stored');
});

test('files: no directory listing, traversal or dotfiles; html gets a CSP', async () => {
  writeFileSync(path.join(dir, '.secret'), 'x');
  writeFileSync(path.join(dir, 'listing-7.html'), '<p>hi</p>');
  for (const p of ['/files/', '/files', '/files/..%2F..%2Fpackage.json', '/files/../package.json', '/files/.secret', '/']) {
    assert.equal((await fetch(base + p)).status, 404, p);
  }
  const html = await fetch(`${base}/files/listing-7.html`);
  assert.equal(html.status, 200);
  assert.match(html.headers.get('content-security-policy') ?? '', /default-src 'none'/);
});

test('GET /healthz returns 200 {ok:true}, query string or not; POST is 404', async () => {
  for (const p of ['/healthz', '/healthz?probe=1']) {
    const res = await fetch(base + p);
    assert.equal(res.status, 200, p);
    assert.deepEqual(await res.json(), { ok: true });
  }
  assert.equal((await fetch(base + '/healthz', { method: 'POST' })).status, 404);
});

test("saveToken logs instead of throwing when the file can't be written", async () => {
  const { saveToken } = await import('../src/spacetime.js');
  const tokDir = mkdtempSync(path.join(tmpdir(), 'moove-token-'));
  try {
    assert.equal(saveToken(path.join(tokDir, 'no-such-dir', '.worker-token'), 'tok'), false);
    const ok = path.join(tokDir, '.worker-token');
    assert.equal(saveToken(ok, 'tok'), true);
    assert.equal(readFileSync(ok, 'utf8'), 'tok');
  } finally {
    rmSync(tokDir, { recursive: true, force: true });
  }
});
