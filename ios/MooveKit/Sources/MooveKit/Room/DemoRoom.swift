import Foundation

extension DemoFixtures {
    /// Prefix of the bedroom seeded on maincloud by `npm run seed:demo`
    /// (agents/scripts/demo-room.ts): "demo-bedroom-bed", "demo-bedroom-desk", ...
    public static let seededBedroomPrefix = "demo-bedroom-"

    /// The built-in geometry for a demo room's items, or nil if none of them came
    /// from a demo: the seeded Bedroom's layout for `demo-bedroom-*` ids, else the
    /// offline fixture's (`demo-<item id>`). Real scans carry RoomPlan UUIDs.
    public static func roomGeometry(forScanObjectIds ids: some Sequence<String>) -> RoomGeometry? {
        var isDemo = false
        for id in ids {
            if id.hasPrefix(seededBedroomPrefix) { return seededBedroomGeometry() }
            if id.hasPrefix("demo-") { isDemo = true }
        }
        return isDemo ? roomGeometry() : nil
    }

    /// A 4 m × 3.5 m bedroom laid out like a RoomPlan scan, with one object per
    /// demo item (`scanObjectId` "demo-<item id>"). Replaced by the real #3 scan.
    public static func roomGeometry() -> RoomGeometry {
        let quarter = Float.pi / 2
        func object(_ item: UInt64, _ category: String, _ dims: SIMD3<Float>, _ x: Float, _ z: Float, yaw: Float = 0, y: Float? = nil) -> RoomGeometry.Object {
            demoObject("demo-\(item)", category, dims, x, z, yaw: yaw, y: y)
        }
        return demoBedroom(objects: [
            object(10, "bed", SIMD3(1.6, 0.4, 2.1), -0.9, -0.7),
            object(15, "storage", SIMD3(0.45, 0.55, 0.4), 0.2, -1.5),
            object(19, "decor", SIMD3(0.4, 0.5, 0.05), 0.2, -1.6, y: 0.8),
            object(14, "lamp", SIMD3(0.3, 1.6, 0.3), 0.7, -1.5),
            object(16, "appliance", SIMD3(0.5, 0.5, 0.2), 1.6, -1.35),
            object(12, "table", SIMD3(1.4, 0.75, 0.7), 1.65, 0.6, yaw: quarter),
            object(11, "chair", SIMD3(0.7, 1.1, 0.7), 0.95, 0.5),
            object(21, "appliance", SIMD3(0.5, 0.85, 0.5), 1.0, 1.45),
            object(13, "storage", SIMD3(0.8, 1.8, 0.3), -1.85, 1.0, yaw: quarter),
            object(18, "decor", SIMD3(0.9, 0.9, 0.3), -0.9, 0.6),
            object(20, "sofa", SIMD3(0.9, 0.7, 0.9), 0.15, 1.15),
            object(17, "decor", SIMD3(0.6, 0.9, 0.05), 0.4, 1.7),
        ])
    }

    /// The same bedroom furnished with the 9 objects `npm run seed:demo` puts on
    /// maincloud (agents/scripts/demo-room.ts; same ids, categories and dims), whose
    /// scan has no room.json. Bed against the north wall, shelf with the TV on top,
    /// desk under the monitor against the east wall, guitar leaning on the west wall.
    public static func seededBedroomGeometry() -> RoomGeometry {
        let quarter = Float.pi / 2
        func object(_ name: String, _ category: String, _ dims: SIMD3<Float>, _ x: Float, _ z: Float, yaw: Float = 0, y: Float? = nil) -> RoomGeometry.Object {
            demoObject(seededBedroomPrefix + name, category, dims, x, z, yaw: yaw, y: y)
        }
        return demoBedroom(objects: [
            object("bed", "bed", SIMD3(1.4, 0.36, 1.95), -1.2, -0.77),
            object("lamp", "lamp", SIMD3(0.3, 1.7, 0.3), -0.25, -1.55),
            object("shelf", "storage", SIMD3(0.77, 1.47, 0.39), 0.45, -1.54),
            object("tv", "television", SIMD3(0.73, 0.48, 0.18), 0.45, -1.6, y: 1.47 + 0.24),
            object("fridge", "refrigerator", SIMD3(0.48, 0.85, 0.5), 1.2, -1.49),
            object("desk", "table", SIMD3(1.05, 0.75, 0.5), 1.74, 0.6, yaw: quarter),
            object("monitor", "electronics", SIMD3(0.61, 0.45, 0.18), 1.85, 0.6, yaw: quarter, y: 0.75 + 0.225),
            object("chair", "chair", SIMD3(0.64, 1.02, 0.62), 1.05, 0.6, yaw: quarter),
            object("guitar", "instrument", SIMD3(0.38, 1.02, 0.12), -1.93, 0.9, yaw: quarter),
        ])
    }

    private static func demoObject(_ id: String, _ category: String, _ dims: SIMD3<Float>, _ x: Float, _ z: Float, yaw: Float, y: Float?) -> RoomGeometry.Object {
        .init(id: id, category: category, dimensions: dims, transform: .at(SIMD3(x, y ?? dims.y / 2, z), yaw: yaw))
    }

    /// Walls, door, window and floor of the 4 m × 3.5 m demo bedroom.
    private static func demoBedroom(objects: [RoomGeometry.Object]) -> RoomGeometry {
        let h: Float = 2.5, w: Float = 4, d: Float = 3.5
        let quarter = Float.pi / 2
        func wall(_ id: String, _ x: Float, _ z: Float, _ width: Float, yaw: Float) -> RoomGeometry.Surface {
            .init(id: id, kind: .wall, dimensions: SIMD3(width, h, 0), transform: .at(SIMD3(x, h / 2, z), yaw: yaw))
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
            objects: objects
        )
    }
}
