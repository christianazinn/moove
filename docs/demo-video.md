# Demo video: 2-minute script and shot list

The Devpost video, due with the submission **Sun 9:00 AM**. It's recorded in the morning, one shot at a time, and cut together. Every shot gives the timecode, the voice-over (VO), what's on screen, the state to record in, the sponsor track it hits, and a fallback.

It follows [`docs/demo.md`](demo.md) (the 2-minute script) and [`docs/demo-commerce.md`](demo-commerce.md) (commerce shots, exact fixture strings), with tracks from [`docs/tracks.md`](tracks.md). The stills in [`docs/devpost-media.md`](devpost-media.md) use the same screens.

**Honesty rule:** say "simulated" when the screen shows a simulated thing. Real today: the scan, Claude vision and listing copy, the Apify comps (replayed from real scrapes, since our free Apify credit is used up until Nov 23), SpacetimeDB sync, the fraud rules, x402 payments (the $0.01 Basescan row / `npm run x402:demo`, and new pricing lookups on the hosted worker, which has CDP keys since Sat ~12:40 PM), and Visa checkout on the hosted worker as a real Authorize.net **sandbox** charge (test card, no real money, labeled VISA SANDBOX). Simulated and labeled: the eBay post, and every payment in the Offline demo fixture except the $0.01 Basescan row, plus Live/Demo rows from before the hosted worker got its keys. Not shown working: the Auth0 Guardian push (the in-app inbox is shown) and two-phone sync on real devices (not yet tested).

## States
- **Demo**: Settings (gear, top right) > Backend > Data source "SpacetimeDB (live)" > Database "Demo (moove-demo)", then Items > Inventory > **Join a room** > `4RZ9G8` > **Join**. The seeded Bedroom: 9 priced items, the guitar flagged sentimental.
- **Offline demo**: Data source "Offline demo (fixtures)". Banner: "Offline demo: fixture data, nothing is synced". Strings and figures are fixed and checked by `DemoNumbersTests`.
- **Live scan**: a LiDAR iPhone or iPad Pro on Demo (or Offline demo for the scan only; the scan still runs on device).

Switching data source mid-take is untested, so record the Demo shots and the Offline demo shots as separate takes and relaunch the app after switching.

## Shots (≤ 2:00)

### 1. 0:00–0:15 Scan → voxel dollhouse
- **VO:** "Moving is mostly deciding what to do with your stuff. With Moove, you scan your room with the phone's LiDAR, and it rebuilds the room in 3D, every piece where it stood."
- **ON SCREEN:** Scan tab, the turning voxel dollhouse hero ("Scan a room."). Tap **Scan a room**, sweep a corner (the "Also found" chips, newest first, if the detector catches a bike, plant or guitar), **Done**, **Looks right: check photos** (auto photos marked Auto), **Add N items**. The finished page: "N items added", the voxel dollhouse with real walls, doors and windows, colored from the scan. Drag it a quarter turn: the back walls stand full height with curtains at the window tops, the near walls stay cut low, and they swap as the camera turns. Keep the "N placed by estimate" caption in frame (pieces without a scanned spot).
- **STATE:** Live scan, on Demo.
- **TRACK:** Spacetime (the scan imports through the `import_scan_v2` reducer). Sets up Anthropic (shot 2).
- **FALLBACK:** Offline demo, Scan tab > **Load demo scan**: the same finished page, tagged **Demo scan** ("Demo bedroom, not a live scan: items and prices are fixture data."). Change the VO's last line to "here's a recorded bedroom".

### 2. 0:15–0:27 Claude names what it sees
- **VO:** "Claude looks at the photos the scan already took, plus the LiDAR sizes, and names each item: brand, material, condition. It also catches things the scanner missed."
- **ON SCREEN:** **See inventory** > Items > Inventory, the museum: "Identifying items from room photos…", then names filling in on the exhibits, grouped into halls by function ("The Sleep Hall", "The Work & Study Hall"…), each a voxel model on a plinth with a short placard (name, brand · size, a one-line story, price). Each placard's chip says where it came from: **Scanned** (LiDAR box) or **From photos** (the sweep found it). Tap the room's card in the Rooms strip to focus on just this scan ("Showing 1 of N rooms").
- **STATE:** Live scan on Demo (vision and the photo sweep need the worker and photos; each costs Claude calls).
- **TRACK:** Anthropic (vision + room photo sweep).
- **FALLBACK:** Offline demo after **Load demo scan**: the offline demo plays the sweep (a potted monstera appears). Then the names are fixture data, so cut "Claude names" to "Moove names" or say it's sample data.

### 3. 0:27–0:39 Real comps from Apify
- **VO:** "Then the pricing agent pulls what similar things actually sold for, eBay sold listings and Facebook Marketplace, scraped with Apify, and prices each item from the median."
- **ON SCREEN:** Items > Review > tap the **Sell** tile > **Mesh office chair** (or the **Keep** tile > **IKEA Micke desk**): the estimate and "Comparable listings" with their sources.
- **STATE:** Demo `4RZ9G8` (the seeded items price from committed real Apify scrapes, replayed and labeled `[REPLAYED]` in the event log).
- **TRACK:** Apify.
- **FALLBACK:** Offline demo, Items > Review > **Sell** tile > **Office chair** ($420, three comps). These are fixture comps: change the VO to "comps like these come from Apify's eBay-sold and Marketplace actors".

### 4. 0:39–0:51 Sort, and two phones in sync
- **VO:** "It suggests keep, sell, donate or trash, with a reason. It never decides sentimental things, like this guitar. Your roommate joins with a code, and SpacetimeDB keeps both phones in sync live."
- **ON SCREEN:** Items > Review: the top flip card, the Yamaha acoustic guitar, badged **Needs you** with a heart (possibly sentimental). Tap it to flip it over (value, condition, the sentimental note), then swipe right: the KEEP stamp, and the next card comes up ("2 of 12", Moove's call for it, e.g. "Moove says: Sell · …"). Then the **Where it goes** board: on phone A, tap the **Keep** tile (its list opens) and use a row's ⇄ menu to move **Floor lamp** to **Sell**; phone B's Sell tile count and total change at the same moment. Split screen in the edit.
- **STATE:** Demo `4RZ9G8`, **two devices** both joined to the room.
- **TRACK:** Spacetime (two-phone sync, live shared state). Anthropic (knowing where the model shouldn't decide).
- **FALLBACK:** Two-phone sync is **not yet tested on real devices**. If it lags or fails: one device only. Show the guitar, then Items > Inventory > **Join a room** with `4RZ9G8` typed in (the share icon on a room header only shows for rooms you own, not the joined seeded Bedroom). VO: "a roommate joins with a code like this". Don't claim the live sync you didn't show.

### 5. 0:51–1:04 The agent pays for its own data (x402)
- **VO:** "When the pricing agent needs premium data, it pays for it itself: one cent of USDC over x402 on Base Sepolia, from a Coinbase server wallet. This Basescan link is the real transaction. Rows tagged Simulated are simulated, and a request over the per-call cap was refused before anything was signed."
- **ON SCREEN:** Sell & Buy > **Agents**, scrolled down to the receipts (swipe sideways between them; the Pricing agent receipt is 2 of 3). Totals **Spent $0.01**, **Simulated $180.005**, **Refused 1**. The $0.01 "Premium comps for "Herman Miller Aeron"" row, tap **Basescan 0xc794…136c** (Safari shows the tx). Scroll to the red **Refused** $0.25 row, "Nothing was signed or paid."
- **STATE:** Offline demo (the only state with the real payment's row; on Demo every x402 row is simulated with no Basescan link).
- **TRACK:** Coinbase x402 (spending log, budget + per-call cap). Spacetime (every payment is a row).
- **FALLBACK:** Laptop cutaway: `npm run x402:demo -- "Herman Miller Aeron"` in `agents/`, then the `On-chain:` link (a real 0.01 testnet USDC payment; its comps are canned fixture data, so don't call the data live). If the wallet is empty: open the proof tx https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c and say "settled earlier".

### 6. 1:04–1:15 Big decisions come to you (Auth0)
- **VO:** "Claude writes the listing, and anything over your $100 limit waits for your OK, by an Auth0 push or right here. Once approved it posts. The eBay post is simulated today, and it says so."
- **ON SCREEN:** Sell & Buy > **Agents · 2**, the top of the screen. "Needs your OK · 2", the Sell request "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition" **$410** with the SIMULATED pill, "Also sent to your phone via Auth0 Guardian when set up. Approving here works too." Tap **Approve**: it moves to Decided, "You approved it. The listing agent posts it." Optional flash of Sell & Buy > **Listings**, the poster wall: the Aeron poster now stamped **POSTED** with its SIMULATED pill and "eBay · simulated" tear-off tabs (never LIVE, since the post is simulated).
- **STATE:** Offline demo, fresh launch (continue in the same take through shot 11, don't relaunch).
- **TRACK:** Auth0 (approval above the threshold). Anthropic (Claude-written listing).
- **FALLBACK:** Demo with the seeded commerce chair (`SEED_COMMERCE=1`; re-arm with `npm run seed:demo -- --maincloud --reset-commerce`), approved from the joined phone (needs the #200 member-approval module on `moove-demo`). Never say "you just got a push".

### 7. 1:15–1:28 The fraud screen blocks a scam (Visa trust)
- **VO:** "For the new place, the buy agent shops deals and screens every one for fraud. This Zelle-only 'brand new' Aeron is a scam we planted for the demo. It scores 0.85, and the agent won't buy it. The $79 chair checks out after you confirm. In this offline take that checkout is simulated."
- **ON SCREEN:** Sell & Buy > **Shopping**, the storefront: the hero ("Your new place still needs 4 things", the Desk chair's -65% saving) and the category chips; flick to the bottom for the **Blocked for your safety** section with the struck-through Aeron. Tap **See deals** (or the Desk chair card in **Work & study**) > **Desk chair**. "Herman Miller Aeron, brand new, $95, Zelle only, ship only", seller "Planted demo scam (not a real listing)", **"Likely fraud · 0.85"**, "asks for payment by Zelle", "shipping only, no meetup", red **"Blocked: likely fraud"**. Tap **Choose** on the Target "Mesh task chair with arms, black" ($79.99): the confirm "Buy this for $79.99?" with "SIMULATED: no real card is charged."; tap **Pay $79.99 to target**: "Paid through the simulated Visa rail. No real card was charged."
- **STATE:** Offline demo (same take). The 0.85 is a fixture value; the real fraud rules give the same planted deal 0.85 live.
- **TRACK:** Visa (fraud check, trust and responsibility). Apify (deal search; fixture deals carry a Sample badge).
- **FALLBACK:** If the screen misbehaves, relaunch and redo shots 6–7. Fraud screening is rules, not Claude, so don't credit Claude here.

### 8. 1:28–1:36 Over the limit, it asks before paying
- **VO:** "Over your limit, it asks first and pays with Visa only after you approve. On our hosted worker that's a real Visa Acceptance sandbox charge, test card, no real money. In this offline take it's a labeled simulation."
- **ON SCREEN:** Back on Shopping, the **Needs you · 1** card under the hero: "78" upholstered sofa, gray", "$429.99 from wayfair", "Over your approval limit. The agent pays with Visa only after you approve." Tap **Approve**.
- **STATE:** Offline demo (same take).
- **TRACK:** Visa (approval before checkout). Auth0.
- **FALLBACK:** Cut this shot if over time (it buys 8 s); shots 9–11 still work (only the Agents figures change).

### 9. 1:36–1:48 Everything flies into the new home
- **VO:** "Paste the new place's listing link, and Moove builds the floor plan. Everything you kept flies from where it stood into the new home, with what the agent bought."
- **ON SCREEN:** Move (one page, no segments) > **Paste a Zillow link** (top of the picker; Zillow, Redfin or Realtor.com): paste a link, add a floor-plan screenshot, **Build floor plan**, **Use this home**. (With a home already chosen, tap **Change home** next to the title.) The room chip under the title picks which scans move (the newest of each room by default). After "Arranging your home…", the fly-in: pieces lift from the scanned room drawn beside the house, arc over the walls and land in a designer layout (furniture grouped by what each room is for, walkways kept clear). Tap **Rearrange** to replay.
- **STATE:** Offline demo (same take) for the house; the import needs the worker (Claude reads the floor-plan screenshot), so record the import part on Demo and cut it in.
- **TRACK:** Anthropic (floor plan from screenshots). Visa (bought items land in the layout).
- **FALLBACK:** The **Demo house** card > **Use this home**, and drop the first sentence of the VO. With no worker reachable, the import builds an estimate from beds, baths and square feet (labeled Estimated); say "estimated".

### 10. 1:48–1:54 Pack: boxes by room, loaded into the truck
- **VO:** "It plans the packing too: fewer, fuller boxes by room, each with a reason, loaded into the truck in order."
- **ON SCREEN:** same Move page, scroll down to **Getting there**: the loaded voxel truck sits right on the truck card; tap **Load the truck** and the pieces arc in, in load order. Keep scrolling: the grid of kraft box cards under small room headings (9 boxes on the demo); tap one for its reasons (e.g. "Fragile: wrapped, nothing heavy, under 8 kg"). Optional if time: **Print labels** > **4 × 6 in labels** (PDF preview: room band, big number, QR code).
- **STATE:** Offline demo (same take, after shot 9).
- **TRACK:** None directly (product depth). The truck and crew figures are estimates and the card says so. On the offline demo the card says "Fits a cargo van by volume; packs best in a 10 ft truck." and the 3D truck is the 10 ft one, so say "truck", not a size. The inline truck is an ARView: record it on a device or Simulator, not from CI.
- **FALLBACK:** Cut this shot and give shot 11 its six seconds back.

### 11. 1:54–2:00 Agents: agents kept you safe
- **VO:** "Moove shows every guardrail that fired, real and simulated. Moove runs your move, and you stay in control."
- **ON SCREEN:** Sell & Buy > **Agents**, scrolled to **Agents kept you safe** (between "Needs your OK" and "Decided"; the tab is Simulated-tagged): "1 scam deal blocked · fraud score 0.85", the approvals line, "1 sentimental item left for you", spend against the data and card budgets with Sim tags.
- **STATE:** Offline demo (same take, after shots 6–10).
- **TRACK:** All of them in one card. Visa trust, Coinbase spend caps, Auth0 approvals.
- **FALLBACK:** If a figure looks off, hold on Agents kept you safe only (the VO names no numbers).

## Before recording
- [ ] **Devices:** a LiDAR iPad Pro or iPhone for shot 1, a second phone for shot 4, both on the latest `main` build, charged.
- [ ] **Backend:** `cd agents && npm run status` shows `moove-demo` UP (worker online, uploads healthy). Check the Claude/Apify daily caps aren't used up (`docs/demo.md`, "Before the demo").
- [ ] **Hide old test rooms** on every device, on Demo and Live: Items > Inventory > the room's card in the Rooms strip > **⋯** > **Hide room**. It's local to the device and deletes nothing; **Show hidden rooms (N)** at the bottom brings them back. Hidden rooms also stay out of the Scan hero, Review's kg-kept banner, New Home and Pack.
- [ ] **Seeded room:** both devices on Demo and joined to `4RZ9G8`, the Bedroom visible with prices. For the Demo approval fallback in shot 6, ask Christian to run `--reset-commerce`.
- [ ] **Do Not Disturb** on every device and the laptop (no Guardian, Slack or message banners).
- [ ] **Screen recording** in Control Center on each device; laptop browser tab with the Basescan proof tx loaded.
- [ ] **Reset data:** force-quit and relaunch before the Offline demo take (resets "Agents · 2" and the totals). Don't run **Load demo scan** on Demo before shot 1 (it adds a "Demo bedroom" room that then shows in the hero and the room list).
- [ ] Tap **"Continue without an account"** at login unless you're showing sign-in.

## Recording tips
- Record each shot separately, with a second of stillness at each end. Cut in the edit.
- Use the built-in iOS/iPadOS screen recording (Control Center) and export the edit at 60 fps so the dollhouse turn and fly-in stay smooth. Same orientation and appearance on every shot: set it in the app, Settings > **Appearance** (System / Light / Dark), on every device.
- Record the VO separately, after the cut, reading the lines above. Trim screen time to fit, not the words.
- Shot 4: start both devices' screen recordings, then clap or tap at the same time to sync the split screen.
- Move slowly while scanning (RoomPlan needs it), and let the fly-in finish before cutting. Turn the dollhouse slowly in shot 1 so the wall swap reads.
- Keep the SIMULATED pills and Demo tags in frame; don't crop them out.
