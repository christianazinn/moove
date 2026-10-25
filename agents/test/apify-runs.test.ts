import { test } from "node:test";
import assert from "node:assert/strict";

// The shared Apify run queue: at most APIFY_MAX_CONCURRENT_RUNS at once across every agent, and
// a capacity refusal ("concurrent-runs-limit-exceeded", "actor-memory-limit-exceeded") retried.
process.env.APIFY_MAX_CONCURRENT_RUNS = "2";
process.env.APIFY_CAPACITY_RETRY_MS = "5,5";
const { apifyFetch, apifyRunState, isApifyCapacityError } = await import("../src/integrations/apify-runs.js");
const { isTransientPricingError } = await import("../src/agents/pricing.js");

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));

test("no more than APIFY_MAX_CONCURRENT_RUNS run at once", async () => {
  let running = 0, peak = 0;
  const slow = (async () => {
    running++; peak = Math.max(peak, running);
    await sleep(15);
    running--;
    return new Response("[]", { status: 200 });
  }) as unknown as typeof fetch;
  await Promise.all(Array.from({ length: 6 }, () => apifyFetch("https://api.apify.com/x", {}, slow)));
  assert.equal(peak, 2);
  assert.deepEqual(apifyRunState(), { active: 0, waiting: 0 });
});

const capacity = JSON.stringify({ error: { type: "actor-memory-limit-exceeded", message: "By launching this job you will exceed the memory limit of 16384MB" } });

test("a capacity refusal is retried, then the run goes through", async () => {
  let calls = 0;
  const flaky = (async () => (++calls < 3 ? new Response(capacity, { status: 402 }) : new Response("[1]", { status: 200 }))) as unknown as typeof fetch;
  const res = await apifyFetch("https://api.apify.com/x", {}, flaky);
  assert.equal(res.status, 200);
  assert.equal(calls, 3);
});

test("other errors come back at once, body intact", async () => {
  let calls = 0;
  const credit = (async () => { calls++; return new Response('{"error":{"type":"not-enough-usage"}}', { status: 402 }); }) as unknown as typeof fetch;
  const res = await apifyFetch("https://api.apify.com/x", {}, credit);
  assert.equal(res.status, 402);
  assert.equal(calls, 1);
  assert.match(await res.text(), /not-enough-usage/);
});

test("capacity errors are recognized, and pricing treats them as transient", () => {
  assert.ok(isApifyCapacityError(capacity));
  assert.ok(isApifyCapacityError('{"error":{"type":"concurrent-runs-limit-exceeded"}}'));
  assert.ok(!isApifyCapacityError('{"error":{"type":"not-enough-usage"}}'));
  assert.ok(isTransientPricingError(new Error(`comps lookup failed: apify x: HTTP 402 ${capacity}`)));
});
