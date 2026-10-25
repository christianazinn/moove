# Demo runbook

The judging demo is live, 2 minutes, on a phone. This page covers the seeded backup room, the script, and what to do when something breaks.

## Before the demo (5 minutes)
1. `cd agents && npm run status`, then `npm run smoke -- moove-demo 4RZ9G8`. **Expected:** both backends **UP** with uploads healthy, and 6 PASS lines (join, 10/10 priced and sorted, upload round trip, room/user private). See `docs/backends.md` if not.
2. **Re-arm the commerce beat** the morning of judging, so the Herman Miller chair's $325 listing is fresh and pending (approvals expire after 12 h and are asked again at most twice): `SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_DB_NAME=moove-demo npm run seed:demo -- --maincloud --reset-commerce --wait`. It costs one Claude call, and the join code stays the same. Do it again after any rehearsal that approves the chair.
3. **Money rails:**
   - **x402 is real** (Base Sepolia). Check the wallet with `npm run x402:wallet`. Each lookup is $0.01, and `-- --faucet` tops it up for free.
   - **Visa is the Authorize.net sandbox**: the test card, no real money, approvals say VISA SANDBOX. Each user has their own card budget (`VISA_SPEND_CAP_USD`).
   - **eBay is simulated.**
4. Phones: **Settings → Backend → Demo** (maincloud `moove-demo`, a clean database for judges), then Items → **Join a room → `4RZ9G8`** to get the seeded Bedroom (10 priced and sorted items, the guitar flagged sentimental, the chair to approve). The app reads the worker's upload URL from `service_config`, so there's nothing to configure. A joined phone sees the room's x402 payments under Spending → **Shared room**.
5. Budget: live Claude calls stop at `CLAUDE_MAX_USD_PER_DAY` (default $3) and live comps runs at `APIFY_MAX_USD_PER_DAY` (default $5), shared by both workers. Check `.cache/claude-spend.json` / `.cache/apify-spend.json` in `agents/` on Christian's laptop, and raise the caps in `.env.local` if a rehearsal used them up (the workers restart on save).
6. Rehearse on **Demo**, not Live. Live `moove` holds earlier test scans, junk included.
7. Hide old test rooms on each phone: **Items → Inventory → Rooms strip at the top → the room's ⋯ (or long-press its chip) → Hide room**. It's local to the phone; **Show hidden rooms** at the bottom brings them back.

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

The **Offline demo** Bedroom (`MooveKit/DemoFixtures`) has the same 9 items with these names, categories, sizes, estimates and decisions (#243; `DemoSeedTests` checks it against a copy of this list), plus three offline-only commerce items set to sell: the Herman Miller office chair (the seed's `SEED_COMMERCE` chair), a nightstand and a bean bag. If you change an item here, change both.

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

1. **Scan (20s).** "Moving is mostly deciding what to do with your stuff." Scan tab (the top shows your last room, or the demo bedroom, turning in 3D), **Scan a room**, scan a corner of the table with RoomPlan, **Done**, **Looks right: check photos** (Moove already cut a photo of each item from the scan, marked **Auto**; retake any that look bad). The **Room** field above the list is already filled in from what the scan found (a bed says Bedroom, a sofa or TV Living room, a stove or fridge Kitchen, a toilet Bathroom, a desk and monitor Office); tap a chip (Bedroom, Living room, Kitchen, Bathroom, Office, Dining room, Garage, Other…) or type a name, and if you already have a Bedroom it offers "Bedroom 2". Then **Add N items**. Rename a room any time from its chip's **⋯ → Rename room** in Items > Inventory. Point out the "Also found: …" chip during the scan for things RoomPlan doesn't know (bike, plant, guitar). The finished page shows the room as a voxel dollhouse (real walls, doors, windows, each piece where it stood, colored from the scan) with the items below. If the scan is slow, cut to the seeded Bedroom (join with the code), or tap **Load demo scan**: it imports a recorded bedroom and shows the same dollhouse page, tagged **Demo scan**. **See inventory** goes to Items > Inventory. Under the Rooms strip, "Identifying items from room photos…" shows while the photo sweep names unidentified boxes and adds missed items; the offline demo plays this too (a potted monstera appears).
2. **Inventory (10s).** Items tab, **Inventory**. "Everything you own" as a tabbed binder: one page per function behind index tabs (**Sleep**, **Work & study**, ...), each page a wall of wooden voxel shelves with the items standing on them (small things up top, the bed on the floor row), each with a hanging tag (name, price). Tap a tab or swipe to turn the page. Tap the guitar: its placard has the name, the LiDAR size and the price. Rooms are name chips on top (tap to focus); share, 3D, rename, hide and add are in the Rooms ⋯ menu.
3. **Prices (20s).** Each item gets an estimate and its real eBay sold / FB Marketplace comps. Open Sell & Buy > **Agents** and scroll to the receipts: the pricing agent paid $0.01 per lookup over x402 (Base Sepolia, or labeled simulated). Comps from the cache say `[REPLAYED]`.
4. **Sort (15s).** Items tab, **Review**. At the very top, a green strip: "~49 kg kept out of landfill · 4 items sold or donated" (tap it for how it is estimated); it updates as you decide. Under it, the **flip cards**: the whole move as a stack ("1 of 12"). The guitar is first with a **Needs you** badge, since it's flagged sentimental and the agent leaves it to you. Tap it to flip it over (voxel model, size, value, the agent's reason), then swipe it right to **Keep** (left to Sell; Donate and Trash are the buttons; **Undo** brings it back). The next cards are the agent's calls, each with "Moove says: Sell · worth $30, costs ~$24 to move", ready to confirm or change. Below, **Where it goes**: four tiles, Keep (new home), Sell ($ expected), Donate (kg kept from landfill) and Trash, each with a count and its items fanned; tap one for its list, each with the agent's reason and a change menu (⇄). Change one on phone A and phone B updates live (SpacetimeDB).
5. **List and approve (20s).** Sell & Buy tab (**Listings**, then **Agents**, whose "Needs your OK" section is on top; the tab badge and the "Agents · N" pill count pending approvals). Mark something sell. The listing agent drafts an eBay listing. Anything over the $100 threshold needs approval: a Guardian push (Auth0 CIBA) or the in-app inbox (Sell & Buy > Agents).
6. **Buy (15s).** Sell & Buy > **Shopping**. The new place needs something. The buy agent finds deals, screens them for fraud, and checks out after approval.
7. **New home and fly-in (15s).** Move tab: one page, no segments (the new home on top, then the truck and boxes). Pick the demo house (**Use this home**), or **Paste a Zillow link** (top of the picker; on a chosen home, **Change home** next to the title opens the picker again): paste the link, optionally add floor-plan screenshots, **Build floor plan**, **Use this home**. Everything you kept flies out of your scanned room (drawn beside the house) to its new spot, and things you bought fly in too. The small room chip under the title (one for the whole page) picks which scanned rooms move (newest scan of each room name by default, so a re-scanned bedroom doesn't bring a second bed; Select all / None). The layout follows designer rules: one bed per bedroom with nightstands either side (extra beds are listed as **Storage**; the bought mattress goes on the kept bed frame, "on the Full size metal bed frame", not into Bedroom 2), the sofa facing the TV with the coffee table in front, the table with chairs around it, the desk by a window, and a clear path from every door. There is one layout (by function), saved on its own; **Rearrange** replays the fly-in. If there's time, keep scrolling to **Getting there** (same page; the Moving from row above also decides what the boxes, furniture and truck include): the truck card with the voxel moving truck in 3D (roof and near side cut away) holding every kept piece and box loaded cab-first (bought pieces are delivered, so not on it); **Load the truck** replays them flying in in load order; tap the truck itself to open it full screen, orbit it and tap a piece for its name. Under it, the truck size. Under it, **Boxes**: 9 plain kraft box cards (number, room, a fragile glass where it applies) under small room headings; tap a box for the reason each thing goes there ("Throws pad the vases") and for its contents in 3D, **Print labels** for a PDF of labels with QR codes (share sheet: Print or Save), and the bought mattress under **Delivered to your new home**. At the bottom, folded: **Pieces** (where each placed piece goes). The layout, the truck and the boxes all hold the same things Review shows under **Keep** (the guitar, still waiting on you, rides in **Keep with you**).
8. **Agents kept you safe (5s).** Sell & Buy > **Agents**, scroll past "Needs your OK" to **Agents kept you safe**: the scam deal blocked, approvals asked, sentimental items left to you, and spend against the caps (simulated labeled). Money made and spent is on the receipts tape below; kg kept out of landfill is the banner on top of Review (step 4). There is no Summary tab any more (decision 0129 addendum).

## Fallbacks
Everything simulated says so, in the data (`simulated: true`) and in the UI.

| If this breaks | Do this |
|---|---|
| Wifi or the backend | Settings, then backend "Offline demo (fixtures)". The banner says "Offline demo". The whole flow runs on `MooveKit/DemoFixtures`. |
| The live scan | Join the seeded Bedroom with its code, tap **Load demo scan** on the Scan tab, or use the offline demo. |
| The scan misread something (a table drawn as a cabinet, a lamp called "pillow", a piece facing the wall, a ghost item) | Items > Review, open the item, **Fix it**: type a name (**Coffee table** re-routes the 3D model), tap a **What is it?** chip (Table, Lamp, ...), **Turn around** / **90°**, or **Not a real item** then **Remove**. Or long-press it on its Inventory shelf for the same menu. Every 3D view updates live; works offline too. |
| Listing import | With no worker reachable it builds an estimate from beds, baths and square feet (labeled Estimated). Or skip it and use the demo house. |
| Apify (slow, down, out of credit) | Comps replay from `agents/fixtures/comps/` and are labeled `[REPLAYED]`. Seeded items always replay. Out of credit (as since Sat noon): new items borrow the real cached comps of the most similar item, labeled `[REPLAYED, similar item "…"]`, and no x402 payment is made for them (#303, #338). |
| x402 / CDP | Real since Sat ~12:40 PM (CDP keys on the worker). If the wallet runs dry, `npm run x402:wallet -- --faucet`. Without CDP keys, or with `X402_SIMULATE=1`, payments are recorded `simulated: true` and badged in the spending log. If a paid call fails, pricing falls back to Apify directly. `PRICING_PAY_X402=0` skips paying. |
| eBay sandbox | Without every `EBAY_*` key, listings are simulated (`simulated: true`) and written to `uploads/listing-<id>.html`. |
| Visa sandbox | If Authorize.net's sandbox is down, the purchase fails with an error event and the deal stays chooseable. Show the fraud block and the approval card instead, or set `VISA_PROVIDER=simulated` in `.env.local` (labeled SIMULATED, and the workers restart). |
| Auth0 push | CIBA is live for owners signed in with Auth0. If the push doesn't arrive (a guest, the seeded Demo owner, Guardian not enrolled, or the 5-minute expiry), the approval stays `pending` in the in-app inbox (Sell & Buy > Agents). Approve it there. |
