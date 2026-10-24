# Morning: Saturday, Oct 24

_Written overnight by Christian's agent from what's on `main`; refreshed until ~7:30 AM. Devpost is due **Sun 9:00 AM**._

## TL;DR
- **Everything you need to test is in one batch below.** Each person has about 15–30 minutes of device testing. Nothing needs a rebuild to switch backends: **Settings → Backend → Live / Demo**.
- Two backends are live on maincloud, each with its own auto-restarting worker and tunnel:
  - **Live `moove`**: real scans, junk included.
  - **Demo `moove-demo`**: a clean seeded Bedroom, **join code `4RZ9G8`**. Use it for judging.
- The app reads the worker's upload URL from the database (`service_config`, #126/#132), so tunnel restarts no longer need config changes.
- The whole backend pipeline passes end to end: `cd agents && npm run e2e -- --replay`, 19/19, also in CI.
- **Needs humans:** the decisions at the bottom (keys, Anthropic pitch community, Devpost text, demo video).

## Check the backends first (10 seconds)
```sh
cd agents && npm run status
```
Expected: `UP maincloud.spacetimedb.com/moove` and `UP …/moove-demo`, each with a worker version, `upload … healthy`, and recent agent events. If one is DOWN, tell Christian's agent (or run the commands in `docs/backends.md`).

## What changed overnight (high level)
- **Scan:** RoomPlan + a 127-class household detector (#98), auto photos, VoiceOver in the 3D room (#153), share/join a room (#78), RoomPlan attributes and scanned colors stored on items (#110/#117/#119/#121).
- **3D:** voxel models are the only 3D look (#108). Voxel dollhouse, lived-in rooms with real wall colors (#113/#124). The offline demo opens the dollhouse (#137). New 5-tab layout (#136). Bigger type (#134). Scan home hero (#152). Listing-link import for the new home (#112/#116).
- **Agents:**
  - Room photo sweep fixes "other" and finds missed items (#92).
  - Vision categories and names match the voxel builders (#111/#131).
  - Pricing: an Apify concurrency queue (#107), and collectible comps are filtered out (#114).
  - Listings for items without photos (#115).
  - Vision concurrency cap (#148).
- **Commerce:** hardening for idempotency, fraud gating, stale Visa holds and approval edge cases (#138/#143). A `[SIMULATED]` label on every simulated money step, and a planted scam deal the demo can show being blocked (#154). Bought items appear in the new-home layout (#125). Empty, error and loading states (#140).
- **Platform:**
  - Contract hardening: input limits and worker pins on both maincloud DBs (#146/#159).
  - `service_config` (#126).
  - Self-healing tunnel + worker (#142).
  - Claude record/replay (#118).
  - E2E test + CI job (#120/#133).
  - `npm run status` (#139).
- Full list: `gh pr list --state merged --search "merged:>=2026-10-24T07:30:00Z"`.

## The one test batch

### Rio: capture (LiDAR iPhone)
1. Pull `main`, then `cd ios && xcodegen`, build to the phone. Settings → Backend → **Live**. Settings shows the worker as online, with its version and start time (from `service_config`).
2. Scan a real room. **Expected:**
   - items appear in Items within seconds
   - each object's auto photo uploads (no "upload unreachable" warning)
   - vision renames items within about a minute (names carry color + shape words)
   - prices appear, then keep/sell/donate/trash
3. Room photo sweep (#92, #156/#178): **no extra step.** After **Add N items**, the app sends up to 4 wide frames from the scan by itself. **Expected:**
   - Items shows "Identifying items from room photos…" under the room for about 10–30 s.
   - Then "Unidentified item" / "other" boxes get real names, and missed things are added. Item detail says "Found by: Room photos (size estimated)", and those items aren't placed in the 3D room.
   - The Xcode console prints `[sweep] sent N of M room photos for scan <id>`.
   - Impossible boxes are skipped, and the finished page then says "N objects looked wrong and were skipped" (#180).
4. Share the room (Items → Share) and join it on a second phone. **Expected:** the same items stream in live, and edits sync both ways.
5. Report back, ideally on #28 or a new issue: objects in wrong places, wrong labels, sizes that look off. The worker now stores every scan's files, so the agents can inspect them.

### Lisa: new home / 3D
1. Settings → Backend → **Demo**, then Items → Join a room → **`4RZ9G8`**. **Expected:** the seeded Bedroom (bed frame, Micke desk, mesh chair, Kallax, mini fridge, TV, monitor, floor lamp, guitar) appears with prices and decisions.
2. Move tab: the voxel dollhouse renders every item as a recognizable model. Fly-in, layouts, and the truck/packing plan all work.
3. After Rio's real scan on Live: the scan → dollhouse hook shows the real room shape with items at their scanned spots.
4. Import a new home from a listing link (#89). **Expected:** an address from a Zillow/Redfin link, rooms from a floor-plan screenshot.

### Aiden: commerce
1. On **Demo**, Sell & Buy tab:
   - The mesh chair's listing is drafted (posted with the `[SIMULATED]` eBay label, or waiting in Approvals if above the threshold). Approve it in the inbox and check it posts.
2. Create the new home (Move tab), then the shopping list fills in, deals appear and fraud flags show (the planted scam deal is blocked, #154). Choose a card deal, approve it, and expect a **simulated** Visa payment in Spending.
3. Spending log: every x402 comps payment is listed (simulated, since there are no CDP keys on the worker).

### Christian: decisions + submission
See "Needs a human" below, then the Devpost draft (`docs/devpost.md`) and the demo video.

## Needs a human
1. **Keys (or keep simulated):** real CDP keys on the worker would make the x402 payments real Base Sepolia testnet transactions (Coinbase track). The same goes for eBay sandbox keys and Auth0 CIBA config. Everything is labeled simulated today. Put keys in the repo-root `.env.local`; the workers restart themselves when it changes.
2. **Anthropic pitch community:** still a TODO in `docs/devpost.md` (suggestions are there).
3. **Devpost text + demo video:** `docs/devpost.md` is a draft checked against `main`. Record the demo on the **Demo** backend.
   - Devpost gallery: capture the 8 screenshots/GIFs in [`docs/devpost-media.md`](devpost-media.md) (about 10 minutes on the Offline demo).
4. **Budget:** the Anthropic key was low last night. Overnight runs used recorded answers (`LLM_REPLAY`), but live scans call vision (up to 3 at a time), the sweep, listings and the shopping list. Check the balance before demo rehearsals.
5. **#41 part B step 2:** room/user tables go private once the app reads `my_room` / `my_user` (asked on #41). Until then, join codes and emails are readable by any client.

## Known issues
- `room`/`user` are world-readable until #41 step 2 (above).
- One agents unit test failed once under load overnight and passed on 4 reruns. Possibly a timing flake; rerun if CI is red with no code change.
- Live `moove` holds junk items from earlier scans (2 m "vacuum", 6 cm-deep "refrigerator"). Use **Demo** for anything judges see.
- Quick tunnels change URL when they restart. The app follows via `service_config`, but anything else (curl, docs) should read the URL from `npm run status`.

## Reference
`docs/backends.md` (backends, workers, reseeding) · `docs/demo.md` and `docs/demo-commerce.md` (demo runbooks) · `docs/data-model.md` (contract + input limits) · `agents/CLAUDE.md` (every agent) · `npm run e2e -- --replay` (pipeline test).
