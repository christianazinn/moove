import RealityKit
import UIKit
import MooveKit

/// Builds RealityKit entities for a floor plan: the voxel dollhouse shell (wooden base,
/// plank floors, cut-away tiled walls with door gaps and windows, from `VoxelHouse`) plus
/// small room labels floating just above the wall tops. World space matches RoomPlan
/// (meters, Y-up; plan y is world z), so items drop straight in at `VoxelHouse.floorTopM`.
@MainActor
final class NewHomeScene {
    /// Walls are cut at this height so the camera can see in from above (dollhouse view).
    static let cutawayHeightM: Float = 1.1

    let root = Entity()
    private(set) var plan: FloorPlan?
    private var colors: [VoxelColor?] = [nil, nil]
    private var houseTask: Task<Void, Never>?

    /// `wallColor` / `floorColor`: colors measured from the scan's photos, when known.
    func build(_ plan: FloorPlan, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) {
        guard plan != self.plan || [wallColor, floorColor] != colors else { return }
        self.plan = plan
        colors = [wallColor, floorColor]
        houseTask?.cancel()
        root.children.removeAll()
        for room in plan.rooms { root.addChild(Self.label(for: room)) }

        // Voxelizing and meshing the whole house is pure MooveKit work: do it off the main actor.
        let height = Double(Self.cutawayHeightM)
        houseTask = Task { [weak self] in
            let mesh = await Task.detached(priority: .userInitiated) {
                VoxelMesher.mesh(VoxelHouse.build(plan, cutawayHeightM: height, wallColor: wallColor, floorColor: floorColor), centered: false)
            }.value
            guard let self, !Task.isCancelled, self.plan == plan,
                  let house = VoxelEntity.entity(mesh, name: "house") else { return }
            let o = VoxelHouse.origin(of: plan)
            house.position = [Float(o.x), Float(o.y), Float(o.z)]
            self.root.addChild(house)
        }
    }

    /// Center and rough radius of the plan, for framing the camera.
    var focus: (center: SIMD3<Float>, radius: Float) {
        guard let plan, !plan.rooms.isEmpty else { return (.zero, 5) }
        return Self.focus(on: plan.bounds)
    }

    /// Center (at half wall height) and half the diagonal of `b`.
    static func focus(on b: PlanBounds) -> (center: SIMD3<Float>, radius: Float) {
        let c = b.center
        let y = Float(VoxelHouse.floorTopM) + cutawayHeightM * 0.4
        return ([Float(c.x), y, Float(c.y)], max(1, Float((b.width * b.width + b.depth * b.depth).squareRoot()) / 2))
    }

    // MARK: Labels

    /// Small mono label lying flat just above the wall tops, so furniture doesn't hide it.
    private static func label(for room: FloorPlanRoom) -> Entity {
        let group = Entity()
        let c = room.centroid
        group.position = [Float(c.x), Float(VoxelHouse.floorTopM) + cutawayHeightM + 0.03, Float(c.y)]
        // Text meshes face +Z; lay them flat, reading upright from the default (front) camera.
        group.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        let small = min(room.widthM, room.depthM) < 2
        let title = text(room.name.uppercased(), size: small ? 0.13 : 0.17, weight: .semibold, color: Theme.uiColor(0x2A241D))
        group.addChild(title)
        if room.kind != .hallway {
            let dims = text(String(format: "%.1f × %.1f m", room.widthM, room.depthM), size: small ? 0.1 : 0.12,
                            weight: .regular, color: Theme.uiColor(0x5E564B))
            dims.position.y -= small ? 0.17 : 0.22
            group.addChild(dims)
        }
        return group
    }

    private static func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generateText(
            string, extrusionDepth: 0.003, font: .monospacedSystemFont(ofSize: size, weight: weight),
            containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail
        )
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: color)])
        let b = mesh.bounds
        entity.position = [-b.center.x, -b.center.y, 0]
        return entity
    }
}
