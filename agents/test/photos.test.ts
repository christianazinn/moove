import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  assertPublicHost,
  isBlockedAddress,
  loadPhoto,
  parseAllowedHosts,
  PhotoUrlError,
  resolvePhotoSource,
  type PhotoPolicy,
} from "../src/integrations/photos.js";
import { selectApprovalGateway } from "../src/integrations/auth0.js";

const uploadDir = mkdtempSync(path.join(tmpdir(), "moove-photos-"));
const NAME = "3f2b8c1e-1111-4a2b-9c3d-0123456789ab.jpg";
writeFileSync(path.join(uploadDir, NAME), Buffer.from("jpeg-bytes"));

const policy: PhotoPolicy = {
  publicUploadBaseUrl: "https://moove-tunnel.example.com",
  uploadDir,
  allowedHosts: ["photos.example.com", "127.0.0.1"],
};

/** A fetch that fails the test if it is ever called. */
const noFetch = async () => {
  throw new Error("fetch must not be called");
};
const publicDns = async () => [{ address: "93.184.216.34" }];

test("own upload URLs are read from disk, never fetched", async () => {
  const src = resolvePhotoSource(`https://moove-tunnel.example.com/files/${NAME}`, policy);
  assert.deepEqual(src, { kind: "local", file: path.join(uploadDir, NAME), ext: "jpg" });
  const img = await loadPhoto(`https://moove-tunnel.example.com/files/${NAME}`, policy, { fetch: noFetch });
  assert.equal(img.mediaType, "image/jpeg");
  assert.equal(Buffer.from(img.data, "base64").toString(), "jpeg-bytes");
});

test("upload base URL with a path prefix and host case differences still match", () => {
  const p = { ...policy, publicUploadBaseUrl: "http://192.168.1.20:8787/moove/" };
  const src = resolvePhotoSource(`HTTP://192.168.1.20:8787/moove/files/${NAME}`, p);
  assert.equal(src.kind, "local");
});

test("path traversal and odd names under /files/ are rejected", () => {
  for (const url of [
    "https://moove-tunnel.example.com/files/../.env.local",
    "https://moove-tunnel.example.com/files/%2e%2e%2f.env.local",
    "https://moove-tunnel.example.com/files/..%2F..%2F.env.local",
    "https://moove-tunnel.example.com/files/sub/dir.jpg",
    "https://moove-tunnel.example.com/files/listing-1.html",
    "https://moove-tunnel.example.com/files/.worker-token",
    "https://moove-tunnel.example.com/files/a.b.jpg",
    `https://moove-tunnel.example.com/files/${NAME}?x=1`,
    `https://user:pw@moove-tunnel.example.com/files/${NAME}`,
  ]) {
    assert.throws(() => resolvePhotoSource(url, policy), PhotoUrlError, url);
  }
});

test("'../' is normalized away by URL parsing, so it falls out of /files/ and is refused as remote", () => {
  // new URL resolves /files/../x to /x, which is not under /files/ and not an allowed host.
  assert.throws(() => resolvePhotoSource("https://moove-tunnel.example.com/files/../.env.local", policy), PhotoUrlError);
});

test("remote URLs need https and an allowlisted host", () => {
  assert.throws(() => resolvePhotoSource("http://photos.example.com/a.jpg", policy), /only https/);
  assert.throws(() => resolvePhotoSource("https://evil.example.net/a.jpg", policy), /ALLOWED_PHOTO_HOSTS/);
  assert.throws(() => resolvePhotoSource("file:///etc/passwd", policy), /only https/);
  assert.throws(() => resolvePhotoSource("data:image/png;base64,AAAA", policy), /only https/);
  assert.throws(() => resolvePhotoSource("not a url", policy), /valid URL/);
  assert.throws(() => resolvePhotoSource("https://u:p@photos.example.com/a.jpg", policy), /credentials/);
  const src = resolvePhotoSource("https://Photos.Example.com/a.jpg", policy);
  assert.equal(src.kind, "remote");
});

test("the default allowlist is empty, so nothing remote is fetched", () => {
  const p = { ...policy, allowedHosts: parseAllowedHosts("") };
  assert.deepEqual(p.allowedHosts, []);
  assert.throws(() => resolvePhotoSource("https://photos.example.com/a.jpg", p), /ALLOWED_PHOTO_HOSTS/);
  assert.deepEqual(parseAllowedHosts(" A.com, ,b.com "), ["a.com", "b.com"]);
});

test("a private IP literal is refused even when allowlisted", () => {
  assert.throws(() => resolvePhotoSource("https://127.0.0.1/a.jpg", policy), /private address/);
});

test("isBlockedAddress covers loopback, private, link-local, metadata and mapped addresses", () => {
  for (const ip of [
    "127.0.0.1",
    "10.1.2.3",
    "172.16.0.1",
    "172.31.255.255",
    "192.168.1.20",
    "169.254.169.254",
    "100.64.0.1",
    "0.0.0.0",
    "224.0.0.1",
    "::1",
    "[::1]",
    "::",
    "fe80::1",
    "fd00::1",
    "::ffff:127.0.0.1",
    "::ffff:7f00:1",
    "not-an-ip",
  ]) {
    assert.equal(isBlockedAddress(ip), true, ip);
  }
  for (const ip of ["93.184.216.34", "8.8.8.8", "172.32.0.1", "2606:4700:4700::1111"]) {
    assert.equal(isBlockedAddress(ip), false, ip);
  }
});

test("assertPublicHost rejects hosts that resolve to any private address", async () => {
  await assertPublicHost("photos.example.com", publicDns);
  await assert.rejects(
    assertPublicHost("photos.example.com", async () => [{ address: "93.184.216.34" }, { address: "10.0.0.5" }]),
    /private address/
  );
  await assert.rejects(assertPublicHost("photos.example.com", async () => []), /did not resolve/);
});

test("remote fetches refuse redirects and check DNS first", async () => {
  let init: RequestInit | undefined;
  const fakeFetch = async (_url: URL, i: RequestInit) => {
    init = i;
    return new Response(Buffer.from("png-bytes"), { headers: { "content-type": "image/png" } });
  };
  const img = await loadPhoto("https://photos.example.com/a.png", policy, { fetch: fakeFetch, lookup: publicDns });
  assert.equal(init?.redirect, "error");
  assert.equal(img.mediaType, "image/png");
  await assert.rejects(
    loadPhoto("https://photos.example.com/a.png", policy, { fetch: noFetch, lookup: async () => [{ address: "169.254.169.254" }] }),
    /private address/
  );
});

test("the simulated auto-approver is gone (#42): without Auth0 there is no gateway", () => {
  const { warn } = console;
  console.warn = () => {};
  try {
    const choice = selectApprovalGateway({ APPROVAL_SIM_AUTO_APPROVE_SEC: "5" });
    assert.equal(choice.gateway, null);
  } finally {
    console.warn = warn;
  }
});
