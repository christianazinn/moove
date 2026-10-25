import RealityKit
import UIKit
import MooveKit

/// The kept items as voxel models in the new home, plus the fly-in: items start where they
/// stood in the scanned old room (`FlyInStarts`: that room's footprint drawn left of the house),
/// or piled beside the house when there's no scanned spot, then lift, arc over the walls and
/// settle into their layout spots, staggered. Switching layouts glides them to new spots.
/// Props `PropPlacer` put on furniture land on top of it (`Placement.elevationM`); wall-hung
/// items use their flat wall model.
@MainActor
final class FurnitureLayer {
    /// How pieces first appear. `.flyIn` (default, the Move page and scan results) is the arc
    /// from the old room / pile; `.dropIn` (the Scan hero) builds the room from above.
    enum Entrance {
        case flyIn
        /// Pieces drop a short way onto their spots layer by layer (floor pieces, then things on
        /// them, wall pieces last), staggered, with a tiny settle; just shown with Reduce Motion.
        case dropIn
    }

    let root = Entity()
    /// The house shell; a drop-in waits until it's built, so pieces never fall into nothing.
    weak var shell: NewHomeScene?
    private var dropping: Task<Void, Never>?
    private var entities: [UInt64: ModelEntity] = [:]
    /// Items currently shown with their flat wall-hung model.
    private var wallModels: Set<UInt64> = []
    private var items: [UInt64: LayoutItem] = [:]
    private var flight: Task<Void, Never>?
    /// The old rooms' footprints (low voxel shells) shown during a fly-in from scanned spots.
    private let oldRooms = Entity()
    private var oldRoomsTask: Task<Void, Never>?

    init() {
        root.addChild(oldRooms)
    }

    /// Shows `placements`, flying in if `flyIn` (from `starts` where an item has one, else from the
    /// pile), otherwise gliding from where items are. Returns how long the fly-in takes (0 if none).
    @discardableResult
    func show(_ placements: [Placement], items list: [LayoutItem], plan: FloorPlan, flyIn: Bool, starts: FlyInStarts? = nil,
              entrance: Entrance = .flyIn) -> Double {
        if let dropping {
            // Interrupted drop: show every piece again (the moves below put them in place).
            dropping.cancel()
            self.dropping = nil
            for e in entities.values { e.isEnabled = true }
        }
        flight?.cancel()
        oldRoomsTask?.cancel()
        oldRooms.children.removeAll()
        items = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // A mattress laid on its bed frame is drawn as part of the bed (the bed model has one).
        let onBeds = MattressPairing.drawnWithBed(placements, items: list)
        let placed = placements.filter { items[$0.itemId] != nil && !onBeds.contains($0.itemId) }
        let wanted = Set(placed.map(\.itemId))
        // Drop items that left, and items switching between the floor and the wall model.
        let wall = Set(placed.filter(\.isWallMounted).map(\.itemId))
        for (id, e) in entities where !wanted.contains(id) || wall.contains(id) != wallModels.contains(id) {
            e.removeFromParent()
            entities[id] = nil
        }
        wallModels = wall
        var newcomers = Set<UInt64>()
        for p in placed where entities[p.itemId] == nil {
            let e = VoxelEntity.furniture(items[p.itemId]!, wallMounted: p.isWallMounted)
            entities[p.itemId] = e
            root.addChild(e)
            newcomers.insert(p.itemId)
        }

        if flyIn, entrance == .dropIn {
            return dropIn(placed)
        }
        if flyIn {
            // Scanned spot in the old room when known; the pile for the rest (added by photo, no scan).
            let scanned = starts?.placements ?? [:]
            let pile = Self.pile(placed.filter { scanned[$0.itemId] == nil }.compactMap { items[$0.itemId] }, beside: plan.bounds)
            for p in placed {
                if let start = scanned[p.itemId] {
                    entities[p.itemId]?.transform = transform(for: start)
                } else if let t = pile[p.itemId] {
                    entities[p.itemId]?.transform = t
                }
            }
            let shownRooms = placed.contains { scanned[$0.itemId] != nil } ? (starts?.rooms ?? []) : []
            showOldRooms(shownRooms)
            // Biggest pieces first, like real movers; things that sit on others land after them.
            let order = placed.sorted { (($0.onTopOf == nil ? 0 : 1), -area($0)) < (($1.onTopOf == nil ? 0 : 1), -area($1)) }
            let duration = Double(max(order.count - 1, 0)) * 0.11 + 1.6
            flight = Task { [weak self] in
                for (i, p) in order.enumerated() {
                    if i > 0 { try? await Task.sleep(for: .milliseconds(110)) }
                    guard let self, !Task.isCancelled, let e = self.entities[p.itemId] else { return }
                    self.launch(e, to: self.transform(for: p))
                }
                // Everything has left the old room: clear its footprint.
                try? await Task.sleep(for: .seconds(1.6))
                guard let self, !Task.isCancelled else { return }
                self.oldRoomsTask?.cancel()
                self.oldRooms.children.removeAll()
            }
            return duration
        } else {
            for p in placed {
                guard let e = entities[p.itemId] else { continue }
                let target = transform(for: p)
                if newcomers.contains(p.itemId) {
                    e.transform = target
                } else {
                    _ = e.move(to: target, relativeTo: root, duration: 0.7, timingFunction: .easeInOut)
                }
            }
            return 0
        }
    }

    /// The `.dropIn` entrance: each piece starts hidden a short way above its spot, then
    /// appears and falls onto it (ease-out), squashes a hair and settles. Floor pieces first
    /// (biggest first), then things on furniture (lowest first), wall pieces last; ≤ 2 s in all.
    /// Transform-only: the entities are already built. Returns how long it takes.
    private func dropIn(_ placed: [Placement]) -> Double {
        let targets = Dictionary(placed.map { ($0.itemId, transform(for: $0)) }, uniquingKeysWith: { a, _ in a })
        if Self.showsWithoutMotion {
            for (id, t) in targets { entities[id]?.transform = t }
            return 0
        }
        func tier(_ p: Placement) -> Int {
            p.isWallMounted ? 2 : (p.onTopOf != nil || (p.elevationM ?? 0) > 0.05 ? 1 : 0)
        }
        let order = placed.sorted { a, b in
            (tier(a), a.elevationM ?? 0, -area(a), a.itemId) < (tier(b), b.elevationM ?? 0, -area(b), b.itemId)
        }
        let fall = 0.42, squash = 0.07, recover = 0.12
        let lift: [Float] = [0.55, 0.38, 0.3]
        let stagger = order.count > 1 ? min(0.085, max(0.03, (2.0 - fall - squash - recover) / Double(order.count - 1))) : 0

        struct Step {
            var at: Double
            var id: UInt64
            var appear: Transform?
            var to: Transform
            var duration: Double
            var timing: AnimationTimingFunction
        }
        var steps: [Step] = []
        for (i, p) in order.enumerated() {
            guard let target = targets[p.itemId] else { continue }
            let t0 = Double(i) * stagger
            var from = target
            from.translation.y += lift[tier(p)]
            var squashed = target
            squashed.scale = [1.03, 0.95, 1.03]
            steps.append(Step(at: t0, id: p.itemId, appear: from, to: target, duration: fall, timing: .easeOut))
            steps.append(Step(at: t0 + fall, id: p.itemId, to: squashed, duration: squash, timing: .easeOut))
            steps.append(Step(at: t0 + fall + squash, id: p.itemId, to: target, duration: recover, timing: .easeInOut))
            entities[p.itemId]?.transform = target
            entities[p.itemId]?.isEnabled = false
        }
        let timeline = steps.sorted { $0.at < $1.at }

        dropping = Task { [weak self] in
            // Wait for the shell (up to 3 s), so the room is there before anything falls into it.
            let waitStart = ContinuousClock.now
            while self?.shell?.isBuilt == false, ContinuousClock.now - waitStart < .seconds(3) {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
            }
            let start = ContinuousClock.now
            for step in timeline {
                let at = start + .milliseconds(Int(step.at * 1000))
                if at > ContinuousClock.now { try? await Task.sleep(until: at, clock: .continuous) }
                guard let self, !Task.isCancelled else { return }
                guard let e = self.entities[step.id] else { continue }
                if let appear = step.appear {
                    e.transform = appear
                    e.isEnabled = true
                }
                _ = e.move(to: step.to, relativeTo: self.root, duration: step.duration, timingFunction: step.timing)
            }
            guard let self, !Task.isCancelled else { return }
            self.dropping = nil
        }
        return timeline.map { $0.at + $0.duration }.max() ?? 0
    }

    /// Reduce Motion, and UI tests (screenshots want the finished room): no drop.
    private static var showsWithoutMotion: Bool {
        if UIAccessibility.isReduceMotionEnabled { return true }
        #if DEBUG
        if ProcessInfo.processInfo.environment["MOOVE_UI_TEST_RESET"] != nil { return true }
        #endif
        return false
    }

    /// The old rooms as low voxel shells (floor and a short wall stub) where the fly-in starts.
    private func showOldRooms(_ plans: [FloorPlan]) {
        guard !plans.isEmpty else { return }
        oldRoomsTask = Task { [weak self] in
            for (i, plan) in plans.enumerated() {
                let mesh = await Task.detached(priority: .userInitiated) {
                    VoxelMesher.mesh(VoxelHouse.build(plan, cutawayHeightM: 0.25, realism: false), centered: false)
                }.value
                guard let self, !Task.isCancelled, let shell = VoxelEntity.entity(mesh, name: "old-room-\(i)") else { return }
                let o = VoxelHouse.origin(of: plan)
                shell.position = [Float(o.x), Float(o.y), Float(o.z)]
                self.oldRooms.addChild(shell)
            }
        }
    }

    private func area(_ p: Placement) -> Double {
        items[p.itemId].map { $0.widthM * $0.depthM } ?? 0
    }

    private func transform(for p: Placement) -> Transform {
        // Voxel models have their origin at the bottom center; they stand on the plank floor,
        // or `elevationM` above it (on a nightstand, hung on a wall).
        Transform(
            scale: .one,
            rotation: simd_quatf(angle: Float(p.rotationDeg * .pi / 180), axis: [0, 1, 0]),
            translation: [Float(p.x), Float(VoxelHouse.floorTopM + (p.elevationM ?? 0)), Float(p.y)]
        )
    }

    /// Up to an apex above the midpoint, then down onto the spot: a two-segment arc.
    private func launch(_ e: ModelEntity, to target: Transform) {
        let start = e.transform
        let distance = simd_distance(start.translation, target.translation)
        var apex = target
        apex.translation = (start.translation + target.translation) / 2
        apex.translation.y = max(start.translation.y, target.translation.y) + 1.6 + distance * 0.12
        apex.rotation = simd_slerp(start.rotation, target.rotation, 0.5)
        let up = 0.5 + Double(distance) * 0.02, down = 0.45 + Double(distance) * 0.015
        _ = e.move(to: apex, relativeTo: root, duration: up, timingFunction: .easeOut)
        Task { [weak e] in
            try? await Task.sleep(for: .seconds(up))
            guard let e, !Task.isCancelled else { return }
            _ = e.move(to: target, relativeTo: e.parent, duration: down, timingFunction: .easeIn)
        }
    }

    // MARK: Look

    /// Items laid out in rows to the left of the house: where the fly-in starts.
    private static func pile(_ items: [LayoutItem], beside b: PlanBounds) -> [UInt64: Transform] {
        var out: [UInt64: Transform] = [:]
        let columns = 3
        var x = 0.0, z = 0.0, rowDepth = 0.0, col = 0
        let originX = b.minX - 6.0, originZ = b.center.y - 3
        for item in items.sorted(by: { $0.id < $1.id }) {
            if col == columns { col = 0; x = 0; z += rowDepth + 0.3; rowDepth = 0 }
            out[item.id] = Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: [Float(originX + x + item.widthM / 2), 0, Float(originZ + z + item.depthM / 2)])
            x += item.widthM + 0.3
            rowDepth = max(rowDepth, item.depthM)
            col += 1
        }
        return out
    }
}
