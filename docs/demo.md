# Demo runbook

The judging demo is live, 2 minutes, on a phone. This page covers the seeded backup room, the script, and what to do when something breaks.

## Before the demo (5 minutes)
1. `cd agents && npm run status`: both backends **UP**, with uploads healthy and recent agent events. See `docs/backends.md` if not.
2. Phones: **Settings → Backend → Demo** (maincloud `moove-demo`, a clean database for judges), then Items → **Join a room → `4RZ9G8`** to get the seeded Bedroom (9 priced and sorted items, the guitar flagged sentimental). The app reads the worker's upload URL from `service_config`, so there's nothing to configure.
3. Budget: live Claude calls stop at `CLAUDE_MAX_USD_PER_DAY` (default $3) and live comps runs at `APIFY_MAX_USD_PER_DAY` (default $2), shared by both workers. Check `.cache/claude-spend.json` / `.cache/apify-spend.json` in `agents/` on Christian's laptop, and raise the caps in `.env.local` if a rehearsal used them up (the workers restart on save).
4. Rehearse on **Demo**, not Live. Live `moove` holds earlier test scans, junk included.

## The seeded room (safety net)
`npm run seed:demo` (in `agents/`) creates a college-student bedroom through the same app reducers iOS calls (`register_user`, `import_scan`, `set_sentimental`). It connects as a **normal user**, not the worker. The room is "Bedroom", home `old`, with 9 RoomPlan-style objects (`agents/scripts/demo-room.ts`):

| Item | Category | Cached comps | Estimate |
|---|---|---|---|
| Full size metal bed frame | bed | 16 (ebay 10, fb 6) | $77 ($60-$130) |
| IKEA Micke desk | table | 12 (ebay 4, fb 8) | $60 ($40-$75) |
| Mesh office chair | chair | 17 (ebay 10, fb 7) | $30 ($27-$40) |
| IKEA Kallax shelf | storage | 17 (ebay 10, fb 7) | $50 ($35-$70) |
| Mini fridge | refrigerator | 18 (ebay 10, fb 8) | $38 ($25-$50) |
| TCL 32 inch TV | television | 18 (ebay 10, fb 8) | $55 ($45-$60) |
| Dell 27 inch monitor | electronics | 18 (ebay 10, fb 8) | $100 ($60-$125) |
| Floor lamp | lamp | 18 (ebay 10, fb 8) | $60 ($47-$104) |
| Yamaha acoustic guitar (flagged sentimental) | instrument | 18 (ebay 10, fb 8) | $109 ($70-$140) |

Every item name is exactly the pricing agent's query (`queryFor`: brand + name, and the brand is `''` because seeded items have no photos). Each query has a real Apify cache committed in `agents/fixtures/comps/`, so a running worker prices the whole room from replays (`[REPLAYED]` in the event log): no Apify calls, no Claude calls. `test/demo-room.test.ts` fails if an item's cache goes missing. The estimates above are the uncorrected medians (condition is unknown without vision).

Behavior:
- Skips if this user already has a "Bedroom" and prints its join code. `--force` imports another one.
- Refuses a maincloud `SPACETIME_URI` (the `.env.example` default) unless `--maincloud` is passed, so a bare run can't write the live database.
- `--wait` (or `--wait=SEC`, default 90) waits for the worker to price the items and prints the estimates. Exits 1 if they aren't all priced.
- The user's token is saved to `agents/.user-token.<db>` (gitignored), so re-runs act as the same user. `SEED_USER_TOKEN_FILE` points it at another token file.
- `npm run comps:prefetch -- --dry` lists which demo queries are cached. Without `--dry` it fetches the missing ones live (Apify spend only, capped per actor by `APIFY_MAX_USD_PER_RUN`). If you rename a demo item, run it and commit the new fixture.

Known limits:
- Seeded items have no photos, so vision never runs and `details_status` stays `pending`. The listing agent only drafts for items with details `done`, so **seeded items won't get listings**. Show list/approve on an item scanned and photographed live, or add a photo to a seeded item in the app (that runs vision, costs one Claude call, and may rename it, so its re-pricing can miss the cache and call Apify).
- The seed user owns the room. A phone that joins with the code sees the room and its items live, but owner-scoped screens (spending log, approvals) show the phone user's own rows, not the seed user's.

### Seed locally
```sh
cd spacetime && npm ci && spacetime publish -s local -p . --yes=all --delete-data moove-demo
cd ../agents && npm ci
# worker, in its own terminal (prices from the caches; PRICING_PAY_X402=0 skips x402)
SPACETIME_URI=ws://localhost:3000 SPACETIME_DB_NAME=moove-demo SPACETIME_WORKER_TOKEN_FILE=.worker-token.moove-demo \
  UPLOAD_PORT=8795 PRICING_PAY_X402=0 npm start
# seed and watch it price
SPACETIME_URI=ws://localhost:3000 SPACETIME_DB_NAME=moove-demo npm run seed:demo -- --wait
```

### Seed maincloud (Christian only)
Only Christian touches maincloud, and only once the module there is current. From `agents/`:
```sh
SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_DB_NAME=moove npm run seed:demo -- --maincloud --wait
```
The live worker must be running against maincloud for `--wait` to see prices. Note the printed join code for the demo phones.

## The 2-minute script
Two phones if we have them: A (presenter) and B (shows live sync). Have the worker, tunnel and SpacetimeDB up, the seeded room's join code at hand, and the app on the live backend.

1. **Scan (20s).** "Moving is mostly deciding what to do with your stuff." Scan tab (the top shows your last room, or the demo bedroom, turning in 3D), **Scan a room**, scan a corner of the table with RoomPlan, **Done**, **Looks right: photograph items** (Moove already cut a photo of each item from the scan, marked **Auto**; retake any that look bad), then **Add N items**. Point out the "Also found: …" chip during the scan for things RoomPlan doesn't know (bike, plant, guitar). The finished page shows the room as a voxel dollhouse (real walls, doors, windows, each piece where it stood, colored from the scan) with the items below. If the scan is slow, cut to the seeded Bedroom (join with the code), or tap **Load demo scan**: it imports a recorded bedroom and shows the same dollhouse page, tagged **Demo scan**. **Done** goes to Items > Inventory. Under the room, "Identifying items from room photos…" shows while the photo sweep names unidentified boxes and adds missed items; the offline demo plays this too (a guitar appears).
2. **Inventory (10s).** Items tab, **Inventory**. The room's items, with dimensions from LiDAR. Vision names and conditions come from Claude when there are photos.
3. **Prices (20s).** Each item gets an estimate and its real eBay sold / FB Marketplace comps. Open Sell & Buy > **Spending**: the pricing agent paid $0.01 per lookup over x402 (Base Sepolia, or labeled simulated). Comps from the cache say `[REPLAYED]`.
4. **Sort (15s).** Items tab, **Review**. Keep/sell/donate/trash, each with a reason. The guitar is flagged sentimental, so the agent leaves it to you. Change one on phone A and phone B updates live (SpacetimeDB).
5. **List and approve (20s).** Sell & Buy tab (**Listings**, then **Approvals**; the tab badge counts pending approvals). Mark something sell. The listing agent drafts an eBay listing. Anything over the $100 threshold needs approval: a Guardian push (Auth0 CIBA) or the in-app Approvals inbox.
6. **Buy (15s).** Sell & Buy > **Shopping**. The new place needs something. The buy agent finds deals, screens them for fraud, and checks out after approval.
7. **New home and fly-in (15s).** Move tab, **New Home**. Pick the demo house (**Use this home**), or **Import from a listing**: paste a Zillow link, optionally add floor-plan screenshots, **Build floor plan**, **Use this home**. Everything you kept flies out of your scanned room (drawn beside the house) to its new spot, and things you bought fly in too. Switch layout style (By function / Compact / Open), **Fly in** replays it, **Save layout** saves it. If there's time: **Pack** (same tab) for the boxes and the truck estimate.
8. **Summary (5s).** Summary tab. Money made, money spent (real vs simulated), and kg kept out of landfill. At the bottom, "Agents kept you safe": the scam deal blocked, approvals asked, sentimental items left to you, and spend against the caps (simulated labeled).

## Fallbacks
Everything simulated says so, in the data (`simulated: true`) and in the UI.

| If this breaks | Do this |
|---|---|
| Wifi or the backend | Settings, then backend "Offline demo (fixtures)". The banner says "Offline demo: fixture data, nothing is synced". The whole flow runs on `MooveKit/DemoFixtures`. |
| The live scan | Join the seeded Bedroom with its code, tap **Load demo scan** on the Scan tab, or use the offline demo. |
| Listing import | With no worker reachable it builds an estimate from beds, baths and square feet (labeled Estimated). Or skip it and use the demo house. |
| Apify (slow, down, out of credit) | Comps replay from `agents/fixtures/comps/` and are labeled `[REPLAYED]`. Seeded items always replay. |
| x402 / CDP | Without CDP keys, or with `X402_SIMULATE=1`, payments are recorded `simulated: true` and badged in the spending log. If a paid call fails, pricing falls back to Apify directly. `PRICING_PAY_X402=0` skips paying. |
| eBay sandbox | Without every `EBAY_*` key, listings are simulated (`simulated: true`) and written to `uploads/listing-<id>.html`. |
| Auth0 push | The approval stays `pending` in the in-app Approvals inbox. Approve it there. |
