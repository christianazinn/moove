import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const dir = mkdtempSync(path.join(tmpdir(), "spend-"));
process.env.CLAUDE_SPEND_FILE = path.join(dir, "claude.json");
process.env.APIFY_SPEND_FILE = path.join(dir, "apify.json");
process.env.CLAUDE_MAX_USD_PER_DAY = "3";
process.env.APIFY_MAX_USD_PER_DAY = "2";
const { spendToday, announceSpend, announceService } = await import("../src/service.js");
const { visaCheckoutMode, checkoutMode } = await import("../src/integrations/visa.js");

test("spend_today reports today's spend against both caps", () => {
  const s = JSON.parse(spendToday(new Date("2026-10-24T12:00:00Z")));
  assert.deepEqual(s, { day: "2026-10-24", claude: { usd: 0, calls: 0, capUsd: 3 }, apify: { usd: 0, runs: 0, capUsd: 2 } });
});

test("announceSpend writes once and again only when it changes", async () => {
  const writes: { key: string; value: string }[] = [];
  const conn = { reducers: { setServiceConfig: async (a: { key: string; value: string }) => void writes.push(a) } };
  const t = announceSpend(conn as never, 20);
  await new Promise(r => setTimeout(r, 70));
  clearInterval(t);
  assert.equal(writes.length, 1);
  assert.equal(writes[0].key, "spend_today");
  rmSync(dir, { recursive: true });
});

const KEYS = { VISA_ACCEPTANCE_MERCHANT_ID: "m", VISA_ACCEPTANCE_KEY_ID: "k", VISA_ACCEPTANCE_SECRET: Buffer.from("s").toString("base64") };

test("visaCheckoutMode follows the provider choice (#191)", () => {
  assert.equal(visaCheckoutMode({}), "simulated");
  assert.equal(visaCheckoutMode({ ...KEYS, VISA_PROVIDER: "simulated" }), "simulated");
  assert.equal(visaCheckoutMode({ VISA_PROVIDER: "vic" }), "simulated");
  assert.equal(visaCheckoutMode({ VISA_PROVIDER: "paypal" }), "simulated");
  // Keys and no explicit provider: acceptance, with the simulated fallback on by default.
  assert.equal(visaCheckoutMode(KEYS), "sandbox+fallback");
  assert.equal(visaCheckoutMode({ ...KEYS, VISA_FALLBACK_SIMULATED: "0" }), "sandbox");
  assert.equal(visaCheckoutMode({ ...KEYS, VISA_PROVIDER: "acceptance" }), "sandbox");
  assert.equal(visaCheckoutMode({ ...KEYS, VISA_PROVIDER: "acceptance", VISA_FALLBACK_SIMULATED: "1" }), "sandbox+fallback");
  // Explicit acceptance without keys fails loudly and is never simulated.
  assert.equal(visaCheckoutMode({ VISA_PROVIDER: "acceptance" }), "sandbox");
  assert.equal(checkoutMode({ simulated: true }, { simulated: true }), "simulated");
});

function recordingConn(reject: (key: string) => boolean) {
  const writes: { key: string; value: string }[] = [];
  const calls: string[] = [];
  const conn = {
    reducers: {
      setServiceConfig: async (a: { key: string; value: string }) => {
        calls.push(a.key);
        if (reject(a.key)) throw new Error(`key must be one of upload_base_url, worker_version, worker_started_at, spend_today`);
        writes.push(a);
      },
    },
  };
  return { conn, writes, calls };
}

async function quietly<T>(fn: () => Promise<T>): Promise<{ result: T; warns: string[] }> {
  const warns: string[] = [];
  const [w, l] = [console.warn, console.log];
  console.warn = (...a: unknown[]) => void warns.push(a.join(" "));
  console.log = () => {};
  try {
    return { result: await fn(), warns };
  } finally {
    console.warn = w;
    console.log = l;
  }
}

test("announceService writes visa_checkout from the configured provider", async () => {
  const { conn, writes } = recordingConn(() => false);
  await quietly(() => announceService(conn as never, new Date("2026-10-24T12:00:00Z"), {}));
  assert.deepEqual(writes.find(w => w.key === "visa_checkout"), { key: "visa_checkout", value: "simulated" });
  const sandbox = recordingConn(() => false);
  await quietly(() => announceService(sandbox.conn as never, new Date(), { ...KEYS, VISA_PROVIDER: "acceptance" }));
  assert.equal(sandbox.writes.find(w => w.key === "visa_checkout")?.value, "sandbox");
});

test("a module without the visa_checkout key logs one line and keeps the other keys", async () => {
  const { conn, writes, calls } = recordingConn(k => k === "visa_checkout");
  const { warns } = await quietly(() => announceService(conn as never, new Date("2026-10-24T12:00:00Z"), {}));
  assert.deepEqual(writes.map(w => w.key), ["upload_base_url", "worker_version", "worker_started_at"]);
  assert.equal(calls.filter(k => k === "visa_checkout").length, 1, "no retry");
  assert.equal(warns.length, 1);
  assert.match(warns[0], /visa_checkout=simulated.*#191/);
});
