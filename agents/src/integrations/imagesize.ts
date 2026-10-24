// Pixel size of a JPEG, PNG, GIF or WebP from its header, without decoding it. SAM 3D's box
// prompts are in pixels, and Claude gives boxes as fractions of the image, so we need the size.
// Returns undefined for anything it can't read (the box is then just left out).
export function imageSize(buf: Buffer): { width: number; height: number } | undefined {
  try {
    // PNG: IHDR is always the first chunk.
    if (buf.length >= 24 && buf.readUInt32BE(0) === 0x89504e47) {
      return ok(buf.readUInt32BE(16), buf.readUInt32BE(20));
    }
    // GIF: logical screen size.
    if (buf.length >= 10 && buf.toString('latin1', 0, 3) === 'GIF') return ok(buf.readUInt16LE(6), buf.readUInt16LE(8));
    // WebP: lossy (VP8 ), lossless (VP8L) or extended (VP8X).
    if (buf.length >= 30 && buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WEBP') {
      const fourcc = buf.toString('latin1', 12, 16);
      if (fourcc === 'VP8 ') return ok(buf.readUInt16LE(26) & 0x3fff, buf.readUInt16LE(28) & 0x3fff);
      if (fourcc === 'VP8L') {
        const b = buf.readUInt32LE(21);
        return ok((b & 0x3fff) + 1, ((b >> 14) & 0x3fff) + 1);
      }
      if (fourcc === 'VP8X') return ok(buf.readUIntLE(24, 3) + 1, buf.readUIntLE(27, 3) + 1);
      return undefined;
    }
    // JPEG: walk the segments to the first start-of-frame marker.
    if (buf.length >= 4 && buf[0] === 0xff && buf[1] === 0xd8) {
      let i = 2;
      while (i + 9 < buf.length) {
        if (buf[i] !== 0xff) return undefined;
        const marker = buf[i + 1];
        if (marker === 0xff) {
          i++; // fill byte
          continue;
        }
        const len = buf.readUInt16BE(i + 2);
        // SOF0..SOF15, except DHT (C4), JPG (C8) and DAC (CC).
        if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
          return ok(buf.readUInt16BE(i + 7), buf.readUInt16BE(i + 5));
        }
        i += 2 + len;
      }
    }
  } catch {
    // truncated header
  }
  return undefined;
}

function ok(width: number, height: number) {
  return width > 0 && height > 0 ? { width, height } : undefined;
}
