# ios/ - SwiftUI app + MooveKit

Lanes: ios-capture (capture, review, sync, auth), ios-newhome (new home, fly-in, summary, logistics), commerce (spending log, approvals, shopping screens).

- **XcodeGen**: the project is defined in `ios/project.yml`, and `*.xcodeproj` is gitignored. Run `xcodegen` after pulling or adding files. Never commit the `.xcodeproj`.
- Target iOS 17+, Swift 6, SwiftUI.
- Feature folders live under `Moove/Features/<Feature>/` (Auth, Scan, Inventory, Review, Spending, Approvals, Listings, Shopping, NewHome, Summary). Stay in your own folders to avoid conflicts. Shared UI goes in `Moove/Shared/`.
- **`MooveKit/`** is a local Swift package for models mirroring `docs/data-model.md` plus pure logic (layout solver, volume/truck estimate, packing). No UIKit, RealityKit or RoomPlan imports, so it builds and tests on Linux (`swift test`). Put anything testable here.
- RoomPlan needs a physical LiDAR iPhone. Keep a fixture scan in `agents/fixtures/` for Simulator and preview work.
- SpacetimeDB from Swift: community SDK `ekscrypto/spacetimedb-swift-sdk` (spike passed, no gateway; see `docs/decisions/0020-swift-spacetimedb-sdk.md`). Screens only use `MooveStore` (`Moove/Sync/`), which drives a `SyncBackend`: `SpacetimeBackend` (live) or MooveKit's `FixtureBackend` (offline demo, previews, tests). How to regenerate the Swift bindings: `Moove/Sync/README.md`.
- Per-developer config (signing team, bundle id, local server IP, Auth0 ids) goes in `Config/Local.xcconfig` (gitignored; copy `Local.xcconfig.example`).
- Add your screen's tab in `Moove/App/RootView.swift` (one line) and keep the screen in your feature folder.
- No secrets in the app bundle beyond public Auth0 client config.
