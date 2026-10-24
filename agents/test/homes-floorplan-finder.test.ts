import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { importHome } from "../src/homes/listing.js";
import { scrapeZillow } from "../src/homes/zillowApify.js";
import { MAX_CANDIDATES, MAX_CANDIDATES_FULL_SIZE, type PhotoVerdicts } from "../src/homes/floorplanFinder.js";
import type { ImageInput } from "../src/integrations/photos.js";

const ZURL = "https://www.zillow.com/homedetails/418-Alder-St-Portland-OR-97204/2061234567_zpid/";
const img = (n: number, size: number) => `https://photos.zillowstatic.com/fp/p${n}-cc_ft_${size}.jpg`;

/** A listing photo with Zillow mixedSources (small + large jpeg). */
const photo = (n: number, caption?: string) => ({
  ...(caption ? { caption } : {}),
  mixedSources: { jpeg: [{ url: img(n, 384), width: 384 }, { url: img(n, 1536), width: 1536 }] },
});

function row(extra: Record<string, unknown>) {
  return { listingAddress: { full: "418 Alder St, Portland, OR 97204" }, bedrooms: 2, bathrooms: 1, livingArea: 850, ...extra };
}

/** Loader that encodes the URL as the image data, so tests can tell images apart. */
function fakeLoader() {
  const urls: string[] = [];
  const load = async (url: string): Promise<ImageInput> => {
    urls.push(url);
    return { mediaType: "image/jpeg", data: Buffer.from(url).toString("base64") };
  };
  return { load, urls };
}
const urlOf = (i: ImageInput) => Buffer.from(i.data, "base64").toString();

type Classify = (args: { model: string; images?: ImageInput[]; fallbacks?: boolean }) => Promise<PhotoVerdicts>;

function setup(actorRow: unknown, classify: Classify, cacheDir = mkdtempSync(path.join(tmpdir(), "zillow-"))) {
  const loader = fakeLoader();
  const events: { kind: string; message: string }[] = [];
  const read: ImageInput[][] = [];
  let classifyCalls = 0;
  let actorRuns = 0;
  const fetchImpl = (async () => {
    actorRuns++;
    return new Response(JSON.stringify([actorRow]), { status: 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  const run = () =>
    importHome(
      { url: ZURL, useScraper: true },
      {
        apifyToken: "t",
        log: (kind, message) => events.push({ kind, message }),
        scrapeZillow: (u, o) =>
          scrapeZillow(u, {
            ...o,
            fetch: fetchImpl,
            loadImage: loader.load,
            cacheDir,
            classify: async a => {
              classifyCalls++;
              return classify(a);
            },
          }),
        readFloorPlan: async images => {
          read.push(images);
          return { floorPlan: null, notes: [] };
        },
      }
    );
  return { run, loader, events, read, cacheDir, calls: () => classifyCalls, actorRuns: () => actorRuns };
}

test("captioned floor plan present -> classifier not called", async () => {
  const s = setup(row({ photos: [photo(1, "Kitchen"), { url: "https://photos.zillowstatic.com/fp/plan.jpg", caption: "Floor plan" }] }), async () =>
    assert.fail("classifier must not run when a floor plan is captioned")
  );
  await s.run();
  assert.equal(s.calls(), 0);
  assert.deepEqual(s.read.map(imgs => imgs.map(urlOf)), [["https://photos.zillowstatic.com/fp/plan.jpg"]]);
});

test("no caption: classifier flags photo 18 -> floorplanVision reads it; replay doesn't re-classify", async () => {
  const photos = Array.from({ length: 20 }, (_, n) => photo(n, n === 0 ? "Front exterior" : undefined));
  let seen: { model: string; count: number; fallbacks?: boolean } | undefined;
  const s = setup(row({ photos }), async a => {
    seen = { model: a.model, count: a.images!.length, fallbacks: a.fallbacks };
    return {
      images: a.images!.map((im, index) => {
        const u = urlOf(im);
        if (u === img(18, 384)) return { index, floorPlan: true, confidence: 0.93 };
        if (u === img(19, 384)) return { index, floorPlan: true, confidence: 0.4 }; // below 0.6: ignored
        return { index, floorPlan: false, confidence: 0.9 };
      }),
    };
  });
  const r = await s.run();
  assert.equal(s.calls(), 1);
  assert.equal(seen!.count, 19, "the captioned exterior is skipped");
  assert.equal(seen!.fallbacks, false);
  assert.ok(s.loader.urls.slice(0, 19).every(u => u.endsWith("cc_ft_384.jpg")), "classified at the small size");
  assert.deepEqual(s.read.map(imgs => imgs.map(urlOf)), [[img(18, 1536)]], "the plan is read at full size");
  assert.ok(r.notes.some(n => /found among the listing photos/.test(n)), r.notes.join(" | "));
  assert.ok(s.events.some(e => e.kind === "plan" && e.message === "Looking for a floor plan among 20 listing photos"));
  assert.ok(s.events.some(e => e.kind === "result" && e.message === "Found 1 floor plan in the listing photos"));

  // The outcome is in the per-zpid cache entry.
  const [file] = readdirSync(s.cacheDir);
  const cached = JSON.parse(readFileSync(path.join(s.cacheDir, file), "utf8"));
  assert.equal(cached.photoPlanScan.picked[0].photoIndex, 18);

  // Replay: no actor run, no classification, same plan image.
  const again = setup(row({ photos }), async () => assert.fail("replay must not re-classify"), s.cacheDir);
  const r2 = await again.run();
  assert.equal(again.actorRuns(), 0);
  assert.equal(again.calls(), 0);
  assert.deepEqual(again.read.map(imgs => imgs.map(urlOf)), [[img(18, 1536)]]);
  assert.ok(r2.notes.some(n => /found among the listing photos/.test(n)));
  assert.ok(again.events.some(e => e.message.startsWith("[REPLAYED] Found 1 floor plan")));
});

test("classifier finds none -> floorPlan null + note", async () => {
  const s = setup(row({ photos: Array.from({ length: 5 }, (_, n) => photo(n)) }), async a => ({
    images: a.images!.map((_, index) => ({ index, floorPlan: false, confidence: 0.95 })),
  }));
  const r = await s.run();
  assert.equal(s.calls(), 1);
  assert.equal(r.floorPlan, null);
  assert.equal(s.read.length, 0);
  assert.ok(r.notes.some(n => /No floor plan was found among 5 listing photos/.test(n)), r.notes.join(" | "));
  assert.ok(r.notes.some(n => /app estimates/.test(n)));
  assert.ok(s.events.some(e => e.message === "No floor plan in the listing photos; estimating from beds/baths/sqft"));
});

test("classifier throws -> same fallback, no 500, error event, nothing cached", async () => {
  const s = setup(row({ photos: Array.from({ length: 5 }, (_, n) => photo(n)) }), async () => {
    throw new Error("overloaded");
  });
  const r = await s.run();
  assert.equal(r.floorPlan, null);
  assert.equal(r.method, "scraper");
  assert.equal(s.read.length, 0);
  assert.ok(r.notes.some(n => /listing photos for one failed/.test(n)));
  assert.ok(r.notes.some(n => /app estimates/.test(n)));
  assert.ok(s.events.some(e => e.kind === "error" && /overloaded/.test(e.message)));
  const [file] = readdirSync(s.cacheDir);
  assert.equal(JSON.parse(readFileSync(path.join(s.cacheDir, file), "utf8")).photoPlanScan, undefined);
});

test("no listing photos -> no classification", async () => {
  const s = setup(row({}), async () => assert.fail("no photos, no call"));
  const r = await s.run();
  assert.equal(s.calls(), 0);
  assert.equal(r.floorPlan, null);
});

test("photo count capped: 24 latest with small variants, 12 latest at full size", async () => {
  let count = 0;
  let first = "";
  const classify: Classify = async a => {
    count = a.images!.length;
    first = urlOf(a.images![0]);
    return { images: [] };
  };
  await setup(row({ photos: Array.from({ length: 40 }, (_, n) => photo(n)) }), classify).run();
  assert.equal(count, MAX_CANDIDATES);
  assert.equal(first, img(40 - MAX_CANDIDATES, 384), "later photos are preferred");

  const bare = Array.from({ length: 40 }, (_, n) => `https://photos.zillowstatic.com/fp/b${n}.jpg`);
  await setup(row({ photos: bare }), classify).run();
  assert.equal(count, MAX_CANDIDATES_FULL_SIZE);
  assert.equal(first, `https://photos.zillowstatic.com/fp/b${40 - MAX_CANDIDATES_FULL_SIZE}.jpg`);
});

test("classifier picks: >= 0.6, max 4, best first, invented indices ignored", async () => {
  const s = setup(row({ photos: Array.from({ length: 8 }, (_, n) => photo(n)) }), async () => ({
    images: [
      { index: 0, floorPlan: true, confidence: 0.61 },
      { index: 1, floorPlan: true, confidence: 0.99 },
      { index: 2, floorPlan: true, confidence: 0.7 },
      { index: 3, floorPlan: true, confidence: 0.8 },
      { index: 4, floorPlan: true, confidence: 0.9 },
      { index: 5, floorPlan: true, confidence: 0.59 },
      { index: 99, floorPlan: true, confidence: 1 },
      { index: 1, floorPlan: true, confidence: 0.98 },
    ],
  }));
  await s.run();
  assert.deepEqual(s.read.map(imgs => imgs.map(urlOf)), [[img(1, 1536), img(4, 1536), img(3, 1536), img(2, 1536)]]);
});
