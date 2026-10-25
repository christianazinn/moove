# Morning: Saturday, Oct 24

_By Christian's agent, from what's on `main` (e856e51) and live on maincloud. Last checked **Sat 11:40 AM PDT**, later than planned: the 7:30 refresh slipped because my clock was off. Devpost is due **Sun 9:00 AM**._

## TL;DR
- **Rebuild the app from `main` first.** `room` and `user` became private tables overnight (#198), and builds from before #176 can't sync any more.
- **Everything to test is in one batch below.** It's about 15–30 minutes of device testing per person. You can switch backends without a rebuild: **Settings → Database → Live / Demo**.
- Two backends are live on maincloud, each with its own auto-restarting worker and Cloudflare tunnel:
  - **Live `moove`**: real scans, junk included.
  - **Demo `moove-demo`**: the clean seeded Bedroom, **join code `4RZ9G8`**. Use it for judging. It has 10 items, including a Herman Miller chair whose **$325 listing is awaiting approval**. Since #200 a joined phone can approve it. **This beat is single-use** (see Aiden's step 2).
- Backend pipeline: `cd agents && npm run e2e -- --replay` passes **22/22** (scan → pricing → sort → sweep → listing → approval → shopping → deals → fraud → purchase → sharing → privacy). It also runs in CI on every PR.
- Spending is capped in code: live Claude stops at **$3/day** and Apify at **$2/day**. Settings shows today's spend (#232).
- **Needs humans:** the decisions at the bottom (keys, the Anthropic pitch community, Devpost text, the demo video).

## Since 7 AM
- **Aiden is back as `AidenJeong8`** (the old `aidenyj` account was suspended, and he has push now). Work from the old account was rescued by lisa's agent: #263 (bigger object catalogue + voxel builders, from #141/#230) and #265 (commerce at the largest text size + dark mode). Nothing else is missing from `main`. Commerce has its owner back. Mention `@AidenJeong8`, not `@aidenyj`.
- Lisa's iPad scan feedback (#267): lisa's agent is fixing detector boxes (center, facing, duplicates), Inventory clarity (scan dates, Demo tag, origin chips), and sweep renames that respect the scanned size (#270, merged and live).
- Auth: an expired Auth0 ID token is renewed before connecting (#264).
- **Lisa's iPad retest** of today's scan, dollhouse, Inventory and Pack changes: [`docs/ipad-retest.md`](ipad-retest.md).

## Check the backends first (1 minute)
```sh
cd agents && npm run status                     # both backends
npm run smoke -- moove-demo 4RZ9G8              # what a judge's phone does
```
**Expected:**
- `status`: `UP maincloud.spacetimedb.com/moove` and `UP …/moove-demo`, each with a worker version, `upload … healthy`, and `0 errors in the last hour`.
- `smoke`: 6 PASS lines, then `all checks passed` (join by code, 10/10 priced and sorted, upload round trip through the tunnel, room/user private).

If either fails, tell Christian's agent on #2, or follow `docs/backends.md`.

## What changed overnight
About 90 PRs merged. Full list: `gh pr list --state merged --search "merged:>=2026-10-24T09:30:00Z" --limit 200`.
- **Scan (Rio):**
  - **Detection:** 127-class household detector with auto photos (#98). A per-category size sanity check runs before import (#182). The module skips impossible objects instead of rejecting the scan (#177), and the finished page says which objects were skipped (#180).
  - **Room photo sweep:** it runs by itself after the scan (#92, #156, #178). The offline demo plays it too (#205).
  - **Item status:** items show whether they're being identified, priced, or couldn't be priced (#193). Item detail says how an item was found (#209) and has **Add photo** (#240). Leftover boxes are labeled "Unidentified item" (#215).
  - **Connection:** the "Reconnecting" banner can't get stuck any more, and you can tap it to retry (#196). Uploads retry and follow a new tunnel URL (#233).
  - **Testing:** XCUITest smoke tests in CI (#161, #241).
- **3D / new home (Lisa):**
  - **Look:** voxel dollhouse, lived-in rooms, and a five-tab layout (#136). Bigger type (#134). Scan home hero (#152).
  - **Dollhouse:** the fly-in starts from each piece's scanned spot (#137). Photo-only items are placed around the scanned furniture (#184/#203). Voxel models for the detector's extra categories (#230, on Aiden's catalog branch). A render-budget test (#228).
  - **Accessibility:** accessibility and empty/error states on New Home, Pack and Summary (#179).
  - **Summary:** an **"Agents kept you safe"** card (#229).
- **Commerce (Aiden):**
  - **Labels and hardening:** `[SIMULATED]` on every simulated money step (#154). A planted scam deal that the demo shows being blocked (#154, #168). Restart hardening (#138/#143).
  - **Approvals:** stale approvals expire and are asked again (#186, #214, #231). Joined members see shared listings (#208) and **may approve listing approvals** (#200, #239). Purchases stay owner-only.
  - **Visa:** the checkout mode is announced (#191, #235, #238). Since ~1:50 PM checkout is a real Authorize.net **sandbox** charge (#302), so approvals say VISA SANDBOX.
  - **Buy agent:** deal search counts toward the Apify cap (#185, #210).
  - **Demo seed:** the Herman Miller chair (#194).
- **Backend / platform (Christian):**
  - **Privacy:** `room` / `user` are private and read through per-user views (#41, #176, #198). Contract input limits and pinned workers (#146/#159). Rate limits and a storage cap on the public upload port (#202).
  - **Spend caps:** daily Claude and Apify caps (#169, #170), published in `service_config.spend_today` (#220).
  - **Restarts:** after a worker restart, rows left at `running` are retried (#190).
  - **Tooling:** self-healing tunnel and worker (#142). `npm run status` (#139), `npm run smoke` (#213) and `npm run comps:audit` (#174). The e2e covers sharing, vision and privacy (#167, 22 stages).
  - **CI:** superseded runs are cancelled, and the macOS build runs only when `ios/` changed (#207).
  - **Contract:** the listing `posting` status (#144 part A, module side, #199), `expire_approval` (#186), and `visa_checkout` (#191).

## The one test batch
Everyone: pull `main`, then `cd ios && xcodegen`, then build to your phone.

### Rio: capture (LiDAR iPhone)
1. Go to Settings → Database → **Live**. **Expected:** Settings shows the worker online with its version and start time, plus **"AI today: $x of $3 · Price lookups: $y of $2"** (#232).
2. Scan a real room. **Expected:**
   - Items appear in Items within seconds, and each object's auto photo uploads with no "upload unreachable" warning.
   - Vision renames items within about a minute (names carry color and shape words).
   - Prices appear, then keep/sell/donate/trash.
   - Impossible boxes are dropped on the device (#182) or skipped by the module, and the finished page then says "N objects looked wrong and were skipped" (#180).
3. Room photo sweep (#92): **there's no extra step.** After **Add N items**, the app sends up to 4 wide frames by itself. **Expected:** "Identifying items from room photos…" for about 10–30 s. Then "Unidentified item" boxes get real names and missed things are added. Item detail says "Found by: Room photos (size estimated)".
4. Share the room (Items → Share), then join it on a second phone. **Expected:** the same items stream in live, and edits sync both ways.
5. Report anything wrong (placement, labels, sizes) on #28 or a new issue.

### Lisa: new home / 3D
1. Settings → Database → **Demo**, then Items → Join a room → **`4RZ9G8`**. **Expected:** the seeded Bedroom appears with prices and decisions: bed frame, Micke desk, mesh chair, Kallax, mini fridge, TV, monitor, floor lamp, guitar (sentimental, left to you) and the Herman Miller chair.
2. Move tab. **Expected:** the voxel dollhouse renders every item as a recognizable model, and the fly-in, layouts, Save layout and Pack all work.
3. Sell & Buy > Agents (the Summary tab was removed). **Expected:** the "Agents kept you safe" card under "Needs your OK"; Items > Review shows the kg kept out of landfill on top.
4. After Rio's real scan on Live: the dollhouse shows the real room shape with items at their scanned spots, and photo-only items are placed by estimate.
5. Import a new home from a listing link (#89). **Expected:** the address comes from a Zillow/Redfin link and the rooms from a floor-plan screenshot.

### Aiden: commerce
1. Open **Demo** (joined to `4RZ9G8`), then the Sell & Buy tab. **Expected:**
   - The mesh chair's listing is posted, labeled `[SIMULATED]` eBay.
   - **Approvals** lists the Herman Miller chair, $325, pending. Your phone is a room member, so Approve/Deny work (#200).
2. **Approving the chair uses up the demo beat.** To check it during testing, approve it, check that it posts, then re-arm it from a laptop: `cd agents && SPACETIME_URI=wss://maincloud.spacetimedb.com SPACETIME_DB_NAME=moove-demo npm run seed:demo -- --maincloud --reset-commerce --wait` (#246). That's one Claude call, and the join code stays the same. Otherwise, approve it only on stage.
3. Create the new home (Move tab). **Expected:**
   - The shopping list fills in, deals appear, and fraud flags show. The planted Zelle-only Aeron is blocked.
   - When you choose a card deal, the purchase approval says **VISA SANDBOX** (#238, #302). Approve it, and a sandbox Visa payment (hold, then capture, test card) appears in Spending.
4. Spending log: every x402 comps payment is listed. **Since ~12:40 PM the worker has CDP keys**, so new lookups are real Base Sepolia payments with a Basescan link. Older rows stay SIMULATED. A joined phone shows only its own payments, so scan something on Live to see a real row.

### Christian: decisions + submission
See "Needs a human" below, then the Devpost draft (`docs/devpost.md`) and the demo video.

## Needs a human
1. **Keys:** ✅ CDP keys are on the worker (12:40 PM): x402 is real on Base Sepolia, and the wallet holds 1.69 testnet USDC (`npm run x402:wallet -- --faucet` tops it up). ✅ Auth0 CIBA is configured (6:30 PM, tested live): approvals push to the owner's phone when they're signed in with Auth0. ✅ Visa runs in the Authorize.net sandbox. eBay sandbox keys are still missing, so listings are labeled simulated. Put keys in the repo-root `.env.local`; the workers restart themselves when it changes.
2. **Anthropic pitch community:** still a TODO in `docs/devpost.md` (suggestions are there).
3. **Devpost text, gallery and demo video:**
   - [`docs/devpost.md`](devpost.md) is ready to paste (checked against `main` Sat ~12:30 PM, through #284); its "How to submit" checklist covers screenshots, fields, video, team and tracks.
   - Gallery shots: [`docs/devpost-media.md`](devpost-media.md), about 10 minutes on the Offline demo.
   - Record the demo on the **Demo** backend.
   - Demo video: record from the timed script and shot list in [`docs/demo-video.md`](demo-video.md).
4. **Budget:** overnight work used recorded answers (`LLM_REPLAY`), with only a handful of live Claude calls (the chair listing draft, verification). Live scans call vision (up to 3 at a time), the sweep, listings and the shopping list. The worker refuses live Claude past `CLAUDE_MAX_USD_PER_DAY` (default $3), and Settings shows the running total. Check the real balance before rehearsals, and raise the cap in `.env.local` if it's healthy.
5. **Deferred decisions (fine to leave until after the demo):**
   - #144 part B: payment rows written before paying.
   - Each member still needs a verified Coinbase account for the x402 prize.
   - #200: a real `approval.decided_by` column. For now an `agent_event` records who decided.
   - `REQUIRE_AUTH0`: the connection gate is built but off, because the app still allows Guest.

## Known issues
- The agents unit test `approval agent: an approval tapped just before expiry` can fail under load and passes when rerun. Rerun CI if it's red with no code change.
- Live `moove` still holds junk items from earlier scans (a 2 m "vacuum", a 6 cm-deep "refrigerator"). Use **Demo** for anything judges see.
- Quick tunnels change URL when they restart. The app follows via `service_config`, but anything else (curl, docs) should get the URL from `npm run status`.
- #230 (voxel builders) reached `main` through #263.

## Reference
`docs/backends.md` (backends, one-command tests, reseeding) · `docs/demo.md` and `docs/demo-commerce.md` (demo runbooks) · `docs/data-model.md` (contract, views, input limits) · `docs/security.md` · `agents/CLAUDE.md` (every agent) · `npm run e2e -- --replay` (pipeline test).
