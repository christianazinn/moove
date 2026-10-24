// swift-tools-version: 6.1
import PackageDescription

// Swift bindings generated from the SpacetimeDB module (spacetime/src/index.ts)
// with the SDK's `spacetime-swift generate`. Never hand-edit Sources/; see
// ios/Moove/Sync/README.md to regenerate. A separate module keeps generated
// names (ListingRow, RoomRow, ...) from colliding with app types.
let package = Package(
    name: "MooveBindings",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MooveBindings", targets: ["MooveBindings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ekscrypto/spacetimedb-swift-sdk", revision: "c966b6b5bab9248e186a7453de94bc6c49e07fb6"),
    ],
    targets: [
        .target(
            name: "MooveBindings",
            dependencies: [
                .product(name: "SpacetimeDB", package: "spacetimedb-swift-sdk"),
                .product(name: "BSATN", package: "spacetimedb-swift-sdk"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
