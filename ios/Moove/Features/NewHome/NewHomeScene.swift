import RealityKit
import UIKit
import MooveKit

/// Builds RealityKit entities for a floor plan: floors, cut-away walls with
/// door gaps, window glass and flat room labels. World space matches RoomPlan
/// (meters, Y-up; plan y is world z), so #14 can drop items straight in.
@MainActor
final class NewHomeScene {
    /// Walls are cut at this height so the camera can see in from above (dollhouse view).
    static let cutawayHeightM: Float = 1.1
    static let wallThicknessM: Float = 0.08

    let root = Entity()
    private(set) var plan: FloorPlan?

    func build(_ plan: FloorPlan) {
        guard plan != self.plan else { return }
        self.plan = plan
        root.children.removeAll()
        for room in plan.rooms {
            if let floor = Self.floor(for: room) { root.addChild(floor) }
            root.addChild(Self.label(for: room))
        }
        for wall in plan.wallSegments() { root.addChild(Self.wall(wall)) }
        for window in plan.windows { root.addChild(Self.window(window)) }
    }

    /// Center and rough radius of the plan, for framing the camera.
    var focus: (center: SIMD3<Float>, radius: Float) {
        guard let plan, !plan.rooms.isEmpty else { return (.zero, 5) }
        return Self.focus(on: plan.bounds)
    }

    static func focus(on b: PlanBounds) -> (center: SIMD3<Float>, radius: Float) {
        let c = b.center
        return ([Float(c.x), 0, Float(c.y)], Float(max(b.width, b.depth)) / 2)
    }

    // MARK: Pieces

    private static func floor(for room: FloorPlanRoom) -> ModelEntity? {
        let indices = room.triangulate()
        guard !indices.isEmpty else { return nil }
        var mesh = MeshDescriptor(name: "floor-\(room.name)")
        mesh.positions = MeshBuffers.Positions(room.polygon.map { SIMD3<Float>(Float($0.x), 0, Float($0.y)) })
        mesh.normals = MeshBuffers.Normals(Array(repeating: SIMD3<Float>(0, 1, 0), count: room.polygon.count))
        // Counterclockwise in plan (x right, y up) faces -Y once y becomes world z, so flip each triangle.
        var flipped: [UInt32] = []
        for t in stride(from: 0, to: indices.count, by: 3) { flipped += [indices[t], indices[t + 2], indices[t + 1]] }
        mesh.primitives = .triangles(flipped)
        guard let resource = try? MeshResource.generate(from: [mesh]) else { return nil }
        return ModelEntity(mesh: resource, materials: [material(floorColor(room.kind))])
    }

    private static func wall(_ w: WallSegment) -> ModelEntity {
        let h = cutawayHeightM, t = wallThicknessM
        let box = ModelEntity(mesh: .generateBox(width: Float(w.lengthM) + t, height: h, depth: t), materials: [material(.wall)])
        // Each room draws its own copy of a shared wall, half a thickness inside the room, so copies sit side by side.
        let center = w.center + w.inward * Double(t / 2)
        box.position = [Float(center.x), h / 2, Float(center.y)]
        box.orientation = simd_quatf(angle: Float(w.yawRadians), axis: [0, 1, 0])
        return box
    }

    private static func window(_ o: WallOpening) -> ModelEntity {
        let seg = WallSegment(from: o.from, to: o.to, room: "")
        let h: Float = 0.35, t = wallThicknessM * 2.5
        var glass = material(.glass)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        let box = ModelEntity(mesh: .generateBox(width: Float(seg.lengthM), height: h, depth: t), materials: [glass])
        box.position = [Float(seg.center.x), cutawayHeightM - h / 2 + 0.02, Float(seg.center.y)]
        box.orientation = simd_quatf(angle: Float(seg.yawRadians), axis: [0, 1, 0])
        return box
    }

    private static func label(for room: FloorPlanRoom) -> Entity {
        let group = Entity()
        let c = room.centroid
        group.position = [Float(c.x), 0.02, Float(c.y)]
        // Text meshes face +Z; lay them flat on the floor, reading upright from the default camera.
        group.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        let small = min(room.widthM, room.depthM) < 2
        let title = text(room.name, size: small ? 0.22 : 0.32, weight: .semibold, color: UIColor(white: 0.15, alpha: 1))
        group.addChild(title)
        if room.kind != .hallway {
            let dims = text(String(format: "%.1f × %.1f m", room.widthM, room.depthM), size: small ? 0.15 : 0.2, weight: .regular, color: UIColor(white: 0.42, alpha: 1))
            dims.position.y -= small ? 0.28 : 0.4
            group.addChild(dims)
        }
        return group
    }

    private static func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(
            string, extrusionDepth: 0.005, font: .systemFont(ofSize: size, weight: weight),
            containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail
        )
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        let b = mesh.bounds
        entity.position = [-b.center.x, -b.center.y, 0]
        return entity
    }

    // MARK: Look

    enum Swatch {
        case wall, glass, floor(UIColor)
    }

    private static func floorColor(_ kind: RoomKind) -> Swatch {
        switch kind {
        case .bedroom: .floor(UIColor(red: 0.80, green: 0.86, blue: 0.97, alpha: 1))
        case .living: .floor(UIColor(red: 0.96, green: 0.90, blue: 0.80, alpha: 1))
        case .kitchen: .floor(UIColor(red: 0.84, green: 0.94, blue: 0.84, alpha: 1))
        case .dining: .floor(UIColor(red: 0.97, green: 0.86, blue: 0.82, alpha: 1))
        case .bathroom: .floor(UIColor(red: 0.80, green: 0.93, blue: 0.95, alpha: 1))
        case .office: .floor(UIColor(red: 0.90, green: 0.86, blue: 0.96, alpha: 1))
        case .hallway, .other: .floor(UIColor(white: 0.90, alpha: 1))
        }
    }

    static func material(_ swatch: Swatch) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        switch swatch {
        case .wall: m.baseColor = .init(tint: UIColor(white: 0.97, alpha: 1))
        case .glass: m.baseColor = .init(tint: UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1))
        case .floor(let color): m.baseColor = .init(tint: color)
        }
        m.roughness = .init(floatLiteral: 0.9)
        m.metallic = .init(floatLiteral: 0)
        m.faceCulling = .none
        return m
    }
}
