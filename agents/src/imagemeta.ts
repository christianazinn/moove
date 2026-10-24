// Strips metadata (EXIF GPS, XMP, IPTC, comments, text chunks) from uploaded photos before they
// are stored, because upload URLs are public (eBay needs them) and phone photos can carry the
// exact GPS position of the user's home. Pure TS, no native deps. JPEG keeps only the EXIF
// orientation so photos don't come out rotated. Anything it can't parse is rejected, not
// stored as-is.

export class BadImageError extends Error {}

// ---------- sniffing ----------
export function sniffType(buf: Buffer): string | undefined {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(PNG_SIG)) return 'image/png';
  if (buf.length >= 12 && buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WEBP') return 'image/webp';
  if (buf.length >= 12 && buf.toString('latin1', 4, 8) === 'ftyp') {
    const brand = buf.toString('latin1', 8, 12);
    if (['heic', 'heix', 'hevc', 'heim', 'heis', 'mif1', 'msf1'].includes(brand)) return 'image/heic';
  }
  if (buf.length >= 4 && buf[0] === 0x50 && buf[1] === 0x4b && buf[2] === 0x03 && buf[3] === 0x04) return 'model/vnd.usdz+zip';
  return undefined;
}

// ---------- JPEG ----------
// Keep: APP0 (JFIF), APP2 only if ICC_PROFILE (colour), APP14 (Adobe), and all non-APP segments.
// Drop: APP1 (EXIF/XMP), other APPn (IPTC in APP13, MPF in APP2, ...), COM. Truncate after EOI so
// trailing embedded images (MPF gain maps with their own EXIF) are dropped too.
export function stripJpeg(buf: Buffer): Buffer {
  if (!(buf[0] === 0xff && buf[1] === 0xd8)) throw new BadImageError('not a JPEG');
  const out: Buffer[] = [buf.subarray(0, 2)];
  let orientation = 1;
  let i = 2;
  for (;;) {
    if (i + 4 > buf.length) throw new BadImageError('truncated JPEG header');
    if (buf[i] !== 0xff) throw new BadImageError('bad JPEG marker');
    const marker = buf[i + 1];
    if (marker === 0xff) { i++; continue; } // fill byte
    const len = buf.readUInt16BE(i + 2);
    if (len < 2 || i + 2 + len > buf.length) throw new BadImageError('bad JPEG segment length');
    const seg = buf.subarray(i, i + 2 + len);
    const payload = buf.subarray(i + 4, i + 2 + len);
    if (marker === 0xda) {
      // Start of scan: entropy-coded data follows. 0xFF in scan data is always stuffed (FF 00) or a
      // restart marker (FF D0-D7), so the first FF D9 is the end of image.
      const eoi = findEoi(buf, i + 2 + len);
      if (orientation !== 1) out.push(exifOrientationSegment(orientation));
      out.push(buf.subarray(i, eoi + 2));
      return reorderAfterSoi(out);
    }
    const isApp = marker >= 0xe0 && marker <= 0xef;
    if (marker === 0xe1 && payload.toString('latin1', 0, 6) === 'Exif\0\0') {
      orientation = readOrientation(payload.subarray(6)) ?? orientation;
    } else if (marker === 0xe0 || marker === 0xee || (marker === 0xe2 && payload.toString('latin1', 0, 12) === 'ICC_PROFILE\0')) {
      out.push(seg);
    } else if (!isApp && marker !== 0xfe) {
      out.push(seg);
    }
    i += 2 + len;
  }
}

// The minimal EXIF segment goes right after SOI (and after APP0 if present), as the spec expects.
function reorderAfterSoi(parts: Buffer[]): Buffer {
  const [soi, ...rest] = parts;
  const exifIdx = rest.findIndex(p => p[1] === 0xe1);
  if (exifIdx < 0) return Buffer.concat(parts);
  const [exif] = rest.splice(exifIdx, 1);
  const app0 = rest[0]?.[1] === 0xe0 ? 1 : 0;
  rest.splice(app0, 0, exif);
  return Buffer.concat([soi, ...rest]);
}

function findEoi(buf: Buffer, from: number): number {
  for (let j = from; j < buf.length - 1; j++) if (buf[j] === 0xff && buf[j + 1] === 0xd9) return j;
  throw new BadImageError('JPEG has no end-of-image marker');
}

function readOrientation(tiff: Buffer): number | undefined {
  if (tiff.length < 8) return undefined;
  const le = tiff.toString('latin1', 0, 2) === 'II';
  if (!le && tiff.toString('latin1', 0, 2) !== 'MM') return undefined;
  const u16 = (o: number) => (le ? tiff.readUInt16LE(o) : tiff.readUInt16BE(o));
  const u32 = (o: number) => (le ? tiff.readUInt32LE(o) : tiff.readUInt32BE(o));
  const ifd = u32(4);
  if (ifd + 2 > tiff.length) return undefined;
  const n = u16(ifd);
  for (let k = 0; k < n; k++) {
    const e = ifd + 2 + k * 12;
    if (e + 12 > tiff.length) return undefined;
    if (u16(e) === 0x0112 && u16(e + 2) === 3) {
      const v = u16(e + 8);
      return v >= 1 && v <= 8 ? v : undefined;
    }
  }
  return undefined;
}

// APP1 "Exif\0\0" + big-endian TIFF with one IFD0 entry: Orientation (0x0112, SHORT, 1).
function exifOrientationSegment(orientation: number): Buffer {
  const tiff = Buffer.alloc(8 + 2 + 12 + 4);
  tiff.write('MM', 0, 'latin1');
  tiff.writeUInt16BE(42, 2);
  tiff.writeUInt32BE(8, 4);
  tiff.writeUInt16BE(1, 8);
  tiff.writeUInt16BE(0x0112, 10);
  tiff.writeUInt16BE(3, 12);
  tiff.writeUInt32BE(1, 14);
  tiff.writeUInt16BE(orientation, 18);
  // next IFD offset (bytes 22..25) stays 0
  const payload = Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), tiff]);
  const head = Buffer.alloc(4);
  head[0] = 0xff;
  head[1] = 0xe1;
  head.writeUInt16BE(payload.length + 2, 2);
  return Buffer.concat([head, payload]);
}

// ---------- PNG ----------
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PNG_DROP = new Set(['eXIf', 'tEXt', 'zTXt', 'iTXt', 'tIME']);

export function stripPng(buf: Buffer): Buffer {
  if (!buf.subarray(0, 8).equals(PNG_SIG)) throw new BadImageError('not a PNG');
  const out: Buffer[] = [PNG_SIG];
  let i = 8;
  while (i < buf.length) {
    if (i + 12 > buf.length) throw new BadImageError('truncated PNG chunk');
    const len = buf.readUInt32BE(i);
    const type = buf.toString('latin1', i + 4, i + 8);
    const end = i + 12 + len;
    if (end > buf.length) throw new BadImageError('bad PNG chunk length');
    if (!PNG_DROP.has(type)) out.push(buf.subarray(i, end));
    i = end;
    if (type === 'IEND') break;
  }
  return Buffer.concat(out);
}

// ---------- entry point ----------
/** Returns the bytes to store. Throws BadImageError if the body doesn't match `type`. */
export function sanitizeUpload(type: string, buf: Buffer): Buffer {
  if (type === 'application/json') {
    try {
      JSON.parse(buf.toString('utf8'));
    } catch {
      throw new BadImageError('body is not valid JSON');
    }
    return buf;
  }
  const sniffed = sniffType(buf);
  if (sniffed !== type) throw new BadImageError(`body looks like ${sniffed ?? 'unknown data'}, not ${type}`);
  if (type === 'image/jpeg') return stripJpeg(buf);
  if (type === 'image/png') return stripPng(buf);
  // HEIC/WebP metadata isn't stripped server-side (no cheap parser). The iOS app re-encodes
  // camera photos to JPEG before upload, which drops location. USDZ holds geometry, not EXIF.
  return buf;
}
