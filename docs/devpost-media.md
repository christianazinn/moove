# Devpost media: the 8 gallery images

The 8 images for the Devpost gallery, in story order, one per step of the move and covering all five tabs (**Scan, Items, Sell & Buy, Move, Summary**). For each one: the file to use from CI's **`devpost-screenshots`** artifact (written by `ios/MooveUITests/DevpostShotsTests.swift`, #242) or "by hand" when CI can't render it, the screen and taps, the state, a one-line caption, and the sponsor track it supports ([`docs/tracks.md`](tracks.md)).

They match the [demo video](demo-video.md) and the commerce [video shot list](demo-commerce.md#video-shot-list-commerce-70-s), so the stills and the video show the same rows and figures. On-screen strings come from the Swift source and fixtures on `main` (`ios/MooveKit/Sources/MooveKit/Sync/DemoFixtures.swift`, `ShoppingFixtures.swift`, `ios/Moove/Features/*`).

## The gallery at a glance
| # | Upload as | Source | Tab | Caption |
|---|---|---|---|---|
| 1 | `01-scan.png` (or a GIF) | CI `01-scan` | Scan | Scan a room with LiDAR and Moove rebuilds it as a voxel dollhouse, every piece where it stood (our recorded demo bedroom). |
| 2 | `02-scan-dollhouse.png` | **by hand** (CI `01b-scan-finished` renders blank) | Scan | The finished scan: real walls, doors and windows, tall at the back and cut low at the front, each piece colored from the scan's own frames (demo scan shown). |
| 3 | `03-review.png` | CI `04-review` | Items | Moove suggests keep, sell, donate or trash with a reason for each, and leaves possibly sentimental items like the guitar to you (fixture data). |
| 4 | `04-spending.png` | CI `03-spending` | Sell & Buy | The pricing agent pays for its own comps, $0.01 USDC per lookup over x402: the Basescan row is a real Base Sepolia transaction, and every SIMULATED row is simulated. |
| 5 | `05-approvals.png` | CI `05-approvals` | Sell & Buy | Claude writes the listing, and anything over your $100 limit waits for your OK, by Auth0 push or in the app (the eBay post is simulated). |
| 6 | `06-scam-blocked.png` | CI `06-desk-chair-deals` | Sell & Buy | The buy agent screens every deal and refuses this planted Zelle-only "brand new" Aeron (fraud score 0.85); checkout runs on a labeled simulated Visa rail. |
| 7 | `07-new-home.gif` | **by hand** (CI `07-new-home` renders blank) | Move | Everything you kept, plus what the buy agent bought, flies from its old spot into the new home's 3D layout (demo house shown). |
| 8 | `08-summary-safe.png` | **by hand** (CI `08-summary` stops above the card) | Summary | The summary totals what you sold, spent and kept out of landfill, and shows every guardrail that fired; simulated money is tagged Simulated. |

**Extras** (not in the 8, useful for a track write-up or if Devpost allows more): CI `02-items` (Items > Inventory) and CI `03b-item-comps` (an item's price and its comparable listings). **Room shots** (by hand, see below): one furnished room on its own, to show the layouts look good, e.g. `09-room-bedroom.png` / `10-room-living.png`, caption "Each room of the new home, furnished with what you kept and bought (demo house shown)."

## Getting the CI screenshots
Every `ios-ui` CI run (on every push to `main`, and on PRs that touch `ios/`) uploads a `devpost-screenshots` artifact with `01-scan`, `01b-scan-finished`, `02-items`, `03-spending`, `03b-item-comps`, `04-review`, `05-approvals`, `06-desk-chair-deals`, `07-new-home` and `08-summary` (PNG, 1206 × 2622, light mode). The artifact can also hold other PNGs. Ignore anything not on that list.

```sh
gh run list -R christianazinn/moove -b main -w CI -s success -L 5
gh run download <run-id> -R christianazinn/moove -n devpost-screenshots -D ~/Desktop/moove-devpost
```

- **Use a run from after #280** (merged Sat 12:12 PM PT), so the hero has the tall back walls (#269, #280). Main runs often get cancelled when the next merge supersedes them, so the newest *green* run can be older than the newest commit. Check its date. The last green one before this doc was 40098106518 (Sat 6:25 AM PT, before the wall change).
- The shots show the **starting state** (Approvals · 2, no purchases yet), so 4 to 6 match the captions as is.
- Under XCUITest, the RealityKit dollhouses that don't auto-turn (the scan finished page and the new home) come out **blank**, and the Summary shot stops at "Where everything went". So images 2, 7 and 8 are captured by hand, below. The Scan hero (1) renders fine.

## Capturing by hand (images 2, 7, 8)
**Decision (Aiden's agent):** capture on the **Offline demo**: Settings (the gear at top right) > Backend > Data source **"Offline demo (fixtures)"**. The banner reads "Offline demo: fixture data, nothing is synced". It's the only data source whose rows are known in advance, and `DemoNumbersTests` checks its figures. It has the voxel dollhouse and the new home too, so nothing here needs the **Demo** backend.

> **⚠️ Don't approve or deny the Demo chair.** On the Demo backend (`moove-demo`, join code `4RZ9G8`), the seeded "Herman Miller Office Chair…" ($325) approval is **single-use** and meant for the judges. Capture everything on the Offline demo. If it does get used, ask Christian to run `npm run seed:demo -- --maincloud --reset-commerce` (#246).

**Honesty rule for captions:** every caption names what's simulated or fixture data. The only real payment in the Offline demo is the $0.01 Aeron comps row with the Basescan link.

- [ ] Offline demo selected, then **"Continue without an account"** on the login screen.
- [ ] **Relaunch** (force-quit and reopen) to reset the fixture.
- [ ] Do Not Disturb on, light mode (to match the CI shots).
- [ ] Simulator works for all three: `xcrun simctl io booted screenshot ~/Desktop/moove-02.png`, or `xcrun simctl io booted recordVideo ~/Desktop/flyin.mov` (Ctrl-C to stop) for a GIF.

## The shots

### 1. Scan home: the turning voxel dollhouse
- **Source:** CI `01-scan`. For a GIF, record 3 to 4 s of the hero turning.
- **Screen:** Scan tab (first tab). No taps.
- **State:** "01 — Scan", "Scan a room.", the hero with the **DEMO** tag and "Bedroom · 12 objects", the back walls full height and the front walls low as it turns, then **Scan a room** and **Load demo scan** below. The tab bar shows all five tabs, with the Sell & Buy badge at 2.
- **Caption:** "Scan a room with LiDAR and Moove rebuilds it as a voxel dollhouse, every piece where it stood (our recorded demo bedroom)."
- **Track:** Spacetime (the scan imports through `import_scan_v2`), Best Planet-First Hack (the story starts here).
- **Live swap:** a real LiDAR scan's finished page on the Demo backend (same layout, no Demo tag) is better if one is ready. Change the caption to "a real scan".

### 2. Scan finished: the room as a dollhouse
- **Source:** by hand. Scan tab > **Load demo scan**.
- **State:** "01 — Scan · Done", the **DEMO SCAN** tag, "12 items added", "A recorded bedroom, not a live scan. Offline demo: items, prices and colors are fixture data, as if the agents had run.", then the dollhouse: real walls with windows and a door, **back walls full height, near walls cut at 1.1 m**, items in their scanned spots and colors. Below it, "13 objects · 4.0 × 3.5 m", "1 placed by estimate", and the inventory starting with "Full size metal bed frame". Drag to turn it so two tall back walls frame the room before taking the shot.
- **Caption:** "The finished scan: real walls, doors and windows, tall at the back and cut low at the front, each piece colored from the scan's own frames (demo scan shown)."
- **Track:** Spacetime, Anthropic (the photo sweep runs next and names what the scanner couldn't).
- Loading the demo scan adds a second room, so **relaunch** before images 7 and 8.

### 3. Items > Review: keep, sell, donate, trash
- **Source:** CI `04-review`.
- **State:** "03 — Review", "Decide what goes.", the totals **Expected sales $500**, **Items to move 7**, **Need you 1** (red), the **"Needs you"** section with the **Yamaha acoustic guitar** ("Possibly sentimental") and "Moove never decides possibly sentimental items for you.", then the Keep rows with their reasons (for example, Full size metal bed frame: "Beds rarely resell (~$77); ~$59 to move: keep").
- **Caption:** "Moove suggests keep, sell, donate or trash with a reason for each, and leaves possibly sentimental items like the guitar to you (fixture data)."
- **Track:** Anthropic (knowing where the model shouldn't decide), Best Planet-First Hack (donate and resell over trash).

### 4. Sell & Buy > Spending: the agent pays over x402
- **Source:** CI `03-spending`.
- **State:** "Where the money went.", totals **Spent $0.01**, **Simulated $180.005** (orange), **Refused 1**, the row "$0.01", "Premium comps for "Herman Miller Aeron"", "Pricing agent · x402 · USDC", "Settled", **"Basescan 0xc794…136c"**, and below it rows with the filled **SIMULATED** pill and no Basescan link.
- **Caption:** "The pricing agent pays for its own comps, $0.01 USDC per lookup over x402: the Basescan row is a real Base Sepolia transaction, and every SIMULATED row is simulated."
- **Track:** Coinbase x402 (the headline image), Apify (the comps come from Apify's eBay sold and Marketplace actors), Spacetime (each payment is a `payment` row).
- Don't capture this on the Demo backend: its worker has no CDP keys, so there's no real row there.

### 5. Sell & Buy > Approvals: a $410 listing waits for you
- **Source:** CI `05-approvals`.
- **State:** "Your go-ahead.", **"Needs you · 2"**: the Sell request "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition", **$410**, with the Sell tag and SIMULATED pill; the Buy request for the "78" upholstered sofa, gray", $429.99 "from wayfair", with its own **SIMULATED** pill; and "Also sent to your phone via Auth0 Guardian when set up. Approving here works too." Further down, History includes the $699 KIVIK sofa with an **EXPIRED** pill ("No answer in 12 h. The agent asked again.").
- **Caption:** "Claude writes the listing, and anything over your $100 limit waits for your OK, by Auth0 push or in the app (the eBay post is simulated)."
- **Track:** Auth0 (approval over the limit; the in-app inbox is shown, the push isn't verified on a real tenant), Anthropic (the Claude-written listing).

### 6. Sell & Buy > Shopping > Desk chair: the scam is blocked
- **Source:** CI `06-desk-chair-deals`.
- **State:** three deals with voxel chairs. The planted deal **"Herman Miller Aeron, brand new, $95, Zelle only, ship only"**, seller "Planted demo scam (not a real listing)", the **Sample** badge, **"Likely fraud · 0.85"**, the reasons "asks for payment by Zelle" and "shipping only, no meetup", and the red **"Blocked: likely fraud"** tag where Choose would be.
- **Caption:** "The buy agent screens every deal and refuses this planted Zelle-only "brand new" Aeron (fraud score 0.85); checkout runs on a labeled simulated Visa rail."
- **Track:** Visa (fraud checks, trust and responsibility), Apify (deal search; fixture deals are labeled Sample).

### 7. Move > New Home: the fly-in
- **Source:** by hand, best as a **GIF** (3 to 6 s). On a fresh fixture first do the video's taps so bought pieces fly in too: Sell & Buy > Approvals > **Approve** the Aeron; Shopping > Desk chair > **Choose** the Target "Mesh task chair with arms, black"; back on Shopping, **Approve** the sofa ($429.99). Then Move tab > **New Home** > the **"Demo house · 2 bed, 1 bath"** card > **Use this home**, and tap **Fly in** to replay.
- **State:** "06 — New home", "Demo house · 2 bed, 1 bath", "6 rooms · 112 m²", the **DEMO HOUSE** tag, the voxel house with the back walls tall, and the kept pieces flying from the scanned room (drawn beside the house) to their new spots, plus the bought ones ("8" memory foam mattress, Full", "78" upholstered sofa, gray"). **Fly in** and **Save layout** under it.
- **Caption:** "Everything you kept, plus what the buy agent bought, flies from its old spot into the new home's 3D layout (demo house shown)."
- **Track:** Visa (bought items land in the new home), Best Planet-First Hack.

### 8. Summary: "Agents kept you safe"
- **Source:** by hand, after the taps in image 7 (don't relaunch in between). Summary tab, scrolled to the bottom so **Money** and the **"Agents kept you safe"** card are both visible.
- **State:** **Money** with the **Simulated** tag ("Visa purchases" tagged Simulated, "x402 data payments" tagged with its simulated share), then **"Agents kept you safe"** (Simulated tag): "1 scam deal blocked · fraud score 0.85", the approvals line ("6 approvals asked · 3 approved · 2 denied · 1 expired", "Anything over $100 needs your OK"), "1 sentimental item left for you", "Spent $0.025 of $10.00 data budget ($0.015 simulated)" and "Spent $689.97 of $1,500.00 card budget (simulated)". If a second image is allowed, CI `08-summary` (the top: Net, "Kept from landfill 49 kg", "Where everything went") is a good partner.
- **Caption:** "The summary totals what you sold, spent and kept out of landfill, and shows every guardrail that fired; simulated money is tagged Simulated."
- **Track:** Best Planet-First Hack, Coinbase and Visa (real and simulated spend kept apart), Auth0 (approvals counted).

### Room shots (extras)
- **Source:** by hand, after the taps in image 7. Move > **New Home**, scroll to **Room shots** under Layout: one card per furnished room (rendered a few seconds after the fly-in). Tap a card, then **Share** > **Save Image** (or AirDrop it to a Mac). The full-screen viewer swipes between rooms; **Orbit** to turn the room, **Use this angle** retakes the photo from there at full-screen resolution, which is the one to upload.
- The cards are ARView snapshots, so like image 7 they may be blank under XCUITest (`newhome.roomShot.<room>` identifiers exist for a future test, but capture these by hand).

## Upload tips
- **GIFs:** `ffmpeg -i flyin.mov -vf "fps=12,scale=600:-1:flags=lanczos" -loop 0 flyin.gif`, or Gifski or Kap. Keep them 3 to 6 s and under a few MB.
- **Devpost limits** (from memory, not verified, so check the upload form): JPG, PNG and GIF up to about 5 MB each, shown at 3:2. Phone shots are tall, so put each on a 3:2 canvas (Figma, Keynote or Preview) to avoid cropping.
- Upload in the order of the table above, and paste each caption into the image's caption field.
- **Other CI screenshots:** the `ios-ui-screenshots` artifact (same runs) has `MooveSmokeTests/*` and `CommerceUITests/*` PNGs, such as `6-desk-chair-paid` (the Target chair after **Choose**). To run locally: `cd ios && xcodegen && xcodebuild test -scheme Moove -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -resultBundlePath /tmp/ui.xcresult`, then `xcrun xcresulttool export attachments --path /tmp/ui.xcresult --output-path /tmp/ui-shots`.
