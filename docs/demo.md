# Demo runbook

The judging demo is live, 2 minutes, on a phone. This page covers the seeded backup room, the script, and what to do when something breaks.

## Before the demo (5 minutes)
1. `cd agents && npm run status`: both backends **UP**, with uploads healthy and recent agent events. See `docs/backends.md` if not.
2. Phones: **Settings → Backend → Demo** (maincloud `moove-demo`, a clean database for judges), then Items → **Join a room → `4RZ9G8`** to get the seeded Bedroom (9 priced and sorted items, the guitar flagged sentimental). The app reads the worker's upload URL from `service_config`, so there's nothing to configure.
3. Budget: live Claude calls stop at `CLAUDE_MAX_USD_PER_DAY` (default $3) and live comps runs at `APIFY_MAX_USD_PER_DAY` (default $5), shared by both workers. Check `.cache/claude-spend.json` / `.cache/apify-spend.json` in `agents/` on Christian's laptop, and raise the caps in `.env.local` if a rehearsal used them up (the workers restart on save).
4. Rehearse on **Demo**, not Live. Live `moove` holds earlier test scans, junk included.
5. Hide old test rooms on each phone: **Items → Inventory → Rooms strip at the top → the room's ⋯ (or long-press its chip) → Hide room**. It's local to the phone; **Show hidden rooms** at the bottom brings them back.

## The seeded room (safety net)
`npm run seed:demo` (in `agents/`) creates a college-student bedroom through the same app reducers iOS calls (`register_user`, `import_scan`, `set_sentimental`). It connects as a **normal user**, not the worker. The room is "Bedroom", home `old`, with 9 RoomPlan-style objects (`agents/scripts/demo-room.ts`):

| Item | Category | Cached comps | Estimate | Decision |
|---|---|---|---|---|
| Full size metal bed frame | bed | 16 (ebay 10, fb 6) | $77 ($60-$130) | keep |
| IKEA Micke desk | table | 12 (ebay 4, fb 8) | $60 ($40-$75) | keep |
| Mesh office chair | chair | 17 (ebay 10, fb 7) | $30 ($27-$40) | sell |
| IKEA Kallax shelf | storage | 17 (ebay 10, fb 7) | $50 ($35-$70) | keep |
| Mini fridge | refrigerator | 18 (ebay 10, fb 8) | $38 ($25-$50) | keep |
| TCL 32 inch TV | television | 18 (ebay 10, fb 8) | $55 ($45-$60) | keep |
| Dell 27 inch monitor | electronics | 18 (ebay 10, fb 8) | $100 ($60-$125) | keep |
| Floor lamp | lamp | 18 (ebay 10, fb 8) | $60 ($47-$104) | keep |
| Yamaha acoustic guitar (flagged sentimental) | instrument | 18 (ebay 10, fb 8) | $109 ($70-$140) | left to you |

Every item name is exactly the pricing agent's query (`queryFor`: brand + name, and the brand is `''` because seeded items have no photos). Each query has a real Apify cache committed in `agents/fixtures/comps/`, so a running worker prices the whole room from replays (`[REPLAYED]` in the event log): no Apify calls, no Claude calls. `test/demo-room.test.ts` fails if an item's cache goes missing. The estimates above are the uncorrected medians (condition is unknown without vision). The decisions are what the sort agent's rules (`agents/src/agents/sort.ts`) give those estimates: every item is worth at least 1.25x its moving cost except the mesh chair ($30 vs ~$24 to move: "barely worth moving, sell"), and the bed is kept by the bed rule. Total $579: 7 keep, 1 sell, 1 left to you.

The **Offline demo** Bedroom (`MooveKit/DemoFixtures`) has the same 9 items with these names, categories, sizes, estimates and decisions (#243; `DemoSeedTests` checks it against a copy of this list), and nothing else. Its listings are only for what the sort agent sells, so today one: the mesh office chair, posted (simulated) at $30. That's under the $100 threshold, so the Offline demo has no listing approval; show that beat on Demo (the `SEED_COMMERCE` chair) or a live scan. If you change an item here, change both.

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

1. **Scan (20s).** "Moving is mostly deciding what to do with your stuff." Scan tab (the top shows your last room, or the demo bedroom, turning in 3D), **Scan a room**, scan a corner of the table with RoomPlan, **Done**, **Looks right: check photos** (Moove already cut a photo of each item from the scan, marked **Auto**; retake any that look bad), then **Add N items**. Point out the "Also found: …" chip during the scan for things RoomPlan doesn't know (bike, plant, guitar). The finished page shows the room as a voxel dollhouse (real walls, doors, windows, each piece where it stood, colored from the scan) with the items below. If the scan is slow, cut to the seeded Bedroom (join with the code), or tap **Load demo scan**: it imports a recorded bedroom and shows the same dollhouse page, tagged **Demo scan**. **See inventory** goes to Items > Inventory. Under the Rooms strip, "Identifying items from room photos…" shows while the photo sweep names unidentified boxes and adds missed items; the offline demo plays this too (a potted monstera appears).
2. **Inventory (10s).** Items tab, **Inventory**. "Everything you own" as a small museum: items hang in halls by what they're for (**The Work & Study Hall**, **The Sleep Hall**, ...), each a voxel model on a plinth with a placard: name, catalog line with the LiDAR size ("Mesh, Herman Miller · 70 × 110 cm"), a one-line story from the data ("Worth ~$30, cheaper to sell than to move", the guitar's gold ribbon and "Possibly sentimental. Moove leaves this one to you"), and "Catalogued <date> · from the Bedroom". Tap the guitar's story and type "Grandma's, 1974": the placard now says "Acquired 1974". Rooms (share, 3D, hide, add) are chips on top.
3. **Prices (20s).** Each item gets an estimate and its real eBay sold / FB Marketplace comps. Open Sell & Buy > **Spending**: the pricing agent paid $0.01 per lookup over x402 (Base Sepolia, or labeled simulated). Comps from the cache say `[REPLAYED]`.
4. **Sort (15s).** Items tab, **Review**. On top, the **Needs you** deck: the guitar is flagged sentimental, so the agent leaves it to you as a card. Swipe it right to **Keep** (left to Sell; Donate and Trash are the buttons under the card; **Undo** brings it back), and "All decided" shows the totals. Below, **Where it goes**: Keep (→ new home), Sell ($ expected), Donate (kg kept from landfill) and Trash tiles with the items fanned on them; tap one for its items, each with the agent's reason and a change menu (⇄). Change one on phone A and phone B updates live (SpacetimeDB).
5. **List and approve (20s).** Sell & Buy tab (**Listings**, then **Approvals**; the tab badge counts pending approvals). Mark something sell. The listing agent drafts an eBay listing. Anything over the $100 threshold needs approval: a Guardian push (Auth0 CIBA) or the in-app Approvals inbox.
6. **Buy (15s).** Sell & Buy > **Shopping**. The new place needs something. The buy agent finds deals, screens them for fraud, and checks out after approval.
7. **New home and fly-in (15s).** Move tab, **New Home**. Pick the demo house (**Use this home**), or **Paste a Zillow link** (top of the picker; on a chosen home it is the button under the title, and **Change home** at top left picks another): paste the link, optionally add floor-plan screenshots, **Build floor plan**, **Use this home**. Everything you kept flies out of your scanned room (drawn beside the house) to its new spot, and things you bought fly in too. **Moving from N rooms · M items ›** under the title picks which scanned rooms move (newest scan of each room name by default, so a re-scanned bedroom doesn't bring a second bed; Select all / None). The layout follows designer rules: one bed per bedroom with nightstands either side (extra beds are listed as **Storage**; the bought mattress goes on the kept bed frame, "on the Full size metal bed frame", not into Bedroom 2), the sofa facing the TV with the coffee table in front, the table with chairs around it, the desk by a window, and a clear path from every door. Switch layout style (By function / Compact / Open), **Fly in** replays it, **Save layout** saves it. Scroll to **Room shots**: each furnished room on its own, framed like an interior photo (they re-render when the style changes); tap one for full screen, swipe to the next room, **Share** to save it. If there's time: **Pack** (same tab): the same **Moving from N rooms ›** row (once you've kept things; it opens the same picker, so boxes, furniture and the truck only include the rooms that move), 9 boxes, one row per room ("Bedroom · 3 boxes · 37 kg"); tap a room for its boxes in the room's color with the reason each thing goes there ("Throws pad the vases"; everyday stuff Moove estimates sits under "Everyday stuff (estimate)"), tap a box for its contents in 3D, **Print labels** for a PDF of labels with QR codes (share sheet: Print or Save), the bought mattress under **Delivered to your new home**, and the truck estimate. Then the 3D truck on the card (**Full screen** to orbit) on the Truck and crew card: the voxel moving truck (roof and near side cut away) with every kept piece and box loaded cab-first (bought pieces are delivered, so not on it); **Load the truck** replays them flying in in load order, tap a piece for its name.
8. **Summary (5s).** Summary tab. Money made, money spent (real vs simulated), and kg kept out of landfill. At the bottom, "Agents kept you safe": the scam deal blocked, approvals asked, sentimental items left to you, and spend against the caps (simulated labeled).

## Fallbacks
Everything simulated says so, in the data (`simulated: true`) and in the UI.

| If this breaks | Do this |
|---|---|
| Wifi or the backend | Settings, then backend "Offline demo (fixtures)". The banner says "Offline demo: fixture data, nothing is synced". The whole flow runs on `MooveKit/DemoFixtures`. |
| The live scan | Join the seeded Bedroom with its code, tap **Load demo scan** on the Scan tab, or use the offline demo. |
| The scan misread something (a table drawn as a cabinet, a lamp called "pillow", a piece facing the wall, a ghost item) | Items > Review, open the item, **Fix it**: type a name (**Coffee table** re-routes the 3D model), tap a **What is it?** chip (Table, Lamp, ...), **Turn around** / **90°**, or **Not a real item** then **Remove**. Or long-press its exhibit in Inventory for the same menu. Every 3D view updates live; works offline too. |
| Listing import | With no worker reachable it builds an estimate from beds, baths and square feet (labeled Estimated). Or skip it and use the demo house. |
| Apify (slow, down, out of credit) | Comps replay from `agents/fixtures/comps/` and are labeled `[REPLAYED]`. Seeded items always replay. |
| x402 / CDP | Without CDP keys, or with `X402_SIMULATE=1`, payments are recorded `simulated: true` and badged in the spending log. If a paid call fails, pricing falls back to Apify directly. `PRICING_PAY_X402=0` skips paying. |
| eBay sandbox | Without every `EBAY_*` key, listings are simulated (`simulated: true`) and written to `uploads/listing-<id>.html`. |
| Auth0 push | The approval stays `pending` in the in-app Approvals inbox. Approve it there. |
