import Foundation

/// New Home's room shots: one room on its own, furnished, seen from a cozy 3/4 interior angle.
///
/// `FloorPlan.isolating(_:)` cuts a room out as a one-room plan (with the doors and windows on
/// its walls), so every wall becomes an exterior wall with tall and low looks (`VoxelHouse.buildLayers`).
/// `RoomShot.viewDirection` picks the camera side so the two back walls left standing full height
/// are the room's most solid ones (longest, fewest door gaps, preferring walls that were outside
/// walls of the house), and the near two are cut low.
public enum RoomShot {
    /// Horizontal direction from the room's center to the camera, world (x, z), unit length.
    /// Its two back facings (`VoxelHouse.Facing.isBack`) are `backFacings(for:in:)`.
    public static func viewDirection(for room: FloorPlanRoom, in plan: FloorPlan) -> SIMD2<Double> {
        let backs = backWalls(for: room, in: plan)
        // Lean toward squarely facing the more solid wall, but stay within 30-60° of each so both stand.
        let a = backs.x, b = backs.z
        var vx = -a.facing.normal.x * a.score, vz = -b.facing.normal.y * b.score
        let len = (vx * vx + vz * vz).squareRoot()
        guard len > 1e-9 else { return SIMD2(-a.facing.normal.x, -b.facing.normal.y) / 2.0.squareRoot() }
        vx /= len
        vz /= len
        let lo = 0.5, hi = 0.75.squareRoot()
        let cx = min(max(abs(vx), lo), hi)
        let cz = (1 - cx * cx).squareRoot()
        return SIMD2(vx < 0 ? -cx : cx, vz < 0 ? -cz : cz)
    }

    /// Camera yaw (radians, about +Y) for `viewDirection`: the yaw `FloorPlan3DView` orbits with
    /// (eye = target + (sin yaw, _, cos yaw)).
    public static func yaw(for room: FloorPlanRoom, in plan: FloorPlan) -> Double {
        let v = viewDirection(for: room, in: plan)
        return atan2(v.x, v.y)
    }

    /// The facings drawn full height in the shot: one x facing and one z facing.
    public static func backFacings(for room: FloorPlanRoom, in plan: FloorPlan) -> Set<VoxelHouse.Facing> {
        let b = backWalls(for: room, in: plan)
        return [b.x.facing, b.z.facing]
    }

    /// How much solid wall each facing of the room has: its length minus door gaps, plus a
    /// little for walls on the outside of the house (they carry the windows, and nothing is behind them).
    static func wallScores(for room: FloorPlanRoom, in plan: FloorPlan) -> [VoxelHouse.Facing: Double] {
        var scores: [VoxelHouse.Facing: Double] = [:]
        let flip = room.signedArea < 0 ? -1.0 : 1.0
        for (a, b) in room.edges {
            let d = b - a, len = d.length
            guard len > 0.05 else { continue }
            // Left of travel is inward for counterclockwise rooms; outward is the other side.
            let outward = PlanPoint(d.y / len, -d.x / len) * flip
            let facing = VoxelHouse.Facing(nearest: outward.x, outward.y)
            let doorGap = plan.doors.compactMap { FloorPlan.span(of: $0, onEdge: a, b) }.reduce(0) { $0 + ($1.1 - $1.0) }
            let probe = (a + b) * 0.5 + outward * 0.2
            let exterior = !plan.rooms.contains { $0.name != room.name && $0.contains(probe) }
            let score = max(0, len - doorGap) * (exterior ? 1.15 : 1)
            scores[facing, default: 0] += score
        }
        return scores
    }

    private static func backWalls(for room: FloorPlanRoom, in plan: FloorPlan)
        -> (x: (facing: VoxelHouse.Facing, score: Double), z: (facing: VoxelHouse.Facing, score: Double)) {
        let s = wallScores(for: room, in: plan)
        // Ties go to -x / -z (the camera then sits front-right, like the whole-home view).
        let x: VoxelHouse.Facing = (s[.plusX] ?? 0) > (s[.minusX] ?? 0) ? .plusX : .minusX
        let z: VoxelHouse.Facing = (s[.plusZ] ?? 0) > (s[.minusZ] ?? 0) ? .plusZ : .minusZ
        return ((x, max(s[x] ?? 0, 0.1)), (z, max(s[z] ?? 0, 0.1)))
    }

    /// Placements that belong in a room's shot.
    public static func placements(_ placements: [Placement], in room: String) -> [Placement] {
        placements.filter { $0.room == room }
    }
}

extension FloorPlan {
    /// The room named `name` as a plan of its own, keeping the doors and windows on its walls.
    public func isolating(_ name: String) -> FloorPlan? {
        guard let room = room(named: name) else { return nil }
        func onRoom(_ o: WallOpening) -> Bool { room.edges.contains { a, b in Self.span(of: o, onEdge: a, b) != nil } }
        return FloorPlan(rooms: [room], doors: doors.filter(onRoom), windows: windows.filter(onRoom), wallHeightM: wallHeightM)
    }
}
