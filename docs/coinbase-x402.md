# Moove x Coinbase: x402 payment agents

Submission notes for the Coinbase **Best Use of x402 / Payment Agents** track (Cal Hacks 13.0). The same text is pasted into Devpost.

Where each submission item is:
- **Summary:** the "Summary" section below.
- **Demo:** shot 5 of [`docs/demo-video.md`](demo-video.md) (the Spending screen, the Basescan link, a refused call), with the live runbook in [`docs/demo.md`](demo.md). The video is recorded Sunday morning.
- **Repo and setup:** https://github.com/christianazinn/moove, and the "Setup" section below.
- **Architecture diagram:** the "Architecture diagram" section below (Mermaid, plus an ASCII fallback).
- **Builder feedback:** the "Builder feedback" section at the end.

## Summary
**Who it's for.** People in the middle of a move. Pricing, selling, buying and paying for a whole household is hours of tedious work, so Moove hands it to agents. The user stays in control: they set the limits, approve anything big, and watch every cent the agents spend.

**What it does.** Moove is an iOS app. You scan your room and agents inventory, price and sort your stuff, then sell, buy and pay on your behalf. When an agent needs paid data (for example a premium comps report to price an item), it pays for it itself, per call, over **x402** with USDC on Base Sepolia. A payment rail sits between the agents and the wallet. It enforces a per-agent budget and a per-call max before anything is signed. Every step and every payment is written to SpacetimeDB, and the app shows them in a live spending log with a basescan link for each transaction. Before listing an item for sale, a safety agent can also pay a third-party x402 service from the CDP x402 Bazaar ($0.002 per lookup) to check the brand against US CPSC recalls, since selling a recalled product is illegal in the US.

**Coinbase tools used.**
- `@coinbase/cdp-sdk` 1.60.0
  - `CdpX402Client` is the buyer. It signs with a CDP server wallet (EOA) named `moove-agents`, and its `spendControls` are set as a backstop.
  - `createX402Server` is the seller. It paywalls our comps endpoint and provisions the receiver wallet.
  - `CdpClient.evm.requestFaucet` funds the wallet with testnet USDC.
  - `listTokenBalances` shows the wallet's balance.
- x402 v2 packages at 2.28.0: `@x402/core` (we use `x402HTTPClient` to drive the 402 flow by hand), `@x402/express` (`paymentMiddlewareFromHTTPServer`), plus `@x402/evm`, `@x402/svm` and `@x402/extensions`.
- The CDP facilitator verifies and settles payments on **Base Sepolia** (`eip155:84532`) in USDC (`0x036CbD53842c5426634e7929541eC2318f3dCF7e`).

## How it works
1. An agent (the pricing agent today, the buy agent later) calls `rail.paidFetch({ owner, agent, purpose, refTable, refId }, url)`.
2. The rail makes the request. If the server answers `402 Payment Required`, it decodes the payment requirements with `x402HTTPClient.getPaymentRequiredResponse`.
3. It keeps only options that pay **Base Sepolia USDC**, and picks the cheapest. A server offering anything else is refused and the refusal is logged.
4. **Before signing**, it reserves the amount in the agent's budget. The reservation fails if the amount is over the per-call max (`X402_MAX_PER_CALL_USDC`, default $0.10) or would push the agent past its cap (`AGENT_SPEND_CAP_USDC`, default $5). A refusal throws `SpendRefusedError` and writes an `agent_event` row with `refused: true`, and nothing is signed.
5. `CdpX402Client` signs only the option we budgeted for, using the `moove-agents` CDP wallet. The rail retries the request with the `PAYMENT-SIGNATURE` header.
6. The seller (`createX402Server` + `@x402/express`) has the CDP facilitator verify and settle the payment on Base Sepolia, then returns the data with a `PAYMENT-RESPONSE` header.
7. The rail decodes the settlement (`getPaymentSettleResponse`) to get the **tx hash**, writes a `payment` row (`rail=x402`, amount, payee, txHash, status, `simulated`), and writes a `payment` agent event with the basescan link. If anything fails, it releases the reservation and logs an `error` event.
8. The iOS app subscribes to the `payment` and `agent_event` tables, so the spending log updates live (PR #36).

We drive the 402 flow by hand instead of using `wrapFetchWithPayment`. That way every call carries its agent and purpose, and our budget check happens before signing. The client-wide SDK hooks can't do either per request.

The comps endpoint (`GET /x402/comps?q=...`, $0.01) is hosted by our own worker code (`agents/src/paywall.ts`, served on `127.0.0.1:8402` by `agents/src/integrations/paid-comps.ts`) and backed by the Apify comps lookup, so the payment flow is real end to end. **The pricing agent buys every item's comps from it** (PRs #37, #46): each pricing run is one $0.01 x402 payment and one `payment` row. Payments never block pricing. If the rail refuses (over budget) or the paid call fails, pricing logs the fallback and calls Apify directly (unpaid). If the paywall can't start at all (port taken, CDP outage), the worker logs it and keeps pricing on direct lookups. `PRICING_PAY_X402=0` turns the paid path off. It pays from `0x3224220E5007e8F4c0440447bdfeb846c96f8A52` (the agents' wallet) to `0x6644b110FD0B1671599E36db749d09b1EAeEF952` (our receiver wallet).

**A third-party x402 service: CPSC recall check.** Before the listing agent drafts a listing, the `safety` agent pays `GET https://api.stablecoingateways.com/v1/recalls?q=<brand>&source=cpsc`, a product recall service listed in the CDP x402 Bazaar that we don't run. It costs $0.002 (2000 atomic USDC) on Base Sepolia, paid to `0x3177FA489523ddF60f293898f7Ee5912576f3d9b`. The service's 402 also offers Base mainnet and XRPL; the rail picks the Base Sepolia USDC option and signs only that one (a test checks it with the service's real `accepts`). It goes through the same `paidFetch`, so the safety agent has its own budget, the per-call max applies, and `X402_ALLOWED_PAYEES` refuses it unless that address is on the list. The service is a keyword search of CPSC product text that returns at most 10 recalls, so we search the brand and match the item's name words against titles and product names in the worker. A probable match logs `Possible CPSC recall for "...": <title> (#<recall number>)` and makes the listing ask for approval whatever its price, with the recall in the approval summary. No match logs `No CPSC recalls match "..."`. Unbranded items are skipped, and each brand is paid for once (cached in memory and in `agents/.cache/recalls/`). A refusal, a non-2xx answer, a timeout (15 s) or a body we can't read logs one event and the listing goes ahead. It's off unless `RECALL_CHECK_X402=1` (`agents/src/integrations/recalls.ts`, called from `agents/src/agents/listing.ts`). On the simulated rail nothing can be paid, so the service answers 402 and the check logs `[SIMULATED] ... unavailable`.

## Architecture diagram
```mermaid
flowchart LR
  subgraph Phone["iOS app (SwiftUI)"]
    UI["Spending log<br/>amount, agent, purpose,<br/>basescan link, budget left,<br/>SIMULATED badge"]
  end

  STDB[("SpacetimeDB<br/>payment + agent_event tables")]

  subgraph Worker["Agent worker (Node/TS)"]
    Agents["Pricing agent<br/>Safety agent (recall check)"]
    Rail["x402 rail: paidFetch<br/>Base Sepolia USDC only<br/>per-agent budget + per-call max<br/>reserve / release"]
    Signer["CdpX402Client<br/>spendControls backstop"]
    Paywall["GET /x402/comps ($0.01)<br/>createX402Server +<br/>@x402/express"]
  end

  Wallet["CDP server wallet<br/>moove-agents (EOA)"]
  Facilitator["CDP x402 facilitator"]
  Chain[("Base Sepolia<br/>USDC")]

  UI -- "subscribe" --> STDB
  Agents -- "paidFetch(agent, purpose, url)" --> Rail
  Rail -- "1. GET, gets 402 + requirements" --> Paywall
  Rail -- "2. budget OK: sign" --> Signer
  Signer -- "sign payment" --> Wallet
  Rail -- "3. retry with PAYMENT-SIGNATURE" --> Paywall
  Paywall -- "verify + settle" --> Facilitator
  Facilitator -- "USDC transfer" --> Chain
  Paywall -- "4. data + PAYMENT-RESPONSE (tx hash)" --> Rail
  Rail -- "same flow, $0.002" --> Recalls["Third-party recall service<br/>api.stablecoingateways.com"]
  Recalls -- "settle (their facilitator)" --> Chain
  Rail -- "record_payment + log_agent_event" --> STDB
```

ASCII fallback:
```
iOS app (spending log) <--live subscription-- SpacetimeDB (payment, agent_event)
                                                   ^
                                                   | record_payment / log_agent_event
Agent worker                                       |
  pricing agent --paidFetch--> x402 rail ----------+
                                 |  ^  (1) GET -> 402 + requirements
     (2) budget + per-call check |  |  (4) 200 + PAYMENT-RESPONSE (tx hash)
         then sign               v  |
  CdpX402Client -> CDP wallet  GET /x402/comps ($0.01, createX402Server)
  "moove-agents"                     | (3) verify + settle
                                     v
                        CDP facilitator --> Base Sepolia USDC
```

## Controls
- **Spend caps, enforced before signing.** There's a per-agent budget (`AGENT_SPEND_CAP_USDC`, default $5) and a per-call max (`X402_MAX_PER_CALL_USDC`, default $0.10). Amounts are reserved before signing and released on failure, so concurrent calls from one agent can't overspend (there's a test for this). Over-cap calls are refused and logged as `agent_event` rows that the app shows. A bad cap value (say `5usd` or a negative number) logs a warning and falls back to the default instead of breaking the rail (#143, `agents/src/integrations/caps.ts`). Budgets survive a restart: at startup the worker counts the last 24h of x402 `payment` rows against each agent (`agents/src/payments.ts`).
- **Our own API spend is capped too.** Live Claude calls stop at `CLAUDE_MAX_USD_PER_DAY` (default $3, #169), and live Apify runs (comps, the buy agent's deal search and Google Lens lookups) share `APIFY_MAX_USD_PER_DAY` (default $5, #170, #210, #294). The worker publishes today's spend against both caps in `service_config.spend_today` (#220), and the app's Settings shows it (#232).
- **Asset, network and payee allowlist.** The rail only pays USDC on Base Sepolia, and with `X402_ALLOWED_PAYEES` set (comma-separated) it refuses any `payTo` outside the list. A third-party payee has to be added by hand: with only our own receiver listed, the recall check was refused before signing and the listing went ahead (checked against the real service). The SDK's `spendControls` (per-payment max, a 24h cumulative cap, allowed networks and assets) sit underneath as a backstop.
- **Human approval for big spends.** Purchases or listings above the user's `approvalThresholdCents` create an `approval` row and need an Auth0 async authorization (CIBA) on the phone, or a tap in the in-app inbox, first (task #12). An approval nobody answers expires after `APPROVAL_EXPIRE_HOURS` (default 12) and is asked again at most `APPROVAL_MAX_REASKS` (2) times (#186, #199, #214; `agents/src/agents/approval-expiry.ts`). Room members may decide listing approvals, but purchases spend the owner's money and stay owner-only (#200, #239, #248; `decide_approval` in `spacetime/src/index.ts`). x402 data calls stay far below the threshold, and the per-call max keeps them there.
- **Simulated labeling.** With no CDP keys, or with `X402_SIMULATE=1`, the rail signs nothing. Every `payment` row has `simulated: true`, every event message starts with `[SIMULATED]` (#154), and the app shows a SIMULATED badge. Simulated payments are never shown as real.
- **Checked on every PR.** `npm run e2e -- --replay` (22 stages, #133) runs the worker on a local SpacetimeDB with a $0.05 budget and checks that pricing calls past it are refused before anything is signed, and that every rail event is labeled `[SIMULATED]` (`agents/scripts/e2e.ts`). It makes no paid calls, and the worker refuses `LLM_REPLAY` against maincloud (#157). CI also taps through Sell & Buy, Spending included, in an iOS Simulator on the Offline demo (#155; it runs when a PR touches `ios/` and on pushes to `main`).
- **Keys in env only.** CDP keys live in the gitignored `.env.local` or in the worker's environment, never in git. CI runs gitleaks. The wallet is a CDP server wallet, so its private keys never touch our machines.
- **Full audit trail.** Every step (tool call, payment, refusal, error) is an `agent_event` row, and every payment is a `payment` row with its tx hash.

## Setup
Requires Node 22+ and a CDP API key and wallet secret from https://portal.cdp.coinbase.com.

```sh
cd agents && npm ci
npm test                           # all worker tests, incl. the x402 rail: caps, refusals, concurrency, settlement, simulated mode
X402_SIMULATE=1 npm run x402:demo  # one paid comps call on the simulated rail (no keys needed)
```

For real testnet payments, copy `.env.example` to `.env.local` at the repo root and fill in:
```
CDP_API_KEY_ID=...
CDP_API_KEY_SECRET=...
CDP_WALLET_SECRET=...
AGENT_SPEND_CAP_USDC=5
X402_MAX_PER_CALL_USDC=0.10
X402_ALLOWED_PAYEES=           # optional payTo allowlist (empty = any address, still capped)
X402_SEED_BUDGETS=1            # count the last 24h of payments against each budget at startup (0 = start at zero)
PRICING_PAY_X402=1             # pricing buys comps over x402 (0 = direct Apify lookups)
RECALL_CHECK_X402=             # 1 = CPSC recall check before listing ($0.002 per brand, third-party service)
# With X402_ALLOWED_PAYEES set, add the recall service's payee or the check is refused:
# X402_ALLOWED_PAYEES=0x6644b110FD0B1671599E36db749d09b1EAeEF952,0x3177FA489523ddF60f293898f7Ee5912576f3d9b
```
Then, from `agents/`:
```sh
npm run x402:wallet -- --faucet    # creates/loads the moove-agents wallet, funds it with testnet USDC, prints balances
npm run x402:demo                  # starts the paywalled comps endpoint, pays it over x402, prints the basescan link
npm run x402:recall -- "IKEA Malm dresser"   # one paid CPSC recall check (brand IKEA) on the third-party service, prints the tx
npm start                          # the worker: the pricing agent now pays $0.01 per item for comps over the same rail
```

To reuse the rail in another project, copy `agents/src/integrations/x402.ts` and implement `PaymentSink` (two methods: `recordPayment` and `logAgentEvent`) for your own storage. `agents/src/payments.ts` is our SpacetimeDB version.

## Proof
A real x402 payment of 0.01 USDC from the agents' CDP wallet to the comps paywall settled on Base Sepolia in block 49461682:
https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c

That payment was made by `npm run x402:demo`. A second one came from the local end-to-end run `npm run x402:e2e` (PR #48), which landed its `payment` and `agent_event` rows in SpacetimeDB:
https://sepolia.basescan.org/tx/0x9bf1f717c8901a4a5dfc137099cb4254e4dfd5d0b584873184b883924a8ff37d

Three payments of 0.002 USDC to the third-party recall service (`0x3177FA48…3d9b`), made with `npm run x402:recall` on Sat Oct 24 around 2:30 PM PDT. Each receipt shows a USDC `Transfer` of 2000 from `0x3224…8A52` to `0x3177…3d9b`. The script prints to the console and writes nothing to SpacetimeDB, so these have no `payment` rows:
- query "IKEA Malm dresser" (before we switched to brand queries), 0 results: [0xc7796f5e…](https://sepolia.basescan.org/tx/0xc7796f5e865543d7d19cef92a70c66c730c692237aa0dc86e8b83ccb81a2196f)
- query "IKEA", 10 recalls back (garlic presses, LETTAN mirrors, ODGER chairs, ...), none for a MALM dresser, so no match: [0x5baa6d3c…](https://sepolia.basescan.org/tx/0x5baa6d3c87ddc3078788fe9b5a3779ef0b82aa35d9a04ecca5c102c9932ad643)
- query "Peloton" for a "Tread treadmill", 3 recalls back (all bikes and pedals), no match: [0x59daacf9…](https://sepolia.basescan.org/tx/0x59daacf9080118ba5db3a3e021b79ef2f214ae2911991db0f6aa4a32cca3b1d4)

The pricing agent's payments in the worker go through the same rail and paywall, and with CDP keys each one lands as a `payment` row with its tx hash, shown in the app's spending log. The hosted worker has CDP keys since Sat Oct 24 ~12:40 PM PDT, so its new x402 rows are real; earlier rows stay simulated (see "Known limitations").

## Known limitations
- **Testnet only** (Base Sepolia, testnet USDC).
- **The hosted worker pays for real since Sat Oct 24, ~12:40 PM PDT.** CDP keys are on the worker that serves the Live and Demo databases, so new pricing lookups settle $0.01 USDC on Base Sepolia from the `moove-agents` wallet (`0x3224…8A52`), and their rows are `simulated: false` with a tx hash (first one on Demo: [tx](https://sepolia.basescan.org/tx/0x698e3721c1df84e3c183ec2bfebca3037c26fc511b9c513c7f94064be2f03031)). Rows written before then stay labeled simulated. A joined phone's Spending shows only that phone's own payments, so to see real rows in the app, scan on Live or use the owner's phone. The Offline demo's spending log also carries a real $0.01 row with its Basescan link. CI's e2e still forces `X402_SIMULATE=1`.
- **One shared wallet for all agents.** Per-agent budgets are enforced in the worker process, not on-chain. A bug in the worker could bypass them. Only the SDK `spendControls` backstop would still apply.
- **Budgets are tracked in the worker.** The spend ledger lives in memory. On startup it is seeded from the last 24h of `payment` rows (`X402_SEED_BUDGETS=1`, the default), so a restart doesn't reset an agent's budget, but the window is rolling rather than a fixed period.
- **The comps endpoint is our own paywall.** The money for comps goes between two of our own wallets. The recall check pays a third party, but it's off by default (`RECALL_CHECK_X402=1`), and the hosted worker also needs `0x3177FA489523ddF60f293898f7Ee5912576f3d9b` added to its `X402_ALLOWED_PAYEES`. Until both are set there, its real payments are only the three script runs in "Proof".
- **The recall match is a heuristic.** The service returns at most 10 recalls per query, newest first, so a brand with many recalls can hide an older one: "IKEA" doesn't return the 2016 MALM tip-over recall. A match needs the brand plus one name word, so it can also flag the wrong model. A match only asks the user; it never blocks a sale by itself. The app has no recall-specific screen; the result is an `agent_event` and, on a match, the approval summary.
- **Pricing and the safety check are the only agents that pay over x402.** Pricing buys its comps through the paywall (#46). If a payment fails it falls back to a direct (unpaid) Apify lookup, so not every pricing run is guaranteed to produce a payment. The buy agent doesn't use the rail yet.
- **The live spending log is unverified on device.** Since PR #28 the app subscribes to `payment` and `agent_event` for the signed-in identity, so worker payments should appear live; nobody has checked it on a phone against the maincloud worker yet. The Offline demo (fixture data, including the real Basescan link) is the fallback, and CI opens its Spending screen in a Simulator (#155). `npm run e2e` checks the worker side on a local SpacetimeDB (with a $0.05 budget, 5 of the 9 demo items get a simulated x402 `payment` row and the rest are refused and priced with a direct lookup).
- **Joined room members see the room's x402 payments** (decision 0254). The `my_payment` / `my_agent_event` views (#305, live on both maincloud DBs) add the pricing agent's comps payments and agent steps for shared items, and the app shows them under Spending → Shared room (#256). Purchase payments stay owner-only.

## Builder feedback
**Biggest blocker: installing and type-checking the CDP x402 packages.**
1. `@coinbase/cdp-sdk/x402` imports `@x402/evm`, `@x402/svm` and `@x402/extensions` at runtime, but they are declared as *optional* peer dependencies. A plain `npm install @coinbase/cdp-sdk` crashes on import with `ERR_MODULE_NOT_FOUND`. **Workaround:** install all of them explicitly (as the quickstart does) and pin them to the same version (2.28.0).
2. The cdp-sdk package has no `"type": "module"`, so TypeScript resolves `@x402/core`'s CJS declarations through cdp-sdk's `.d.ts`, while `@x402/express` gets the ESM declarations. The `X402Server` from `createX402Server` is then "not assignable" to `x402HTTPResourceServer` (two declarations of the same private member). **Workaround:** one commented cast in `agents/src/paywall.ts`, because it's the same class at runtime.

**Other friction, in order of pain:**

3. The docs don't say how a buyer gets the settlement result or tx hash. The quickstarts only check the HTTP status. We found `decodePaymentResponseHeader`, `x402HTTPClient.getPaymentSettleResponse` and the `PAYMENT-RESPONSE` header by reading the type definitions.
4. The README and our brief pointed to `x402-fetch` (v1, stale since April), while v2 is `@x402/*`. Package naming across v1 and v2 is confusing.
5. Client hooks like `onBeforePaymentCreation` apply to the whole client, not per request, so per-agent budgets meant driving the 402 flow by hand.
6. The server-side `createX402Server` registers the Bazaar discovery extension automatically, and it logs a rejection for every non-HTTPS (localhost) resource. That's noisy in development.
7. The CDP policy engine can't cap x402 amounts, and its USD limit is ignored on testnet, so spend caps have to live in the app.

**The missing capability we want most:** per-request spend context and limits in the SDK. That means a budget per agent or sub-account with built-in reserve and release, plus a first-class `paidFetch` that returns the settlement and tx hash along with the response. Our ~450-line rail (`agents/src/integrations/x402.ts`) is basically that, and every multi-agent app will need to write it again.
