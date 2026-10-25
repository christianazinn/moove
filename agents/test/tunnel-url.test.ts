import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const script = path.join(path.dirname(fileURLToPath(import.meta.url)), "../scripts/tunnel.sh");
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

test("tunnel.sh never takes api.trycloudflare.com from cloudflared's error text as the URL", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "moove-tunnel-"));
  const cf = path.join(dir, "cloudflared");
  // A fake cloudflared: the quick-tunnel API error first, the real URL two seconds later.
  writeFileSync(
    cf,
    `#!/usr/bin/env bash
echo 'ERR failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel": dial tcp: lookup api.trycloudflare.com: no such host'
sleep 2
echo '|  https://brave-otter-quiet-lake.trycloudflare.com  |'
exec sleep 300
`
  );
  chmodSync(cf, 0o755);
  const urlFile = path.join(dir, "url");
  const child = spawn("bash", [script, "1", urlFile], { env: { ...process.env, CLOUDFLARED: cf }, detached: true, stdio: "ignore" });
  try {
    for (let i = 0; i < 80 && !existsSync(urlFile); i++) await sleep(100);
    assert.equal(readFileSync(urlFile, "utf8").trim(), "https://brave-otter-quiet-lake.trycloudflare.com");
  } finally {
    // Kill the whole group (the script and the fake cloudflared); bash defers TERM traps during sleep.
    process.kill(-child.pid!, "SIGKILL");
  }
});
