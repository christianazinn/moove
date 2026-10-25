import RealityKit
import UIKit
import MooveKit

/// Turns a `VoxelMesh` into a RealityKit `ModelEntity`: one mesh, one material per
/// palette color (per-face material indices). Furniture meshes are cached by spec so
/// repeated pieces (four dining chairs) share one MeshResource.
@MainActor
enum VoxelEntity {
    private struct Resources {
        let mesh: MeshResource
        let materials: [any RealityKit.Material]
    }

    private static var furnitureCache: [VoxelItemSpec: Resources] = [:]
    private static var materialCache: [VoxelColor: PhysicallyBasedMaterial] = [:]
    /// Furniture models `prepare` is building right now, so a second caller waits for them.
    private static var preparing: [VoxelItemSpec: Task<Void, Never>] = [:]

    /// A model for `mesh`, or nil if it's empty or RealityKit rejects it.
    static func entity(_ mesh: VoxelMesh, name: String) -> ModelEntity? {
        guard let r = resources(mesh, name: name) else { return nil }
        let e = ModelEntity(mesh: r.mesh, materials: r.materials)
        e.name = name
        return e
    }

    /// A voxel model for one piece of furniture: origin at the bottom center, front toward +z.
    /// `wallMounted`: the flat wall-hung variant (no easel leg / TV feet). Falls back to a plain
    /// box if the model can't be built.
    static func furniture(_ item: LayoutItem, wallMounted: Bool = false) -> ModelEntity {
        let spec = Self.spec(item, wallMounted: wallMounted)
        let r: Resources? = furnitureCache[spec] ?? {
            let made = resources(VoxelMesher.mesh(VoxelModels.build(spec), centered: true), name: spec.name)
            if let made { furnitureCache[spec] = made }
            return made
        }()
        if let r {
            let e = ModelEntity(mesh: r.mesh, materials: r.materials)
            e.name = item.name
            return e
        }
        // generateBox is centered; lift it inside a holder so the origin is the bottom, like voxel meshes.
        let w = Float(item.widthM), h = Float(item.heightM), d = Float(spec.depthM)
        let body = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [material(0xB98D5E)])
        body.position.y = h / 2
        let holder = ModelEntity()
        holder.addChild(body)
        holder.name = item.name
        return holder
    }

    /// The spec `furniture` builds (and caches) for `item`.
    nonisolated static func spec(_ item: LayoutItem, wallMounted: Bool) -> VoxelItemSpec {
        wallMounted ? VoxelModels.wallVariant(VoxelItemSpec(item)) : VoxelItemSpec(item)
    }

    /// Builds and caches the furniture models `FurnitureLayer` will show for these placements
    /// (mattresses drawn with their bed skipped), so showing them later costs no meshing.
    static func prepare(_ items: [LayoutItem], placements: [Placement]) async {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let onBeds = MattressPairing.drawnWithBed(placements, items: items)
        await prepare(placements.compactMap { p in
            onBeds.contains(p.itemId) ? nil : byId[p.itemId].map { Self.spec($0, wallMounted: p.isWallMounted) }
        })
    }

    /// Voxelizes and meshes `specs` off the main actor, then makes their MeshResources on it
    /// one per frame (RealityKit wants them on the main actor), so frames keep drawing meanwhile.
    static func prepare(_ specs: [VoxelItemSpec]) async {
        let unique = Array(Set(specs))
        let waiting = unique.compactMap { preparing[$0] }
        let todo = unique.filter { furnitureCache[$0] == nil && preparing[$0] == nil }
        if !todo.isEmpty {
            let task = Task { @MainActor in
                let meshes = await Task.detached(priority: .userInitiated) {
                    todo.map { (spec: $0, mesh: VoxelMesher.mesh(VoxelModels.build($0), centered: true)) }
                }.value
                for (i, made) in meshes.enumerated() {
                    if i > 0 { try? await Task.sleep(for: .milliseconds(16)) }
                    if Self.furnitureCache[made.spec] == nil, let r = Self.resources(made.mesh, name: made.spec.name) {
                        Self.furnitureCache[made.spec] = r
                    }
                }
                for spec in todo { Self.preparing[spec] = nil }
            }
            for spec in todo { preparing[spec] = task }
            await task.value
        }
        for task in waiting { await task.value }
    }

    private static func resources(_ mesh: VoxelMesh, name: String) -> Resources? {
        guard mesh.triangleCount > 0, !mesh.palette.isEmpty, mesh.positions.count == mesh.normals.count else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(mesh.positions)
        d.normals = MeshBuffers.Normals(mesh.normals)
        d.primitives = .triangles(mesh.indices)
        d.materials = mesh.triangleColors.count == mesh.triangleCount ? .perFace(mesh.triangleColors) : .allFaces(0)
        guard let resource = try? MeshResource.generate(from: [d]) else { return nil }
        return Resources(mesh: resource, materials: mesh.palette.map { material($0) })
    }

    /// Matte voxel material; the house's glass color is translucent.
    static func material(_ color: VoxelColor) -> PhysicallyBasedMaterial {
        if let m = materialCache[color] { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Theme.uiColor(color))
        m.metallic = .init(floatLiteral: 0)
        if color == VoxelHouse.Palette.glass {
            m.roughness = .init(floatLiteral: 0.15)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.45))
        } else {
            m.roughness = .init(floatLiteral: 0.85)
        }
        materialCache[color] = m
        return m
    }
}
