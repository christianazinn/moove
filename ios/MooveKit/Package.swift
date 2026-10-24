// swift-tools-version: 6.1
import PackageDescription

// Pure Swift: no UIKit, RealityKit, RoomPlan or SpacetimeDB SDK imports,
// so `swift test` runs on Linux CI.
let package = Package(
    name: "MooveKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MooveKit", targets: ["MooveKit"]),
    ],
    targets: [
        .target(name: "MooveKit", resources: [.copy("Resources/demo-house.json")]),
        .testTarget(name: "MooveKitTests", dependencies: ["MooveKit"]),
    ]
)
