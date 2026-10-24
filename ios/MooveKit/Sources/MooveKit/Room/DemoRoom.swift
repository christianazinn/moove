import Foundation

extension DemoFixtures {
    /// A 4 m × 3.5 m bedroom laid out like a RoomPlan scan, with one object per
    /// demo item (`scanObjectId` "demo-<item id>"). Replaced by the real #3 scan.
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
            ]
        )
    }
}
