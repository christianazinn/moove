# Devpost media: the 8 gallery images

The 8 images for the Devpost gallery, in story order, one per step of the move and covering all four tabs (**Scan, Items, Sell & Buy, Move**; Summary was removed, decision 0129 addendum). For each one: the file to use from CI's **`devpost-screenshots`** artifact (written by `ios/MooveUITests/DevpostShotsTests.swift`, #242) or "by hand" when CI can't render it, the screen and taps, the state, a one-line caption, and the sponsor track it supports ([`docs/tracks.md`](tracks.md)).

They match the [demo video](demo-video.md) and the commerce [video shot list](demo-commerce.md#video-shot-list-commerce-70-s), so the stills and the video show the same rows and figures. On-screen strings come from the Swift source and fixtures on `main` (`ios/MooveKit/Sources/MooveKit/Sync/DemoFixtures.swift`, `ShoppingFixtures.swift`, `ios/Moove/Features/*`).

## The gallery at a glance
| # | Upload as | Source | Tab | Caption |
|---|---|---|---|---|
| 1 | `01-scan.png` (or a GIF) | CI `01-scan` | Scan | Scan a room with LiDAR and Moove rebuilds it as a voxel dollhouse, every piece where it stood (our recorded demo bedroom). |
| 2 | `02-scan-dollhouse.png` | **by hand** (CI `01b-scan-finished` renders blank) | Scan | The finished scan: real walls, doors and windows, tall at the back and cut low at the front, each piece colored from the scan's own frames (demo scan shown). |
| 3 | `03-review.png` | CI `04-review` | Items > Review | Swipe each item to keep, sell, donate or trash; Moove suggests one with a reason, and leaves possibly sentimental items like the guitar to you (fixture data). |
| 4 | `04-agents-receipts.png` | CI `03-spending` | Sell & Buy > Agents | The pricing agent pays for its own comps, $0.01 USDC per lookup over x402: the Base Sepolia line is a real transaction, and every SIMULATED line is simulated. |
| 5 | `05-agents-approvals.png` | CI `05-approvals` | Sell & Buy > Agents | Claude writes the listing, and anything over your $100 limit waits for your OK, by Auth0 push or in the app (the eBay post is simulated). |
| 6 | `06-scam-blocked.png` | CI `06-desk-chair-deals` | Sell & Buy > Shopping | The buy agent screens every deal and refuses this planted Zelle-only "brand new" Aeron (fraud score 0.85); checkout runs in the Visa Acceptance sandbox (no real money), and the offline demo shown here simulates it. |
| 7 | `07-new-home.gif` | **by hand** (CI `07-new-home` renders blank) | Move (top of the page) | Everything you kept, plus what the buy agent bought, flies from its old spot into the new home, then "Welcome home" (demo house shown). |
| 8 | `08-agents-safety.png` | CI `08-agents-safety` | Sell & Buy > Agents | "Agents kept you safe": every guardrail that fired, from the blocked scam deal to spend against each budget; simulated money is tagged Simulated. |

**Must be captured by hand:** images 2 and 7. They are RealityKit `ARView` scenes, which come out blank under XCUITest in CI. The other six come straight from CI.

**Extras** (not in the 8, useful for a track write-up or if Devpost allows more): CI `02-items` (Items > Inventory, the binder: a page per function behind index tabs, items standing on wooden voxel shelves with hanging tags; caption idea "Your inventory as a binder of shelves: every piece measured, priced and filed by what it's for."), `02b-items-binder-page2` (a second page, after tapping its tab), `02c-items-placard` (an item's placard sheet, opened by tapping it on its shelf), CI `03b-item-comps` (an item's price and its comparable listings) and CI `08b-review-impact` (Items > Review with the "49 kg kept from landfill" strip on top; caption idea "Moove defaults to resell or donate, and Review shows roughly how many kg that keeps out of landfill (an estimate)."; Best Planet-First Hack). **Listings shot** (Sell & Buy > Listings, the poster wall): CI's `ios-ui-screenshots` artifact has it as `2-listings` (from `CommerceUITests`); caption idea "Every listing the agent wrote, as a plain paper poster: the item's voxel model, title, price and status stamp (NEEDS YOUR OK, POSTED, SOLD); simulated eBay posts are labeled SIMULATED." Take a dark-mode one by hand if you want it (Settings > Appearance > Dark).

## Getting the CI screenshots
Every `ios-ui` CI run (on every push to `main`, and on PRs that touch `ios/`) uploads a `devpost-screenshots` artifact with `01-scan`, `01b-scan-finished`, `02-items`, `03-spending`, `03a-spending-top`, `03b-item-comps`, `04-review`, `05-approvals`, `06-desk-chair-deals`, `07-new-home`, `08-agents-safety` and `08b-review-impact` (PNG, 1206 × 2622, light mode). The artifact can also hold other PNGs. Ignore anything not on that list.

```sh
gh run list -R christianazinn/moove -b main -w CI -s success -L 5
gh run download <run-id> -R christianazinn/moove -n devpost-screenshots -D ~/Desktop/moove-devpost
```

- **Use a run from after #412 merges** (Lisa's UI batch), so the shots show the four tabs, voxel models for every item image, the binder Inventory (#353), the plain poster Listings, the four-way swipe Review deck (#395), the Agents receipts carousel and the one-page Move. Main runs often get cancelled when the next merge supersedes them, so the newest *green* run can be older than the newest commit. Check its date.
- The shots show the **starting state** (Agents · 2, no purchases yet), so 4 to 6 match the captions as is.
- Under XCUITest, the RealityKit `ARView` scenes that don't auto-turn (the scan finished page, the new home and Move's inline truck) come out **blank**. So images 2 and 7 are captured by hand, below. The Scan hero (1) renders fine.

## Capturing by hand (images 2, 7)
**Decision (Aiden's agent):** capture on the **Offline demo**: Settings (the gear at top right) > Backend > Data source **"Offline demo (fixtures)"**. The banner reads "Offline demo". It's the only data source whose rows are known in advance, and `DemoNumbersTests` checks its figures. It has the voxel dollhouse and the new home too, so nothing here needs the **Demo** backend.

> **⚠️ Don't approve or deny the Demo chair.** On the Demo backend (`moove-demo`, join code `4RZ9G8`), the seeded "Herman Miller Office Chair…" ($325) approval is **single-use** and meant for the judges. Capture everything on the Offline demo. If it does get used, ask Christian to run `npm run seed:demo -- --maincloud --reset-commerce` (#246).

**Honesty rule for captions:** every caption names what's simulated or fixture data. The only real payment in the Offline demo is the $0.01 Aeron comps row with the Basescan link.

- [ ] Offline demo selected, then **"Continue without an account"** on the login screen.
- [ ] **Relaunch** (force-quit and reopen) to reset the fixture.
- [ ] Do Not Disturb on, and Settings > **Appearance** > **Light** (to match the CI shots; the app's own setting overrides the system one, #352). The app uses one muted style on every tab.
- [ ] Simulator works for both: `xcrun simctl io booted screenshot ~/Desktop/moove-02.png`, or `xcrun simctl io booted recordVideo ~/Desktop/flyin.mov` (Ctrl-C to stop) for a GIF.

## The shots

### 1. Scan home: the turning voxel dollhouse
- **Source:** CI `01-scan`. For a GIF, record 3 to 4 s of the hero turning.
- **Screen:** Scan tab (first tab). No taps.
- **State:** "Scan a room.", the hero with the room's name under it, its furniture settling in layer by layer from above, then turning with the back walls full height and the front walls low, then **Scan a room** and **Load demo scan** below. The tab bar shows the four tabs (Scan, Items, Sell & Buy, Move), with the Sell & Buy badge at 2. Wait for the pieces to settle before the still (or start the GIF before they land).
- **Caption:** "Scan a room with LiDAR and Moove rebuilds it as a voxel dollhouse, every piece where it stood (our recorded demo bedroom)."
- **Track:** Spacetime (the scan imports through `import_scan_v2`), Best Planet-First Hack (the story starts here).
- **Live swap:** a real LiDAR scan's finished page on the Demo backend (same layout, no Demo tag) is better if one is ready. Change the caption to "a real scan".

### 2. Scan finished: the room as a dollhouse
- **Source:** by hand. Scan tab > **Load demo scan**.
- **State:** "12 items added", then the dollhouse: real walls with windows and a door, **back walls full height, near walls cut at 1.1 m**, items in their scanned spots and colors. Below it (no caption), the inventory, one line per item (name and value), starting with "Full size metal bed frame". Drag to turn it so two tall back walls frame the room before taking the shot.
- **Caption:** "The finished scan: real walls, doors and windows, tall at the back and cut low at the front, each piece colored from the scan's own frames (demo scan shown)."
- **Track:** Spacetime, Anthropic (the photo sweep runs next and names what the scanner couldn't).
- Loading the demo scan adds a second room, so **relaunch** before images 7 and 8.

### 3. Items > Review: keep, sell, donate, trash
- **Source:** CI `04-review`.
- **State:** the kg-kept-from-landfill strip on top, then the flip-card stack ("1 of 12") with the **Yamaha acoustic guitar** on top, badged **Needs you** (possibly sentimental). The card front is the item's voxel model (every item image is a voxel model now). Swipe right keeps, left sells, up donates, down trashes, with Undo. Then the top of the **Where it goes** board with a tile per pile.
- **Caption:** "Moove suggests keep, sell, donate or trash with a reason for each, and leaves possibly sentimental items like the guitar to you (fixture data)."
- **Track:** Anthropic (knowing where the model shouldn't decide), Best Planet-First Hack (donate and resell over trash).

### 4. Sell & Buy > Agents (receipts): the agent pays over x402
- **Source:** CI `03-spending`.
- **State:** the Agents screen scrolled down to its paper receipts in Courier (a sideways carousel, paged to receipt 2 of 3), scrolled to the Pricing agent receipt ("PRICING AGENT"): the line "Premium comps for "Herman Miller Aeron"", `x402`, "$0.01", **"TX 0xc794…136c"**, and below it lines with the filled **SIMULATED** mark and no link. CI also saves `03a-spending-top` (scrolled to the totals tape "TOTALS · YOUR AGENTS": **SPENT $0.01**, **SIMULATED $180.005**).
- **Caption:** "The pricing agent pays for its own comps, $0.01 USDC per lookup over x402: the Base Sepolia line is a real transaction, and every SIMULATED line is simulated."
- **Track:** Coinbase x402 (the headline image), Apify (the comps come from Apify's eBay sold and Marketplace actors), Spacetime (each payment is a `payment` row).
- Capture this on the Offline demo, whose rows are known in advance. (The hosted worker has CDP keys since Sat ~12:40 PM, but a joined phone's Agents receipts show only its own payments.)

### 5. Sell & Buy > Agents (top): a $410 listing waits for you
- **Source:** CI `05-approvals`.
- **State:** the Agents screen's top: **"Needs your OK"**: the Sell request "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition", **$410**, with the SIMULATED pill, and the Buy request for the "78" upholstered sofa, gray", $429.99 "from wayfair", with its own **SIMULATED** pill. (Agents no longer lists past decisions.)
- **Caption:** "Claude writes the listing, and anything over your $100 limit waits for your OK, by Auth0 push or in the app (the eBay post is simulated)."
- **Track:** Auth0 (approval over the limit; the in-app inbox is shown, and the same request goes out as a CIBA push on the hosted worker), Anthropic (the Claude-written listing).

### 6. Sell & Buy > Shopping > Desk chair: the scam is blocked
- **Source:** CI `06-desk-chair-deals` (Shopping is sorted by category: the Desk chair card is in the **Work & study** section, the scam also sits in **Blocked for your safety** at the bottom). Deal cards show price, title, store and seller.
- **State:** (reached from the Desk chair card, the hero's **See deals**, or the **Blocked for your safety** section) a big voxel picture of the desk chair, then three deals as product cards with voxel chairs (the Target chair has the **Best deal** ribbon and a filled **Choose**). The planted deal, on a red-bordered card with its price struck through, **"Herman Miller Aeron, brand new, $95, Zelle only, ship only"**, seller "Planted demo scam (not a real listing)", the **Sample** badge, **"Likely fraud · 0.85"**, the reasons "asks for payment by Zelle" and "shipping only, no meetup", and the red **"Blocked: likely fraud"** tag where Choose would be.
- **Caption:** "The buy agent screens every deal and refuses this planted Zelle-only "brand new" Aeron (fraud score 0.85); checkout runs in the Visa Acceptance sandbox (no real money), and the offline demo shown here simulates it."
- **Track:** Visa (fraud checks, trust and responsibility), Apify (deal search; fixture deals are labeled Sample).

### 7. Move: the fly-in
- **Source:** by hand, best as a **GIF** (3 to 6 s). On a fresh fixture first do the video's taps so bought pieces fly in too: Sell & Buy > Agents > **Approve** the Aeron; Shopping > Desk chair > **Choose** the Target "Mesh task chair with arms, black", then **Pay $79.99 to target** in the confirm ("SIMULATED: no real card is charged."); back on Shopping, **Approve** the sofa ($429.99) on its **Needs you** card. Then Move tab (one page, no segments) > the **"Demo house · 2 bed, 1 bath"** card at the top > **Use this home**. Wait for the fly-in, the camera's one slow orbit and "Welcome home"; tap **Rearrange** to replay.
- **State:** "New home", "Demo house · 2 bed, 1 bath", a small **Demo** tag on the 3D (offline demo items), the voxel house with the back walls tall, and the kept pieces flying from the scanned room (drawn beside the house) to their new spots, plus the bought ones ("8" memory foam mattress, Full", "78" upholstered sofa, gray"), then "Welcome home" over it. **Rearrange** under it (the layout saves itself). Further down: the 3D truck (tap to open, **Load the truck**) and the packing boxes (6 on the demo).
- **Caption:** "Everything you kept, plus what the buy agent bought, flies from its old spot into the new home, then "Welcome home" (demo house shown)."
- **Track:** Visa (bought items land in the new home), Best Planet-First Hack.

### 8. Sell & Buy > Agents: "Agents kept you safe"
- **Source:** CI `08-agents-safety` (Sell & Buy > Agents, scrolled to the card between "Needs your OK" and the receipts; it moved here from the removed Summary tab). By hand works too: after the taps in image 7 (don't relaunch), Sell & Buy > Agents, scroll to the card.
- **State:** **"Agents kept you safe"** (Simulated tag): "1 scam deal blocked · fraud score 0.85", the approvals line ("6 approvals asked · 1 approved · 2 denied · 2 waiting · 1 expired" in CI's starting state; "6 approvals asked · 3 approved · 2 denied · 1 expired" after the scripted taps), "Anything over $100 needs your OK", "1 sentimental item left for you", "Spent $0.025 of $10.00 data budget ($0.015 simulated)" and the card budget line ("Spent $179.99 of $1,500.00 card budget (simulated)" at the start, $689.97 after). If a second image is allowed, CI `08b-review-impact` (the kg kept out of landfill strip on Review) is a good partner.
- **Caption:** "Agents kept you safe: every guardrail that fired, from the blocked scam deal to spend against each budget; simulated money is tagged Simulated."
- **Track:** Coinbase and Visa (real and simulated spend kept apart), Auth0 (approvals counted); with `08b-review-impact`, Best Planet-First Hack.

## Upload tips
- **GIFs:** `ffmpeg -i flyin.mov -vf "fps=12,scale=600:-1:flags=lanczos" -loop 0 flyin.gif`, or Gifski or Kap. Keep them 3 to 6 s and under a few MB.
- **Devpost limits** (from memory, not verified, so check the upload form): JPG, PNG and GIF up to about 5 MB each, shown at 3:2. Phone shots are tall, so put each on a 3:2 canvas (Figma, Keynote or Preview) to avoid cropping.
- Upload in the order of the table above, and paste each caption into the image's caption field.
- **Other CI screenshots:** the `ios-ui-screenshots` artifact (same runs) has `MooveSmokeTests/*` and `CommerceUITests/*` PNGs, such as `6-desk-chair-paid` (the Target chair after **Choose**). To run locally: `cd ios && xcodegen && xcodebuild test -scheme Moove -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath /tmp/ui.xcresult`, then `xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path /tmp/ui-shots`.
