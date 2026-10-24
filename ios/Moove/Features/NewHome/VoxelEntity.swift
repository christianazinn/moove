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
        let spec = wallMounted ? VoxelModels.wallVariant(VoxelItemSpec(item)) : VoxelItemSpec(item)
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
