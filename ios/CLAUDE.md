# ios/ - SwiftUI app + MooveKit

Lanes: ios-capture (capture, review, sync, auth), ios-newhome (new home, fly-in, summary, logistics), commerce (spending log, approvals, shopping screens).

- **XcodeGen**: the project is defined in `ios/project.yml`, and `*.xcodeproj` is gitignored. Run `xcodegen` after pulling or adding files. Never commit the `.xcodeproj`.
- Target iOS 17+, Swift 6, SwiftUI.
- Feature folders live under `Moove/Features/<Feature>/` (Auth, Scan, Inventory, Review, Spending, Approvals, Listings, Shopping, NewHome, Summary). Stay in your own folders to avoid conflicts. Shared UI goes in `Moove/Shared/`.
- **`MooveKit/`** is a local Swift package for models mirroring `docs/data-model.md` plus pure logic (layout solver, volume/truck estimate, packing). No UIKit, RealityKit or RoomPlan imports, so it builds and tests on Linux (`swift test`). Put anything testable here.
- RoomPlan needs a physical LiDAR iPhone. Keep a fixture scan in `agents/fixtures/` for Simulator and preview work.
- SpacetimeDB from Swift: community SDK `ekscrypto/spacetimedb-swift-sdk`. If the hour-0 spike fails, we go through the worker gateway instead (see `docs/architecture.md`). Hide either behind one `MooveStore` type so screens don't care.
- No secrets in the app bundle beyond public Auth0 client config.
