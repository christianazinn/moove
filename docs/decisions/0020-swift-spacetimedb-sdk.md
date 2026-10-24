# 0020: iOS talks to SpacetimeDB directly with the community Swift SDK

## Context
SpacetimeDB has no official Swift SDK. `docs/architecture.md` planned an hour-0 spike, with a fallback of a worker-hosted WebSocket/REST gateway (#10).

## Decision
Use `ekscrypto/spacetimedb-swift-sdk`, pinned to `c966b6b` (2026-09-27, protocol `v2.bsatn.spacetimedb`). **No gateway.**

Spike (Fri 8 PM, local SpacetimeDB 2.13, TS module, macOS client on the same SDK):
- Connect, subscribe, reducer calls with typed codegen (`spacetime-swift generate`): OK
- Two clients sharing a token: live update A->B in ~1.5 ms (median of 5)
- A third identity calling an ownership-checked reducer: rejected
- Reconnect with a saved token: same identity, current rows visible

## Consequences
- Screens use `MooveStore` -> `SyncBackend`. The SDK is only touched in `ios/Moove/Sync/`.
  Falling back to a gateway later is a new `SyncBackend`, not a screen rewrite.
- Swift row types are generated from the published module (`ios/Moove/Sync/README.md`), so
  hand-mirroring Swift models in MooveKit is only needed for the plain models screens use.
- The SDK doesn't replay subscriptions after auto-reconnect; `SpacetimeBackend` does that.
- Not yet verified: maincloud from a physical phone, and the Auth0 OIDC token as the connection token (#1).
