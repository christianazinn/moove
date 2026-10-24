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
 RoomPlan scan, review,                        tables = shared state                        vision, sweep, pricing,
 spending log, approvals,  <--live updates--   reducers = every write   --live updates-->   sort, listing, approval,
 new home 3D, summary                          (no outbound I/O)                            shopping, buy, fraud;
                                                                                            all outbound I/O here
        |                                                                                          ^
        +---------------------------- photo / USDZ upload over HTTP -------------------------------+
```
- **SpacetimeDB is the system of record.** The app and the worker never talk to each other directly. The worker subscribes to rows that need work (an unpriced item, a sell item with no listing, a pending approval), does the work, and writes back through reducers. The app sees every change live.
- **Every agent step is a row.** Each plan, tool call, payment, refusal and error is an `agent_event` row, and each payment is a `payment` row, so the app can show exactly what the agents did and spent.
- **Guardrails live in the worker and the data.** There are per-agent spend caps and a per-call max on x402, a user approval threshold for listings (Auth0 CIBA push or the in-app inbox), and possibly sentimental items are never auto-decided. Anything simulated carries `simulated: true` in the data and a SIMULATED badge in the app.

## Status at a glance
_Checked against `main` on Sat Oct 24, ~01:00. "Simulated" rows are labeled as such in the data (`simulated: true`) and in the app._

| Flow | State on `main` |
|---|---|
| Photo → item details (Claude vision) | Built (#5). Runs on items that have a photo. |
| Room photo sweep (fix "other" and missed items) | Built (#92): a few wide room photos → one Claude vision call names RoomPlan's boxes and adds what it missed. The iOS capture step is not on `main` yet. |
| Pricing from Apify comps, paid for over x402 | Built (#6, #7, #46): Apify eBay-sold + FB Marketplace comps, rules + Haiku relevance filter (#62), queue under Apify's concurrency limit (#107). Real Base Sepolia settlement is proven by `npm run x402:demo`. The live worker has no CDP keys, so its payments are **labeled simulated**. |
| Auto-sort keep/sell/donate/trash | Built (#8, rules only, no model calls). Never overrides a user's choice; possibly sentimental items are left to the user. |
| eBay listing | Built (#11, #32). Real sandbox posting needs the `EBAY_*` keys, which aren't on the live worker, so listings are **labeled simulated**. |
| Approval for expensive listings and purchases | Built (#12, #53, #58), with the approval rules enforced in the database contract (#42). The Auth0 CIBA push is **not tested against a real tenant**. The in-app Approvals inbox always works. |
| Shopping list, buy agent, Visa checkout | Built (#15, #40): Claude drafts the new home's shopping list and the buy agent finds deals (replayed live-deal fixtures, #74). The demo checkout is the **labeled simulation** (`VISA_PROVIDER=simulated`, see [`docs/demo-commerce.md`](docs/demo-commerce.md)). |
| Fraud screening for deals | Built (#18): price outliers, off-platform/scam wording, new-seller signals, duplicate listings. AI-text detection is a hook (`PANGRAM_URL`) and is off unless configured. |
| New home | Built: 3D floor plan from a demo house (#13), layouts + fly-in (#14), truck and packing plan (#19). Voxel item models are the 3D look ([#108](https://github.com/christianazinn/moove/issues/108), in progress). Import from a listing link is #89 (in progress). |
| iOS screens | On `main`: Auth0 login (#25), Review (#9), Spending (#36), Approvals, Listings, Shopping, New Home, Pack, Summary (#16), app-wide theme (#50). |
| **iOS live data (scan → inventory)** | **Wired on `main` (#28)**: RoomPlan capture plus `ios/Moove/Sync/SpacetimeBackend+Contract.swift` mapping every table (including `payment` and `agent_event` for the spending log). Checked against a local server, **not yet verified on a device**. Two-phone share / join is open PR #78. The **Offline demo** backend (Settings → Data source) still works as the fallback. |
| Shared database | SpacetimeDB maincloud `moove`: 16 tables, per-user views `my_room` / `my_user` (#97). The connection gate is built but off until the app always signs in (#41). |
| Worker hosting | Runs on a laptop behind a Cloudflare quick tunnel under an auto-restart supervisor (#99). A Docker/DO/Fly deploy is prepared (#60, [`docs/deploy.md`](docs/deploy.md)) but not deployed. |
| Security | Built (#38, #68): upload hardening + EXIF/GPS strip, SSRF-safe photo fetching, prompt-injection fencing, approval separation, pinned worker identity, x402 budgets that survive restarts, gitleaks over full history. Open items: [`docs/security.md`](docs/security.md). |

## Sponsor tools used
Each integration is one file in `agents/src/integrations/` behind an interface, with a labeled simulated fallback.

### Coinbase x402 + CDP (Payment Agents)
- **Where:** `agents/src/integrations/x402.ts` (payment rail: `paidFetch`, budgets, signing), `agents/src/payments.ts` (writes `payment` + `agent_event` rows), `agents/src/paywall.ts` (the $0.01 `GET /x402/comps` paywall), `agents/src/integrations/paid-comps.ts` (the pricing agent buys its comps through it), `agents/scripts/x402-{wallet,demo,e2e}.ts`, and the iOS spending log `ios/Moove/Features/Spending/SpendingView.swift`.
- **Real:** `@coinbase/cdp-sdk` `CdpX402Client` signing from a CDP server wallet, `createX402Server` + `@x402/express`, and the CDP facilitator settling USDC on Base Sepolia. Proof tx: [basescan](https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c). Per-agent budget and per-call max are checked before signing.
- **Simulated / limits:** with no CDP keys (or `X402_SIMULATE=1`) payments are recorded with `simulated: true`. The data seller is our own paywall, so the money moves between two of our own testnet wallets. The in-app log is wired to the live backend (#28), pending verification on a device.
- **Full write-up** (diagram, controls, limitations, builder feedback): [`docs/coinbase-x402.md`](docs/coinbase-x402.md).

### SpacetimeDB
- **Where:** `spacetime/src/index.ts` (all tables and reducers; summarized in `docs/data-model.md`), the worker's client `agents/src/spacetime.ts` with generated bindings in `agents/src/module_bindings/`, and the iOS client `ios/Moove/Sync/` on the community Swift SDK `ekscrypto/spacetimedb-swift-sdk`.
- **Real:** it is the only backend. Agents coordinate through tables: vision finishes, then pricing picks the item up, then listing, then approval. Reducers authorize by `ctx.sender`, worker-only reducers check the `worker` table, and shared rooms use `join_room(code)`. The team DB is on maincloud.
- **Not done yet:** the iOS table mapping is on `main` (#28) but not yet verified on a device, and two-phone share / join is open PR #78 (#10). The Swift spike itself (connect, subscribe, reducer calls, ~1.5 ms A->B update) passed.

### Apify
- **Where:** `agents/src/integrations/apify.ts` (comps), used by `agents/src/agents/pricing.ts`.
- **Actors:** `caffein.dev~ebay-sold-listings` (sold prices) and `apify~facebook-marketplace-scraper` (local asking prices). `ivanvs~craigslist-scraper` is optional (`APIFY_SOURCES`). Each run is capped with `maxItems` and `maxTotalChargeUsd`.
- **Real:** live runs through `run-sync-get-dataset-items` when `APIFY_TOKEN` is set. Every query is cached to `agents/fixtures/comps/`, and cache hits are labeled `[REPLAYED]` (the demo fallback; real caches for the demo items are committed, #61). Lookups are queued under the free plan's 5-concurrent-run limit (#107).
- **Buy agent (#40):** live deal search in `agents/src/integrations/deals-apify.ts` (`apify~facebook-marketplace-scraper`, `ivanvs~craigslist-scraper-pay-per-result`, `automation-lab~ebay-scraper`) when `APIFY_TOKEN` is set, otherwise labeled replays of real live searches for every demo item (`agents/fixtures/deals-live-*.json`, #74, #79). No published Actor of our own.

### Anthropic Claude
- **Where:** `agents/src/integrations/anthropic.ts` (`structuredCall`: zod-validated structured output, refusal fallbacks), `agents/src/agents/vision.ts` (`MODEL_VISION`: photos + LiDAR dimensions -> name, brand, material, condition, fragile, maybe-sentimental), `agents/src/agents/listing.ts` (`MODEL_AGENT`: listing copy, price clamped in code to 70-130% of the pricing estimate's range, or 50-150% of the comps' min/max when there's no estimate; `agents/src/agents/listingPrompt.ts`).
- **Design choices:** brands are named only with visible evidence. When unsure about sentimental value the model leans true, and those items always go to the user. The model never sets a final price on its own.
- **Prompt injection (#38):** scraped comps are cleaned and fenced as untrusted data (`agents/src/untrusted.ts`), and links/contact details are scrubbed from published copy. `npm run spotcheck:injection` is a live check (it calls Claude).
- **Shopping list (#40):** Claude (`MODEL_AGENT`) drafts what the new home still needs, minus kept items, with a rule-based fallback.
- **Room photo sweep (#92):** `agents/src/agents/sweep.ts` (`MODEL_VISION`): a few room photos plus the scan's object list → better names for RoomPlan's boxes and items it missed. Output is vetted in code (invented ids, low confidence and duplicates dropped, sizes bounded, strings cleaned).

### Auth0
- **Where:** `agents/src/agents/approval.ts` + `agents/src/integrations/auth0.ts` (Auth0 for AI Agents async authorization / CIBA: `/bc-authorize`, Guardian push, poll `/oauth/token`, check `sub`, then `decide_approval`), and `ios/Moove/Features/Approvals/` (in-app inbox).
- **Built but not verified:** CIBA has only been tested against stubbed HTTP, not a real tenant. Without Auth0 config, approvals wait in the in-app inbox.
- **Login (#25):** Auth0 Web Auth (Universal Login) in the app (`ios/Moove/Features/Auth/`), with the ID token used as the SpacetimeDB connection token, plus a guest mode. On the live backend, `register_user` is wired (#28) but not yet demoed on a phone.

### Visa (Reimagining Shopping)
- **Built (#40):** `agents/src/integrations/visa.ts`: an approval gate, a spend ledger, an auth-hold, a re-check, then capture or void. The `acceptance` backend targets the Visa Acceptance (CyberSource) REST **sandbox** with the public test card. `simulated` is the default without keys, and `vic` (Visa Intelligent Commerce) is a documented seam only. **No real sandbox call has been made** (no keys), so the demo checkout is labeled simulated.

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
