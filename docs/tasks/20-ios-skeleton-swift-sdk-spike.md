---
title: Swift SpacetimeDB spike + iOS app skeleton
lane: ios-capture
depends: none
tracks: Spacetime
stretch: false
---

## Goal
Decide how the iOS app talks to SpacetimeDB (community Swift SDK vs worker gateway) and land the iOS app skeleton every iOS lane builds on.

## Context
The hour-0 spike is in `docs/TEAM.md` and #10. `ios/` was empty, and three lanes (ios-capture, ios-newhome, commerce screens) need `project.yml`, MooveKit and a shared store before they can start.

## Scope
- Spike: community SDK `ekscrypto/spacetimedb-swift-sdk` against SpacetimeDB 2.13. Connect, subscribe, call a reducer, two-client live update, ownership rejection, reconnect.
- `ios/project.yml` (XcodeGen), `Config/*.xcconfig` with a gitignored `Local.xcconfig` for per-developer values.
- MooveKit: capture-lane models (users, rooms, scans, items, comps), the `SyncBackend` protocol, and an in-memory `FixtureBackend` with the same reducer rules plus demo data.
- App: `MooveStore` (the only thing screens touch), `SpacetimeBackend` over the SDK (contract glue pending #2), tab shell, connection banner, and a Settings sheet with an "Offline demo" toggle.

## Tables / reducers touched
None yet. Contract glue is filled in once #2 publishes.

## Acceptance criteria
- [x] Spike passes locally: A->B update ~1.5 ms, another identity's write rejected, same token resumes the same identity.
- [x] `swift test` passes in `ios/MooveKit`.
- [x] `xcodegen && xcodebuild ... build` succeeds for the Simulator, and the app runs.

## Demo fallback
Offline demo backend (Settings -> Data source).

## Depends on
None. Unblocks #4, #9, #10, #13 and the commerce screens.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.
