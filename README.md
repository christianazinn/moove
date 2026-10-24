# Moove

Moove is an iOS app that runs your move. Scan your room, and AI agents inventory, price and sort your stuff. They sell what you don't need, buy what the new place needs, and pay for things on your behalf with guardrails. Then everything you kept flies into a 3D model of your new home.

Built at Cal Hacks 13.0.

| Path | What |
|---|---|
| `ios/` | SwiftUI app (RoomPlan, RealityKit) + `MooveKit` Swift package |
| `spacetime/` | SpacetimeDB module (TypeScript): shared real-time state |
| `agents/` | Node/TS agent worker: Claude, Apify, x402/CDP, eBay, Visa, Auth0 |
| `docs/` | Team plan, architecture, data model, task briefs, sponsor tracks |

Start with [`docs/TEAM.md`](docs/TEAM.md). For the commerce part of the live demo, see [`docs/demo-commerce.md`](docs/demo-commerce.md). Setup instructions per component will be added as each one lands. Copy `.env.example` to `.env.local` for keys.

## Sponsor tools used
_To be filled in as features land (required by several tracks): where x402/CDP, SpacetimeDB, Apify, Visa, Claude and Auth0 are used._

- **Coinbase x402 + CDP:** agents pay for data per call over x402 with USDC on Base Sepolia from a CDP server wallet (`@coinbase/cdp-sdk` `CdpX402Client` buyer, `createX402Server` paywall, `@x402/*` v2). Per-agent budgets and a per-call max are checked before signing, and every payment lands in SpacetimeDB and the app's live spending log with a basescan link. Simulated payments are labeled. Details, architecture diagram, setup and builder feedback: [`docs/coinbase-x402.md`](docs/coinbase-x402.md).
- **Visa:** the buy agent checks out by card through the Visa Acceptance (CyberSource) REST sandbox (auth hold, then capture or reversal), with Auth0 approval above your threshold and the approved amount re-checked before capture. The demo checkout is a labeled simulation. Details: [`docs/visa.md`](docs/visa.md).
- **Auth0:** login (Auth0.swift) plus CIBA async authorization with Guardian push for expensive listings and purchases, with an in-app inbox fallback. Details: [`docs/auth0.md`](docs/auth0.md).

## Security & responsible AI
How we keep users' data and money safe: [`docs/security.md`](docs/security.md). It covers the threat model, what's built (EXIF-stripped uploads, code-enforced x402 spend caps, the approval amount binding, prompt-injection defenses with a spot check, and gitleaks over the full history), what's still open (with issues), and our responsible-AI choices. In short: agents propose, code enforces the limits, the user approves anything big, and anything simulated is labeled.
