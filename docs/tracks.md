# Sponsor tracks: requirements & submission checklist

Source: the Cal Hacks 13.0 Hacker Guide and the live prizes page (local copies are gitignored). Starter packs are posted on the live site. **Devpost may cap how many tracks we can select. Priority order: Coinbase > Spacetime > Apify > Visa > Anthropic > Auth0.**

## Tier 1
**Coinbase: Best Use of x402, Payment Agents track** ($500 USDC per member, plus a recruiter call)
- Use Coinbase for Agents (MCP / CDP) + x402. Docs: https://docs.cdp.coinbase.com/ai-agents/overview, https://docs.cdp.coinbase.com/x402/welcome. Keys: portal.cdp.coinbase.com
- **Every member needs a verified Coinbase account** (US/Canada, 18+).
- Judged on usefulness, technical design, ease of reuse, and product feedback. Not judged on code volume or money spent. Real money is not required. **Label simulated actions**, keep credentials private, and don't manage other people's funds.
- Submit:
  - [x] project summary (who it's for, what it does, which Coinbase tools)
  - [ ] demo + repo with setup instructions (repo + setup done in the doc below; the demo video and the live in-app log, pending #6 and #10, are not)
  - [x] **architecture diagram**, controls and known limitations (whole-app security controls: [`docs/security.md`](security.md))
  - [x] **builder feedback** (biggest blocker, how we worked around it, the missing capability we want most)

  **Devpost block (paste from [`docs/coinbase-x402.md`](coinbase-x402.md)):**
  - *Summary:* Moove's agents pay for the data they need (e.g. a $0.01 premium comps report to price an item) per call over x402, in USDC on Base Sepolia, from a CDP server wallet. A payment rail enforces a per-agent budget and a per-call max before anything is signed, and every payment shows up live in the iOS spending log with a basescan link. Coinbase tools: `@coinbase/cdp-sdk` (`CdpX402Client`, `createX402Server`, faucet), `@x402/*` v2, the CDP facilitator.
  - *Repo + setup:* https://github.com/christianazinn/moove, see "Setup" in `docs/coinbase-x402.md` (`cd agents && npm ci`, `npm test`, `npm run x402:wallet -- --faucet`, `npm run x402:demo`).
  - *Architecture, controls, limitations:* the Mermaid diagram, "Controls" and "Known limitations" sections of the doc.
  - *Proof:* 0.01 USDC settled on Base Sepolia: https://sepolia.basescan.org/tx/0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c
  - *Builder feedback:* the "Builder feedback" section of the doc (optional peer deps crash on import, CJS/ESM type split, settlement/tx hash undocumented for buyers, missing per-request spend context).

**Spacetime** (prize TBD)
- SpacetimeDB must be the core real-time backend, used meaningfully and not as an add-on. They like live shared state, agent coordination, marketplaces and live dashboards.
- [ ] Demo the two-phone live sync and the live spending log, and show the agents coordinating through tables.

**Apify** ($5k pool for the top 5, plus $400 Best Actor)
- Use Apify meaningfully. Best Actor means building and publishing an Actor during the event (stretch: a "moving comps" Actor).
- [ ] Show live scraping in the demo, and name the Actors in the README.

**Visa: Reimagining Shopping** ($5,000)
- Judged on innovation 25%, UX 25%, technical execution 20%, commerce impact 15%, trust & responsibility 15%.
- [ ] Use the Visa Starter Pack tooling for checkout (#15, stubbed until then).
- [ ] Show privacy, transparency, approvals and fraud checks (trust & responsibility write-up: [`docs/security.md`](security.md)).
- **Write-up and Devpost block:** [`docs/visa.md`](visa.md) (checkout merged in #40; the demo checkout is a labeled simulation because the CyberSource sandbox returned 502; fraud screen #18 pending).

**Anthropic** ($5k credits, plus 1 year of Max 20x)
- Name a specific community (to be decided), show a real problem we've lived, make it work, and use Claude thoughtfully, including knowing where it could go wrong for users.
- Where it could go wrong, and what we did about it: the prompt-injection and responsible-AI sections of [`docs/security.md`](security.md).
- [ ] Settle the community and the pitch line.

## Tier 2
- **Auth0 (MLH)**: use any Auth0 API. We use login, plus Auth0 for AI Agents async authorization for approvals. Write-up and Devpost block: [`docs/auth0.md`](auth0.md).
- **CRS Credit**: the Identity/Fraud Innovation prize, if the fraud screening (#18) uses the CRS sandbox.
- **Best Planet-First Hack** (overall prize): the resell / donate-over-trash story.
- **Notability**: keep the build notes there if someone wants it.

## Not targeting
Convex (we chose SpacetimeDB). Bright Data (it disqualifies mocked demo data and scraping behind a login). Hyphenate, Atlassian, Meta, SpaceXAI, Factory, Mana, Moss, Bitdeer, Elastic, Cartesia.

## Security (all tracks; Armadin Best Security Hack)
- Security and responsible-AI notes for judges are in [`docs/security.md`](security.md) (#17). Armadin's criteria were still "coming soon" at kickoff, so check the live prizes page.
- No keys in the repo (Cartesia and others require this): gitleaks runs on every PR and over the full history.

## General submission rules
- Submit on Devpost **by Sun 9:00 AM**. Late submissions are not judged. Draft by Sat night.
- The whole team stays at the table 10:30-12:30. Live demo, 2-minute pitch. Commerce demo runbook: [`docs/demo-commerce.md`](demo-commerce.md).
- All work must be started during the event. Follow the MLH Code of Conduct.
