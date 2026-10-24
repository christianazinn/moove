import Foundation

// The designer layout behind `LayoutSolver` (decision 0300). Pieces are grouped by what the
// room is for, each group's anchor is placed first (bed, sofa, desk, dining table), the other
// members are arranged around it by the clearance rules, and a small cost function picks the
// best of the candidate anchor spots. Every candidate keeps the room walkable: a WalkGrid
// flood from the doors must still reach each piece's use side and every other door.
// Deterministic: candidates are enumerated in a fixed order and ties keep the first one.

extension LayoutSolver {
    /// Clearances for a style, in meters (sources in decision 0300).
    struct Rules: Sendable {
        /// Narrowest path kept from the doors to each piece's use side (24": a squeeze).
        var walkMin: Double
        /// The path designers aim for (36" main walkway).
        var walkGood: Double
        /// Sofa front to coffee table (14-18").
        var coffeeGap: Double
        /// Dining table edge to the wall or furniture behind the chairs (36" all around).
        var diningClear: Double
        /// Sofa to TV, in screen diagonals (1.5-2.5x).
        var tvFactor: Double
        /// Chair front to the table or desk edge.
        var chairGap: Double
    }

    static func rules(_ style: Style) -> Rules {
        switch style {
        case .byFunction: Rules(walkMin: 0.6, walkGood: 0.9, coffeeGap: 0.4, diningClear: 0.9, tvFactor: 2.0, chairGap: 0.12)
        case .compact: Rules(walkMin: 0.6, walkGood: 0.75, coffeeGap: 0.35, diningClear: 0.75, tvFactor: 1.75, chairGap: 0.11)
        case .open: Rules(walkMin: 0.7, walkGood: 1.0, coffeeGap: 0.45, diningClear: 1.0, tvFactor: 2.25, chairGap: 0.15)
        }
    }
}

/// One straight wall of a room, wound counterclockwise so `inward` points into the room.
struct RoomWall {
    var a: PlanPoint
    var b: PlanPoint
    var len: Double
    var dir: PlanPoint
    var inward: PlanPoint

    static func of(_ room: FloorPlanRoom) -> [RoomWall] {
        let ccw = room.signedArea >= 0 ? room.polygon : room.polygon.reversed()
        return ccw.indices.compactMap { i in
            let a = ccw[i], b = ccw[(i + 1) % ccw.count]
            let len = (b - a).length
            guard len > 1e-6 else { return nil }
            let dir = (b - a) * (1 / len)
            return RoomWall(a: a, b: b, len: len, dir: dir, inward: PlanPoint(-dir.y, dir.x))
        }
    }

    /// Spans (t0, t1) of the openings that lie on this wall.
    func spans(_ openings: [WallOpening]) -> [(Double, Double)] {
        openings.compactMap { FloorPlan.span(of: $0, onEdge: a, b) }
    }
}

struct Designer {
    let solver: LayoutSolver
    let style: LayoutSolver.Style
    let rules: LayoutSolver.Rules
    let plan: FloorPlan
    let rooms: [FloorPlanRoom]
    let doorBlocks: [OrientedRect]
    /// Placed and fixed pieces, each grown by half the item gap (rugs aren't in here).
    var furniture: [OrientedRect]
    /// Floor kept open for a group's use but walkable: the space between the sofa and the TV.
    var zones: [OrientedRect] = []
    /// Spots that must stay reachable from the doors, per room (each piece's use side).
    var targets: [String: [PlanPoint]] = [:]
    var used: [String: Double]
    var placements: [Placement] = []
    var unplaced: [UInt64] = []
    /// Placed pieces' own rectangles and roles, for members and props to find their parents.
    var placed: [(item: LayoutItem, role: DesignRole, room: String, rect: OrientedRect)] = []

    /// Each room's empty walk grid per path width, built once.
    let baseGrids: [String: [Double: WalkGrid]]

    var gap: Double { solver.itemGapM }
    /// How many anchor candidates get the (slower) walkability check.
    static let walkChecked = 14

    init(solver: LayoutSolver, style: LayoutSolver.Style, rooms: [FloorPlanRoom], fixed: [OrientedRect], used: [String: Double]) {
        self.solver = solver
        self.style = style
        self.rules = LayoutSolver.rules(style)
        self.plan = solver.plan
        self.rooms = rooms
        self.doorBlocks = solver.doorKeepOuts()
        self.furniture = fixed
        self.used = used
        let widths = [rules.walkMin, rules.walkGood]
        var grids: [String: [Double: WalkGrid]] = [:]
        for room in rooms {
            for w in widths { grids[room.name, default: [:]][w] = WalkGrid(room: room, plan: solver.plan, furniture: [], radius: w / 2) }
        }
        self.baseGrids = grids
    }

    /// The room's walk grid for a path `width` wide with the placed furniture and `extra` marked.
    func grid(_ room: FloorPlanRoom, width: Double, extra: [OrientedRect] = []) -> WalkGrid {
        let base = baseGrids[room.name]?[width] ?? WalkGrid(room: room, plan: plan, furniture: [], radius: width / 2)
        return base.adding(furniture(in: room) + extra.map { $0.inflated(by: gap / 2) })
    }

    // MARK: Basics

    func free(_ r: OrientedRect, in room: FloorPlanRoom, besides extra: [OrientedRect] = []) -> Bool {
        LayoutSolver.inside(r, room) && !doorBlocks.contains { $0.overlaps(r) } && !furniture.contains { $0.overlaps(r) }
            && !zones.contains { $0.overlaps(r) } && !extra.contains { $0.overlaps(r) }
    }

    func rect(_ item: LayoutItem, at c: PlanPoint, facing f: PlanPoint) -> OrientedRect {
        OrientedRect(center: c, halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: LayoutSolver.rotationDeg(facing: f))
    }

    /// Back against the wall at distance `t` along it, facing into the room. `side`: long side
    /// to the wall instead (a bathtub whose length is its depth), facing along the wall.
    func wallRect(_ item: LayoutItem, _ w: RoomWall, t: Double, side: Bool = false) -> OrientedRect {
        if side {
            return rect(item, at: w.a + w.dir * t + w.inward * (solver.wallGapM + item.widthM / 2), facing: w.dir)
        }
        return rect(item, at: w.a + w.dir * t + w.inward * (solver.wallGapM + item.depthM / 2), facing: w.inward)
    }

    /// Positions along a wall for a piece `along` meters long, every 10 cm plus the middle.
    func offsets(_ w: RoomWall, along: Double, step: Double = 0.1) -> [Double] {
        guard w.len >= along - 1e-9 else { return [] }
        var ts = Array(stride(from: along / 2, through: w.len - along / 2 + 1e-9, by: step))
        ts.append(w.len / 2)
        return ts
    }

    /// Door centers on this room's walls.
    func doorCenters(_ room: FloorPlanRoom) -> [PlanPoint] {
        RoomWall.of(room).flatMap { w in w.spans(plan.doors).map { w.a + w.dir * (($0.0 + $0.1) / 2) } }
    }

    /// Front-of-piece point where someone stands to use it.
    static func front(_ r: OrientedRect, _ out: Double = 0.35) -> PlanPoint { r.center + r.axes.z * (r.halfDepth + out) }

    /// Furniture rectangles touching this room's bounds.
    func furniture(in room: FloorPlanRoom) -> [OrientedRect] {
        let b = room.bounds
        return furniture.filter { r in
            let c = r.corners
            return c.map(\.x).max()! > b.minX && c.map(\.x).min()! < b.maxX && c.map(\.y).max()! > b.minY && c.map(\.y).min()! < b.maxY
        }
    }

    /// Unreachable targets (the room's own plus `newTargets`, at least `need` of which must be
    /// reachable) when `adding` is placed; doors cut off from each other count as 10.
    func walkPenalty(_ room: FloorPlanRoom, adding: [OrientedRect], newTargets: [PlanPoint], need: Int? = nil, width: Double) -> Int {
        let g = self.grid(room, width: width, extra: adding)
        if !g.doorsConnected() { return 10 }
        let old = g.reachable(targets[room.name] ?? []).filter { !$0 }.count
        let new = g.reachable(newTargets).filter { $0 }.count
        let missing = max(0, (need ?? newTargets.count) - new)
        return old * 3 + missing
    }

    mutating func commit(_ item: LayoutItem, _ r: OrientedRect, in room: FloorPlanRoom, role: DesignRole, targets t: [PlanPoint] = [], blocks: Bool = true) {
        placements.append(Placement(itemId: item.id, room: room.name, x: r.center.x, y: r.center.y, rotationDeg: r.rotationDeg))
        if blocks { furniture.append(r.inflated(by: gap / 2)) }
        targets[room.name, default: []] += t
        used[room.name, default: 0] += item.widthM * item.depthM
        placed.append((item, role, room.name, r))
    }

    /// The candidate with the lowest cost after the walk check (cheap cost first, then the
    /// `walkChecked` best get the flood). Nil when there are none.
    func best<C>(_ cands: [(cost: Double, c: C)], walk: (C) -> Double) -> C? {
        let order = cands.indices.sorted { (cands[$0].cost, $0) < (cands[$1].cost, $1) }
        var best: (Double, C)?
        for i in order.prefix(Self.walkChecked) {
            let total = cands[i].cost + walk(cands[i].c)
            if best == nil || total < best!.0 - 1e-9 { best = (total, cands[i].c) }
        }
        return best?.1
    }

    // MARK: Against a wall

    /// The best free wall spot for a single piece by `score` (lower is better) whose use side
    /// stays reachable; with `requireWalk` false it settles for the best free spot.
    mutating func placeOnWall(_ item: LayoutItem, role: DesignRole, in room: FloorPlanRoom, side: Bool = false,
                              requireWalk: Bool = true, score: (RoomWall, Double, OrientedRect) -> Double = { _, _, _ in 0 }) -> Bool {
        var cands: [(cost: Double, c: OrientedRect)] = []
        let along = side ? item.depthM : item.widthM
        for w in RoomWall.of(room) {
            for t in offsets(w, along: along) {
                let r = wallRect(item, w, t: t, side: side)
                if free(r, in: room) { cands.append((score(w, t, r), r)) }
            }
        }
        let order = cands.indices.sorted { (cands[$0].cost, $0) < (cands[$1].cost, $1) }
        for i in order.prefix(40) {
            let r = cands[i].c
            let use = [Self.front(r)]
            if walkPenalty(room, adding: [r], newTargets: use, width: rules.walkMin) == 0 {
                commit(item, r, in: room, role: role, targets: use)
                return true
            }
        }
        if !requireWalk, let i = order.first {
            commit(item, cands[i].c, in: room, role: role)
            return true
        }
        return false
    }

    // MARK: Sleep: bed + nightstands, then dresser / wardrobe

    struct SleepSpot {
        var beds: [OrientedRect]
        var stands: [(LayoutItem, OrientedRect)]
        var wall: RoomWall
    }

    /// One bed, or a twin pair side by side, headboard on a solid wall, nightstands flanking.
    mutating func placeSleep(beds: [LayoutItem], stands: [LayoutItem], in room: FloorPlanRoom) -> [LayoutItem] {
        let rules = self.rules
        let walls = RoomWall.of(room)
        let maxLen = walls.map(\.len).max() ?? 1
        let doors = doorCenters(room)
        let twin = beds.count == 2
        let mid = twin ? max(stands.first.map { $0.widthM + 2 * gap + 0.01 } ?? 0, 0.6) : 0
        let unit = beds.reduce(0) { $0 + $1.widthM } + mid
        var cands: [(cost: Double, c: SleepSpot)] = []
        for w in walls {
            let windows = w.spans(plan.windows)
            let doorOnWall = !w.spans(plan.doors).isEmpty
            for t in offsets(w, along: unit) {
                var bedRects: [OrientedRect] = []
                var x = t - unit / 2
                for (k, bed) in beds.enumerated() {
                    bedRects.append(wallRect(bed, w, t: x + bed.widthM / 2))
                    x += bed.widthM + (k == 0 ? mid : 0)
                }
                guard bedRects.allSatisfy({ free($0, in: room) }) else { continue }
                // Nightstands: between twins, else either side of the bed, back on the wall.
                var standSpots: [(LayoutItem, OrientedRect)] = []
                let slots: [Double] = twin ? [t] : stands.isEmpty ? [] : [t + unit / 2, t - unit / 2]
                var left = stands
                for s in slots {
                    guard let ns = left.first else { break }
                    let off = twin ? 0 : (s > t ? 1.0 : -1.0) * (gap + 0.01 + ns.widthM / 2)
                    let r = wallRect(ns, w, t: s + off)
                    if free(r, in: room, besides: bedRects.map { $0.inflated(by: gap / 2) } + standSpots.map { $0.1.inflated(by: gap / 2) }) {
                        standSpots.append((ns, r))
                        left.removeFirst()
                    }
                }
                var cost = 0.0
                // Headboard on a solid wall: not under a window, not beside the door.
                let span = (t - unit / 2, t + unit / 2)
                if windows.contains(where: { min($0.1, span.1) - max($0.0, span.0) > 0.05 }) { cost += style == .compact ? 1.5 : 2.5 }
                if doorOnWall { cost += 0.4 }
                // Not in line with the door (the foot of the bed pointing at it).
                for r in bedRects {
                    for d in doors {
                        let v = d - r.center
                        if v.dot(r.axes.z) > 0 && abs(v.dot(r.axes.x)) < r.halfWidth + 0.3 { cost += 1.5 }
                    }
                }
                cost += (1 - w.len / maxLen) * 0.8 + abs(t - w.len / 2) / w.len * 1.2
                cost += Double(stands.count - standSpots.count) * 0.7
                cands.append((cost, SleepSpot(beds: bedRects, stands: standSpots, wall: w)))
            }
        }
        guard let spot = best(cands, walk: { s in
            var penalty = 0.0
            let all = s.beds + s.stands.map(\.1)
            for b in s.beds {
                let sides = [b.center + b.axes.x * (b.halfWidth + 0.35), b.center - b.axes.x * (b.halfWidth + 0.35)]
                let need = b.halfWidth * 2 >= 1.2 && style != .compact ? 2 : 1
                let p = walkPenalty(room, adding: all, newTargets: sides, need: need, width: rules.walkMin)
                penalty += p >= 10 ? 20 : Double(p) * (need == 2 && p == 1 ? 1.5 : 6)
                if walkPenalty(room, adding: all, newTargets: sides, need: need, width: rules.walkGood) > 0 { penalty += 0.4 }
            }
            return penalty
        }) else { return beds + stands }
        for (bed, r) in zip(beds, spot.beds) {
            let sides = [r.center + r.axes.x * (r.halfWidth + 0.35), r.center - r.axes.x * (r.halfWidth + 0.35)]
            let g = self.grid(room, width: rules.walkMin, extra: spot.beds + spot.stands.map(\.1))
            let reach = zip(sides, g.reachable(sides)).filter { $0.1 }.map(\.0)
            commit(bed, r, in: room, role: .bed, targets: Array(reach.prefix(1)))
        }
        for (ns, r) in spot.stands { commit(ns, r, in: room, role: .nightstand) }
        let placedStands = Set(spot.stands.map(\.0.id))
        return stands.filter { !placedStands.contains($0.id) }
    }

    /// A dresser faces the bed from the opposite wall (or sits on a side wall), with room to
    /// open its drawers and stand back: 0.9 m from the foot of the bed.
    mutating func placeCaseGood(_ item: LayoutItem, role: DesignRole, in room: FloorPlanRoom) -> Bool {
        let beds = placed.filter { $0.room == room.name && $0.role == .bed }.map(\.rect)
        let open = style == .open
        return placeOnWall(item, role: role, in: room) { w, t, r in
            var cost = open ? abs(t - w.len / 2) / w.len * 0.5 : 0
            guard let bed = beds.first else { return cost }
            let facing = r.axes.z.dot(bed.axes.z)
            let foot = bed.center + bed.axes.z * bed.halfDepth
            let clear = (r.center - foot).dot(bed.axes.z) - r.halfDepth
            if role == .dresser {
                if facing < -0.7 { cost += clear >= 0.9 ? 0 : 0.8 } else if abs(facing) < 0.3 { cost += 0.5 } else { cost += 1.2 }
            } else {
                // Wardrobes and tall pieces: a side wall, out of the bed's view.
                cost += abs(facing) < 0.3 ? 0 : 0.6
            }
            return cost
        }
    }

    // MARK: Living: sofa facing the TV, coffee table, chairs, lamp, rug

    struct LivingSpot {
        var sofa: OrientedRect
        var media: OrientedRect?
        var coffee: OrientedRect?
        var chairs: [(LayoutItem, OrientedRect)]
        var side: (LayoutItem, OrientedRect)?
        var lamp: (LayoutItem, OrientedRect)?
        var rug: OrientedRect?
    }

    /// Distance from `p` along `dir` to the room's outline.
    static func ray(_ p: PlanPoint, _ dir: PlanPoint, in room: FloorPlanRoom) -> Double {
        var best = Double.infinity
        for (a, b) in room.edges {
            let e = b - a
            let den = dir.cross(e)
            guard abs(den) > 1e-9 else { continue }
            let t = (a - p).cross(e) / den, u = (a - p).cross(dir) / den
            if t > 1e-6 && u >= -1e-9 && u <= 1 + 1e-9 { best = min(best, t) }
        }
        return best
    }

    /// `screen`: a floor-standing TV that goes on top of the `media` stand.
    mutating func placeLiving(sofa: LayoutItem, media: LayoutItem?, screen: LayoutItem? = nil, tvWidth: Double?, coffee: LayoutItem?, chairs: [LayoutItem],
                              side: LayoutItem?, lamp: LayoutItem?, rug: LayoutItem?, in room: FloorPlanRoom) -> [LayoutItem]? {
        let rules = self.rules
        let walls = RoomWall.of(room)
        let maxLen = walls.map(\.len).max() ?? 1
        let doors = doorCenters(room)
        var cands: [(cost: Double, c: LivingSpot)] = []
        // Anchors: the media piece on a wall with the sofa across from it at viewing distance,
        // or (no TV) the sofa's back on a wall.
        var anchors: [(sofa: OrientedRect, media: OrientedRect?, cost: Double)] = []
        for w in walls {
            let windows = w.spans(plan.windows)
            if let media {
                for t in offsets(w, along: media.widthM, step: 0.2) {
                    let m = wallRect(media, w, t: t)
                    guard free(m, in: room) else { continue }
                    let diag = max(tvWidth ?? media.widthM * 0.8, 0.5) / 0.87
                    let ideal = min(3.5, max(1.5, rules.tvFactor * diag))
                    let mFront = m.center + w.inward * m.halfDepth
                    let room0 = Self.ray(mFront, w.inward, in: room) - solver.wallGapM - sofa.depthM
                    guard room0 >= 1.3 else { continue }
                    var d = min(ideal, room0)
                    if room0 - d < rules.walkMin { d = room0 } // too tight to walk behind: back it onto the wall
                    let s = rect(sofa, at: mFront + w.inward * (d + sofa.depthM / 2), facing: w.inward * -1)
                    guard free(s, in: room, besides: [m.inflated(by: gap / 2)]) else { continue }
                    var cost = abs(d - ideal) * 0.8 + abs(t - w.len / 2) / w.len * 0.8
                    let span = (t - media.widthM / 2, t + media.widthM / 2)
                    if windows.contains(where: { min($0.1, span.1) - max($0.0, span.0) > 0.05 }) { cost += 0.8 } // TV against glare
                    if room0 - d > 0.05 { cost += style == .compact ? 0.5 : 0.2 } // a floating sofa
                    // Nobody walks between the sofa and the screen.
                    for dc in doors {
                        let v = dc - m.center
                        let along = v.dot(w.inward), across = abs(v.dot(w.dir))
                        if along > 0 && along < d + 0.2 && across < max(m.halfWidth, s.halfWidth) + 0.2 { cost += 1.0 }
                    }
                    anchors.append((s, m, cost))
                }
            } else {
                for t in offsets(w, along: sofa.widthM, step: 0.2) {
                    let s = wallRect(sofa, w, t: t)
                    guard free(s, in: room) else { continue }
                    var cost = (1 - w.len / maxLen) * 0.6 + abs(t - w.len / 2) / w.len * 0.8
                    if !w.spans(plan.doors).isEmpty { cost += 0.5 }
                    anchors.append((s, nil, cost))
                }
            }
        }
        for a in anchors {
            let s = a.sofa
            let f = s.axes.z, r = s.axes.x
            var taken = [s.inflated(by: gap / 2)] + (a.media.map { [$0.inflated(by: gap / 2)] } ?? [])
            var cost = a.cost
            let sofaFront = s.center + f * s.halfDepth
            // Coffee table 14-18" in front of the sofa, centered on it.
            var ct: OrientedRect?
            if let coffee {
                let c = rect(coffee, at: sofaFront + f * (rules.coffeeGap + coffee.depthM / 2), facing: f)
                if free(c, in: room, besides: taken) { ct = c; taken.append(c.inflated(by: gap / 2)) } else { cost += 1.2 }
            }
            let hub = ct ?? OrientedRect(center: sofaFront + f * (rules.coffeeGap + 0.3), halfWidth: min(0.5, s.halfWidth * 0.6), halfDepth: 0.3,
                                         rotationDeg: s.rotationDeg)
            // Chairs at the table's ends, facing in (a conversation group within ~2.5 m).
            var chairSpots: [(LayoutItem, OrientedRect)] = []
            for (k, ch) in chairs.prefix(2).enumerated() {
                let sgn = k == 0 ? 1.0 : -1.0
                var spot: OrientedRect?
                for sideSgn in [sgn, -sgn] where spot == nil {
                    let c = rect(ch, at: hub.center + r * sideSgn * (hub.halfWidth + 0.45 + ch.depthM / 2), facing: r * -sideSgn)
                    if free(c, in: room, besides: taken) { spot = c; continue }
                    // Angled in at the sofa's end instead.
                    let p = sofaFront + f * (0.55 + ch.depthM / 2) + r * sideSgn * (s.halfWidth + 0.15 + ch.widthM / 2)
                    let toward = hub.center - p
                    let c2 = rect(ch, at: p, facing: toward * (1 / max(toward.length, 1e-6)))
                    if free(c2, in: room, besides: taken) { spot = c2 }
                }
                if let c = spot { chairSpots.append((ch, c)); taken.append(c.inflated(by: gap / 2)) } else { cost += 1.2 }
            }
            // Side table and floor lamp at the sofa's ends, backs in line with the sofa's.
            func atEnd(_ item: LayoutItem, _ sgn: Double) -> OrientedRect? {
                let c = s.center + r * sgn * (s.halfWidth + gap + 0.01 + item.widthM / 2) - f * (s.halfDepth - item.depthM / 2)
                let o = rect(item, at: c, facing: f)
                return free(o, in: room, besides: taken) ? o : nil
            }
            var sideSpot: (LayoutItem, OrientedRect)?
            if let side {
                if let o = atEnd(side, 1) ?? atEnd(side, -1) { sideSpot = (side, o); taken.append(o.inflated(by: gap / 2)) } else { cost += 0.5 }
            }
            var lampSpot: (LayoutItem, OrientedRect)?
            if let lamp {
                let order: [Double] = sideSpot.map { ($0.1.center - s.center).dot(r) > 0 ? [-1.0, 1.0] : [1.0, -1.0] } ?? [-1, 1]
                if let o = atEnd(lamp, order[0]) ?? atEnd(lamp, order[1]) {
                    lampSpot = (lamp, o); taken.append(o.inflated(by: gap / 2))
                } else if let ch = chairSpots.first?.1 {
                    // Beside the armchair, behind its shoulder.
                    let c = ch.center - ch.axes.z * (ch.halfDepth - lamp.depthM / 2) + ch.axes.x * (ch.halfWidth + gap + 0.01 + lamp.widthM / 2)
                    let o = rect(lamp, at: c, facing: ch.axes.z)
                    if free(o, in: room, besides: taken) { lampSpot = (lamp, o); taken.append(o.inflated(by: gap / 2)) } else { cost += 0.4 }
                } else { cost += 0.4 }
            }
            // Rug under the front of the seating, centered on the coffee table.
            var rugSpot: OrientedRect?
            if let rug {
                for turn in [0.0, 90.0] {
                    let o = OrientedRect(center: hub.center - f * 0.1, halfWidth: rug.widthM / 2, halfDepth: rug.depthM / 2, rotationDeg: s.rotationDeg + turn)
                    if LayoutSolver.inside(o, room) { rugSpot = o; break }
                }
                if rugSpot == nil { cost += 0.3 }
            }
            cands.append((cost, LivingSpot(sofa: s, media: a.media, coffee: ct, chairs: chairSpots, side: sideSpot, lamp: lampSpot, rug: rugSpot)))
        }
        guard let spot = best(cands, walk: { l in
            let all = [l.sofa] + [l.media, l.coffee].compactMap { $0 } + l.chairs.map(\.1) + [l.side?.1, l.lamp?.1].compactMap { $0 }
            let ends = [l.sofa.center + l.sofa.axes.x * (l.sofa.halfWidth + 0.35), l.sofa.center - l.sofa.axes.x * (l.sofa.halfWidth + 0.35),
                        l.sofa.center + l.sofa.axes.z * (l.sofa.halfDepth + 0.35)]
            let p = walkPenalty(room, adding: all, newTargets: ends, need: 1, width: rules.walkMin)
            var penalty = p >= 10 ? 20 : Double(p) * 4
            if let m = l.media, walkPenalty(room, adding: all, newTargets: [Self.front(m)], width: rules.walkMin) > 0 { penalty += 0.8 }
            if walkPenalty(room, adding: all, newTargets: ends, need: 1, width: rules.walkGood) > 0 { penalty += 0.4 }
            return penalty
        }) else { return nil }
        commit(sofa, spot.sofa, in: room, role: .sofa, targets: [])
        // Nothing else goes between the sofa and the screen (or on the coffee table's patch).
        let sf = spot.sofa.axes.z, front = spot.sofa.center + sf * spot.sofa.halfDepth
        let depth = spot.media.map { max(0.3, ($0.center - front).dot(sf) - $0.halfDepth) } ?? (rules.coffeeGap + 0.8)
        zones.append(OrientedRect(center: front + sf * (depth / 2), halfWidth: max(spot.sofa.halfWidth, spot.media?.halfWidth ?? 0),
                                  halfDepth: depth / 2, rotationDeg: spot.sofa.rotationDeg))
        var rest: [LayoutItem] = []
        if let media { if let m = spot.media { commit(media, m, in: room, role: DesignRole.of(media)) } else { rest.append(media) } }
        if let tv = screen, let stand = spot.media, let media, DesignRole.of(media) == .tvStand {
            // The TV stands on its console, toward the back, facing the sofa.
            let top = Double(VoxelModels.build(VoxelItemSpec(media)).ny) * VoxelGrid.voxelSize
            let c = stand.center - stand.axes.z * max(0, stand.halfDepth - tv.depthM / 2 - 0.02)
            placements.append(Placement(itemId: tv.id, room: room.name, x: c.x, y: c.y, rotationDeg: stand.rotationDeg,
                                        elevationM: PropPlacer.mm(top), onTopOf: media.id))
            placed.append((tv, .tv, room.name, rect(tv, at: c, facing: stand.axes.z)))
        } else if let tv = screen {
            rest.append(tv)
        }
        if let coffee { if let c = spot.coffee { commit(coffee, c, in: room, role: .coffeeTable) } else { rest.append(coffee) } }
        let seated = Set(spot.chairs.map(\.0.id))
        for (ch, r) in spot.chairs { commit(ch, r, in: room, role: .armchair) }
        rest += chairs.filter { !seated.contains($0.id) }
        if let side { if let s = spot.side { commit(side, s.1, in: room, role: .sideTable) } else { rest.append(side) } }
        if let lamp { if let s = spot.lamp { commit(lamp, s.1, in: room, role: .floorLamp) } else { rest.append(lamp) } }
        if let rug { if let r = spot.rug { commit(rug, r, in: room, role: .rug, blocks: false) } else { rest.append(rug) } }
        // Keep a way to the sofa's open end.
        let ends = [spot.sofa.center + spot.sofa.axes.x * (spot.sofa.halfWidth + 0.35), spot.sofa.center - spot.sofa.axes.x * (spot.sofa.halfWidth + 0.35)]
        let after = grid(room, width: rules.walkMin)
        targets[room.name, default: []] += zip(ends, after.reachable(ends)).filter { $0.1 }.map(\.0).prefix(1)
        return rest
    }

    // MARK: Office: desk by the window, chair at it, shelf and lamp nearby

    mutating func placeOffice(desk: LayoutItem, chair: LayoutItem?, in room: FloorPlanRoom) -> [LayoutItem]? {
        let rules = self.rules
        let walls = RoomWall.of(room)
        let doors = doorCenters(room)
        let others = furniture(in: room)
        var cands: [(cost: Double, c: (OrientedRect, OrientedRect?))] = []
        for (wi, w) in walls.enumerated() {
            let windows = w.spans(plan.windows)
            // Windows on the neighbouring walls, near this wall's ends.
            let prev = walls[(wi + walls.count - 1) % walls.count], next = walls[(wi + 1) % walls.count]
            let nearStart = prev.spans(plan.windows).contains { prev.len - $0.1 < 1.0 }
            let nearEnd = next.spans(plan.windows).contains { $0.0 < 1.0 }
            for t in offsets(w, along: desk.widthM) {
                let d = wallRect(desk, w, t: t)
                guard free(d, in: room) else { continue }
                var cost = 0.0
                var ch: OrientedRect?
                if let chair {
                    let c = rect(chair, at: d.center + w.inward * (d.halfDepth + rules.chairGap + chair.depthM / 2), facing: w.inward * -1)
                    if free(c, in: room, besides: [d.inflated(by: gap / 2)]) { ch = c } else { cost += 1.0 }
                }
                let span = (t - desk.widthM / 2, t + desk.widthM / 2)
                if windows.contains(where: { min($0.1, span.1 + 0.6) - max($0.0, span.0 - 0.6) > 0 }) {
                    cost -= 0.8 // daylight on the desk
                } else if (nearStart && span.0 < 1.0) || (nearEnd && w.len - span.1 < 1.0) {
                    cost -= 0.6 // window beside it
                }
                if !w.spans(plan.doors).isEmpty { cost += 0.3 }
                // Back to the door is uneasy.
                for dc in doors {
                    let v = dc - d.center
                    if v.dot(w.inward) > 0 && abs(v.dot(w.dir)) < d.halfWidth + 0.3 { cost += 0.3 }
                }
                // In a shared room, away from what's there already.
                if let near = others.map({ ($0.center - d.center).length - $0.halfWidth }).min() { cost += max(0, 1.5 - near) * 0.4 }
                cands.append((cost, (d, ch)))
            }
        }
        guard let spot = best(cands, walk: { c in
            let back = c.1.map { [$0.center - $0.axes.z * ($0.halfDepth + 0.3)] } ?? [Self.front(c.0)]
            let p = walkPenalty(room, adding: [c.0] + (c.1.map { [$0] } ?? []), newTargets: back, width: rules.walkMin)
            return p >= 10 ? 20 : Double(p) * 4
        }) else { return nil }
        let back = spot.1.map { $0.center - $0.axes.z * ($0.halfDepth + 0.3) } ?? Self.front(spot.0)
        commit(desk, spot.0, in: room, role: .desk, targets: [back])
        if let chair {
            if let c = spot.1 { commit(chair, c, in: room, role: .deskChair); return [] }
            return [chair]
        }
        return []
    }

    /// A piece that belongs next to a placed one (bookshelf by the desk, lamp by the bed): the
    /// free wall spot nearest it.
    mutating func placeNear(_ item: LayoutItem, role: DesignRole, to anchor: OrientedRect, in room: FloorPlanRoom) -> Bool {
        placeOnWall(item, role: role, in: room) { _, _, r in (r.center - anchor.center).length * 0.5 }
    }

    // MARK: Dining: table in the middle of its zone, chairs around it

    mutating func placeDining(table: LayoutItem, chairs: [LayoutItem], in room: FloorPlanRoom) -> [LayoutItem]? {
        let rules = self.rules
        let b = room.bounds
        let c0 = room.centroid
        var cands: [(cost: Double, c: (OrientedRect, [(LayoutItem, OrientedRect)]))] = []
        let longX = b.width >= b.depth
        var rotations: [Double] = table.widthM >= table.depthM ? (longX ? [0, 90] : [90, 0]) : (longX ? [90, 0] : [0, 90])
        if abs(table.widthM - table.depthM) < 0.05 { rotations = [0] }
        let chairW = chairs.map(\.widthM).max() ?? 0.5
        for rot in rotations {
            var ys = Array(stride(from: b.minY + 0.3, through: b.maxY - 0.3, by: 0.2)); ys.append(c0.y)
            var xs = Array(stride(from: b.minX + 0.3, through: b.maxX - 0.3, by: 0.2)); xs.append(c0.x)
            for y in ys {
                for x in xs {
                    let t = OrientedRect(center: PlanPoint(x, y), halfWidth: table.widthM / 2, halfDepth: table.depthM / 2, rotationDeg: rot)
                    guard free(t, in: room) else { continue }
                    let ax = t.axes.x, az = t.axes.z
                    // Seats: the long sides first (alternating), then the ends.
                    let perSide = max(1, Int((table.widthM + 0.05) / (chairW + 0.12)))
                    var slots: [(lateral: PlanPoint, out: PlanPoint, dist: Double)] = []
                    for i in 0..<perSide {
                        let along = -table.widthM / 2 + (Double(i) + 0.5) * table.widthM / Double(perSide)
                        for s in [1.0, -1.0] { slots.append((ax * along, az * s, t.halfDepth)) }
                    }
                    if table.depthM >= chairW * 0.9 { for s in [1.0, -1.0] { slots.append((PlanPoint(0, 0), ax * s, t.halfWidth)) } }
                    var seats: [(LayoutItem, OrientedRect)] = []
                    var taken = [t.inflated(by: gap / 2)]
                    var queue = chairs[...]
                    for slot in slots {
                        guard let ch = queue.first else { break }
                        let center = t.center + slot.lateral + slot.out * (slot.dist + rules.chairGap + ch.depthM / 2)
                        let r = rect(ch, at: center, facing: slot.out * -1)
                        if free(r, in: room, besides: taken) { seats.append((ch, r)); taken.append(r.inflated(by: gap / 2)); queue.removeFirst() }
                    }
                    var cost = Double(chairs.count - seats.count) * 1.0
                    // Room to pull a chair out and walk behind it: 36" from the table edge.
                    let clear = [rules.diningClear, 0.8, 0.7, 0.6].first { c in
                        LayoutSolver.inside(t.inflated(by: c), room) && !furniture.contains { $0.overlaps(t.inflated(by: c)) }
                    }
                    cost += clear.map { (rules.diningClear - $0) * 3 } ?? 2
                    cost += (t.center - c0).length * 0.3
                    cands.append((cost, (t, seats)))
                }
            }
        }
        guard let spot = best(cands, walk: { c in
            let behind = c.1.map { $0.1.center - $0.1.axes.z * ($0.1.halfDepth + 0.3) }
            let p = walkPenalty(room, adding: [c.0] + c.1.map(\.1), newTargets: behind.isEmpty ? [Self.front(c.0, 0.5)] : behind,
                                need: 1, width: rules.walkMin)
            return p >= 10 ? 20 : Double(p) * 3
        }) else { return nil }
        let behind = spot.1.map { $0.1.center - $0.1.axes.z * ($0.1.halfDepth + 0.3) }
        let g = self.grid(room, width: rules.walkMin, extra: [spot.0] + spot.1.map(\.1))
        commit(table, spot.0, in: room, role: .diningTable, targets: Array(zip(behind, g.reachable(behind)).filter { $0.1 }.map(\.0).prefix(1)))
        for (ch, r) in spot.1 { commit(ch, r, in: room, role: .diningChair) }
        let seated = Set(spot.1.map(\.0.id))
        return chairs.filter { !seated.contains($0.id) }
    }
}
