import Foundation
import RealityKit
import UIKit
import MooveKit

/// Builds a "dollhouse" RealityKit scene from a scanned room: an oak floor
/// slab, warm-white walls cut open at doors and windows (no ceiling, so you
/// can look in), and every piece of furniture as a rounded, colored block at
/// its real size and position.
@available(iOS 18.0, *)
@MainActor
enum RoomScene {
    static let wallThickness: Float = 0.1
    static let objectPrefix = "obj:"

    static func make(_ geometry: RoomGeometry) -> Entity {
        let room = Entity()
        room.name = "room"
        let floorGroup = Entity()
        floorGroup.name = "floor"
        for outline in geometry.floorOutlines {
            if let slab = floorSlab(outline) { floorGroup.addChild(slab) }
        }
        room.addChild(floorGroup)

        let center = geometry.bounds.map { ($0.min + $0.max) / 2 } ?? .zero
        for wall in geometry.walls {
            // Doors swing toward the room's center, whichever way the wall faces.
            let inward: Float = wall.transform.inverseApply(center).z < 0 ? -1 : 1
            room.addChild(wallEntity(wall, holes: geometry.holes(in: wall), inward: inward))
        }

        let objects = Entity()
        objects.name = "objects"
        for object in geometry.objects {
            objects.addChild(objectEntity(object))
        }
        room.addChild(objects)
        room.addChild(sunlight(for: geometry))
        return room
    }

    // MARK: Floor

    private static func floorSlab(_ outline: [SIMD2<Float>]) -> ModelEntity? {
        let thickness: Float = 0.06
        let tris = Triangulation.triangulate(outline)
        guard !tris.isEmpty else { return nil }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        // Top face. Triangulation is CCW in (x, z); flip winding so the face points up (+y).
        for p in outline {
            positions.append(SIMD3(p.x, 0, p.y))
            normals.append(SIMD3(0, 1, 0))
        }
        for t in stride(from: 0, to: tris.count, by: 3) { indices += [tris[t], tris[t + 2], tris[t + 1]] }

        // Side faces, one quad per edge with its own outward normal.
        let ccw = Triangulation.signedArea(outline) > 0
        for i in outline.indices {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let edge = b - a
            var n = SIMD3<Float>(edge.y, 0, -edge.x)
            if !ccw { n = -n }
            n = normalize(n)
            let base = UInt32(positions.count)
            positions += [SIMD3(a.x, 0, a.y), SIMD3(b.x, 0, b.y), SIMD3(b.x, -thickness, b.y), SIMD3(a.x, -thickness, a.y)]
            normals += [n, n, n, n]
            indices += ccw ? [base, base + 2, base + 1, base, base + 3, base + 2] : [base, base + 1, base + 2, base, base + 2, base + 3]
        }

        var descriptor = MeshDescriptor(name: "floor")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return nil }
        var oak = material(RoomPalette.floor, roughness: 0.85)
        oak.faceCulling = .none  // hand-built mesh: don't depend on winding
        return ModelEntity(mesh: mesh, materials: [oak])
    }

    // MARK: Walls

    private static func wallEntity(_ wall: RoomGeometry.Surface, holes: [WallHole], inward: Float) -> Entity {
        let entity = Entity()
        entity.name = "wall:\(wall.id)"
        entity.transform = RealityKit.Transform(matrix: wall.transform.matrix)
        let size = SIMD2(wall.dimensions.x, wall.dimensions.y)
        let wallMaterial = material(RoomPalette.wall, roughness: 0.95)
        let capMaterial = material(RoomPalette.wallTop, roughness: 0.6)

        for piece in RoomGeometry.pieces(wallSize: size, holes: holes) {
            let box = ModelEntity(mesh: .generateBox(width: piece.size.x, height: piece.size.y, depth: wallThickness), materials: [wallMaterial])
            box.position = SIMD3(piece.center.x, piece.center.y, 0)
            entity.addChild(box)
            // A dark cut-line along the wall tops reads like an architect's section.
            if abs(piece.center.y + piece.size.y / 2 - size.y / 2) < 0.01 {
                let cap = ModelEntity(mesh: .generateBox(width: piece.size.x, height: 0.012, depth: wallThickness + 0.004), materials: [capMaterial])
                cap.position = SIMD3(piece.center.x, size.y / 2 + 0.006, 0)
                entity.addChild(cap)
            }
        }
        for hole in holes {
            switch hole.kind {
            case .door: entity.addChild(doorLeaf(hole, inward: inward))
            case .window: windowPane(hole).forEach { entity.addChild($0) }
            case .opening, .wall: break
            }
        }
        return entity
    }

    /// A door leaf hinged at the hole's left edge, swung 65° open into the room.
    /// `inward` is the sign of the wall-local z axis that points into the room.
    private static func doorLeaf(_ hole: WallHole, inward: Float) -> Entity {
        let hinge = Entity()
        hinge.position = SIMD3(hole.center.x - hole.size.x / 2, hole.center.y, 0)
        // Rotating local +x by +θ about y moves it toward -z.
        hinge.orientation = simd_quatf(angle: -inward * .pi * 65 / 180, axis: SIMD3(0, 1, 0))
        let leaf = ModelEntity(mesh: .generateBox(width: hole.size.x - 0.02, height: hole.size.y - 0.01, depth: 0.035, cornerRadius: 0.008),
                               materials: [material(RoomPalette.door, roughness: 0.55)])
        leaf.position = SIMD3((hole.size.x - 0.02) / 2, 0, 0)
        hinge.addChild(leaf)
        return hinge
    }

    private static func windowPane(_ hole: WallHole) -> [Entity] {
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: RoomPalette.glass)
        glass.roughness = .init(floatLiteral: 0.05)
        glass.metallic = .init(floatLiteral: 0)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        let pane = ModelEntity(mesh: .generateBox(width: hole.size.x, height: hole.size.y, depth: 0.02), materials: [glass])
        pane.position = SIMD3(hole.center.x, hole.center.y, 0)
        let sill = ModelEntity(mesh: .generateBox(width: hole.size.x + 0.08, height: 0.03, depth: wallThickness + 0.08, cornerRadius: 0.006),
                               materials: [material(RoomPalette.wall, roughness: 0.7)])
        sill.position = SIMD3(hole.center.x, hole.center.y - hole.size.y / 2 - 0.015, 0)
        return [pane, sill]
    }

    // MARK: Objects

    /// One piece of furniture: a container (named "obj:<id>", the tap target)
    /// holding the colored block and, when `FurnitureFactory` has one for the
    /// category, a stand-in furniture model ("furniture") that hides the block.
    private static func objectEntity(_ object: RoomGeometry.Object) -> Entity {
        let d = object.dimensions
        let tint = RoomPalette.category(object.category)
        let container = Entity()
        container.name = objectPrefix + object.id
        container.transform = RealityKit.Transform(matrix: object.transform.matrix)
        container.components.set(InputTargetComponent())
        container.components.set(CollisionComponent(shapes: [.generateBox(width: d.x, height: d.y, depth: d.z)]))

        let radius = min(0.04, min(d.x, d.y, d.z) / 4)
        let block = ModelEntity(mesh: .generateBox(width: d.x, height: d.y, depth: d.z, cornerRadius: radius),
                                materials: [material(tint, roughness: 0.5)])
        block.name = "block"
        block.components.set(GroundingShadowComponent(castsShadow: true))
        container.addChild(block)
        if let shadow = contactShadow(for: d) { container.addChild(shadow) }

        if let furniture = FurnitureFactory.makeEntity(category: object.category, size: d, tint: tint) {
            furniture.name = "furniture"
            castShadows(furniture)
            container.addChild(furniture)
            block.isEnabled = false
        }
        return container
    }

    /// The visible stand-in for an object: its furniture model if it has one, else its block.
    static func body(of container: Entity) -> Entity? {
        container.findEntity(named: "furniture") ?? container.findEntity(named: "block")
    }

    /// Gives every model under `entity` the same tinted material (and glow when selected).
    static func recolor(_ entity: Entity, _ color: UIColor, roughness: Float, glow: Bool) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = Array(repeating: material(color, roughness: roughness, glow: glow), count: max(model.materials.count, 1))
            entity.components.set(model)
        }
        for child in entity.children where child.name != "label" { recolor(child, color, roughness: roughness, glow: glow) }
    }

    private static func castShadows(_ entity: Entity) {
        if entity.components.has(ModelComponent.self) { entity.components.set(GroundingShadowComponent(castsShadow: true)) }
        for child in entity.children { castShadows(child) }
    }

    /// Floating, camera-facing name tag above an object.
    /// `fontSize` is in room meters; pass something proportional to the room so
    /// labels stay readable however big the room is.
    static func label(_ text: String, above object: RoomGeometry.Object, fontSize: Float) -> Entity {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: CGFloat(fontSize), weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail)
        let textEntity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(white: 0.15, alpha: 1))])
        let bounds = mesh.bounds
        textEntity.position = SIMD3(-bounds.center.x, -bounds.center.y, 0)

        let tag = Entity()
        tag.name = "label"
        tag.position = SIMD3(0, object.dimensions.y / 2 + fontSize * 1.4, 0)
        tag.components.set(BillboardComponent())
        tag.addChild(textEntity)
        return tag
    }

    // MARK: Light

    private static func sunlight(for geometry: RoomGeometry) -> Entity {
        let sun = DirectionalLight()
        sun.name = "sun"
        sun.light.intensity = 2600
        sun.light.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 12, depthBias: 1.5)
        sun.look(at: .zero, from: SIMD3(2.5, 6, 3.5), relativeTo: nil)
        return sun
    }

    static func material(_ color: UIColor, roughness: Float, glow: Bool = false) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: 0)
        if glow {
            m.emissiveColor = .init(color: color)
            m.emissiveIntensity = 0.6
        }
        return m
    }
}
