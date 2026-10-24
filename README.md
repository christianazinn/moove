# Moove

Moove is an iOS app that runs your move. Scan your room, and AI agents inventory, price and sort your stuff. They sell what you don't need, buy what the new place needs, and pay for things on your behalf with guardrails. Then everything you kept flies into a 3D model of your new home.

Built at Cal Hacks 13.0. Devpost draft: [`docs/devpost.md`](docs/devpost.md). Sponsor-track checklist: [`docs/tracks.md`](docs/tracks.md).

| Path | What |
|---|---|
| `ios/` | SwiftUI app (RoomPlan, RealityKit) + `MooveKit` Swift package (models, layout solver, summary math) |
| `spacetime/` | SpacetimeDB module (TypeScript): every table and reducer, the shared real-time state |
| `agents/` | Node/TS agent worker: Claude, Apify, x402/CDP, eBay sandbox, Auth0 CIBA, upload endpoint |
| `docs/` | Team plan, architecture, data model, task briefs, sponsor tracks, Devpost draft |

Team docs: [`docs/TEAM.md`](docs/TEAM.md), [`docs/architecture.md`](docs/architecture.md), [`docs/data-model.md`](docs/data-model.md).

## Architecture
```
iOS app (SwiftUI)  --subscribe + reducers-->  SpacetimeDB module  <--subscribe + reducers--  Agent worker (Node/TS)
 RoomPlan scan, review,                        tables = shared state                        vision, pricing, listing,
 spending log, approvals,  <--live updates--   reducers = every write   --live updates-->   approval agents; all
 new home 3D, summary                          (no outbound I/O)                            outbound I/O lives here
        |                                                                                          ^
        +---------------------------- photo / USDZ upload over HTTP -------------------------------+
```
- **SpacetimeDB is the system of record.** The app and the worker never talk to each other directly. The worker subscribes to rows that need work (an unpriced item, a sell item with no listing, a pending approval), does the work, and writes back through reducers. The app sees every change live.
- **Every agent step is a row.** Each plan, tool call, payment, refusal and error is an `agent_event` row, and each payment is a `payment` row, so the app can show exactly what the agents did and spent.
- **Guardrails live in the worker and the data.** There are per-agent spend caps and a per-call max on x402, a user approval threshold for listings (Auth0 CIBA push or the in-app inbox), and possibly sentimental items are never auto-decided. Anything simulated carries `simulated: true` in the data and a SIMULATED badge in the app.

## Status at a glance
| Flow | State on `main` |
|---|---|
| Photo -> item details (Claude vision) | Built (#5). |
| Pricing from Apify comps, paid for over x402 | Built (#6, #7). Real Base Sepolia settlement is proven by `npm run x402:demo`. Without CDP keys the pricing payments are labeled simulated. |
| Auto-sort keep/sell/donate/trash | **Not on `main`** (#8; rules-only agent in open PR #57). The reducer `set_auto_disposition` exists, but no agent on `main` calls it yet. Users set dispositions on the Review screen. |
| eBay listing | Built (#11, #32). Real sandbox posting needs the `EBAY_*` keys, and it has **not yet run against the real sandbox**. Otherwise listings are labeled simulated. |
| Approval for expensive listings | Built (#12). The Auth0 CIBA path is **not yet tested against a real tenant**. The in-app Approvals inbox always works. |
| Shopping list, buy agent, Visa checkout | **Open PR #40** (+ #52 live Apify deals). Not on `main`. The purchase-approval push text (#53) is on `main` but has nothing to approve until #40 lands. |
| iOS screens | Auth0 login (#25), Review, Spending, Approvals, Listings, New Home (3D floor plan + layouts + fly-in), Summary are on `main`. Scan -> inventory (#28) is an open PR. |
| iOS live sync | The SDK spike passed (`docs/decisions/0020-swift-spacetimedb-sdk.md`), but the table/reducer glue in `ios/Moove/Sync/SpacetimeBackend+Contract.swift` is still a stub (#10). Until it lands, screens run on the **Offline demo** backend (Settings). |
| Security pass | Built (#38): upload hardening + EXIF/GPS strip, prompt-injection fencing, x402 budgets that survive restarts, gitleaks over full history. Open items are listed in [`docs/security.md`](docs/security.md). |

## Sponsor tools used
Each integration is one file in `agents/src/integrations/` behind an interface, with a labeled simulated fallback.

### Coinbase x402 + CDP (Payment Agents)
- **Where:** `agents/src/integrations/x402.ts` (payment rail: `paidFetch`, budgets, signing), `agents/src/payments.ts` (writes `payment` + `agent_event` rows), `agents/src/paywall.ts` (the $0.01 `GET /x402/comps` paywall), `agents/src/integrations/paid-comps.ts` (the pricing agent buys its comps through it), `agents/scripts/x402-{wallet,demo,e2e}.ts`, and the iOS spending log `ios/Moove/Features/Spending/SpendingView.swift`.
- **Real:** `@coinbase/cdp-sdk` `CdpX402Client` signing from a CDP server wallet, `createX402Server` + `@x402/express`, and the CDP facilitator settling USDC on Base Sepolia. Proof tx: [basescan](https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c). Per-agent budget and per-call max are checked before signing.
- **Simulated / limits:** with no CDP keys (or `X402_SIMULATE=1`) payments are recorded with `simulated: true`. The data seller is our own paywall, so the money moves between two of our own testnet wallets. The in-app log runs on Offline demo data until #10 lands.
- **Full write-up** (diagram, controls, limitations, builder feedback): [`docs/coinbase-x402.md`](docs/coinbase-x402.md).

### SpacetimeDB
- **Where:** `spacetime/src/index.ts` (all tables and reducers; summarized in `docs/data-model.md`), the worker's client `agents/src/spacetime.ts` with generated bindings in `agents/src/module_bindings/`, and the iOS client `ios/Moove/Sync/` on the community Swift SDK `ekscrypto/spacetimedb-swift-sdk`.
- **Real:** it is the only backend. Agents coordinate through tables: vision finishes, then pricing picks the item up, then listing, then approval. Reducers authorize by `ctx.sender`, worker-only reducers check the `worker` table, and shared rooms use `join_room(code)`. The team DB is on maincloud.
- **Not done yet:** the iOS table mapping (#10), so two-phone live sync isn't demoable from `main` yet. The Swift spike itself (connect, subscribe, reducer calls, ~1.5 ms A->B update) passed.

### Apify
- **Where:** `agents/src/integrations/apify.ts` (comps), used by `agents/src/agents/pricing.ts`.
- **Actors:** `caffein.dev~ebay-sold-listings` (sold prices) and `apify~facebook-marketplace-scraper` (local asking prices). `ivanvs~craigslist-scraper` is optional (`APIFY_SOURCES`). Each run is capped with `maxItems` and `maxTotalChargeUsd`.
- **Real:** live runs through `run-sync-get-dataset-items` when `APIFY_TOKEN` is set. Every query is cached to `agents/fixtures/comps/`, and cache hits are labeled `[REPLAYED]` (the demo fallback). No cache files are committed yet.
- **Open PR #52 / #40:** live deal search for the buy agent (`apify~facebook-marketplace-scraper`, `ivanvs~craigslist-scraper-pay-per-result`, `automation-lab~ebay-scraper`). No published Actor of our own.

### Anthropic Claude
- **Where:** `agents/src/integrations/anthropic.ts` (`structuredCall`: zod-validated structured output, refusal fallbacks), `agents/src/agents/vision.ts` (`MODEL_VISION`: photos + LiDAR dimensions -> name, brand, material, condition, fragile, maybe-sentimental), `agents/src/agents/listing.ts` (`MODEL_AGENT`: listing copy, price clamped in code to 70-130% of the pricing estimate's range, or 50-150% of the comps' min/max when there's no estimate; `agents/src/agents/listingPrompt.ts`).
- **Design choices:** brands are named only with visible evidence. When unsure about sentimental value the model leans true, and those items always go to the user. The model never sets a final price on its own.
- **Prompt injection (#38):** scraped comps are cleaned and fenced as untrusted data (`agents/src/untrusted.ts`), and links/contact details are scrubbed from published copy. `npm run spotcheck:injection` is a live check (it calls Claude).
- **Open PR:** #40 (Claude drafts the new home's shopping list, with a rule-based fallback).

### Auth0
- **Where:** `agents/src/agents/approval.ts` + `agents/src/integrations/auth0.ts` (Auth0 for AI Agents async authorization / CIBA: `/bc-authorize`, Guardian push, poll `/oauth/token`, check `sub`, then `decide_approval`), and `ios/Moove/Features/Approvals/` (in-app inbox).
- **Built but not verified:** CIBA has only been tested against stubbed HTTP, not a real tenant. Without Auth0 config, approvals wait in the in-app inbox.
- **Login (#25):** Auth0 Web Auth (Universal Login) in the app (`ios/Moove/Features/Auth/`), with the ID token used as the SpacetimeDB connection token, plus a guest mode. On the live backend `register_user` still waits on #10.

### Visa (Reimagining Shopping)
- **Not on `main` yet.** Open PR #40 adds `agents/src/integrations/visa.ts`: an approval gate, a spend ledger, an auth-hold, a re-check, then capture or void. The `acceptance` backend targets the Visa Acceptance (CyberSource) REST **sandbox** with the public test card. `simulated` is the default without keys, and `vic` (Visa Intelligent Commerce) is a documented seam only. **No real sandbox call has been made** (no keys), so the demo checkout is labeled simulated.

### eBay (sandbox)
- **Where:** `agents/src/integrations/ebay.ts` (`sandboxEbay`: Sell Inventory API inventory item -> offer -> publish, category and required aspects picked from the live taxonomy) and `agents/scripts/ebay-setup.ts` (one-time seller setup).
- **Real vs simulated:** sandbox posting turns on only when every `EBAY_*` key is set, and it has not yet run against the real sandbox. Otherwise `simulatedEbay` logs the same steps and writes a labeled HTML mock listing. Listings carry `simulated` truthfully.

## Security & responsible AI
How we keep users' data and money safe: [`docs/security.md`](docs/security.md). It covers the threat model, what's built (EXIF-stripped uploads, code-enforced x402 spend caps, the approval amount binding, prompt-injection defenses with a spot check, and gitleaks over the full history), what's still open (with issues), and our responsible-AI choices. In short: agents propose, code enforces the limits, the user approves anything big, and anything simulated is labeled.

## Setup
Copy `.env.example` to `.env.local` at the repo root (gitignored). Every key is optional: a missing key switches that integration to its labeled simulated or cached path.

**SpacetimeDB module** (`spacetime/`; needs the CLI: `curl -sSf https://install.spacetimedb.com | sh`)
```sh
cd spacetime && npm ci && npm run typecheck
spacetime start                 # local server on :3000 (separate terminal)
npm run publish:local           # or publish:local:reset to wipe data
npm run generate                # regenerate agents/src/module_bindings after schema changes
```

**Agent worker** (`agents/`, Node 22+)
```sh
cd agents && npm ci && npm run typecheck && npm test
SPACETIME_URI=ws://localhost:3000 npm start      # or npm run dev; uploads on :8787
X402_SIMULATE=1 npm run x402:demo                # one paid comps call, no keys needed
```
More: `npm run x402:wallet -- --faucet`, `npm run x402:e2e`, `npm run ebay:setup -- check`. Each is described in [`agents/CLAUDE.md`](agents/CLAUDE.md).

**iOS app** (`ios/`; Xcode 26 / Swift 6.2+, a LiDAR device for real scans)
```sh
cd ios && cp Config/Local.xcconfig.example Config/Local.xcconfig   # signing team, server IP, Auth0 ids
xcodegen && open Moove.xcodeproj
cd MooveKit && swift test                                          # also runs on Linux
```
In the app, Settings -> **Offline demo** runs every screen on in-memory fixtures with no backend.
