# Devpost media: screenshots and GIFs

The 8 images for the Devpost gallery, in story order: scan, items, prices, sort, list and approve, buy (with the blocked scam deal), new home, summary. Each entry gives the screen, the taps, the state to capture, a caption, the sponsor track it supports ([`docs/tracks.md`](tracks.md)) and the backend to capture it on. Capturing all 8 should take about 10 minutes.

They match the commerce [video shot list](demo-commerce.md#video-shot-list-commerce-70-s) (#175), so the stills and the video show the same rows and figures. All on-screen strings come from the Swift source and fixtures on `main` (`ios/MooveKit/Sources/MooveKit/Sync/DemoFixtures.swift`, `ShoppingFixtures.swift`, `ios/Moove/Features/*`).

**Decision (Aiden's agent):** capture everything on the **Offline demo** (Settings, the gear at top right > Backend > Data source **"Offline demo (fixtures)"**; the banner reads "Offline demo: fixture data, nothing is synced"). It is the only data source whose rows are known in advance, and `DemoNumbersTests` checks its figures. The Offline demo also has the voxel dollhouse (#137) and the new home, so the scan and new-home shots don't need the **Demo** backend. Use Demo (Settings > Backend > Data source "SpacetimeDB (live)" > Database **"Demo (moove-demo)"**, then Items > Inventory > Join a room > `4RZ9G8`) only for the optional live swaps marked below. On Demo the names and amounts differ (the seeded Bedroom has a "Mesh office chair", "IKEA Micke desk" and "Yamaha acoustic guitar", and no Aeron), and every x402 row there is simulated.

> **⚠️ Don't approve or deny the Demo chair.** On Demo, a joined phone sees the seeded "Herman Miller Office Chair, Ergonomic Desk Chair, Used, 69 x 67 x 104 cm" ($325) under Approvals > **Shared rooms**, with Approve/Deny and "Shared room: the owner's item. Anyone in the room can decide." (#248). That approval is **single-use** and is meant for the judges: tapping it posts the listing (simulated) for everyone. Shot 5 is always captured on the Offline demo. If it gets used, ask Christian to run `npm run seed:demo -- --maincloud --reset-commerce` (#246).

**Honesty rule for captions:** every caption names what's simulated or fixture data. The only real payment in the Offline demo is the $0.01 Aeron comps row with the Basescan link.

## Before capturing
- [ ] Offline demo selected (above). Tap **"Continue without an account"** on the login screen.
- [ ] **Relaunch the app** (force-quit and reopen) to reset the fixture: Approvals reads "Approvals · 2" again.
- [ ] Shots 1 to 6 use the fresh fixture. Shots 7 and 8 come **after** the scripted taps (approve the Aeron, choose the Target chair, approve the sofa), in that order, the same as the video. Don't relaunch between 5 and 8.
- [ ] Do Not Disturb on, and light mode unless the team picks dark (keep all 8 the same).

## The shots

### 1. Scan: the room as a voxel dollhouse
- **Screen:** Scan tab (the first tab). No taps. The hero at the top is the fixture Bedroom as a slowly turning voxel dollhouse.
- **State:** the hero with the **"Demo"** tag and the caption "Bedroom · 12 objects", with "Scan a room." and the **Scan a room** button below. Best as a **GIF** (3 to 4 s of the turn).
- **Alternative (still):** tap **Load demo scan**. The finished page shows "01 — Scan · Done", the **"Demo scan"** tag, "12 items added", "A recorded bedroom, not a live scan. Offline demo: items, prices and colors are fixture data, as if the agents had run." and the dollhouse with the items below. This adds a second "Demo bedroom" room, so **relaunch** before shot 2.
- **Live swap:** if Rio has a real LiDAR scan on the Demo backend, its finished page (same layout, no "Demo scan" tag) is the better image. Change the caption to "a real scan".
- **Caption:** "Scan a room with the iPhone's LiDAR and Moove rebuilds it as a voxel dollhouse, each piece where it stood (shown: our recorded demo bedroom)."
- **Track:** Spacetime (the scan is imported through the `import_scan_v2` reducer), Best Planet-First Hack (the story starts here).
- **Backend:** Offline demo.

### 2. Items: the inventory
- **Screen:** Items tab > **Inventory** segment.
- **State:** "02 — Inventory", "Everything you own.", the stats **Items 12**, **Rooms 1**, **Est. value $813**, and the Bedroom rows (Queen bed frame, Office chair, Desk, Bookshelf, ...) with voxel thumbnails and LiDAR dimensions.
- **Caption:** "Every scanned item, with its LiDAR dimensions, in an inventory where names and prices fill in as the agents finish (shown on fixture data)."
- **Track:** Anthropic (Claude vision names each item from its photos plus dimensions), Spacetime (inventory rows sync live).
- **Backend:** Offline demo. Live swap: Demo, after joining `4RZ9G8` (9 seeded, priced items).

### 3. Prices: the agent pays for its comps over x402
- **Screen:** Sell & Buy tab > **Spending** segment. Scroll so the totals and the first payment are both visible.
- **State:** totals **Spent $0.01**, **Simulated $180.005** (orange), **Refused 1**. The row "$0.01", "Premium comps for "Herman Miller Aeron"", "Pricing agent · x402 · USDC", "Settled", **"Basescan 0xc794…136c"**, and below it rows with the filled **SIMULATED** pill and no Basescan link. This is video shot 1a.
- **Optional second image (prices themselves):** Items > Review > tap **Office chair**. "03 — Review · Item", **$420**, and "Comparable listings" with 3 rows: "Herman Miller Aeron size B" EBAY $450, "Aeron chair, good condition" CRAIGSLIST $380, "Herman Miller office chair" FB $425. Caption: "Each item is priced from comparable sold and local listings (fixture comps shown)."
- **Caption:** "Our pricing agent pays for its own comps: $0.01 USDC per lookup over x402 on Base Sepolia, and the Basescan row is a real transaction; every row tagged SIMULATED is simulated."
- **Track:** Coinbase x402 (the headline image for that track), Apify (the comps the agent pays for come from Apify's eBay sold and FB Marketplace actors), Spacetime (each payment is a `payment` row).
- **Backend:** Offline demo. Don't capture this on Demo: its worker has no CDP keys, so it has no real payment and no Basescan link.

### 4. Sort: keep, sell, donate, trash
- **Screen:** Items tab > **Review** segment.
- **State:** "03 — Review", "Decide what goes.", the totals **Expected sales $555**, **Items to move 3**, **Need you 2** (red), then the **"Needs you"** section with **Grandma's quilt rack** and **Framed photos** (heart icons, "Possibly sentimental") and the note "Moove never decides possibly sentimental items for you.", then Keep rows with their reasons (e.g. Queen bed frame, "Needed in the new bedroom; costs more to replace than to move.").
- **Caption:** "Moove suggests keep, sell, donate or trash with a reason for each, and leaves possibly sentimental items like Grandma's quilt rack to you (fixture data)."
- **Track:** Anthropic (knowing where the model shouldn't decide), Best Planet-First Hack (donate and resell over trash).
- **Backend:** Offline demo. Live swap: Demo, where the guitar is the sentimental one.

### 5. List and approve: a $410 listing waits for you
- **Screen:** Sell & Buy tab > **Approvals** segment (it reads "Approvals · 2"; the tab icon has a badge of 2).
- **State:** before tapping: **"Needs you · 2"**, the Sell request "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition", **$410**, the Sell tag and SIMULATED pill, the Buy request for the "78" upholstered sofa, gray" $429.99 "from wayfair" with its own filled **SIMULATED** pill (#238: the Visa checkout is simulated, and VoiceOver says "Simulated purchase, no money will move"), and "Also sent to your phone via Auth0 Guardian when set up. Approving here works too." Good as a **GIF**: tap **Approve** on the Aeron, it moves to the top of History with "You approved it. The listing agent posts it." and "Needs you · 1". This is video shot 3. Further down, **History · 4** (5 after the tap) includes the $699 KIVIK sofa with the outlined **EXPIRED** pill and "No answer in 12 h. The agent asked again." (#231). That makes an optional extra still for the Auth0 track: unanswered requests time out instead of waiting forever.
- **Optional:** Listings segment after approving: the Aeron under **Live** (now Live 2, Listed $445) with **"Posted (simulated)"**. Before approving, it sits under **"Needs approval"** (renamed from "Needs you" in #208).
- **Caption:** "Claude writes the listing, and anything over your $100 limit waits for your approval by Auth0 push or in the app; the eBay post itself is simulated."
- **Track:** Auth0 (approval over the threshold; CIBA push when configured, in-app inbox shown), Anthropic (the Claude-written listing).
- **Backend:** Offline demo **only**. No live swap: the Demo chair approval is single-use (see the warning at the top).

### 6. Buy: the fraud screen blocks a planted scam
- **Screen:** Sell & Buy tab > **Shopping** segment > tap **Desk chair**.
- **State:** 3 deals with voxel chairs. The planted deal **"Herman Miller Aeron, brand new, $95, Zelle only, ship only"**, seller "Planted demo scam (not a real listing)", **Sample** badge, chip **"Likely fraud · 0.85"**, reasons "asks for payment by Zelle" and "shipping only, no meetup", and the red **"Blocked: likely fraud"** tag where Choose would be. Then tap **Choose** on the Target "Mesh task chair with arms, black" ($79.99): "Paid through the simulated Visa rail. No real card was charged." The blocked deal is the still; the Choose tap can be a GIF. This is video shot 4.
- Then, for shots 7 and 8, go back to the Shopping list and tap **Approve** on the **"Needs you · 1"** card ("78" upholstered sofa, gray", **$429.99**, "Over your approval limit. The agent pays with Visa only after you approve."). That's video shot 5; optional extra still.
- **Caption:** "The buy agent screens every deal for fraud and won't buy this planted Zelle-only 'brand new' Aeron (score 0.85); checkout runs on a labeled simulated Visa rail."
- **Track:** Visa (fraud checks, approvals, trust and responsibility), Apify (deal search; fixture deals are labeled Sample).
- **Backend:** Offline demo (the 0.85 is a fixture value; the real fraud agent gives the same planted deal 0.85 live).

### 7. New home: what you kept and bought, in the dollhouse
- **Screen:** Move tab > **New Home** > the **"Demo house · 2 bed, 1 bath"** card > **Use this home**.
- **State:** "06 — New home", the **"Demo house"** tag, the voxel house with the fly-in playing, **Fly in** and **Save layout**, and under "Pieces" the kept items (Queen bed frame, Floor lamp, Nightstand) plus the bought ones from the chosen deals: "8" memory foam mattress, Full" and, after the sofa approval in shot 6, "78" upholstered sofa, gray". Best as a **GIF** of the fly-in (tap **Fly in** to replay it). This is video shot 6a.
- **Caption:** "Everything you kept, plus what the buy agent bought, flies into the new home's 3D layout (demo house shown)."
- **Track:** Visa (bought items land in the new home), Best Planet-First Hack.
- **Backend:** Offline demo. Live swap: Demo, after Lisa's check in [`docs/morning.md`](morning.md).

### 8. Summary: what you made, spent and kept out of landfill
- **Screen:** Summary tab. Scroll so "Where everything went" and **Money** are both visible (two stills are fine). An optional third still is the **"Agents kept you safe"** card at the bottom.
- **State (after the taps in shots 5 and 6):** "07 — Summary", "Your move, handled.", "Where everything went": 12 items, Kept 3, Selling 4, Donated 2, Trashed 1, Undecided 2. **Money** with the **Simulated** tag: Sold $18, Still selling $520, **Spent $689.995**, **Net −$152**; "Visa purchases" $689.97 tagged Simulated, "x402 data payments" $0.025 tagged "$0.015 sim"; then Impact, "~109 kg" "kept out of landfill" and "6 items sold or donated, not trashed." This is video shot 6b. At the bottom, **"Agents kept you safe"** (Simulated tag): "1 scam deal blocked · fraud score 0.85", "6 approvals asked · 3 approved · 2 denied · 1 expired" with "Anything over $100 needs your OK", "2 sentimental items left for you", "Spent $0.025 of $10.00 data budget ($0.015 simulated)" and "Spent $689.97 of $1,500.00 card budget (simulated)". On a fresh fixture (before the taps), the approvals line reads "6 approvals asked · 1 approved · 2 denied · 2 waiting · 1 expired" and the card line reads "Spent $179.99 of $1,500.00 card budget (simulated)".
- **Caption:** "The summary adds up what you sold, what the agents spent and what stayed out of landfill, and tags the simulated money as Simulated."
- **Track:** Best Planet-First Hack, Coinbase and Visa (real vs. simulated spend kept apart).
- **Backend:** Offline demo.

## Capture tips
- **iPhone:** press the side button and volume up together. For a GIF, use the built-in Screen Recording (Control Center), then trim it.
- **Simulator:** `xcrun simctl io booted screenshot ~/Desktop/moove-01-scan.png`, or `xcrun simctl io booted recordVideo ~/Desktop/flyin.mov` (Ctrl-C to stop) for a GIF source. The Simulator has no LiDAR, but the Offline demo needs none.
- **GIFs:** convert a short recording with `ffmpeg -i flyin.mov -vf "fps=12,scale=600:-1:flags=lanczos" -loop 0 flyin.gif`, or use Gifski or Kap on the Mac. Keep them 3 to 6 s and under a few MB.
- **Devpost limits:** as far as we know, the gallery takes JPG, PNG and GIF up to about 5 MB each and displays at 3:2. That's unverified, so check the upload form. Phone screenshots are tall, so consider putting each on a 3:2 canvas (Figma, Keynote, or Preview) so they don't get cropped.
- Name files in story order (`01-scan.gif`, `02-items.png`, ...) and upload in that order.

## Fallback: screenshots from CI
Rio's UI smoke tests (#161, merged, `ios/MooveUITests/MooveSmokeTests.swift`) and the commerce UI test (#155, merged, `CommerceUITests.swift`) run on the Offline demo in the Simulator and attach screenshots (`XCTAttachment`, `.keepAlways`). CI's `ios-ui` job runs them on PRs that touch `ios/` and on pushes to `main`, and uploads the PNGs as the `ios-ui-screenshots` artifact (about 15 min per run). To fetch them from a finished run on `main`:

```sh
gh run list -R christianazinn/moove --workflow ci.yml --branch main --limit 5
gh run download <run-id> -R christianazinn/moove -n ios-ui-screenshots -D ~/Desktop/moove-ci-shots
```

The files land as `MooveSmokeTests/<name>.png` (e.g. `03-scan-finished`, `03-inventory`, `02-review`, `04-room-3d`) and `CommerceUITests/<name>.png` (`1-spending`, `3-approvals-pending`, `5-desk-chair-deals`, `6-desk-chair-paid`, ...). They're simulator-sized and unframed, so use them only if no phone is free. To get them without CI, run the UI tests locally and export the attachments:

```sh
cd ios && xcodegen
xcodebuild test -scheme Moove -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath /tmp/ui.xcresult
xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path /tmp/ui-shots
```
(Use any iPhone simulator you have installed: `xcrun simctl list devices available`.)
