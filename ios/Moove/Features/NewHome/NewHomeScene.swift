import RealityKit
import UIKit
import MooveKit

/// Builds RealityKit entities for a floor plan: the voxel dollhouse shell (wooden base,
/// plank floors, tiled walls with door gaps and windows, from `VoxelHouse.buildLayers`). No
/// floating room names (Lisa: removed). World space matches RoomPlan
/// (meters, Y-up; plan y is world z), so items drop straight in at `VoxelHouse.floorTopM`.
///
/// Dollhouse walls: interior walls are cut at `cutawayHeightM`; each exterior facing (and each
/// corner shared by two) has a tall and a low wall piece (`VoxelHouse.buildLayers`).
/// `setViewDirection` shows the tall pieces of the facings that point away from the camera and
/// the low pieces of the rest, so the back walls stand full height as one continuous wall (with
/// their windows, door heads and curtains at the window head) and the near ones stay low with a
/// cap, following the camera as it orbits.
@MainActor
final class NewHomeScene {
    /// Near walls (and all interior walls) are cut at this height so the camera can see in.
    static let cutawayHeightM: Float = 1.1

    let root = Entity()
    private(set) var plan: FloorPlan?
    private var colors: [VoxelColor?] = [nil, nil]
    private var houseTask: Task<Void, Never>?
    /// Exterior wall pieces (tall and low looks), toggled by the view direction.
    private var wallPieces: [(layer: VoxelHouse.Layer, entity: Entity)] = []
    /// Horizontal direction from the orbit target to the camera, world (x, z).
    private var viewDirection = SIMD2<Double>(0, 1)
    /// True once the shell's meshes are in the scene for the current plan.
    private(set) var isBuilt = false
    /// Called each time the shell finishes building (room shots wait for it before a snapshot).
    var onBuilt: (() -> Void)?

    /// `wallColor` / `floorColor`: colors measured from the scan's photos, when known.
    /// A shell `prepare` already built goes in at once; otherwise it's built first (meshing off
    /// the main actor) and appears when done.
    func build(_ plan: FloorPlan, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) {
        guard plan != self.plan || [wallColor, floorColor] != colors else { return }
        self.plan = plan
        colors = [wallColor, floorColor]
        houseTask?.cancel()
        root.children.removeAll()
        wallPieces = []
        isBuilt = false

        let key = ShellKey(plan: plan, wallColor: wallColor, floorColor: floorColor)
        if let shell = Self.shells[key] { return apply(shell) }
        houseTask = Task { [weak self] in
            await Self.prepare(plan, wallColor: wallColor, floorColor: floorColor)
            guard let self, !Task.isCancelled, self.plan == plan, self.colors == [wallColor, floorColor],
                  let shell = Self.shells[key] else { return }
            self.apply(shell)
        }
    }

    /// Clones of the prepared shell's entities (they share its MeshResources), so this is cheap.
    private func apply(_ shell: Shell) {
        root.addChild(shell.house.clone(recursive: true))
        for piece in shell.pieces {
            let walls = piece.entity.clone(recursive: true)
            root.addChild(walls)
            wallPieces.append((piece.layer, walls))
        }
        applyViewDirection()
        isBuilt = true
        onBuilt?()
    }

    // MARK: Prepared shells

    private struct ShellKey: Hashable {
        var plan: FloorPlan
        var wallColor: VoxelColor?
        var floorColor: VoxelColor?
    }

    /// A built shell, never in a scene itself: `apply` adds clones.
    private struct Shell {
        var house: ModelEntity
        var pieces: [(layer: VoxelHouse.Layer, entity: ModelEntity)]
    }

    private static var shells: [ShellKey: Shell] = [:]
    private static var shellOrder: [ShellKey] = []
    private static var shellTasks: [ShellKey: Task<Void, Never>] = [:]

    /// Builds the house shell for `plan` ahead of time (e.g. at launch for the Scan hero):
    /// voxelizing and meshing off the main actor, then one MeshResource per frame on it.
    /// Keeps the last few shells.
    static func prepare(_ plan: FloorPlan, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) async {
        let key = ShellKey(plan: plan, wallColor: wallColor, floorColor: floorColor)
        if shells[key] != nil { return }
        if let task = shellTasks[key] { return await task.value }
        let height = Double(cutawayHeightM)
        let task = Task { @MainActor in
            defer { Self.shellTasks[key] = nil }
            let meshes = await Task.detached(priority: .userInitiated) {
                let layers = VoxelHouse.buildLayers(plan, cutawayHeightM: height, wallColor: wallColor, floorColor: floorColor)
                return (base: VoxelMesher.mesh(layers.base, centered: false),
                        pieces: layers.layers.map { (layer: $0, mesh: VoxelMesher.mesh($0.grid, centered: false)) })
            }.value
            guard let house = VoxelEntity.entity(meshes.base, name: "house") else { return }
            let o = VoxelHouse.origin(of: plan)
            let origin = SIMD3<Float>(Float(o.x), Float(o.y), Float(o.z))
            house.position = origin
            var pieces: [(layer: VoxelHouse.Layer, entity: ModelEntity)] = []
            for (n, piece) in meshes.pieces.enumerated() {
                try? await Task.sleep(for: .milliseconds(16))
                let layer = piece.layer
                guard let walls = VoxelEntity.entity(piece.mesh, name: "walls.\(layer.tall ? "tall" : "low").\(n)") else { continue }
                walls.position = origin + SIMD3<Float>(layer.offset) * Float(VoxelGrid.voxelSize)
                pieces.append((layer, walls))
            }
            Self.shells[key] = Shell(house: house, pieces: pieces)
            Self.shellOrder.removeAll { $0 == key }
            Self.shellOrder.append(key)
            while Self.shellOrder.count > 6 { Self.shells[Self.shellOrder.removeFirst()] = nil }
        }
        shellTasks[key] = task
        await task.value
    }

    /// The camera's horizontal direction from its target, world (x, z). Cheap: only toggles
    /// which wall-piece entities are enabled.
    func setViewDirection(_ v: SIMD2<Double>) {
        viewDirection = v
        applyViewDirection()
    }

    private func applyViewDirection() {
        for (layer, walls) in wallPieces {
            let shown = layer.isShown(viewFromTarget: viewDirection)
            if walls.isEnabled != shown { walls.isEnabled = shown }
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
}
