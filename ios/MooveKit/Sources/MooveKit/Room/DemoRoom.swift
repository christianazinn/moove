import Foundation

extension DemoFixtures {
    /// A 4 m × 3.5 m bedroom laid out like a RoomPlan scan, with one object per
    /// demo item (`scanObjectId` "demo-<item id>"), sized like the seeded Bedroom (demo-room.ts).
    public static func roomGeometry() -> RoomGeometry {
        let h: Float = 2.5, w: Float = 4, d: Float = 3.5
        let quarter = Float.pi / 2
        func wall(_ id: String, _ x: Float, _ z: Float, _ width: Float, yaw: Float) -> RoomGeometry.Surface {
            .init(id: id, kind: .wall, dimensions: SIMD3(width, h, 0), transform: .at(SIMD3(x, h / 2, z), yaw: yaw))
        }
        func object(_ item: UInt64, _ category: String, _ dims: SIMD3<Float>, _ x: Float, _ z: Float, yaw: Float = 0, y: Float? = nil) -> RoomGeometry.Object {
            .init(id: "demo-\(item)", category: category, dimensions: dims, transform: .at(SIMD3(x, y ?? dims.y / 2, z), yaw: yaw))
        }
        return RoomGeometry(
            walls: [
                wall("wall-n", 0, -d / 2, w, yaw: 0),
                wall("wall-s", 0, d / 2, w, yaw: 0),
                wall("wall-e", w / 2, 0, d, yaw: quarter),
                wall("wall-w", -w / 2, 0, d, yaw: quarter),
            ],
            openings: [
                .init(id: "door", kind: .door, parentId: "wall-s", dimensions: SIMD3(0.85, 2.05, 0), transform: .at(SIMD3(-1.0, 1.025, d / 2))),
                .init(id: "window", kind: .window, parentId: "wall-e", dimensions: SIMD3(1.2, 1.2, 0), transform: .at(SIMD3(w / 2, 1.4, -0.8), yaw: quarter)),
            ],
            floors: [
                .init(id: "floor", outline: [SIMD2(-w / 2, -d / 2), SIMD2(w / 2, -d / 2), SIMD2(w / 2, d / 2), SIMD2(-w / 2, d / 2)], elevation: 0),
            ],
            objects: [
                // North wall: bed, guitar on its stand, lamp, mini fridge with the TV on it.
                object(10, "bed", SIMD3(1.4, 0.36, 1.95), -1.25, -0.75),
                object(18, "instrument", SIMD3(0.38, 1.02, 0.12), 0.19, -1.65),
                object(14, "lamp", SIMD3(0.3, 1.7, 0.3), 0.55, -1.55),
                object(21, "refrigerator", SIMD3(0.48, 0.85, 0.5), 1.0, -1.45),
                object(15, "television", SIMD3(0.73, 0.48, 0.18), 1.0, -1.5, y: 0.85 + 0.24),
                // East wall: the desk with the monitor on it, the mesh chair at it.
                object(12, "table", SIMD3(1.05, 0.75, 0.5), 1.7, 0.4, yaw: quarter),
                object(16, "electronics", SIMD3(0.61, 0.45, 0.18), 1.8, 0.4, yaw: quarter, y: 0.75 + 0.225),
                object(17, "chair", SIMD3(0.64, 1.02, 0.62), 1.0, 0.4),
                // West wall: the Kallax.
                object(13, "storage", SIMD3(0.77, 1.47, 0.39), -1.8, 1.0, yaw: quarter),
            ]
        )
    }
}

extension DemoFixtures {
    /// Colors for the demo bedroom (`roomGeometry()`), as if `ColorSampler` had measured them:
    /// a warm off-white wall, an oak floor, and a primary / secondary per object that matches
    /// the demo item's name and material. Keyed by scan object id ("demo-<item id>").
    /// Used when a demo room has no sampled colors (the offline demo, "Load demo scan").
    public static func scanColors() -> ScanColors {
        func c(_ primary: VoxelColor, _ secondary: VoxelColor? = nil) -> ScanColors.ObjectColor {
            .init(primary: primary, secondary: secondary)
        }
        return ScanColors(
            wallColor: 0xEFE3D0,  // warm cream paint
            floorColor: 0xC49A6C,  // oak boards
            objectColors: [
                "demo-10": c(0x2E2F31, 0xE9E3D6),  // black metal bed frame, linen bedding
                "demo-12": c(0xF2F0EB),  // white Micke desk
                "demo-13": c(0xF1EFEA),  // white Kallax
                "demo-14": c(0x2B2B2D, 0xF1E6CF),  // black metal floor lamp, cream shade
                "demo-15": c(0x1B1C1E, 0x3A3C40),  // TV: black screen, dark gray bezel
                "demo-16": c(0x222326, 0x9EA3A8),  // monitor: black, silver stand
                "demo-17": c(0x2A2B2E, 0x1E1F21),  // black mesh chair, black base
                "demo-18": c(0xD9B27C, 0x5A3A22),  // spruce top, mahogany neck
                "demo-21": c(0x262729, 0x8E9093),  // black mini fridge, silver handle
            ]
        )
    }

    /// Whether `item` came from the demo bedroom (its scan object id is "demo-<id>").
    public static func isDemoItem(_ item: Item) -> Bool {
        item.scanObjectId?.hasPrefix("demo-") ?? false
    }
}
