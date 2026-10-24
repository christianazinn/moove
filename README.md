# Moove

Moove is an iOS app that runs your move. Scan your room, and AI agents inventory, price and sort your stuff. They sell what you don't need, buy what the new place needs, and pay for things on your behalf with guardrails. Then everything you kept flies into a 3D model of your new home.

Built at Cal Hacks 13.0.

| Path | What |
|---|---|
| `ios/` | SwiftUI app (RoomPlan, RealityKit) + `MooveKit` Swift package |
| `spacetime/` | SpacetimeDB module (TypeScript): shared real-time state |
| `agents/` | Node/TS agent worker: Claude, Apify, x402/CDP, eBay, Visa, Auth0 |
| `docs/` | Team plan, architecture, data model, task briefs, sponsor tracks |

Start with [`docs/TEAM.md`](docs/TEAM.md). Setup instructions per component will be added as each one lands. Copy `.env.example` to `.env.local` for keys.

## Sponsor tools used
_To be filled in as features land (required by several tracks): where x402/CDP, SpacetimeDB, Apify, Visa, Claude and Auth0 are used._
