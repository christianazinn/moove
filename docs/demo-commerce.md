# Demo runbook: commerce segment

The commerce part of the Sunday live demo (judging Sun 10:30, live demo plus a 2-minute pitch). It covers agents paying over x402, the spending log, listing approval, the buy agent, Visa checkout and the summary.

Read the "Today's reality" box first. Before the demo, check any PR still marked open with `gh pr view <N> --json state`.

> **Today's reality (origin/main, Sat):**
> - **The phone cannot show live worker data yet.** `ios/Moove/Sync/SpacetimeBackend+Contract.swift` on main subscribes to no tables, and every reducer call throws "waiting on the SpacetimeDB module". So every phone screen in this segment, including the Shopping Choose, approve and checkout flow, runs in **Offline demo** mode (fixture data) until Rio's live bindings (#10) land. Draft PR #28 wires some tables (listing, approval), but not `payment` or `agent_event`.
> - **Live proof comes from the laptop:** terminal output from `npm run x402:demo` or the worker, and the basescan tx page.
> - Still open: #28 (scan + live sync, draft), #58 (CIBA fail-closed), #10 (live iOS bindings). Merged:
>   - #40: buy agent, Visa checkout, Shopping tab, live Apify deals folded in from #52
>   - #46: pricing pays over x402
>   - #55: if the paywall fails to start, pricing falls back to unpaid Apify; no double Apify run
>   - #38: security pass, seeded budgets, payee allowlist
>   - #63: Herman Miller comps replay
>   - #25: login
>   - #53: amount-first push text
>   - #36: spending log
>   - #31 and #67: summary
>   - #51: worker no longer crashes on rejected reducer calls

## Setup at the table
- **Laptop A (Christian's):** the only worker against maincloud. One terminal running the worker, one free terminal in `agents/`.
- **Phone:** Moove dev build, set to Offline demo (see the checklist).
- **Browser tab:** the basescan proof link below, already loaded.

## Pre-demo checklist
Do this by 10:00.

Wallet and keys
- [ ] `cd agents && npm ci`
- [ ] `npm run x402:wallet` prints the agent wallet (`0x3224220E5007e8F4c0440447bdfeb846c96f8A52` per `docs/coinbase-x402.md`) and a USDC balance. Each real call costs 0.01 USDC, so any balance above about 0.10 covers the demo plus rehearsals.
- [ ] If it's empty: `npm run x402:wallet -- --faucet`, wait about 10 s, run `npm run x402:wallet` again.
- [ ] `npm run x402:demo` once as a rehearsal. It should end with an `On-chain: https://sepolia.basescan.org/tx/...` line. If it prints "UNPAYWALLED, simulated mode", the CDP keys aren't loaded.

Required env vars (names only; values live in the repo-root `.env.local`, which `agents/scripts/env.ts` and `agents/src/config.ts` load)
- [ ] x402: `CDP_API_KEY_ID`, `CDP_API_KEY_SECRET`, `CDP_WALLET_SECRET`. Optional, with code defaults: `AGENT_SPEND_CAP_USDC` (default 5), `X402_MAX_PER_CALL_USDC` (default 0.10). Leave `X402_SIMULATE` empty for real payments.
- [ ] Worker: `SPACETIME_URI=wss://maincloud.spacetimedb.com`, `SPACETIME_DB_NAME=moove`, `SPACETIME_WORKER_TOKEN_FILE=.worker-token.maincloud`, `ANTHROPIC_API_KEY`, `APIFY_TOKEN`, `UPLOAD_PORT`, `PUBLIC_UPLOAD_BASE_URL`.
- [ ] Approvals: `AUTH0_DOMAIN`, `AUTH0_CIBA_CLIENT_ID`, `AUTH0_CIBA_CLIENT_SECRET`. Keep `APPROVAL_SIM_AUTO_APPROVE_SEC=0`. `APPROVAL_THRESHOLD_CENTS_DEFAULT` defaults to 10000 ($100).
- [ ] eBay (real sandbox posting only; otherwise listings are simulated and labeled): `EBAY_CLIENT_ID`, `EBAY_CLIENT_SECRET`, `EBAY_RUNAME`, `EBAY_REFRESH_TOKEN`, `EBAY_FULFILLMENT_POLICY_ID`, `EBAY_PAYMENT_POLICY_ID`, `EBAY_RETURN_POLICY_ID`, `EBAY_LOCATION_KEY`, plus optional `EBAY_FALLBACK_IMAGE_URL`.
- [ ] Pricing pays over x402: `X402_PORT` (default 8402), `PRICING_PAY_X402` (on unless set to `0`/`false`/`off`). Merged in #46.
- [ ] Visa and buy agent (merged, #40):
  - **Leave `VISA_PROVIDER` empty or set it to `simulated`.** Do **not** set `VISA_PROVIDER=acceptance` for the demo while the CyberSource sandbox returns HTTP 502. With an explicit `acceptance`, every checkout would fail (retried 3 times, then given up) instead of being simulated.
  - With no provider and no `VISA_ACCEPTANCE_*` keys, checkout is simulated and labeled.
  - Defaults: `VISA_SPEND_CAP_USD` 1500, `VISA_MAX_PER_PURCHASE_USD` 750, `VISA_SIM_DELAY_MS` 400, `BUY_AUTO_CHOOSE` 0 (the user chooses), `BUY_FRAUD_BLOCK` 0.7, `BUY_RETRY_DELAY_MS` 60000.
  - Deals: `DEALS_SOURCE` (default `apify`), `DEALS_APIFY_SOURCES` (default `fb,ebay`), `DEALS_SEARCH_CONCURRENCY` (2), `DEALS_PER_SOURCE` (6), optional `DEALS_HOME_LAT` / `DEALS_HOME_LNG`. Deal search reuses `APIFY_TOKEN`.

Worker
- [ ] **Only one worker against maincloud**, on Christian's machine, with the token in `agents/.worker-token.maincloud`. Nobody else runs `npm start` / `npm run dev` with maincloud settings.
- [ ] Start it from `agents/`: `npm start` (with the maincloud vars above). Expect `[spacetime] connected as ...`, `[agents] cache ready: N items`, `[agents] started vision`, `pricing`, `listing`, `approval`, the shopping-list agent and `buy`, and `[visa] checkout ready (SIMULATED)` once the first checkout runs.
- [ ] Don't run `npm run x402:e2e` against maincloud. It connects as a worker and is meant for a local `spacetime start` + `npm run publish:local`. `npm run x402:demo` is fine anywhere because it doesn't touch SpacetimeDB.

Budgets
- [ ] **Budgets survive a restart** (merged, #38). With `X402_SEED_BUDGETS=1` (the default) the worker counts the last 24 h of x402 `payment` rows against each agent's $5 budget at startup (`agents/src/payments.ts`), so a restart does not hand out a fresh budget.
- [ ] **Budget reset after rehearsals:** start the demo worker with `X402_SEED_BUDGETS=0 VISA_SEED_BUDGETS=0 npm start`. Every agent then starts at $0 of $5 (x402) and $0 of $1,500 (card). Card seeding only counts non-simulated (sandbox or real) card payments from the last 24 h, so simulated rehearsals never use up the card cap anyway.
- [ ] `X402_ALLOWED_PAYEES` (merged, #38) is an optional comma-separated `payTo` allowlist. If you set it, include the comps paywall receiver `0x6644b110FD0B1671599E36db749d09b1EAeEF952`, or every pricing payment is refused.

Photos for eBay (only for a real sandbox post)
- [ ] eBay needs public **https** photo URLs. Uploads are served at `PUBLIC_UPLOAD_BASE_URL/files/<name>` on `UPLOAD_PORT` (8787). `agents/src/integrations/ebay.ts` throws "eBay needs at least one public https photo URL: set PUBLIC_UPLOAD_BASE_URL to an https tunnel, or EBAY_FALLBACK_IMAGE_URL". So either point `PUBLIC_UPLOAD_BASE_URL` at an https tunnel to port 8787 (the repo doesn't pick a tunnel tool) or set `EBAY_FALLBACK_IMAGE_URL`. Without eBay keys, the listing is simulated and needs no tunnel.

Phone
- [ ] On launch the login screen appears (merged, #25). Tap **"Continue without an account"** unless you are demoing a real sign-in. End-to-end sign-in was not verified in #25 ("Callback URL mismatch").
- [ ] Settings (gear icon, top right) > Backend > Data source: **"Offline demo (fixtures)"**. The banner should read "Offline demo: fixture data, nothing is synced".
- [ ] Tabs visible: Scan, Review, Spending, New Home, then **More** for Inventory, Listings, Approvals, Summary and Shopping. The Approvals tab shows a badge with the pending count.
- [ ] To reset the fixture between rehearsals, switch Data source to live and back, or relaunch the app. Untested; check once.

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

**Inside the worker (merged, #46):** every pricing run buys its comps from `127.0.0.1:8402/x402/comps` for $0.01 (one `payment` row per item), unless `PRICING_PAY_X402=0`. On a refusal or payment failure it logs a fallback event ("looking up comps ... directly (unpaid)") and calls Apify directly. If the paywall itself fails to start (port 8402 taken, CDP outage), the worker logs `[x402] COMPS PAYWALL FAILED TO START, pricing will use direct (unpaid) Apify lookups` and keeps running (#55). If the paywall's own Apify lookup fails (502), pricing does not run Apify a second time: the payment is refunded and the item is marked failed (#55). Not yet rehearsed against maincloud, so do one dry run.

**Numbers:** $0.01 per comps call (`COMPS_PRICE_USD` in `agents/src/paywall.ts`). Per-call max $0.10, per-agent cap $5 (code defaults).

**Fallback:**
1. `X402_SIMULATE=1 npm run x402:demo`: same flow, nothing signed, every message starts with `[SIMULATED]`. Say it's simulated.
2. Open the proof tx links (below) and say "this is the same call, settled earlier".
3. Worker pricing without Apify: comps are cached in `agents/fixtures/comps/`. The committed replay `herman-miller-office-chair.json` (#63, 18 real comps) covers the demo Herman Miller office chair and is labeled `[REPLAYED]`. Any other item with Apify down or no `APIFY_TOKEN` errors with "APIFY_TOKEN not set and no cached comps for this query". Show those on the phone's Offline demo instead.

## Step 2: The spending log
Merged (PR #36), but **offline only** today: the live backend doesn't subscribe to `payment` / `agent_event` yet.

**Tap:** Spending tab.

**Judges see (Offline demo fixture):**
- Totals row: spent, simulated (orange) and refused counts. Per the fixture, that's $0.01 real spent (the real tx), $0.015 simulated, and 1 refusal.
- Budgets section: "Pricing agent" with an "$X left" amount out of the $5 cap and a progress bar. Rows show "Reported by the agent worker" when the worker sent its budget.
- Activity list: the real $0.01 payment "Premium comps for "Herman Miller Aeron"" with a **"Basescan 0xc794…136c"** link (it opens the real proof tx), two payments with orange **SIMULATED** badges, a red "Refused" row ("$0.25 is over the per-call max of $0.10"), and a "Failed attempt" row.
- Tap the Basescan link to open the real Base Sepolia transaction.

Say clearly: "This screen is on fixture data right now; the Basescan link is our real payment." Every simulated row is labeled.

**Fallback:** the terminal from step 1 plus the basescan tab. A read-only check of real rows on maincloud: `spacetime sql -s maincloud moove "SELECT * FROM payment"` (rows appear once the worker has priced an item).

## Step 3: Listing approval on the phone
Merged: eBay listing agent (#30, real sandbox posting #34), Auth0 CIBA + in-app inbox (#35).

**How it works:** a "sell" item gets a Claude-written listing. If the price is over the owner's `approval_threshold_cents` ($100 by default), the agent calls `request_approval` and waits. With Auth0 configured and the owner's `user.auth0_sub` set, the worker sends a CIBA push to Auth0 Guardian on the owner's phone (expires after 300 s). Otherwise the approval waits in the in-app Approvals inbox.

**Live CIBA path (hard today):** it needs a `sell` item on maincloud and a `user` row with `auth0_sub`, and the app can't create either yet. Login is merged (#25) and passes the Auth0 `sub` to `registerUser`, but the live `registerUser` is still a stub until the Swift bindings land, and live sync is in draft #28. The worker log lines to point at: `Sent approval request to the owner's phone via Auth0 Guardian: ...`, then `Approved on the phone (...)`, then `Posting "..." to eBay at $...` and `Live as item #...` (with `(simulated)` when the eBay keys aren't set). A CLI-only setup is possible (`register_user` takes auth0Sub, name, email and must be called from the owner's identity), but it's untested. Don't attempt it at the table.

**Tap (Offline demo, the reliable path):**
1. More > Approvals. Section "Needs you · 2", with the note "Also sent to your phone via Auth0 Guardian when set up. Approving here works too."
2. The listing request: **Sell "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition" for $410**.
3. Tap **Approve**. It moves to History as "Approved".
4. Optional: More > Listings shows the groups "Needs you", "Live", "Drafting", "Sold". In the fixture, the Aeron is at $410, the desk is live at $35 and the bean bag sold at $18.

**Numbers:** threshold $100 (10000 cents default), Aeron $410, so it needs approval.

**Fallback:** if CIBA doesn't arrive, the in-app inbox is the designed fallback, so say "it falls back to the in-app inbox" and approve there. If Auth0 isn't configured at all, `APPROVAL_SIM_AUTO_APPROVE_SEC` exists but labels everything simulated. Keep it at 0 for the demo.

## Step 4: The buy agent finds a deal
Merged (#40, with the live Apify deals from #52 folded in).

**Worker side:**
1. When a `new_home` row appears, the shopping-list agent lists what the new home still needs.
2. The buy agent searches deals for each item. With `DEALS_SOURCE=apify` it searches live FB Marketplace and eBay listings through Apify. Without `APIFY_TOKEN` it replays committed live searches ("cached replay", REPLAY). Otherwise it uses hand-made sample data ("sample data", SAMPLE).
3. Live and replayed results always include labeled sample retail rows, so every item has a card-checkout option.
4. It ranks the deals, writes the top 5 and recommends the best card-checkout deal. With `BUY_AUTO_CHOOSE=0` (the default) the user chooses. Set `BUY_AUTO_CHOOSE=1` on the worker to let the agent choose its recommendation; until #10 lands, the phone can't send a choice to the live worker.
5. FB and Craigslist sellers get a drafted message instead of a payment. Sellers show as "FB Marketplace seller, <city>" or "eBay seller", and "distance unknown" appears when a listing has no coordinates.

**Live deals are verified for the mattress only:** a real Apify run returned 9 listings (4 FB Marketplace, 5 eBay), committed as `agents/fixtures/deals-live-mattress.json`. Other items use sample data unless searched live.

**Tap (Offline demo):**
1. More > Shopping. "Still to buy" lists Mattress (Bought), Sofa, Desk chair and Dining table.
2. Tap **Desk chair** to see its deals. The Craigslist "Herman Miller Aeron size B" for $95 shows a high fraud score (0.81: "Price is 75% under comparable listings", "Seller asks for payment before pickup").
3. Say that this fraud score is **fixture data**. The fraud agent (#18) is still pending, so live deals are unscored ("Not fraud-screened yet").
4. Tap **Choose** on a deal. Choose is locked while a hold or a purchase approval is pending for that item.

**Fallback:** the Offline demo is already the fallback. If a live search fails, the worker uses the replay or sample data, both labeled.

## Step 5: Visa checkout
Merged (#40). **The demo checkout is the labeled simulation.** The real CyberSource sandbox charge has not succeeded: HTTP 502 `SYSTEM_ERROR`, request id `7928175635416253203813`, most likely because the sandbox account has no card processor enabled.

**How it behaves:** at or under the $100 threshold, the buy agent checks out right away. Over it, it asks first: the worker's approval summary reads `Pay $X to <merchant> for: <title>`, and the phone push reads "Moove: buy X USD: <deal title>".

**Tap (Offline demo):**
1. More > Approvals (or the Sofa in Shopping). The Sofa request is for $429.99 from wayfair, with Approve and Deny and the note "Over your approval limit. The agent pays with Visa only after you approve." The fixture's summary text uses an older wording ("Buy ... from wayfair for $429.99").
2. Tap **Approve**.
3. Spending shows the mattress as a Visa payment ($179.99, SIMULATED badge, rail "Visa").

**Terminal:**
```sh
VISA_PROVIDER=simulated npm run visa:demo -- 129.99
```
It prints `Visa checkout: SIMULATED`, the payment row, every agent event (`[SIMULATED]` hold, then capture) and the result, and exits 0 when the status is `captured`. The default amount without an argument is $42.50.

**Numbers:** Visa card cap $1,500 per agent, $750 max per purchase, approval threshold $100.

**Don't** demo `VISA_PROVIDER=acceptance` until a `npm run visa:demo -- 1.00` with real keys succeeds. On success it would show `[VISA SANDBOX]` events, a `[Visa sandbox]` purpose and a VISA SANDBOX badge.

**Fallback:** the simulated Visa rail, always labeled. If the worker isn't cooperating, `visa:demo` in the terminal shows the full hold, re-check and capture sequence on its own.

## Step 6: Summary
Merged (#31, restyled in #49). **Tap:** More > Summary.

**Judges see:** "Summary · N items", "Your move, handled.", counts by keep / sell / donate / trash, and a **Money** block with sold, still selling, spent and net, plus one line per rail ("x402 data payments", and "Visa purchases" once there are card payments). The Money block shows a **Simulated** tag whenever any money in it is simulated, so on the fixture it will show. Then the landfill line ("~N kg kept out of landfill") and agent activity. Exact figures depend on the fixture; read them off the screen rather than quoting numbers.

**Fallback:** it's Offline demo already. Nothing to fall back to.

## 30-second talk track
"Moving means pricing, selling and buying a whole household. Moove hands that to agents, and you stay in control. When our pricing agent needs comps, it pays for them itself: one cent in USDC over x402 on Base Sepolia, from a Coinbase server wallet. Here's the real transaction on basescan. A payment rail checks a per-agent budget and a per-call max before anything is signed, so a ten-cent cap means a twenty-five-cent request gets refused and logged. Every payment lands in a live spending log, and anything simulated is labeled. Big decisions come to you: a $410 listing needs your approval through Auth0 on your phone. The buy agent shops what the new place needs, recommends the best deal and, once you choose, checks out with Visa, re-checking your approval right before it captures. That checkout is simulated today, and it's labeled. The summary shows what you made, spent and kept out of the landfill."

Don't claim fraud screening: the fraud agent (#18) is pending, and the fraud scores on screen are fixture data. If asked about the sandbox, say our CyberSource sandbox account returned a 502 (most likely no card processor provisioned yet), so we demo the labeled simulation.

## Proof to cite (backup if live payment fails)
Both are real x402 payments of 0.01 USDC on Base Sepolia:
- https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c (from `npm run x402:demo`, block 49461682. It's also the Basescan link in the app's offline spending log.)
- https://sepolia.basescan.org/tx/0x9bf1f717c8901a4a5dfc137099cb4254e4dfd5d0b584873184b883924a8ff37d (from the local end-to-end test `npm run x402:e2e`, PR #48, which landed `payment` + `agent_event` rows in SpacetimeDB)

Payer: `0x3224220E5007e8F4c0440447bdfeb846c96f8A52` (agents' wallet). Payee: `0x6644b110FD0B1671599E36db749d09b1EAeEF952` (comps paywall receiver).

## If everything breaks
1. Phone: Offline demo. Every commerce screen works with no network.
2. Laptop: `X402_SIMULATE=1 npm run x402:demo`, labeled simulated.
3. Browser: the two basescan links above.
4. Say what's simulated. That's a track rule, and judges respect it.
