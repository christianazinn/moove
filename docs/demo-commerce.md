# Demo runbook: commerce segment

The commerce part of the Sunday live demo (judging Sun 10:30, live demo plus a 2-minute pitch). It covers agents paying over x402, the spending log, listing approval, the buy agent, Visa checkout and the summary.

Read the "Today's reality" box first. Before the demo, check any PR still marked open with `gh pr view <N> --json state`.

> **Today's reality (origin/main, Sun morning):**
> - **The phone can show live worker data now** (#28 merged). `ios/Moove/Sync/SpacetimeBackend+Contract.swift` subscribes to all 14 tables for the signed-in identity, including `payment`, `agent_event`, `listing`, `approval`, `shopping_item` and `deal`, and every reducer the app calls is wired (`register_user` with the Auth0 sub, `import_scan_v2`, `decide_approval`, `choose_deal`, `add_shopping_item`, `remove_shopping_item`, ...). Nothing throws "waiting on the SpacetimeDB module" any more. The app's default data source is now **SpacetimeDB (live)** against maincloud.
> - **The live commerce flow is unverified on device.** The worker side is covered end to end by `npm run e2e` (below), but nobody has run Spending, Approvals and Shopping on a phone against the maincloud worker yet. So the plan is: one live dry run at 10:00, and **Offline demo** (fixture data) as the fallback for every phone step. The tap-by-tap steps below describe the Offline demo fixture, whose strings are checked against the code.
> - **The fraud agent runs in the worker** (#64, closes #18). Every new deal gets a fraud score and reasons a moment after it is written (`FRAUD_SETTLE_MS`, 1.5 s). The buy agent never buys a deal scored 0.7 or more.
> - **Every demo shopping item has a committed live deal replay** (16 files, `agents/fixtures/deals-live-*.json`, 3+ real listings each, enforced by `agents/test/deals-apify.test.ts`).
> - **Live proof comes from the laptop:** terminal output from `npm run x402:demo` or the worker, and the basescan tx page. `npm run e2e` is the no-spend rehearsal of the whole worker pipeline.
> - **Five tabs since #136** (proposal #129): Scan · Items · Sell & Buy · Move · Summary. The commerce screens are the **Sell & Buy** tab's segments, in this order: Listings (the default), Shopping, Approvals (reads "Approvals · N" while requests are pending) and Spending. The Sell & Buy tab icon carries the pending-approvals badge. Review and Inventory are under Items, New Home and Pack under Move.
> - **Commerce screens polished in #140:** one filled SIMULATED pill everywhere, "Posted (simulated)" instead of "Live on eBay", a reason on every failed or denied row, voxel thumbnails in Shopping, and a fuller Offline demo fixture (a "Not posted" listing group, an Area rug with a declined checkout, 2 pending approvals and 3 in History). Every commerce screen also has a "Connecting…" and a "Can't reach the backend" state instead of a blank list.
> - Still open: #10 (two-phone room sharing, draft PR #78), #125 (bought items in the new-home layout, draft), #123 (docs). Merged since Saturday:
>   - #28: scan + live sync (all tables, all reducers)
>   - #58: CIBA poll fails closed without a matching id_token
>   - #64: fraud screen for deals (+ optional Pangram AI-text hook)
>   - #74 and #79: live deal replays for every demo shopping item
>   - #75: the demo runs `VISA_PROVIDER=simulated`
>   - #118: `LLM_REPLAY` record/replay for Claude calls
>   - #120: `npm run e2e` + the CI `e2e` job
>   - #122/#126: the worker announces its upload URL in the `service_config` table
> - Merged earlier: #40 (buy agent, Visa checkout, Shopping tab, live Apify deals from #52), #46 (pricing pays over x402), #55 (paywall start failure falls back to unpaid Apify), #38 (security pass, seeded budgets, payee allowlist), #63 (Herman Miller comps replay), #25 (login), #53 (amount-first push text), #36 (spending log), #31 and #67 (summary), #51 (worker survives rejected reducer calls).

## Setup at the table
- **Laptop A (Christian's):** the only worker against maincloud. One terminal running the worker, one free terminal in `agents/`.
- **Phone:** Moove dev build. Live (the default) if the 10:00 dry run worked, otherwise Offline demo (see the checklist).
- **Browser tab:** the basescan proof link below, already loaded.

## Pre-demo checklist
Do this by 10:00.

Wallet and keys
- [ ] `cd agents && npm ci`
- [ ] `npm run x402:wallet` prints the agent wallet (`0x3224220E5007e8F4c0440447bdfeb846c96f8A52` per `docs/coinbase-x402.md`) and a USDC balance. Each real call costs 0.01 USDC, so any balance above about 0.10 covers the demo plus rehearsals.
- [ ] If it's empty: `npm run x402:wallet -- --faucet`, wait about 10 s, run `npm run x402:wallet` again.
- [ ] `npm run x402:demo` once as a rehearsal. It should end with an `On-chain: https://sepolia.basescan.org/tx/...` line. If it prints "UNPAYWALLED, simulated mode", the CDP keys aren't loaded.

Pipeline rehearsal (no spend)
- [ ] In one terminal `spacetime start` (a **local** server on :3000). In `agents/`: `npm run e2e`. It publishes the module to a fresh local `moove-e2e` database, starts its own worker on spare ports (8790, 8412), drives the app's reducers as a normal user and prints a PASS/FAIL table: scan, pricing over x402, sort, sweep, listing + approval (simulated eBay), new home, shopping list, deals + fraud, purchase + approval (simulated Visa). Expect lines like `44 deals, 3 flagged >= 0.3` and `payment settled, simulated: true` (that's the latest CI run on main). It exits non-zero on any FAIL.
- [ ] Why no flags: since #133 and #157 `npm run e2e` is safe by default, even with `.env.local` loaded. Claude runs in replay mode (`LLM_REPLAY=replay`: recorded answers from `agents/fixtures/llm`, and a miss fails instead of calling the API), x402 is simulated (`X402_SIMULATE=1`, so CDP keys never sign Base Sepolia payments), Visa is always `simulated`, and the Apify, fal, Pangram, eBay and Auth0 CIBA keys are blanked (listings use the simulated eBay, approvals are decided in-app by the test). Opt-ins: `E2E_REAL_X402=1` for real testnet payments (the commerce stages then fail, since they assert simulated rows), and `E2E_LLM=auto|record` or `--live` for live Claude calls. The table header prints the modes that ran. It refuses any non-local `E2E_URI`, so it can't touch maincloud.

Required env vars (names only; values live in the repo-root `.env.local`, which `agents/scripts/env.ts` and `agents/src/config.ts` load)
- [ ] x402: `CDP_API_KEY_ID`, `CDP_API_KEY_SECRET`, `CDP_WALLET_SECRET`. Optional, with code defaults: `AGENT_SPEND_CAP_USDC` (default 5), `X402_MAX_PER_CALL_USDC` (default 0.10). Leave `X402_SIMULATE` empty for real payments.
- [ ] Worker: `SPACETIME_URI=wss://maincloud.spacetimedb.com`, `SPACETIME_DB_NAME=moove`, `SPACETIME_WORKER_TOKEN_FILE=.worker-token.maincloud`, `ANTHROPIC_API_KEY`, `APIFY_TOKEN`, `UPLOAD_PORT`, `PUBLIC_UPLOAD_BASE_URL`.
- [ ] Approvals: `AUTH0_DOMAIN`, `AUTH0_CIBA_CLIENT_ID`, `AUTH0_CIBA_CLIENT_SECRET`. `APPROVAL_SIM_AUTO_APPROVE_SEC` no longer does anything (the worker logs that it is ignored; it can't approve its own requests since #42). `APPROVAL_THRESHOLD_CENTS_DEFAULT` defaults to 10000 ($100).
- [ ] eBay (real sandbox posting only; otherwise listings are simulated and labeled): `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_RUNAME`, `EBAY_REFRESH_TOKEN`, `EBAY_FULFILLMENT_POLICY_ID`, `EBAY_PAYMENT_POLICY_ID`, `EBAY_RETURN_POLICY_ID`, `EBAY_LOCATION_KEY`, plus optional `EBAY_FALLBACK_IMAGE_URL`.
- [ ] Pricing pays over x402: `X402_PORT` (default 8402), `PRICING_PAY_X402` (on unless set to `0`/`false`/`off`). Merged in #46.
- [ ] Visa and buy agent (merged, #40):
  - **Set `VISA_PROVIDER=simulated` for the demo** (on the worker's command line or in the worker's env). The demo checkout is the labeled simulation; we are not attempting live sandbox charges. Don't leave it empty: with the CyberSource keys present in `.env.local`, an empty `VISA_PROVIDER` picks the `acceptance` backend from the keys, so every purchase would still call the sandbox (and only fall back to simulated after its 502). Don't set `VISA_PROVIDER=acceptance` either: every checkout would fail (retried 3 times, then given up).
  - With no provider and no `VISA_ACCEPTANCE_*` keys, checkout is simulated and labeled.
  - Defaults: `VISA_SPEND_CAP_USD` 1500, `VISA_MAX_PER_PURCHASE_USD` 750, `VISA_SIM_DELAY_MS` 400, `BUY_AUTO_CHOOSE` 0 (the user chooses), `BUY_FRAUD_BLOCK` 0.7, `BUY_RETRY_DELAY_MS` 60000. A non-numeric or negative cap logs a `[caps] WARNING` at startup and uses the default.
  - Deals: `DEALS_SOURCE` (default `apify`), `DEALS_APIFY_SOURCES` (default `fb,ebay`), `DEALS_SEARCH_CONCURRENCY` (2), `DEALS_PER_SOURCE` (6), optional `DEALS_HOME_LAT` / `DEALS_HOME_LNG`. Deal search reuses `APIFY_TOKEN` (about $0.10 of Apify per item searched live, per the note in `deals-apify.ts`).
  - Fraud (#64): `FRAUD_SETTLE_MS` (1500). Optional `PANGRAM_URL` / `PANGRAM_TOKEN` turn on the AI-text signal; without them it is off and deals keep `ai_text_score = -1`.

Worker
- [ ] **Only one worker against maincloud**, on Christian's machine, with the token in `agents/.worker-token.maincloud`. Nobody else runs `npm start` / `npm run dev` with maincloud settings.
- [ ] Start it from `agents/`: `VISA_PROVIDER=simulated npm start` (with the maincloud vars above). Expect `[spacetime] connected as ...`, `[agents] cache ready: N items`, `[agents] started vision`, `pricing`, `[service] announced upload_base_url=... version=...`, then `[agents] started vision`, `sweep`, `pricing`, `sort`, `listing`, `approval`, `shopping-list`, `buy`, `fraud` and `sam3d` (`agents/src/index.ts`), and `[visa] checkout ready (SIMULATED)` once the first checkout runs.
- [ ] Don't run `npm run x402:e2e` against maincloud. It connects as a worker and is meant for a local `spacetime start` + `npm run publish:local`. `npm run x402:demo` is fine anywhere because it doesn't touch SpacetimeDB. `npm run e2e` only runs against a local server.

Budgets
- [ ] **Budgets survive a restart** (merged, #38). With `X402_SEED_BUDGETS=1` (the default) the worker counts the last 24 h of x402 `payment` rows against each agent's $5 budget at startup (`agents/src/payments.ts`), so a restart does not hand out a fresh budget.
- [ ] **Budget reset after rehearsals:** start the demo worker with `VISA_PROVIDER=simulated X402_SEED_BUDGETS=0 VISA_SEED_BUDGETS=0 npm start`. Every agent then starts at $0 of $5 (x402) and $0 of $1,500 (card). Card seeding only counts non-simulated (sandbox or real) card payments from the last 24 h, so simulated rehearsals never use up the card cap anyway.
- [ ] `X402_ALLOWED_PAYEES` (merged, #38) is an optional comma-separated `payTo` allowlist. If you set it, include the comps paywall receiver `0x6644b110FD0B1671599E36db749d09b1EAeEF952`, or every pricing payment is refused.

Photos for eBay (only for a real sandbox post)
- [ ] eBay needs public **https** photo URLs. Uploads are served at `PUBLIC_UPLOAD_BASE_URL/files/<name>` on `UPLOAD_PORT` (8787). `agents/src/integrations/ebay.ts` throws "eBay needs at least one public https photo URL: set PUBLIC_UPLOAD_BASE_URL to an https tunnel, or EBAY_FALLBACK_IMAGE_URL". So either point `PUBLIC_UPLOAD_BASE_URL` at an https tunnel to port 8787 (the repo doesn't pick a tunnel tool) or set `EBAY_FALLBACK_IMAGE_URL`. Without eBay keys, the listing is simulated and needs no tunnel.
- [ ] **The tunnel URL changes** whenever the tunnel restarts, so don't copy one from this file. The current one is in the latest comments on issue #2 (`gh issue view 2 --comments`). The worker also writes it to the public `service_config` table on every start (`spacetime sql -s maincloud moove "SELECT * FROM service_config"`, key `upload_base_url`). The app on main does **not** read that table yet: it uploads to the build-time `MOOVE_UPLOAD_BASE_URL` (`ios/Config/Local.xcconfig`), so the phone build has to match the worker's current URL.

Phone
- [ ] On launch the login screen appears (merged, #25). Tap **"Continue without an account"** unless you are demoing a real sign-in. End-to-end sign-in was not verified in #25 ("Callback URL mismatch").
- [ ] Settings (gear icon, top right) > Backend > Data source has two options: **"SpacetimeDB (live)"** (the default) and **"Offline demo (fixtures)"**. The choice is remembered across launches.
- [ ] **Live dry run (10:00, unverified on device so far):** with the maincloud worker running, Data source on live, Settings > Status should say Connected (no banner when connected; "Connecting…", "Reconnecting (attempt N)…" or "Offline: ..." otherwise). Pick a home in Move > New Home ("Use this home"), then check Sell & Buy > Shopping fills with items and deals, each deal with a fraud chip, and that Sell & Buy > Spending shows the worker's payment rows. If a commerce screen shows "Connecting…" with a spinner and then **"Can't reach the backend"** (with the reason and "Check the server address in Settings > Backend, or switch Data source to "Offline demo (fixtures)" to see sample data."), the phone isn't reaching maincloud. A connected but empty live account shows an empty state with a next step instead ("No listings yet", "Nothing to approve", "Nothing to buy yet" with an Add item button, and so on), never a blank list. If anything is missing or slow, use Offline demo for the whole segment.
- [ ] For Offline demo, pick **"Offline demo (fixtures)"**. The banner should read "Offline demo: fixture data, nothing is synced".
- [ ] Tabs visible: **Scan, Items, Sell & Buy, Move, Summary** (#136; there is no More tab). Sell & Buy has the segments Listings, Shopping, Approvals · 2 and Spending, and its tab icon shows a badge of 2 (the pending approvals) on the fixture.
- [ ] To reset the fixture between rehearsals, relaunch the app (that's what the #140 test plan uses). Switching Data source to live and back is untested.

## Step 1: The pricing agent pays for data over x402
**Live today (merged rail, PR #23/#45):** from `agents/` on laptop A:
```sh
npm run x402:demo -- "Herman Miller Aeron"
```
- Judges see (terminal): `Comps endpoint on :<port> (x402 paywall, paying to 0x...)`, then `agent_event [payment] Paid $0.01 USDC for comps for 'Herman Miller Aeron'`, `HTTP 200` with the comps JSON, `On-chain: https://sepolia.basescan.org/tx/0x...`, and `pricing budget left: $4.99`.
- Click the `On-chain:` link to show the settled 0.01 USDC transfer on Base Sepolia.
- Note: the comps in this script are fixture comps (`source: "fixture"`, `replayed: true`). The payment is real; the data is canned.

**Show a guardrail (optional, 10 s):**
```sh
X402_MAX_PER_CALL_USDC=0.005 npm run x402:demo
```
The rail refuses before signing: `Refused x402 payment for comps for 'IKEA Poang armchair': $0.01 is over the per-call max of $0.0050`. The script then exits with the `SpendRefusedError`, which is expected. Rehearse once to confirm the inline var wins over `.env.local`.

**Inside the worker (merged, #46):** every pricing run buys its comps from `127.0.0.1:8402/x402/comps` for $0.01 (one `payment` row per item), unless `PRICING_PAY_X402=0`. On a refusal or payment failure it logs a fallback event ("looking up comps ... directly (unpaid)") and calls Apify directly. If the paywall itself fails to start (port 8402 taken, CDP outage), the worker logs `[x402] COMPS PAYWALL FAILED TO START, pricing will use direct (unpaid) Apify lookups` and keeps running (#55). If the paywall's own Apify lookup fails (502), pricing does not run Apify a second time: the payment is refunded and the item is marked failed (#55). `npm run e2e` covers this path locally on the simulated rail (9 x402 payment rows, all `simulated: true`). Not yet rehearsed against maincloud with real payments, so do one dry run.

**Numbers:** $0.01 per comps call (`COMPS_PRICE_USD` in `agents/src/paywall.ts`). Per-call max $0.10, per-agent cap $5 (code defaults).

**Fallback:**
1. `X402_SIMULATE=1 npm run x402:demo`: same flow, nothing signed, every message starts with `[SIMULATED]`. Say it's simulated.
2. Open the proof tx links (below) and say "this is the same call, settled earlier".
3. Worker pricing without Apify: comps are cached in `agents/fixtures/comps/`. The committed replay `herman-miller-office-chair.json` (#63, 18 real comps) covers the demo Herman Miller office chair and is labeled `[REPLAYED]`. `SEED_COMMERCE=1 npm run seed:demo` adds that chair to the seeded Bedroom, set to sell (see `docs/backends.md`). Any other item with Apify down or no `APIFY_TOKEN` errors with "APIFY_TOKEN not set and no cached comps for this query". Show those on the phone's Offline demo instead.

## Step 2: The spending log
Merged (PR #36). Since #28 the live backend subscribes to `payment` and `agent_event`, so in live mode this screen shows the worker's real rows (unverified on device). The steps below are the Offline demo fixture.

**Tap:** Sell & Buy > Spending.

**Judges see (Offline demo fixture):**
- Totals row: **Spent $0.01** (the real tx), **Simulated $180.005** (orange: $0.015 of simulated x402 plus the $179.99 simulated Visa mattress; the declined rug isn't counted) and **Refused 1**. After the scripted actions (approve the Aeron, choose the Target chair, approve the sofa) it reads **Spent $0.01**, **Simulated $689.985** (plus the $79.99 chair and the $429.99 sofa) and **Refused 1**. `DemoNumbersTests` in MooveKit checks these against the fixture rows.
- The $0.01 Aeron comps payment is the only non-simulated payment in the fixture; every other payment, listing and purchase is `simulated: true`.
- Budgets section: "Pricing agent" ($4.975 left) and "Shopping agent" ($5.00 left), each out of the $5 cap with a progress bar. Rows show "Reported by the agent worker" when the worker sent its budget (otherwise "Your payments only").
- Activity list:
  - The real $0.01 payment "Premium comps for "Herman Miller Aeron"" with a **"Basescan 0xc794…136c"** link (it opens the real proof tx).
  - Three rows with the filled **SIMULATED** pill and **no** Basescan link: two x402 data calls ($0.01 IKEA desk comps, $0.005 mini-fridge price history) and the $179.99 Visa mattress ("Buy agent · Visa", Settled).
  - The $89.99 Visa rug, struck through, SIMULATED and Failed, with the red reason "Did not buy "5x7 flatweave area rug, cream/gray": declined (card declined by the issuer, simulated)".
  - The struck-through, Failed $0.02 "Seller report for a used dresser", SIMULATED, with "x402 payment for seller report for a used dresser failed (HTTP 402, insufficient_funds)".
  - A red "Refused" $0.25 row ("$0.25 is over the per-call max of $0.10", "Nothing was signed or paid.") and a "Failed attempt" row.
- Tap the Basescan link to open the real Base Sepolia transaction.

Offline, say clearly: "This screen is on fixture data right now; the Basescan link is our real payment." Live, every row is the worker's, and every simulated row is still labeled.

**Fallback:** the terminal from step 1 plus the basescan tab. A read-only check of real rows on maincloud: `spacetime sql -s maincloud moove "SELECT * FROM payment"` (rows appear once the worker has priced an item).

## Step 3: Listing approval on the phone
Merged: eBay listing agent (#30, real sandbox posting #34), Auth0 CIBA + in-app inbox (#35).

**How it works:** a "sell" item gets a Claude-written listing. If the price is over the owner's `approval_threshold_cents` ($100 by default), the agent calls `request_approval` and waits. With Auth0 configured and the owner's `user.auth0_sub` set, the worker sends a CIBA push to Auth0 Guardian on the owner's phone (expires after 300 s). Otherwise the approval waits in the in-app Approvals inbox.

**Live CIBA path (unverified on device):** it needs a `sell` item owned by the phone's identity on maincloud and a `user` row with `auth0_sub`. Since #28 the app can create both: a scan from the phone goes through `import_scan_v2`, and after an Auth0 sign-in the live `registerUser` passes the Auth0 `sub`. Two open risks: end-to-end sign-in was not verified in #25 ("Callback URL mismatch"), and the item has to be sorted (or set) to sell and priced before the listing agent drafts it. `npm run seed:demo` can't stand in, because it creates the room under its own user identity, not the phone's. The worker log lines to point at: `Sent approval request to the owner's phone via Auth0 Guardian: ...`, then `Approved on the phone (...)`, then `Posting "..." to eBay at $...` and `Live as item #...` (with `(simulated)` when the eBay keys aren't set). Rehearse it once at 10:00 if you want to show the push; otherwise don't attempt it at the table. `npm run e2e` covers the worker side (listing drafted, approval requested, owner approves in the app, simulated eBay post) but not CIBA.

**Tap (Offline demo, the reliable path):**
1. Sell & Buy > Approvals (the segment reads "Approvals · 2"). Section **"Needs you · 2"**: a Sell request for the Aeron at $410 and a Buy request for the 78" upholstered sofa at $429.99 "from wayfair", then the note "Also sent to your phone via Auth0 Guardian when set up. Approving here works too."
2. The listing request: "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition", **$410**, tagged Sell with the SIMULATED pill (fixture listings are simulated).
3. **History · 3**, each with an outcome line: newest first, the denied $699 IKEA KIVIK sofa ("You denied it. Nothing was bought."; the user picked the Wayfair sofa instead), the approved $179.99 Target mattress ("You approved it. The buy agent checks out with Visa."; it's the Bought mattress in Shopping) and the denied $480 Aeron ("You denied it. The listing wasn't posted.").
4. Tap **Approve** on the $410 Aeron. A spinner, then it moves to History as Approved ("You approved it. The listing agent posts it."), and "Needs you" drops to 1.
5. Optional: Sell & Buy > Listings. Groups: **Needs you** (the Aeron $410, until you approve it), **Live** (the IKEA desk $35, plus the Aeron once approved), **Drafting** (mini fridge $70), **Sold** (bean bag $18, "Sold (simulated)") and **Not posted · 2**: the Aeron $480 with "Not posting: denied", and the Mini Fridge $70 "Failed to post" with "Posting failed: eBay needs at least one public https photo URL (simulated)". Live rows read **"Posted (simulated)"**, never "Live on eBay", and every row has the SIMULATED pill. Tap the desk: the notice "Simulated post. Not live on eBay, and no buyer can see it." and no eBay item number. Tap the failed fridge: "Couldn't post this listing. Posting failed: … You can still copy the text and post it yourself."

**Numbers:** threshold $100 (10000 cents default), Aeron $410, so it needs approval. The fixture's first $480 draft was denied, and the agent re-priced it to $410.

**Fallback:** if CIBA doesn't arrive, the in-app inbox is the designed fallback, so say "it falls back to the in-app inbox" and approve there. If Auth0 isn't configured at all, approvals simply wait in the inbox; there is no simulated auto-approver any more.

## Step 4: The buy agent finds a deal
Merged (#40, with the live Apify deals from #52 folded in), fraud screen merged (#64).

**Worker side:**
1. When a `new_home` row appears, the shopping-list agent lists what the new home still needs.
2. The buy agent searches deals for each item. With `DEALS_SOURCE=apify` and `APIFY_TOKEN` it searches live FB Marketplace and eBay listings through Apify. Without a token, or when a live search comes back empty or fails, it replays the last cached live search for that query (`.cache/deals/`, then the committed `fixtures/deals-live-*.json`; labeled "cached replay", REPLAY). With neither, it uses hand-made sample data ("sample data", SAMPLE).
3. Live and replayed results always include labeled sample retail rows, so every item has a card-checkout option.
4. It ranks the deals, writes the top 5 and recommends the best card-checkout deal. With `BUY_AUTO_CHOOSE=0` (the default) the user chooses: in live mode the phone's **Choose** calls `choose_deal` on maincloud (wired since #28, unverified on device). `BUY_AUTO_CHOOSE=1` on the worker lets the agent choose its recommendation instead.
5. The fraud agent (`agents/src/agents/fraud.ts`) scores every new deal once the burst for that item has settled (`FRAUD_SETTLE_MS`, 1.5 s) and writes `set_deal_fraud` with a score and short reasons, plus one `fraud` result event. Signals: price far below the other deals and cached comps, off-platform payment asks (Zelle, Cash App, wire, gift cards, crypto, deposits, ...), new-seller text, duplicate listings, and AI-written text (only with `PANGRAM_URL`). No Claude calls. A deal scored 0.7 or more (`BUY_FRAUD_BLOCK`) is never bought. In the latest e2e run on main, 3 of 44 deals scored 0.3 or more, e.g. an "office chair" at $10, "85% below the other deals (median $68)".
6. FB and Craigslist sellers get a drafted message instead of a payment. Sellers show as "FB Marketplace seller, <city>" or "eBay seller", and "distance unknown" appears when a listing has no coordinates.

**Every demo shopping item has a committed live replay:** 16 files in `agents/fixtures/` (`deals-live-<item>.json`, fetched with real Apify runs on Oct 24): area rug, bed frame, bookshelf, cookware set, desk, desk chair, dining chairs, dining table, dresser, floor lamp, mattress, nightstand, office chair, shower curtain set, sofa and TV stand. Each has 3 to 9 real active listings (the sofa's are 4 eBay only), and `agents/test/deals-apify.test.ts` checks every file has 3+ listings, no seller identities, and is served for its item name. A shopping item with another name (Claude can write e.g. "Full size mattress") has no exact replay; it is searched live with the token, or falls back to sample data.

**Tap (Offline demo):**
1. Sell & Buy > Shopping. A "Needs you · 1" card for the Sofa purchase (sofa thumbnail, $429.99, fraud chip) sits above **"Still to buy · 4"** (bought items don't count): Mattress (Bought, green check), Sofa, Desk chair, Dining table and **Area rug** (Deals found). Every row has a voxel thumbnail. The Area rug row shows SIMULATED and "Checkout failed. Nothing was charged. Pick another deal."
2. Tap **Desk chair**: 3 deals, each with its own voxel chair. The planted demo scam "Herman Miller Aeron, brand new, $95, Zelle only, ship only" (seller "Planted demo scam (not a real listing)", Sample badge) shows the chip **"Likely fraud · 0.85"**, its reasons ("asks for payment by Zelle", "shipping only, no meetup") and a red **"Blocked: likely fraud"** tag where Choose would be (the worker refuses it anyway). Chips read "Low fraud risk", "Some fraud risk" (0.3 and up) or "Likely fraud" (0.7 and up). A deal that hasn't been scored yet says "Not fraud-screened yet" (on the fixture, the IKEA MARKUS chair).
3. Fraud screening is real in the worker (the `fraud` agent, #64), but on Offline demo the 0.85 and every other score are fixture values (the 0.85 is what the real rules give the same planted deal live). Live, every chip comes from the worker's fraud agent. Fixture deals are all sample data, so they show a **Sample** badge; replayed deals show **Replay**; live deals have no badge.
4. Tap **Choose** on the Target "Mesh task chair with arms, black" ($79.99, under the $100 limit). Checkout reads "Paid through the simulated Visa rail. No real card was charged." with a SIMULATED Paid row, and Spending gets a new $79.99 SIMULATED Visa row. Choose is locked while a hold or a purchase approval is pending for that item, and the chosen deal shows "Chosen" instead.
   - **Blocked scam, live:** whatever the deal source (live Apify, replays or sample data), any desk/office chair shopping item (named e.g. "Desk chair", "Office chair", "Ergonomic desk chair", "Task chair"; never dining chairs, armchairs or chair mats; if the list has none, add an "Office chair" in the app) always gets the planted demo scam from `agents/fixtures/deals.json` (`"planted": true`, labeled sample data, never counted as a live deal); the real fraud agent scores it 0.85, and choosing it logs `Not buying "Herman Miller Aeron, brand new, $95, Zelle only, ship only": fraud screen scored it 0.85 (asks for payment by Zelle; shipping only, no meetup)` with no approval and no charge. Say it's a planted test listing.
5. Optional, a declined checkout: back on the list, tap **Area rug**. Checkout shows Failed $89.99 SIMULATED, the red "Did not buy … declined (card declined by the issuer, simulated)" and "Nothing was charged. Pick another deal below to try again." Choose the Amazon "Washable 5x7 boho area rug" ($64.99): it is paid (simulated) and the rug shows Bought on the list.

**Fallback:** Offline demo. If a live search fails, the worker uses the replay or sample data, both labeled.

## Step 5: Visa checkout
Merged (#40). **The demo checkout is the labeled simulation (`VISA_PROVIDER=simulated`).** The real CyberSource sandbox charge has not succeeded: HTTP 502 `SYSTEM_ERROR` every time, latest request ids `7928329698276400003813` and `7928175635416253203813`. The signature is accepted (a bad one returns 401), so this is a merchant-side setup problem in our sandbox account (most likely no card processor enabled). Fixing it needs a human in the CyberSource sandbox Business Center; no code change will.

**How it behaves:** at or under the $100 threshold, the buy agent checks out right away. Over it, it asks first: the worker's approval summary reads `Pay $X to <merchant> for: <title>`, and the phone push reads "Moove: buy X USD: <deal title>".

**Tap (Offline demo):**
1. Sell & Buy > Shopping, the "Needs you" card: the deal "78\" upholstered sofa, gray", "$429.99 from wayfair", Approve and Deny, and the note "Over your approval limit. The agent pays with Visa only after you approve." The same request is the second row in Sell & Buy > Approvals, with the same deal title and "from wayfair" (no note).
2. Tap **Approve**. The fixture records a settled, simulated $429.99 Visa payment for it. With the Aeron approved in step 3, Approvals now reads "Needs you · 0" and "You're all caught up. New requests over your limit show up here." above History.
3. Sell & Buy > Spending: the $179.99 mattress and now the $429.99 sofa as Visa payments with the SIMULATED pill, "Buy agent · Visa", Settled, no Basescan link. In Shopping the sofa's Checkout shows "Paid" with a SIMULATED pill.
4. If you Deny instead (confirm "Deny $429.99"), it moves to History as Denied and Shopping > Sofa's Checkout reads "You denied this purchase. Nothing was bought."

Live (unverified on device): approving a purchase from the phone calls `decide_approval`, the worker re-checks the approval and captures on the simulated rail, and the `payment` row (rail `visa`, `simulated: true`) syncs back. `npm run e2e` covers this on the worker side ("payment settled, simulated: true").

**Terminal:**
```sh
VISA_PROVIDER=simulated npm run visa:demo -- 129.99
```
It prints `Visa checkout: SIMULATED`, the payment row, every agent event (`[SIMULATED]` hold, then capture) and the result, and exits 0 when the status is `captured`. The default amount without an argument is $42.50.

**Numbers:** Visa card cap $1,500 per agent, $750 max per purchase, approval threshold $100.

**Don't** demo `VISA_PROVIDER=acceptance` until a `npm run visa:demo -- 1.00` with real keys succeeds. On success it would show `[VISA SANDBOX]` events, a `[Visa sandbox]` purpose and a VISA SANDBOX badge.

**Fallback:** the simulated Visa rail, always labeled. If the worker isn't cooperating, `visa:demo` in the terminal shows the full hold, re-check and capture sequence on its own.

## Step 6: Summary
Merged (#31, restyled in #49). **Tap:** the Summary tab.

**Judges see:** "07 — Summary", "Your move, handled." and "N items: where each one went, what it brought in, and what the agents did.", the Net and kept-from-landfill stats, "Where everything went" (Kept / Sold / Donated / Trashed / Undecided), and a **Money** block with sold, still selling, spent and net, plus one line per rail ("x402 data payments", and "Visa purchases" once there are card payments). The Money block shows a **Simulated** tag whenever any money in it is simulated, so on the fixture it will show. Then the landfill line ("~N kg kept out of landfill") and "What the agents did". With no payment or event rows (a fresh live account), it shows labeled demo lines and a "Demo" tag.

**Offline demo figures** (checked by `DemoNumbersTests`, which re-derives them from the Spending, Listings and Shopping rows):
- Where everything went: 12 items, Kept 3, Selling 4, Donated 2, Trashed 1, Undecided 2.
- Money before the scripted actions: **Sold $18** (the bean bag), **Still selling $520** (Aeron $410 awaiting approval, desk $35 posted, mini fridge $75 at its estimate since its listing is only a draft), **Spent $180.015**, **Net $357.99**. Rails: "Visa purchases" $179.99 tagged Simulated, "x402 data payments" $0.025 tagged "$0.015 sim" (the other $0.01 is the real tx). Simulated tag on the block.
- After approving the Aeron, choosing the Target chair and approving the sofa: Sold $18 and Still selling $520 are unchanged (the Aeron moves from awaiting approval to posted at the same $410), **Spent $689.995**, **Net −$152**. Visa purchases $689.97 (Simulated), x402 $0.025 ("$0.015 sim").
- Spent always equals Spending's Spent plus Simulated.

**Fallback:** Offline demo.

## 30-second talk track
"Moving means pricing, selling and buying a whole household. Moove hands that to agents, and you stay in control. When our pricing agent needs comps, it pays for them itself: one cent in USDC over x402 on Base Sepolia, from a Coinbase server wallet. Here's the real transaction on basescan. A payment rail checks a per-agent budget and a per-call max before anything is signed, so a ten-cent cap means a twenty-five-cent request gets refused and logged. Every payment lands in a live spending log, and anything simulated is labeled. Big decisions come to you: a $410 listing needs your approval through Auth0 on your phone. The buy agent shops what the new place needs, a fraud screen scores every deal and the agent never buys a likely scam (here's a planted Zelle-only Aeron it refuses at 0.85), it recommends the best deal and, once you choose, checks out with Visa, re-checking your approval right before it captures. That checkout is simulated today, and it's labeled. The summary shows what you made, spent and kept out of the landfill."

Fraud screening is real in the worker (#64): rule-based signals, no model calls, and 0.7 or more is never bought. If you're on Offline demo, say the scores on screen are fixture values; the AI-text signal is off unless `PANGRAM_URL` is set, so don't claim it. If asked about the sandbox, say our CyberSource sandbox account returns a 502 on every charge (a merchant-side setup issue in the sandbox Business Center, not in our code), so we demo the labeled simulation.

## Video shot list (commerce, ~70 s)
For the Devpost video, recorded in the morning. [`docs/demo.md`](demo.md) has no video plan yet, so this list follows the order of its [2-minute script](demo.md#the-2-minute-script): Prices (step 3), List and approve (5), Buy (6), New home (7), Summary (8). The commerce segment slots into those steps; record the scan, sort and fly-in parts from that script.

**Decision (Aiden's agent):** the exact on-screen strings below come from the **Offline demo** fixture (`MooveKit/Sync/DemoFixtures.swift`, `ShoppingFixtures.swift`), because that is the only data source whose rows are known in advance and checked by `DemoNumbersTests`. The rest of the video is recorded on the **Demo** backend (`moove-demo`, join code `4RZ9G8`, per [`docs/morning.md`](morning.md)). If Aiden's morning check on Demo passed (Spending, Approvals and Shopping all fill for the phone's account), you can record the same taps on Demo instead, but the names and amounts will differ: the seeded Bedroom has no Aeron, and the Demo worker has no CDP keys, so **every x402 row there is simulated** and has no Basescan link. Then shot 1's real payment comes only from the laptop (shot 1b). Either way, read the VO lines as written; they hold for both.

### Before recording
- [ ] **Backend:** Settings (gear, top right) > Backend > Data source **"SpacetimeDB (live)"** > Database **"Demo (moove-demo)"** for the non-commerce parts. For the commerce segment, Data source **"Offline demo (fixtures)"**: the banner must read "Offline demo: fixture data, nothing is synced". Record the commerce segment as its own take: switching between live and fixture and back is untested, so relaunch after switching.
- [ ] **Reset by relaunch:** force-quit and reopen the app before each take. The fixture resets on launch (the Aeron and sofa go back to pending, Approvals reads "Approvals · 2").
- [ ] **Do Not Disturb** on the phone and the laptop (no Guardian or Slack banners in shot), screen recording started, battery and Wi-Fi icons don't matter.
- [ ] **Laptop:** a terminal in `agents/` with `npm run x402:demo -- "Herman Miller Aeron"` typed but not run (it spends 0.01 testnet USDC, so run it once for the take, not in rehearsals; `npm run x402:wallet` first if unsure of the balance), and a browser tab with the proof tx already loaded: https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c
- [ ] Rehearse once end to end on the fixture without recording; then relaunch.

### Shots
| # | Screen and taps | On screen (exact strings) | Voice-over | Sec |
|---|---|---|---|---|
| 1a | Sell & Buy tab > **Spending** segment. Hold on the totals, scroll to the first payment, tap **Basescan 0xc794…136c**. | Totals **Spent $0.01**, **Simulated $180.005** (orange), **Refused 1**. Row "$0.01", "Premium comps for "Herman Miller Aeron"", "Pricing agent · x402 · USDC", "Settled", **"Basescan 0xc794…136c"**. Below it, rows with the filled **SIMULATED** pill and no Basescan link ("Premium comps for "IKEA laminate desk"", the $179.99 mattress, "Buy agent · Visa"). Safari opens the Base Sepolia tx. | "When our pricing agent needs sold comps, it pays for them itself: one cent in USDC over x402 on Base Sepolia, and this Basescan link is that real transaction; every row with the orange Simulated pill is simulated." | 14 |
| 1b | *Alternative or cutaway, laptop:* run `npm run x402:demo -- "Herman Miller Aeron"`, then click the `On-chain:` link. | `Comps endpoint on :<port> (x402 paywall, paying to 0x...)`, `agent_event [payment] Paid $0.01 USDC for comps for 'Herman Miller Aeron'`, `HTTP 200`, `On-chain: https://sepolia.basescan.org/tx/0x...`, `pricing budget left: $4.99`; the basescan page with the 0.01 USDC transfer. | "Here it is from the terminal: the agent's Coinbase server wallet pays the paywall, and the payment settles on Base Sepolia." (The comps in this script are canned fixture comps; the payment is real. Don't call the data live.) | (12) |
| 2 | Still on Spending, scroll to the red row. | **"Refused"**, ~~$0.25~~, "Refused x402 payment for a premium deal scan: $0.25 is over the per-call max of $0.10", "Shopping agent · $5.00 budget left", **"Nothing was signed or paid."** Budgets: "Pricing agent", "Shopping agent", each against its $5 cap. | "Every agent has a budget and a per-call cap that the rail checks before it signs, so this 25-cent request was refused: nothing was signed or paid." | 7 |
| 3 | **Approvals** segment (reads "Approvals · 2") > the Sell request "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition" **$410** > **Approve**. Then **Listings** segment. | "Needs you · 2", the Sell tag and SIMULATED pill, "Also sent to your phone via Auth0 Guardian when set up. Approving here works too." After Approve: it moves to History, "You approved it. The listing agent posts it.", "Needs you · 1". In Listings, the Aeron under **Live** with **"Posted (simulated)"** and the SIMULATED pill. | "Claude writes the listing, and anything over your $100 limit waits for you, by Auth0 push or right here; once approved it posts, and today that eBay post is simulated, so it says Posted (simulated)." | 12 |
| 4 | **Shopping** segment > **Desk chair**. Hold on the red deal, then tap **Choose** on the Target "Mesh task chair with arms, black" ($79.99). | Three deals with voxel chairs. **"Herman Miller Aeron, brand new, $95, Zelle only, ship only"**, seller "Planted demo scam (not a real listing)", **Sample** badge, chip **"Likely fraud · 0.85"**, reasons "asks for payment by Zelle", "shipping only, no meetup", and a red **"Blocked: likely fraud"** tag where Choose would be. After Choose: "Paid through the simulated Visa rail. No real card was charged." | "The buy agent shops for the new place and screens every deal for fraud; this Zelle-only Aeron is a listing we planted for the demo, it scores 0.85 and the agent will not buy it, while the $79 chair under the limit checks out on the simulated Visa rail." | 12 |
| 5 | Back to **Shopping** list > the **Needs you · 1** card: "78" upholstered sofa, gray" **$429.99** > **Approve**. Then **Spending** segment. | Card: "$429.99 from wayfair", "Over your approval limit. The agent pays with Visa only after you approve.", Approve / Deny. In Spending: new rows "$429.99" with the **SIMULATED** pill, "Sofa: 78" upholstered sofa, gray", "Buy agent · Visa", "Settled", no Basescan link. Totals now **Spent $0.01**, **Simulated $689.985**, **Refused 1**. | "Over the limit, the agent asks before it pays with Visa; our Visa sandbox account still returns a 502, so this checkout is a labeled simulation and no card was charged." | 12 |
| 6a | **Move** tab > **New Home** > the demo house > **Use this home**. Let the fly-in play, scroll to Pieces. | "06 — New home", "Where are you moving?", then the voxel dollhouse, "Layout", **Fly in**, **Save layout**; under "Pieces" the bought furniture named from the chosen deals, e.g. "78" upholstered sofa, gray" and "8" memory foam mattress, Full", next to the kept items. | "What the agent bought lands in the new home with what you kept, placed in the 3D layout." | 7 |
| 6b | **Summary** tab, scroll to Money. | "Your move, handled.", **Money** with the **Simulated** tag: Sold $18, Still selling $520, **Spent $689.995**, **Net −$152**; "Visa purchases" $689.97 tagged Simulated, "x402 data payments" $0.025 tagged "$0.015 sim"; "kept out of landfill". | "The summary adds up what you sold, what the agents spent and what stayed out of the landfill, and it tags the simulated money as Simulated." | 7 |

Total about 71 s (1a + 2 + 3 + 4 + 5 + 6a + 6b); use 1b as a cutaway inside shot 1 or swap it for 1a. The totals in shots 5 and 6b assume the taps above in this order (Aeron approved, Target chair chosen, sofa approved), and `DemoNumbersTests` checks them. On the Demo backend they will differ, so cut the figures from the VO if you record there.

**Honesty notes for the edit:** the Basescan row in 1a and the terminal run in 1b are the only real payments; every other payment, the eBay post and the Visa checkout are simulated and labeled in the shot. On Offline demo the fraud scores are fixture values (the real fraud agent gives the planted deal the same 0.85 live). Fraud screening is rule-based, so don't credit Claude for it. The Auth0 push isn't shown (the in-app inbox is), so don't say "you just got a push".

**Track callouts:** Coinbase x402: shots 1a, 1b, 2. Visa: shots 4, 5 (fraud screen, approval, simulated checkout; trust and responsibility). Auth0: shot 3 (approval over the threshold; Guardian CIBA push when set up, in-app inbox shown). Anthropic: shot 3 (the Claude-written listing). SpacetimeDB: every screen is table rows (`payment`, `agent_event`, `approval`, `listing`, `deal`) that sync live on the Demo backend. Apify: shot 1 (the comps the agent pays for come from Apify's eBay sold and FB Marketplace actors, replayed from caches here) and shot 4 (deal search; fixture deals are labeled Sample). Mapping per [`docs/tracks.md`](tracks.md).

## Proof to cite (backup if live payment fails)
Both are real x402 payments of 0.01 USDC on Base Sepolia:
- https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c (from `npm run x402:demo`, block 49461682. It's also the Basescan link in the app's offline spending log.)
- https://sepolia.basescan.org/tx/0x9bf1f717c8901a4a5dfc137099cb4254e4dfd5d0b584873184b883924a8ff37d (from the local end-to-end test `npm run x402:e2e`, PR #48, which landed `payment` + `agent_event` rows in SpacetimeDB)

Payer: `0x3224220E5007e8F4c0440447bdfeb846c96f8A52` (agents' wallet). Payee: `0x6644b110FD0B1671599E36db749d09b1EAeEF952` (comps paywall receiver).

## If everything breaks
1. Phone: Settings > Data source > Offline demo. Every commerce screen works with no network.
2. Laptop: `X402_SIMULATE=1 npm run x402:demo`, labeled simulated.
3. Browser: the two basescan links above.
4. Say what's simulated. That's a track rule, and judges respect it.
