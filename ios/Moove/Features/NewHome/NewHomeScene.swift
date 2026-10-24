import RealityKit
import UIKit
import MooveKit

/// Builds RealityKit entities for a floor plan: the voxel dollhouse shell (wooden base,
/// plank floors, tiled walls with door gaps and windows, from `VoxelHouse.buildLayers`) plus
/// small room labels floating just above the low wall tops. World space matches RoomPlan
/// (meters, Y-up; plan y is world z), so items drop straight in at `VoxelHouse.floorTopM`.
///
/// Dollhouse walls: every wall is built up to `cutawayHeightM`; the exterior walls above that,
/// up to the plan's wall height, are one entity per facing. `setViewDirection` shows only the
/// facings that point away from the camera, so the back walls stand full height (with their
/// windows and door heads) and the near ones stay low, following the camera as it orbits.
@MainActor
final class NewHomeScene {
    /// Near walls (and all interior walls) are cut at this height so the camera can see in.
    static let cutawayHeightM: Float = 1.1

    let root = Entity()
    private(set) var plan: FloorPlan?
    private var colors: [VoxelColor?] = [nil, nil]
    private var houseTask: Task<Void, Never>?
    /// Full-height exterior walls above the cut, by outward facing.
    private var upperWalls: [VoxelHouse.Facing: Entity] = [:]
    /// Horizontal direction from the orbit target to the camera, world (x, z).
    private var viewDirection = SIMD2<Double>(0, 1)

    /// `wallColor` / `floorColor`: colors measured from the scan's photos, when known.
    func build(_ plan: FloorPlan, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) {
        guard plan != self.plan || [wallColor, floorColor] != colors else { return }
        self.plan = plan
        colors = [wallColor, floorColor]
        houseTask?.cancel()
        root.children.removeAll()
        upperWalls = [:]
        for room in plan.rooms { root.addChild(Self.label(for: room)) }

        // Voxelizing and meshing the whole house is pure MooveKit work: do it off the main actor.
        let height = Double(Self.cutawayHeightM)
        houseTask = Task { [weak self] in
            let meshes = await Task.detached(priority: .userInitiated) {
                let layers = VoxelHouse.buildLayers(plan, cutawayHeightM: height, wallColor: wallColor, floorColor: floorColor)
                return (base: VoxelMesher.mesh(layers.base, centered: false),
                        upper: layers.upper.mapValues { (mesh: VoxelMesher.mesh($0.grid, centered: false), offset: $0.offset) })
            }.value
            guard let self, !Task.isCancelled, self.plan == plan,
                  let house = VoxelEntity.entity(meshes.base, name: "house") else { return }
            let o = VoxelHouse.origin(of: plan)
            let origin = SIMD3<Float>(Float(o.x), Float(o.y), Float(o.z))
            house.position = origin
            self.root.addChild(house)
            for (facing, layer) in meshes.upper {
                guard let walls = VoxelEntity.entity(layer.mesh, name: "walls.\(facing)") else { continue }
                walls.position = origin + SIMD3<Float>(layer.offset) * Float(VoxelGrid.voxelSize)
                self.root.addChild(walls)
                self.upperWalls[facing] = walls
            }
            self.applyViewDirection()
        }
    }

    /// The camera's horizontal direction from its target, world (x, z). Cheap: only toggles
    /// which upper-wall entities are enabled.
    func setViewDirection(_ v: SIMD2<Double>) {
        viewDirection = v
        applyViewDirection()
    }

    private func applyViewDirection() {
        for (facing, walls) in upperWalls {
            let back = facing.isBack(viewFromTarget: viewDirection)
            if walls.isEnabled != back { walls.isEnabled = back }
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
