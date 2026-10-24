import { test } from "node:test";
import assert from "node:assert/strict";
import { importHome, ImportInputError, parseImportBody, parseListingUrl } from "../src/homes/listing.js";
import type { PlanReading } from "../src/homes/floorplanVision.js";
import { extractZillowFacts, findFloorPlanImages, zillowRunUrl } from "../src/homes/zillowApify.js";

const quiet = () => {};

test("Zillow homedetails link -> address, no fetch", () => {
  const p = parseListingUrl("https://www.zillow.com/homedetails/418-Example-St-APT-3B-Portland-OR-97204/2061234567_zpid/?utm=x");
  assert.equal(p.site, "zillow");
  assert.equal(p.address, "418 Example St Apt 3B, Portland, OR 97204");
  assert.equal(p.note, null);
});

test("Zillow link with only a zpid asks for the address", () => {
  const p = parseListingUrl("zillow.com/homedetails/2061234567_zpid/");
  assert.equal(p.site, "zillow");
  assert.equal(p.address, null);
  assert.match(p.note!, /Type the address/);
});

test("Zillow building and apartments links", () => {
  assert.equal(parseListingUrl("https://www.zillow.com/b/the-addison-seattle-wa-5XjVq9/").address, "The Addison, Seattle, WA");
  assert.equal(parseListingUrl("https://www.zillow.com/apartments/dallas-tx/hanover-turtle-creek/CpjCGP/").address, "Hanover Turtle Creek, Dallas, TX");
});

test("Redfin link with unit", () => {
  const p = parseListingUrl("https://www.redfin.com/WA/Seattle/123-Main-St-98101/unit-4B/home/12345");
  assert.equal(p.site, "redfin");
  assert.equal(p.address, "123 Main St Unit 4B, Seattle, WA 98101");
});

test("Redfin multi-word city", () => {
  assert.equal(parseListingUrl("https://www.redfin.com/CA/San-Francisco/1-Market-St-94105/home/1").address, "1 Market St, San Francisco, CA 94105");
});

test("Realtor.com link", () => {
  const p = parseListingUrl("https://www.realtor.com/realestateandhomes-detail/742-Evergreen-Ter_Springfield_IL_62704_M12345-67890");
  assert.equal(p.site, "realtor");
  assert.equal(p.address, "742 Evergreen Ter, Springfield, IL 62704");
});

test("Apartments.com address and building links", () => {
  assert.equal(parseListingUrl("https://www.apartments.com/500-n-lake-shore-dr-chicago-il/abc123/").address, "500 N Lake Shore Dr, Chicago, IL");
  const b = parseListingUrl("https://www.apartments.com/the-mark-austin-tx/7k2l9p/");
  assert.equal(b.building, "The Mark");
  assert.equal(b.address, "The Mark, Austin, TX");
});

test("StreetEasy building + unit, and listing-number links", () => {
  assert.equal(parseListingUrl("https://streeteasy.com/building/245-east-50-street-new_york/4b").address, "245 East 50 Street #4B, New York, NY");
  assert.equal(parseListingUrl("https://streeteasy.com/building/245-east-50-street-brooklyn").address, "245 East 50 Street, Brooklyn, NY");
  const r = parseListingUrl("https://streeteasy.com/rental/1234567");
  assert.equal(r.address, null);
  assert.match(r.note!, /listing number/);
});

test("Unknown sites and non-links ask for the address", () => {
  const o = parseListingUrl("https://example.com/house/123");
  assert.equal(o.site, "other");
  assert.equal(o.address, null);
  assert.match(o.note!, /Type the address/);
  assert.equal(parseListingUrl("javascript:alert(1)").address, null);
  // Look-alike hosts are not Zillow.
  assert.equal(parseListingUrl("https://notzillow.com.evil.io/homedetails/1-Main-St-Austin-TX-78701/1_zpid/").site, "other");
});

test("body validation", () => {
  assert.throws(() => parseImportBody(null), ImportInputError);
  assert.throws(() => parseImportBody([]), ImportInputError);
  assert.throws(() => parseImportBody({}), ImportInputError);
  assert.throws(() => parseImportBody({ beds: -1 }), ImportInputError);
  assert.throws(() => parseImportBody({ url: 5 }), ImportInputError);
  assert.throws(() => parseImportBody({ floorPlanImageUrls: ["a", "b", "c", "d", "e"] }), ImportInputError);
  assert.throws(() => parseImportBody({ address: "x", useScraper: "yes" }), ImportInputError);
  assert.deepEqual(parseImportBody({ beds: 2, address: null }).beds, 2);
});

test("link only: address from the link, no plan, method facts", async () => {
  const r = await importHome(
    { url: "https://www.zillow.com/homedetails/418-Example-St-APT-3B-Portland-OR-97204/2061234567_zpid/" },
    { log: quiet, scrapeZillow: () => assert.fail("scraper must not run without useScraper") }
  );
  assert.equal(r.address, "418 Example St Apt 3B, Portland, OR 97204");
  assert.equal(r.name, "418 Example St Apt 3B");
  assert.equal(r.site, "zillow");
  assert.equal(r.floorPlan, null);
  assert.equal(r.method, "facts");
  assert.equal(r.simulated, false);
  assert.equal(r.listingUrl, "https://www.zillow.com/homedetails/418-Example-St-APT-3B-Portland-OR-97204/2061234567_zpid/");
  assert.ok(r.notes.some(n => /not opened/.test(n)));
});

test("facts only: typed address wins, numbers passed through", async () => {
  const r = await importHome({ address: "1 Main St, Austin, TX", beds: 2, baths: 1.5, sqft: 950 }, { log: quiet });
  assert.deepEqual([r.name, r.beds, r.baths, r.sqft, r.site, r.listingUrl, r.method], ["1 Main St", 2, 1.5, 950, null, null, "facts"]);
});

test("useScraper without a token is skipped with a note", async () => {
  const r = await importHome(
    { url: "https://www.zillow.com/homedetails/1-Main-St-Austin-TX-78701/1_zpid/", useScraper: true },
    { log: quiet, apifyToken: "", scrapeZillow: () => assert.fail("no token, no scrape") }
  );
  assert.equal(r.method, "facts");
  assert.ok(r.notes.some(n => /APIFY_TOKEN/.test(n)));
});

const READING: PlanReading = {
  isFloorPlan: true,
  units: "feet",
  notes: "",
  rooms: [
    { name: "Bedroom", kind: "bedroom", dimensionLabel: `12' x 11'`, widthM: 3.6, depthM: 3.3, image: 0, box: null, doors: [], windows: [] },
    { name: "Living Room", kind: "living", dimensionLabel: `15'6" x 13'`, widthM: 4.7, depthM: 4, image: 0, box: null, doors: [], windows: [] },
    { name: "Bath", kind: "bathroom", dimensionLabel: "", widthM: 2.4, depthM: 1.6, image: 0, box: null, doors: [], windows: [] },
  ],
};

test("images: floor plan read from uploads, method floorplan, facts filled from the plan", async () => {
  const { readFloorPlan } = await import("../src/homes/floorplanVision.js");
  const r = await importHome(
    { floorPlanImageUrls: ["http://localhost:8787/files/x.jpg"] },
    {
      log: quiet,
      loadImage: async () => ({ mediaType: "image/jpeg", data: "AAAA" }),
      readFloorPlan: (images, opts) => readFloorPlan(images, { ...opts, call: async () => READING }),
    }
  );
  assert.equal(r.method, "floorplan");
  assert.equal(r.floorPlan?.rooms.length, 3);
  assert.equal(r.beds, 1);
  assert.equal(r.baths, 1);
  assert.ok(r.sqft! > 0);
});

test("scraper path: facts + scraped floor plan, labeled", async () => {
  const { readFloorPlan } = await import("../src/homes/floorplanVision.js");
  const r = await importHome(
    { url: "https://www.zillow.com/homedetails/2061234567_zpid/", useScraper: true },
    {
      log: quiet,
      apifyToken: "t",
      scrapeZillow: async () => ({
        address: "418 Example St Apt 3B, Portland, OR 97204",
        beds: 2,
        baths: 1,
        sqft: 850,
        floorPlanImageUrls: ["https://photos.zillowstatic.com/fp/a.jpg"],
        floorPlanImages: [{ mediaType: "image/jpeg", data: "AAAA" }],
        notes: [],
        replayed: false,
      }),
      readFloorPlan: (images, opts) => readFloorPlan(images, { ...opts, call: async () => READING }),
    }
  );
  assert.equal(r.method, "scraper");
  assert.equal(r.address, "418 Example St Apt 3B, Portland, OR 97204");
  assert.equal(r.beds, 2);
  assert.ok(r.floorPlan);
  assert.ok(r.notes.includes("Fetched with an Apify Zillow scraper"));
});

test("zillow actor helpers", () => {
  assert.equal(zillowRunUrl("https://www.zillow.com/homedetails/x/1_zpid/"), "https://www.zillow.com/homedetails/x/1_zpid/");
  assert.equal(zillowRunUrl("https://evil.com/homedetails/x"), null);
  assert.equal(zillowRunUrl("http://www.zillow.com/x"), null);
  const row = {
    listingAddress: { full: "123 Example St APT 6E, New York, NY 10014" },
    bedrooms: 2,
    bathrooms: 1,
    livingArea: 900,
    listingPhotos: [
      { url: "https://photos.zillowstatic.com/fp/front.jpg", caption: "Front exterior" },
      { url: "https://photos.zillowstatic.com/fp/plan.jpg", caption: "Floor plan" },
      { url: "https://evil.example/plan.jpg", caption: "Floor plan" },
    ],
    floorPlans: [{ photos: [{ url: "https://photos.zillowstatic.com/fp/plan2.jpg" }] }],
  };
  const f = extractZillowFacts(row);
  assert.deepEqual([f.address, f.beds, f.baths, f.sqft], ["123 Example St APT 6E, New York, NY 10014", 2, 1, 900]);
  assert.deepEqual(findFloorPlanImages(row).sort(), ["https://photos.zillowstatic.com/fp/plan.jpg", "https://photos.zillowstatic.com/fp/plan2.jpg"]);
});
