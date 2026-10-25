# Sponsor tracks: requirements & submission checklist

Source: the Cal Hacks 13.0 Hacker Guide and the live prizes page (local copies are gitignored). Starter packs are posted on the live site. **Devpost may cap how many tracks we can select. Priority order: Coinbase > Spacetime > Apify > Visa > Anthropic > Auth0.**

## Tier 1
**Coinbase: Best Use of x402, Payment Agents track** ($500 USDC per member, plus a recruiter call)
- Use Coinbase for Agents (MCP / CDP) + x402. Docs: https://docs.cdp.coinbase.com/ai-agents/overview, https://docs.cdp.coinbase.com/x402/welcome. Keys: portal.cdp.coinbase.com
- **Every member needs a verified Coinbase account** (US/Canada, 18+).
  - [ ] Each member confirms their account is verified (not trackable from the repo; check before submitting).
- Judged on usefulness, technical design, ease of reuse, and product feedback. Not judged on code volume or money spent. Real money is not required. **Label simulated actions**, keep credentials private, and don't manage other people's funds.
- Submit:
  - [x] project summary (who it's for, what it does, which Coinbase tools)
  - [ ] demo + repo with setup instructions (repo + setup done in the doc below, and pricing now pays over x402 since #46. The live in-app log is wired: #28 maps `payment` and `agent_event` into the live iOS backend (`ios/Moove/Sync/SpacetimeBackend+Contract.swift`), pending verification on a device. Every simulated x402 step is labeled `[SIMULATED]` (#154), and the e2e test in CI shows calls past the budget refused before paying (#133). Budgets survive restarts (`agents/src/payments.ts`), and bad cap values fall back to the defaults (#143). Since Saturday the demo worker has CDP keys, so new pricing lookups settle on Base Sepolia ([tx](https://sepolia.basescan.org/tx/0x698e3721c1df84e3c183ec2bfebca3037c26fc511b9c513c7f94064be2f03031)). Earlier rows stay labeled simulated, and more proof txs are in the doc's "Proof" section. Since #318 a `safety` agent can also pay a third-party x402 service (a $0.002 CPSC recall check) before an item is listed. It's opt-in (`RECALL_CHECK_X402=1`, plus its payee in `X402_ALLOWED_PAYEES`) and not on the hosted worker yet; its three real Base Sepolia txs came from `npm run x402:recall`. The demo shot is written (shot 5 of [`docs/demo-video.md`](demo-video.md)). Still missing: the recorded demo video)
  - [x] **architecture diagram**, controls and known limitations (whole-app security controls: [`docs/security.md`](security.md))
  - [x] **builder feedback** (biggest blocker, how we worked around it, the missing capability we want most)

  **Devpost block (paste from [`docs/coinbase-x402.md`](coinbase-x402.md)):**
  - *Summary:* Moove's agents pay for the data they need (e.g. a $0.01 premium comps report to price an item) per call over x402, in USDC on Base Sepolia, from a CDP server wallet. A payment rail enforces a per-agent budget and a per-call max before anything is signed, and every payment shows up live in the iOS spending log with a basescan link. Before listing an item, a safety agent can pay a third-party Bazaar service ($0.002) for a CPSC recall check on its brand. Coinbase tools: `@coinbase/cdp-sdk` (`CdpX402Client`, `createX402Server`, faucet), `@x402/*` v2, the CDP facilitator.
  - *Repo + setup:* https://github.com/christianazinn/moove, see "Setup" in `docs/coinbase-x402.md` (`cd agents && npm ci`, `npm test`, `npm run x402:wallet -- --faucet`, `npm run x402:demo`).
  - *Architecture, controls, limitations:* the Mermaid diagram, "Controls" and "Known limitations" sections of the doc.
  - *Proof:* 0.01 USDC settled on Base Sepolia: https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c
  - *Builder feedback:* the "Builder feedback" section of the doc (optional peer deps crash on import, CJS/ESM type split, settlement/tx hash undocumented for buyers, missing per-request spend context).

**Spacetime** (prize TBD)
- SpacetimeDB must be the core real-time backend, used meaningfully and not as an add-on. They like live shared state, agent coordination, marketplaces and live dashboards.
- [ ] Demo the two-phone live sync and the live spending log, and show the agents coordinating through tables.
  - Agents coordinating through tables: **done on the worker side** (vision -> pricing -> listing -> approval, each step an `agent_event` row; `spacetime/src/index.ts`).
  - Live data in the app, including the spending log: **wired on `main`** (#28). `ios/Moove/Sync/SpacetimeBackend+Contract.swift` subscribes per identity and maps every table, including `payment`, `agent_event`, `shopping_item` and `deal`. Live updates were checked against a local server, not yet on a device.
  - Two-phone live sync: share / join a room is on `main` (#78, #10). Not yet tested on two phones.

**Apify** ($5k pool for the top 5, plus $400 Best Actor)
- Use Apify meaningfully. Best Actor means building and publishing an Actor during the event (stretch: a "moving comps" Actor).
- [x] Name the Actors in the README (done: `caffein.dev~ebay-sold-listings`, `apify~facebook-marketplace-scraper`, optional `ivanvs~craigslist-scraper`; plus the buy agent's deal search in `agents/src/integrations/deals-apify.ts` (#40): `apify~facebook-marketplace-scraper`, `ivanvs~craigslist-scraper-pay-per-result`, `automation-lab~ebay-scraper`; plus `zen-studio~google-lens-visual-search` for the vision agent's reverse image search on unsure items, `agents/src/integrations/lens.ts`, #294).
- [ ] Show live scraping in the demo. The pricing agent runs live when `APIFY_TOKEN` is set and replays labeled caches otherwise. Real caches for the demo items are committed: comps in `agents/fixtures/comps/` (#61, #63) and live deal searches for every demo shopping item in `agents/fixtures/deals-live-*.json` (#74, #79). Apify has credit again (new key; the hosted worker's daily cap is raised to $20). Lookups check the cache first: a query with a committed real cache replays it (`[REPLAYED]`), and a new query scrapes live when `APIFY_TOKEN` is set and the daily cap allows. When a live run can't go ahead (capped, out of credit or failed), an item with no exact cache uses a similar item's real comps, labeled `[REPLAYED, similar item "…"]` (#303, #321). A live scrape on stage needs an item whose query isn't cached yet.
- Best Actor: not entering (no Actor published).

**Visa: Reimagining Shopping** ($5,000)
- Judged on innovation 25%, UX 25%, technical execution 20%, commerce impact 15%, trust & responsibility 15%.
- [ ] Use the Visa Starter Pack tooling for checkout (#15). Built (#40): Visa Acceptance (CyberSource) REST sandbox backend, tested against a fake server. CyberSource's sandbox calls (keys in place) fail with HTTP 502 SYSTEM_ERROR, a merchant setup problem (#15). So the hosted worker uses the Authorize.net sandbox backend (a Visa Acceptance product, #302) with real sandbox holds and captures, labeled `sandbox: true`. First one on Live: payment #97, a $89.99 Target bed frame, Authorize.net sandbox transaction 120092631489, `simulated: false`. VIC is a seam only. Purchases before Sat ~1:50 PM are labeled simulated (`[SIMULATED]`, #154). Hardened (#138, #143): holds left by a restart are reversed with no double payment or duplicate approval, and the card caps are validated at startup. Purchase approvals show the checkout mode (VISA SANDBOX now) from `service_config.visa_checkout` (#191, #238).
- [ ] Show privacy, transparency, approvals and fraud checks (trust & responsibility write-up: [`docs/security.md`](security.md)). On `main`: transparency (every step an `agent_event`), listing approvals (#12), the purchase-approval push text (#53), and upload hardening with EXIF/GPS stripping (#38). Purchase approvals and the auth-hold re-check (#40). Fraud screening for deals (#64, #18): price outliers vs. comps and other deals, off-platform payment wording, new sellers and duplicate listings, combined into one score with reasons (`agents/src/agents/fraud.ts`). The buy agent won't buy a deal at or above `BUY_FRAUD_BLOCK` (0.7), and an unscreened deal waits for its score (#138). A planted, labeled demo scam on the Desk chair item scores 0.85 and is refused with no approval or payment (#154). The e2e test in CI proves the card budget refusal and the fraud block on every PR (#133). Unanswered approvals expire and are asked again (#186, #214); room members may decide listing approvals, purchases stay owner-only (#200, #239, #248). In the app: the Sell & Buy tab (#136), voxel thumbnails for deals, and a "Blocked: likely fraud" tag instead of Choose (#140); bought items appear in the new home layout (#125). CI taps through Sell & Buy in an iOS Simulator (#155). Still to do: show it in the demo (not yet verified on a device). AI-text detection (`agents/src/integrations/aitext.ts`) is on. Since Sat ~7:25 PM the hosted workers screen listing text with Christian's own small AI-text detector, running locally (a 150M ModernBERT-style encoder, INT4 ONNX, about 0.1 s per listing on CPU, `agents/scripts/aitext-server.py --backend otd`). It scores calibrated at a 1% and 0.1% false-positive rate, and listing text never leaves the laptop. Checks: the planted AI-written sofa listing scores 0.98, and 0 of 150 real scraped marketplace titles reach the 0.5 floor. Its training data includes non-commercial (CC BY-NC-SA) sources, so it's for research and demo use, not commercial use.

**Anthropic** ($5k credits, plus 1 year of Max 20x)
- Name a specific community (to be decided), show a real problem we've lived, make it work, and use Claude thoughtfully, including knowing where it could go wrong for users.
- Where it could go wrong, and what we did about it: the prompt-injection and responsible-AI sections of [`docs/security.md`](security.md).
- [ ] Settle the community and the pitch line. Suggestions are in the TODO in [`docs/devpost.md`](devpost.md#anthropic).

## Tier 2
- **Auth0 (MLH)**: use any Auth0 API. We use login, plus Auth0 for AI Agents async authorization for approvals.
  - [x] CIBA approvals built (#12, `agents/src/integrations/auth0.ts`) and tested live against our Auth0 tenant on Saturday evening and configured on the hosted worker (Guardian push to the owner, who must be signed in with Auth0; the seeded Demo room's owner isn't, so its approvals use the in-app inbox). Restart edge cases (no duplicate requests, no re-push of expired ones, a tap just before expiry still counts) are unit tested (#138).
  - [x] Login (#25): Auth0 Web Auth in the app, with the ID token as the SpacetimeDB connection token. `register_user` is wired on the live backend (#28), but login hasn't been demoed end to end on a phone yet. If `MOOVE_BUNDLE_ID` changes, the callback URL must be added in the Auth0 dashboard (`ios/CLAUDE.md`).
- **CRS Credit**: the Identity/Fraud Innovation prize, if the fraud screening uses the CRS sandbox. Fraud screening is built (#64): rules plus a local AI-text detector. It doesn't call CRS, so we don't qualify as built.
- **Best Planet-First Hack** (overall prize): the resell / donate-over-trash story. The impact banner on the Review screen (Items > Review) shows a rough "N kg kept out of landfill" figure that updates as you decide, and tapping it explains how it's estimated.
- **Notability**: keep the build notes there if someone wants it.

## Not targeting
Convex (we chose SpacetimeDB). Bright Data (it disqualifies mocked demo data and scraping behind a login). Hyphenate, Atlassian, Meta, SpaceXAI, Factory, Mana, Moss, Bitdeer, Elastic, Cartesia.

## Security (all tracks; Armadin Best Security Hack)
- Security and responsible-AI notes for judges are in [`docs/security.md`](security.md) (#17). Armadin's criteria were still "coming soon" at kickoff, so check the live prizes page.
- No keys in the repo (Cartesia and others require this): gitleaks runs on every PR and over the full history.

## General submission rules
- Submit on Devpost **by Sun 9:00 AM**. Late submissions are not judged. Draft by Sat night. The draft text is in [`docs/devpost.md`](devpost.md).
- The whole team stays at the table 10:30-12:30. Live demo, 2-minute pitch.
- All work must be started during the event. Follow the MLH Code of Conduct.
