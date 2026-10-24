# Sponsor tracks: requirements & submission checklist

Source: the Cal Hacks 13.0 Hacker Guide and the live prizes page (local copies are gitignored). Starter packs are posted on the live site. **Devpost may cap how many tracks we can select. Priority order: Coinbase > Spacetime > Apify > Visa > Anthropic > Auth0.**

## Tier 1
**Coinbase: Best Use of x402, Payment Agents track** ($500 USDC per member, plus a recruiter call)
- Use Coinbase for Agents (MCP / CDP) + x402. Docs: https://docs.cdp.coinbase.com/ai-agents/overview, https://docs.cdp.coinbase.com/x402/welcome. Keys: portal.cdp.coinbase.com
- **Every member needs a verified Coinbase account** (US/Canada, 18+).
- Judged on usefulness, technical design, ease of reuse, and product feedback. Not judged on code volume or money spent. Real money is not required. **Label simulated actions**, keep credentials private, and don't manage other people's funds.
- Submit:
  - [ ] project summary (who it's for, what it does, which Coinbase tools)
  - [ ] demo + repo with setup instructions
  - [ ] **architecture diagram**, controls and known limitations
  - [ ] **builder feedback** (biggest blocker, how we worked around it, the missing capability we want most)

**Spacetime** (prize TBD)
- SpacetimeDB must be the core real-time backend, used meaningfully and not as an add-on. They like live shared state, agent coordination, marketplaces and live dashboards.
- [ ] Demo the two-phone live sync and the live spending log, and show the agents coordinating through tables.

**Apify** ($5k pool for the top 5, plus $400 Best Actor)
- Use Apify meaningfully. Best Actor means building and publishing an Actor during the event (stretch: a "moving comps" Actor).
- [ ] Show live scraping in the demo, and name the Actors in the README.

**Visa: Reimagining Shopping** ($5,000)
- Judged on innovation 25%, UX 25%, technical execution 20%, commerce impact 15%, trust & responsibility 15%.
- [ ] Use the Visa Starter Pack tooling for checkout (#15, stubbed until then).
- [ ] Show privacy, transparency, approvals and fraud checks.

**Anthropic** ($5k credits, plus 1 year of Max 20x)
- Name a specific community (to be decided), show a real problem we've lived, make it work, and use Claude thoughtfully, including knowing where it could go wrong for users.
- [ ] Settle the community and the pitch line.

## Tier 2
- **Auth0 (MLH)**: use any Auth0 API. We use login, plus Auth0 for AI Agents async authorization for approvals.
- **CRS Credit**: the Identity/Fraud Innovation prize, if the fraud screening (#18) uses the CRS sandbox.
- **Best Planet-First Hack** (overall prize): the resell / donate-over-trash story.
- **Notability**: keep the build notes there if someone wants it.

## Not targeting
Convex (we chose SpacetimeDB). Bright Data (it disqualifies mocked demo data and scraping behind a login). Hyphenate, Atlassian, Meta, SpaceXAI, Factory, Mana, Moss, Bitdeer, Elastic, Cartesia.

## General submission rules
- Submit on Devpost **by Sun 9:00 AM**. Late submissions are not judged. Draft by Sat night.
- The whole team stays at the table 10:30-12:30. Live demo, 2-minute pitch.
- All work must be started during the event. Follow the MLH Code of Conduct.
