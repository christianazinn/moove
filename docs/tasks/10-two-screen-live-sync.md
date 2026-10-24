---
title: Two-screen live sync (SpacetimeDB)
lane: ios-capture
depends: 9
tracks: Spacetime
stretch: false
---

## Goal
Two phones (e.g. roommates or a parent and kid) review the same inventory at once, and changes on one appear instantly on the other.

## Context
SpacetimeDB subscriptions are the core real-time layer, and this is the headline Spacetime-track feature. It also proves the iOS client architecture. See `docs/architecture.md`.

## Scope
- Subscribe the review (#9), spending log (#7) and agent activity screens to SpacetimeDB tables with live updates.
- Shared household: add a way for a second user to join a room (an invite code -> `joinRoom` reducer) and adjust the ownership checks.
- **Hour-0 spike (do this first, Fri night):** with the community Swift SDK, connect, subscribe to `items` and call one reducer. Decide SDK vs gateway by ~11 PM and tell the team.
- If the SDK fails: a thin gateway in the worker (`agents/src/gateway.ts`) that relays subscriptions over WebSocket and reducers over REST, with the iOS side behind a `SyncClient` protocol in MooveKit.

## Tables / reducers touched
`items`, `rooms` (members), `payments`, `agentEvents`. New `joinRoom` reducer (coordinate with #2).

## Acceptance criteria
- [ ] With two phones on the same room, an override on phone A appears on phone B in under 1s.
- [ ] Agent updates (prices, dispositions) stream in live on both.
- [ ] Reconnects cleanly after airplane mode.

## Demo fallback
One phone plus the SpacetimeDB web dashboard or `spacetime sql` on a laptop showing rows changing live.

## Notes & gotchas
- `ekscrypto/spacetimedb-swift-sdk` is community-built: manually tested, large messages aren't streamed, and it requires Swift 6.1+. Verify its current state.
- Keep all sync behind the `SyncClient` protocol so switching to the gateway is one file.
- Spacetime judges want SpacetimeDB to be "meaningfully used, not added on the side". Point at the live multi-device and agent coordination.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
