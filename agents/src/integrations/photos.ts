// Photo loading for the vision agent without SSRF (#44). Any room member can put a URL on an item,
// and the worker would fetch it from its own host, so loadPhoto never fetches arbitrary URLs:
// - our own uploads (PUBLIC_UPLOAD_BASE_URL + /files/<name>, or https://<any>.trycloudflare.com/files/<name>
//   from an earlier quick tunnel) are read straight from UPLOAD_DIR on disk;
// - anything else must be https, on a host in ALLOWED_PHOTO_HOSTS (default empty), and resolve only to
//   public addresses. Redirects are refused, so an allowed host can't bounce us to a private one.
// Known gap: DNS can change between our lookup and fetch's own (rebinding). The allowlist is what
// really bounds that, so only list hosts we trust (an S3/R2 bucket, say).
import { lookup as dnsLookup } from 'node:dns/promises';
import { readFile } from 'node:fs/promises';
import { BlockList, isIP } from 'node:net';
import path from 'node:path';

export type ImageMediaType = 'image/jpeg' | 'image/png' | 'image/gif' | 'image/webp';
export type ImageInput = { mediaType: ImageMediaType; data: string };

export type PhotoPolicy = {
  publicUploadBaseUrl: string;
  uploadDir: string;
  allowedHosts: readonly string[]; // lowercase hostnames, exact match
};

export type PhotoSource = { kind: 'local'; file: string; ext: string } | { kind: 'remote'; url: URL };

export class PhotoUrlError extends Error {}

export const MAX_PHOTO_BYTES = 15 * 1024 * 1024;

// Names the upload server hands out: <uuid>.<ext>. Nothing else (no dots, slashes or escapes) is read.
const UPLOAD_NAME = /^[A-Za-z0-9_-]+\.(jpg|jpeg|png|gif|webp|heic)$/;

const MEDIA_BY_EXT: Record<string, ImageMediaType> = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp' };
const MEDIA_TYPES: readonly ImageMediaType[] = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];

// Loopback, private, link-local (incl. cloud metadata 169.254.169.254), CGNAT, multicast and reserved.
const BLOCKED = new BlockList();
for (const [net, prefix] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4],
] as const) {
  BLOCKED.addSubnet(net, prefix, 'ipv4');
}
for (const [net, prefix] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96], // NAT64
  ['fc00::', 7],
  ['fe80::', 10],
  ['ff00::', 8],
] as const) {
  BLOCKED.addSubnet(net, prefix, 'ipv6');
}
// IPv4-mapped IPv6 (::ffff:a.b.c.d): refuse rather than re-check the embedded address. Its own list,
// because a BlockList also matches plain IPv4 addresses against a mapped IPv6 rule.
const MAPPED = new BlockList();
MAPPED.addSubnet('::ffff:0:0', 96, 'ipv6');

// True for any address the worker must never fetch from. Non-IP strings count as blocked.
export function isBlockedAddress(ip: string): boolean {
  const bare = ip.replace(/^\[|\]$/g, '');
  const v = isIP(bare);
  if (v === 0) return true;
  if (v === 6 && MAPPED.check(bare, 'ipv6')) return true;
  return BLOCKED.check(bare, v === 4 ? 'ipv4' : 'ipv6');
}

export function parseAllowedHosts(raw: string): string[] {
  return raw
    .split(',')
    .map(h => h.trim().toLowerCase())
    .filter(Boolean);
}

// An upload URL from a Cloudflare quick tunnel (tunnel.sh), which always proxies the worker's root.
function isQuickTunnelUpload(u: URL): boolean {
  const host = u.hostname.toLowerCase();
  return u.protocol === 'https:' && u.port === '' && host.endsWith('.trycloudflare.com') && u.pathname.startsWith('/files/');
}

// Decides where a photo URL may be read from, without touching the network or disk.
export function resolvePhotoSource(raw: string, policy: PhotoPolicy): PhotoSource {
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    throw new PhotoUrlError('not a valid URL');
  }

  // Our own upload server: read the file directly instead of fetching it. That includes uploads made
  // under an earlier quick-tunnel URL: tunnel.sh gets a new *.trycloudflare.com host after a restart,
  // but the stored URLs keep the old one, and the file is still in UPLOAD_DIR.
  const base = new URL(policy.publicUploadBaseUrl);
  const ownPrefix = `${base.pathname.replace(/\/+$/, '')}/files/`;
  const prefix =
    u.origin === base.origin && u.pathname.startsWith(ownPrefix) ? ownPrefix : isQuickTunnelUpload(u) ? '/files/' : undefined;
  if (prefix) {
    const name = u.pathname.slice(prefix.length);
    if (u.search || u.hash || u.username || u.password || !UPLOAD_NAME.test(name)) {
      throw new PhotoUrlError('not a file name the upload server issues');
    }
    const dir = path.resolve(policy.uploadDir);
    const file = path.resolve(dir, name);
    if (path.dirname(file) !== dir) throw new PhotoUrlError('upload path escapes the upload dir');
    return { kind: 'local', file, ext: name.slice(name.lastIndexOf('.') + 1).toLowerCase() };
  }

  if (u.protocol !== 'https:') throw new PhotoUrlError('only https photo URLs are fetched');
  if (u.username || u.password) throw new PhotoUrlError('credentials in photo URLs are not allowed');
  const host = u.hostname.toLowerCase();
  if (!policy.allowedHosts.includes(host)) throw new PhotoUrlError(`host ${host} is not in ALLOWED_PHOTO_HOSTS`);
  if (isIP(host.replace(/^\[|\]$/g, '')) !== 0 && isBlockedAddress(host)) {
    throw new PhotoUrlError(`host ${host} is a private address`);
  }
  return { kind: 'remote', url: u };
}

type Lookup = (host: string) => Promise<{ address: string }[]>;
const defaultLookup: Lookup = host => dnsLookup(host, { all: true, verbatim: true });

// Every address the host resolves to must be public.
export async function assertPublicHost(host: string, lookup: Lookup = defaultLookup): Promise<void> {
  const bare = host.replace(/^\[|\]$/g, '');
  const addrs = isIP(bare) !== 0 ? [{ address: bare }] : await lookup(bare);
  if (addrs.length === 0) throw new PhotoUrlError(`host ${host} did not resolve`);
  for (const a of addrs) {
    if (isBlockedAddress(a.address)) throw new PhotoUrlError(`host ${host} resolves to a private address`);
  }
}

type Fetch = (url: URL, init: RequestInit) => Promise<Response>;

// Loads a photo as base64 for the Claude API (which never has to reach LAN URLs itself).
export async function loadPhoto(
  raw: string,
  policy: PhotoPolicy,
  deps: { fetch?: Fetch; lookup?: Lookup } = {}
): Promise<ImageInput> {
  const src = resolvePhotoSource(raw, policy);
  if (src.kind === 'local') {
    // Vision errors land in agent_event rows clients can read, so don't echo the server path.
    const buf = await readFile(src.file).catch(() => {
      throw new PhotoUrlError('upload not found on this worker');
    });
    if (buf.length > MAX_PHOTO_BYTES) throw new PhotoUrlError('photo is too large');
    // heic isn't an API media type; label it jpeg like the upload server's fetch path always did.
    return { mediaType: MEDIA_BY_EXT[src.ext] ?? 'image/jpeg', data: buf.toString('base64') };
  }
  await assertPublicHost(src.url.hostname, deps.lookup);
  const res = await (deps.fetch ?? fetch)(src.url, { redirect: 'error', signal: AbortSignal.timeout(15_000) });
  if (!res.ok) throw new Error(`fetch ${src.url.host}: ${res.status}`);
  if (Number(res.headers.get('content-length') ?? '0') > MAX_PHOTO_BYTES) throw new PhotoUrlError('photo is too large');
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length > MAX_PHOTO_BYTES) throw new PhotoUrlError('photo is too large');
  const type = (res.headers.get('content-type') ?? '').split(';')[0];
  const mediaType = MEDIA_TYPES.find(t => t === type) ?? 'image/jpeg';
  return { mediaType, data: buf.toString('base64') };
}
