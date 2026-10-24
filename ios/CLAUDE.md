# ios/ - SwiftUI app + MooveKit

Lanes: ios-capture (capture, review, sync, auth), ios-newhome (new home, fly-in, summary, logistics), commerce (spending log, approvals, shopping screens).

- **XcodeGen**: the project is defined in `ios/project.yml`, and `*.xcodeproj` is gitignored. Run `xcodegen` after pulling or adding files. Never commit the `.xcodeproj`.
- Target iOS 17+, Swift 6, SwiftUI.
- Feature folders live under `Moove/Features/<Feature>/` (Auth, Scan, Room, Inventory, Review, Spending, Approvals, Listings, Shopping, NewHome, Pack, Summary). Stay in your own folders to avoid conflicts. Shared UI goes in `Moove/Shared/`.
- **`MooveKit/`** is a local Swift package for models mirroring `docs/data-model.md` plus pure logic (layout solver, volume/truck estimate, packing). No UIKit, RealityKit or RoomPlan imports, so it builds and tests on Linux (`swift test`). Put anything testable here.
- RoomPlan needs a physical LiDAR iPhone. Keep a fixture scan in `agents/fixtures/` for Simulator and preview work.
- SpacetimeDB from Swift: community SDK `ekscrypto/spacetimedb-swift-sdk` (spike passed, no gateway; see `docs/decisions/0020-swift-spacetimedb-sdk.md`). Screens only use `MooveStore` (`Moove/Sync/`), which drives a `SyncBackend`: `SpacetimeBackend` (live) or MooveKit's `FixtureBackend` (offline demo, previews, tests). How to regenerate the Swift bindings: `Moove/Sync/README.md`.
- Per-developer config (signing team, bundle id, local server IP, Auth0 ids) goes in `Config/Local.xcconfig` (gitignored; copy `Local.xcconfig.example`).
- The app has five tabs (Scan · Items · Sell & Buy · Move · Summary, [#129](https://github.com/christianazinn/moove/issues/129)). To add a screen, add its key to a group in `Moove/App/TabGroups.swift` (`screens` + the `content` switch) and keep the screen in your feature folder. Jump to a screen from anywhere with `@AppStorage("moove.tab") var tab` and `tab = "<screen key>"`.
- No secrets in the app bundle beyond public Auth0 client config.
- Auth0 (#1): the app signs in with Auth0 Web Auth (custom URL scheme) and passes the **ID token** as the SpacetimeDB connection token, so `ctx.sender` is derived from the Auth0 user's `iss` + `sub`. If you change `MOOVE_BUNDLE_ID`, add `<bundle id>://dev-78lq8spq27b2bipk.us.auth0.com/ios/<bundle id>/callback` to the Moove iOS app's Allowed Callback and Logout URLs in the Auth0 dashboard. "Continue without an account" uses an anonymous SpacetimeDB identity saved in the Keychain.

## ios-newhome lane
- **Item 3D is voxel only** ([decision 0108](../docs/decisions/0108-voxel-item-models.md)). Every 3D view draws items as procedural 5 cm voxel models. Don't add USDZ/GLB item models. Shape comes from RoomPlan attributes first, then name/material/brand words, then the scanned size; `condition` sets wear; measured colors (`Item.colors`, or `ScanColors` in-session) override the keyword palette. Seeded randomness only picks small details.
- **Where the voxel pipeline lives:**
  - MooveKit `Sources/MooveKit/Voxel/`: `VoxelGrid.swift` (`VoxelItemSpec`, built from an `Item`), `VoxelModels*.swift` (routing + builders), `VoxelHouse.swift` (the home shell: base, floors, cut-away walls, doors, windows), `VoxelMesher.swift` (greedy meshing into one mesh per piece).
  - MooveKit `NewHome/PropPlacer.swift`: puts small items on free furniture surfaces (`VoxelModels.surfaces`) and hangs art/mirrors/wall TVs on walls; `Placement` carries optional `elevationM` / `onTopOf` / `wallMounted`.
  - MooveKit `Room/ColorSampler.swift`: wall, floor and per-object colors from the scan's camera keyframes (`ScanColors`). The frames are kept by `Moove/Features/Scan/ScanFrameRecorder.swift`.
  - MooveKit `NewHome/`: `FloorPlan`, `LayoutSolver` (three styles), `DemoHouse`, `ManualFloorPlan`, `ListingImport.swift` (`ListingLink.parse`, no network; `EstimatedFloorPlan` from beds/baths/sqft). Packing and the truck estimate are in `Packing/`.
  - App `Features/NewHome/`: `VoxelEntity.swift` (mesh -> RealityKit entity, cached per spec), `FurnitureLayer.swift` (placed items + fly-in), `NewHomeScene.swift` (the house shell + room labels), `FloorPlan3DView.swift` (takes sampled `wallColor`/`floorColor`), `VoxelThumbnail.swift`, `ListingImportView.swift` + `ListingImportClient.swift` (worker `POST /homes/import`). The scan's dollhouse is `Moove/Shared/ScanResultsView.swift`, fed by `Features/Scan/ScanFinishedResults.swift` and `Features/Room/RoomGeometry+Dollhouse.swift`.
- **MooveKit tests without Swift 6.2 locally:** run them in Docker. Docker Desktop can't mount `/private/tmp`, so mount the repo from your home folder, and copy the sources out of the read-only mount without `.build`:
  ```sh
  docker run --rm -v <repo>/ios/MooveKit:/src:ro swift:6.2 bash -c 'mkdir /work && cd /src && tar --exclude=.build -cf - . | (cd /work && tar xf -) && cd /work && swift test'
  ```
