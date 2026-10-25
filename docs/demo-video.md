# Demo video: 2-minute script

The Devpost video, due with the submission **Sun Oct 25, 9:00 AM PT**. Lisa records it. About 280 spoken words at ~150 words a minute, so there's room to breathe. Record the screen per section, then read the voiceover over the cut. Trim screen time to fit, not the words.

**Honesty rule (Coinbase track, and everyone else):** only say what the screen shows. Simulated things are labeled SIMULATED in the app; keep those pills in frame. The Offline demo banner ("Offline demo: fixture data, nothing is synced") stays in frame on the offline takes.

**What's real vs. labeled** (from [`tracks.md`](tracks.md)): the scan, Claude vision / listings / floor plans, SpacetimeDB, fraud rules, x402 on Base Sepolia (the $0.01 Basescan tx), Visa checkout as an Authorize.net **sandbox** charge on the hosted worker (test card, no real money). Apify comps are **replays of real scrapes** (free credit used up until Nov 23). eBay posts are **simulated**. In the Offline demo take, prices, deals and payments are fixture data, and the checkout is simulated.

## Script

| Time | SCREEN (what to tap / show) | VOICEOVER |
|---|---|---|
| **0:00–0:07** Hook | Scan tab, the turning voxel dollhouse. | "Moving means touching every single thing you own. Moove handles it, starting with one scan." |
| **0:07–0:22** Scan | **Scan a room**, sweep slowly, **Done**, **Looks right: check photos**, **Add N items**. The finished voxel dollhouse in the scan's real wall, floor and object colors. Drag it a quarter turn. | "Scan your room with LiDAR. Moove rebuilds it as a voxel dollhouse, colored from your real walls, floor and furniture, and finds every item in it." |
| **0:22–0:42** Items | **Items > Inventory**: the binder, flip one tab (Sleep, Work & study…), voxel models on the shelves. Then **Review**: the kg-kept-from-landfill banner on top; the guitar card with **Needs you** and a heart, tap to flip, swipe right (KEEP). Swipe the next card left (SELL). | "Claude names each item, and the pricing agent prices it from sold listings. Review is a deck: right to keep, left to sell, up to donate, down to trash. The banner counts kilos kept out of landfill. Sentimental things, like this guitar, wait for you. Moove never decides them." |
| **0:42–1:05** Sell & Buy | **Sell & Buy > Listings**: the poster wall, a SIMULATED tag in frame. **Shopping**: deal cards (price, title, store, seller); scroll to the blocked Aeron, open **Desk chair**: "Likely fraud · 0.85", **Blocked: likely fraud**. Back, tap the floating cart. **Agents**: "Needs your OK", tap **Approve** on the $410 Aeron listing. | "What you sell becomes a listing. Posting to eBay is simulated today, and it says so. For the new place, the buy agent finds deals and screens each one for fraud. This Zelle-only 'brand new' Aeron is a scam we planted, so the agent won't buy it. Anything over your limit waits for your OK." |
| **1:05–1:20** Move | **Move**: **Paste a Zillow link** (or the **Demo house** card > **Use this home**). Let the fly-in play: kept furniture lifts out of the scanned room and lands in the new home. Scroll to the truck, tap **Load the truck**, then the box cards. | "Paste the new home's Zillow link. Everything you kept flies into a 3D model of it. Moove sizes the truck and plans the boxes." |
| **1:20–1:54** Sponsors | One proof per line (cut in as each sponsor is named):<br>1. **SpacetimeDB**: split screen of two phones in room `4RZ9G8`; move an item on A, B updates. Or the event log of agent steps.<br>2. **Claude**: an Inventory placard (name, brand, size) or a listing's written title.<br>3. **Apify**: an item's "Comparable listings" with eBay / Facebook sources.<br>4. **Coinbase x402**: **Agents** receipts, the $0.01 "Premium comps" row, tap **Basescan** (Safari shows the tx).<br>5. **Visa**: Shopping, the sofa over the limit, **Approve**, the checkout label.<br>6. **Auth0**: the "Needs your OK" card ("Also sent to your phone (Auth0 Guardian)."). | "Here's what's underneath. SpacetimeDB is the whole backend: both phones and every agent share live tables, and each agent step is a row. Claude identifies items, writes listings and reads floor plans. Apify scrapes eBay sold and Facebook Marketplace comps; today those are replays of real scrapes. With Coinbase x402, the pricing agent pays a cent in USDC on Base Sepolia for its own data, under a budget. That's the real Basescan transaction. Visa: checkout goes through the Visa Acceptance sandbox, only after the fraud check and your approval. In this take it's labeled simulated. And Auth0 async authorization sends big decisions to you for approval." |
| **1:54–2:00** Close | **Sell & Buy > Agents**, scroll to **Agents kept you safe** (scam blocked, approvals asked, sentimental item left to you). | "Moove runs your move. You stay in control." |

Spoken word count: about 285.

### Sponsor proof, at a glance

| Sponsor | What it does in Moove | On-screen proof |
|---|---|---|
| SpacetimeDB | The only backend. App and agents never talk directly; they share tables and reducers. Every agent step writes an `agent_event` row. | Two phones in sync on room `4RZ9G8` (fallback: the join-code screen) |
| Anthropic (Claude) | Vision names items from the scan photos; writes listings; reads floor-plan screenshots; drafts the shopping list | Inventory placard, listing title |
| Apify | eBay sold + Facebook Marketplace comps for pricing, deal search for buying (replays of real scrapes today) | "Comparable listings" with sources |
| Coinbase (x402 + CDP) | The pricing agent pays $0.01 USDC per premium comps lookup on Base Sepolia from a CDP wallet, with per-agent budget and per-call cap | The $0.01 receipt row and its Basescan link; the Refused row |
| Visa (Acceptance) | Checkout for card merchants via the Authorize.net sandbox (a Visa Acceptance product), after fraud screening and approval | Sofa approval and the checkout label (SIMULATED offline, VISA SANDBOX on the hosted worker) |
| Auth0 | Async authorization (CIBA) for listings and purchases over the limit: Guardian push to a signed-in owner, or the in-app inbox | "Needs your OK" card, **Approve** |

## Before recording
- [ ] **Device:** a LiDAR iPhone (or iPad Pro) on the latest `main` build, charged, Do Not Disturb on. Same appearance on every take (Settings > **Appearance**). A second phone only for the SpacetimeDB split screen.
- [ ] **Scan take (0:07–0:22):** live scan on the device (it runs on device on any backend). Don't tap **Load demo scan** first on Demo (it adds a "Demo bedroom" room).
- [ ] **Everything else: Offline demo.** Settings (gear) > Backend > Data source **Offline demo (fixtures)**. Force-quit and relaunch right before the take so approvals and totals are fresh, then record 0:22 through 2:00 in one take without relaunching. This is the only state with the real $0.01 Basescan row.
- [ ] **Two-phone shot (optional):** both phones on **Demo (moove-demo)**, Items > Inventory > **Join a room** > `4RZ9G8`. Check first: `cd agents && npm run status` shows `moove-demo` UP. Start both screen recordings and clap to sync.
- [ ] Hide old test rooms on each device: Items > Inventory > the room card > **⋯** > **Hide room**.
- [ ] Tap **Continue without an account** at login.
- [ ] Laptop: the Basescan tx open in a tab as a cutaway: https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c

## Fallbacks
- **Live scan misbehaves:** Scan tab > **Load demo scan** (tagged Demo scan). Change the scan line to "here's a scanned bedroom" and drop "colored from your real walls" (the demo scan has no camera colors).
- **Two-phone sync lags or fails** (not yet verified on two real devices): show one phone on the **Join a room** screen with `4RZ9G8` typed in, and say "your roommate joins with a code; SpacetimeDB keeps everyone on the same live tables." Don't claim sync you didn't show.
- **Zillow import needs the worker** (Claude reads the floor plan). Offline, use the **Demo house** card and say "Pick the new home."
- **Basescan link won't open:** cut to the laptop tab above and say "settled on Base Sepolia."
- **Over time:** cut the Listings poster wall and the truck/boxes, keep the sponsors segment whole.
