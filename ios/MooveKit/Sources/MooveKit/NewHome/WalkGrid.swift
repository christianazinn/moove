import Foundation

/// Circulation check for one room (Merrell et al. 2011's circulation term, simplified): the
/// free floor for a person of a given half-width, on a 10 cm grid. A cell is walkable when it
/// is inside the room and at least `radius` from every wall (door openings excepted) and every
/// piece of furniture. `reachable` floods from the room's doors and says which spots a person
/// walking a `2 * radius` wide path can get to.
struct WalkGrid {
    static let cell = 0.1

    let room: FloorPlanRoom
    let radius: Double
    let origin: PlanPoint
    let nx: Int, ny: Int
    private(set) var blocked: [Bool]
    /// Points just inside each door of the room (where people come in).
    private(set) var entries: [PlanPoint] = []

    init(room: FloorPlanRoom, plan: FloorPlan, furniture: [OrientedRect], radius: Double) {
        self.room = room
        self.radius = radius
        let b = room.bounds
        origin = PlanPoint(b.minX, b.minY)
        nx = max(1, Int((b.width / Self.cell).rounded(.up)))
        ny = max(1, Int((b.depth / Self.cell).rounded(.up)))
        blocked = Array(repeating: false, count: nx * ny)
        let c = Self.cell
        // Outside the room.
        for j in 0..<ny {
            for i in 0..<nx where !room.contains(PlanPoint(origin.x + (Double(i) + 0.5) * c, origin.y + (Double(j) + 0.5) * c)) {
                blocked[j * nx + i] = true
            }
        }
        // Walls, minus the doorways.
        for (a, e) in room.edges {
            for piece in FloorPlan.cut(from: a, to: e, openings: plan.doors) {
                markSegment(piece.0, piece.1, r: radius)
            }
        }
        for rect in furniture { markRect(rect, r: radius) }
        // Entries: door centers nudged into this room.
        var entries: [PlanPoint] = []
        let flip = room.signedArea < 0 ? -1.0 : 1.0
        for (a, e) in room.edges {
            let len = (e - a).length
            guard len > 1e-9 else { continue }
            let dir = (e - a) * (1 / len)
            let inward = PlanPoint(-dir.y, dir.x) * flip
            for d in plan.doors {
                guard let span = FloorPlan.span(of: d, onEdge: a, e) else { continue }
                entries.append(a + dir * ((span.0 + span.1) / 2) + inward * max(radius, 0.25))
            }
        }
        self.entries = entries
    }

    private func index(_ p: PlanPoint) -> (Int, Int) {
        (Int(((p.x - origin.x) / Self.cell).rounded(.down)), Int(((p.y - origin.y) / Self.cell).rounded(.down)))
    }

    private func center(_ i: Int, _ j: Int) -> PlanPoint {
        PlanPoint(origin.x + (Double(i) + 0.5) * Self.cell, origin.y + (Double(j) + 0.5) * Self.cell)
    }

    /// This grid with more furniture marked (build the empty room once, then add pieces).
    func adding(_ furniture: [OrientedRect]) -> WalkGrid {
        var g = self
        for r in furniture { g.markRect(r, r: radius) }
        return g
    }

    /// lo...hi clamped to 0..<n, nil when empty.
    static func span(_ lo: Int, _ hi: Int, _ n: Int) -> ClosedRange<Int>? {
        let a = max(0, lo), b = min(n - 1, hi)
        return a <= b ? a...b : nil
    }

    private mutating func mark(minX: Double, minY: Double, maxX: Double, maxY: Double, _ hit: (PlanPoint) -> Bool) {
        let (i0, j0) = index(PlanPoint(minX, minY)), (i1, j1) = index(PlanPoint(maxX, maxY))
        guard let js = Self.span(j0, j1, ny), let ir = Self.span(i0, i1, nx) else { return }
        for j in js {
            for i in ir where !blocked[j * nx + i] && hit(center(i, j)) {
                blocked[j * nx + i] = true
            }
        }
    }

    private mutating func markSegment(_ a: PlanPoint, _ b: PlanPoint, r: Double) {
        mark(minX: min(a.x, b.x) - r, minY: min(a.y, b.y) - r, maxX: max(a.x, b.x) + r, maxY: max(a.y, b.y) + r) { p in
            PropPlacer.distance(p, a, b) < r
        }
    }

    mutating func markRect(_ rect: OrientedRect, r: Double) {
        let cs = rect.corners
        let (ax, az) = rect.axes
        mark(minX: cs.map(\.x).min()! - r, minY: cs.map(\.y).min()! - r, maxX: cs.map(\.x).max()! + r, maxY: cs.map(\.y).max()! + r) { p in
            let v = p - rect.center
            let u = max(0, abs(v.dot(ax)) - rect.halfWidth), w = max(0, abs(v.dot(az)) - rect.halfDepth)
            return u * u + w * w < r * r
        }
    }

    /// For each target, whether a walkable cell within `tolerance` of it can be reached from a
    /// door. All true when the room has no door (nothing to walk in from).
    func reachable(_ targets: [PlanPoint], tolerance: Double = 0.35) -> [Bool] {
        guard !entries.isEmpty else { return targets.map { _ in true } }
        var seen = Array(repeating: false, count: nx * ny)
        var queue: [Int] = []
        // Start from the free cells nearest each entry (within 0.4 m).
        for e in entries {
            var best: (Int, Double)?
            let (ci, cj) = index(e)
            guard let js = Self.span(cj - 4, cj + 4, ny), let ir = Self.span(ci - 4, ci + 4, nx) else { continue }
            for j in js {
                for i in ir where !blocked[j * nx + i] {
                    let d = (center(i, j) - e).length
                    if d <= 0.4, d < (best?.1 ?? .infinity) { best = (j * nx + i, d) }
                }
            }
            if let (k, _) = best, !seen[k] { seen[k] = true; queue.append(k) }
        }
        var head = 0
        while head < queue.count {
            let k = queue[head]; head += 1
            let i = k % nx, j = k / nx
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let a = i + di, b = j + dj
                guard a >= 0, b >= 0, a < nx, b < ny else { continue }
                let n = b * nx + a
                if !seen[n] && !blocked[n] { seen[n] = true; queue.append(n) }
            }
        }
        return targets.map { t in
            let (ci, cj) = index(t)
            let reach = Int((tolerance / Self.cell).rounded(.up))
            guard let js = Self.span(cj - reach, cj + reach, ny), let ir = Self.span(ci - reach, ci + reach, nx) else { return false }
            for j in js {
                for i in ir where seen[j * nx + i] {
                    if (center(i, j) - t).length <= tolerance { return true }
                }
            }
            return false
        }
    }

    /// Whether every door of the room can reach every other one (walking through, not blocked off).
    func doorsConnected() -> Bool {
        reachable(entries, tolerance: 0.4).allSatisfy { $0 }
    }
}
