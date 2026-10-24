import Foundation
import MooveKit

// Hook for #81: turns a real RoomPlan scan (`RoomGeometry`, from
// `RoomGeometryLoader` / `ScanSession.geometry`) into the new-home lane's voxel
// dollhouse inputs: a one-room `FloorPlan` and a `Placement` per scanned item.
// Pure math, no RoomPlan or RealityKit, so it can move into MooveKit (and get
// real tests) whenever we want.
//
// Coordinate systems
// ------------------
// RoomGeometry: RoomPlan world space, meters, Y up. Floor positions are world (x, z).
// FloorPlan / Placement: plan meters, plan (x, y) = world (x, z) (see FloorPlan.swift).
// Rotations on both sides are right-handed about +Y: rotating by θ sends
// local +x to (cos θ, 0, −sin θ) and local +z to (sin θ, 0, cos θ). That is
// `RoomTransform.yaw` on Rio's side and `Placement.rotationDeg` on ours
// (`LayoutSolver.rotationDeg(facing:)`, `FurnitureLayer`'s quat about +Y), so a
// yaw converts to rotationDeg 1:1 (radians → degrees) once the room's own
// alignment rotation is added.
//
// Front of a scanned object: our voxel pieces face local +z. RoomPlan's docs
// don't say which way a `CapturedRoom.Object` faces (only that `transform` is
// "position and orientation" and `dimensions` is width/height/depth on local
// x/y/z). We assume +z, like Rio's demo room (the bed's foot points +z into the
// room) and ARKit/RealityKit convention for "the side you look at", and then
// fix the common wrong case with a wall check: a piece whose front is jammed
// against a wall and whose back has open floor is turned 180°. The footprint is
// right either way (width on local x, depth on local z), only the facing can flip.
// `DollhouseTransform.objectFrontOffsetDeg` is the one knob if a device test
// shows RoomPlan fronts are −z.

extension RoomGeometry {
    /// The scanned room as a one-room floor plan: walls → polygon (squared up to the
    /// dominant wall direction, min corner at ~(0, 0)), doors and open passages →
    /// `doors`, windows → `windows`, median wall height → `wallHeightM`.
    func dollhousePlan(roomName: String) -> FloorPlan {
        DollhouseTransform.layout(of: self).plan(roomName: roomName)
    }

    /// A placement for every item whose `scanObjectId` is one of this scan's object
    /// ids (`CapturedRoom.Object.identifier.uuidString`, set in `ScanSession.submit`;
    /// "demo-<id>" for the demo room). Items with no match (added by photo, or from
    /// another scan) are left out; the caller lays those out itself.
    /// `roomName` must match the name passed to `dollhousePlan(roomName:)`.
    func dollhousePlacements(items: [Item], roomName: String = "Room") -> [Placement] {
        DollhouseTransform.layout(of: self).placements(for: self, items: items, roomName: roomName)
    }

    /// Both at once, computing the transform once.
    func dollhouse(roomName: String, items: [Item]) -> (plan: FloorPlan, placements: [Placement]) {
        let layout = DollhouseTransform.layout(of: self)
        return (layout.plan(roomName: roomName), layout.placements(for: self, items: items, roomName: roomName))
    }
}

/// The world → plan transform and the bits of geometry math behind it.
///
/// `plan = rotate(world.xz, by: phi) + offset`, where `phi` squares the room up
/// (dominant wall direction onto the plan x axis) and `offset` moves the room's
/// min corner to (0, 0).
enum DollhouseTransform {
    /// Added to every object's rotation. 0 if RoomPlan objects face local +z (assumed,
    /// unverified); set to 180 if a device scan shows them facing −z.
    static let objectFrontOffsetDeg: Double = 0
    /// Rotations this close to a multiple of 90° snap to it.
    static let snapToleranceDeg: Double = 10
    /// Wall segments this close to a plan axis are made exactly axis-aligned.
    static let wallSquareToleranceDeg: Double = 5
    /// Largest gap between consecutive wall ends that still counts as a corner.
    static let maxCornerGapM: Double = 0.5
    /// Openings farther than this from every polygon edge are dropped.
    static let maxOpeningDistanceM: Double = 0.5
    /// Objects whose bottom is higher than this above the floor keep their scanned height.
    static let minElevationM: Double = 0.3
    /// Smallest RoomPlan floor polygon trusted as the room's outline.
    static let minFloorAreaM2: Double = 1

    struct Frame: Equatable {
        /// Radians, right-handed about +Y, applied to world (x, z).
        var phi: Double
        var offset: PlanPoint

        func point(worldX x: Double, worldZ z: Double) -> PlanPoint {
            DollhouseTransform.rotate(PlanPoint(x, z), by: phi) + offset
        }

        func point(_ world: SIMD3<Float>) -> PlanPoint { point(worldX: Double(world.x), worldZ: Double(world.z)) }

        /// Placement rotation (degrees, [0, 360)) for an object with world `yaw` (radians).
        func rotationDeg(worldYaw yaw: Double) -> Double {
            DollhouseTransform.normalizeDeg((yaw + phi) * 180 / .pi + DollhouseTransform.objectFrontOffsetDeg)
        }
    }

    struct Layout {
        var frame: Frame
        /// Counterclockwise, already in plan coordinates.
        var polygon: [PlanPoint]
        var doors: [WallOpening]
        var windows: [WallOpening]
        var wallHeightM: Double

        func plan(roomName: String) -> FloorPlan {
            FloorPlan(rooms: [FloorPlanRoom(name: roomName, polygon: polygon)], doors: doors, windows: windows, wallHeightM: wallHeightM)
        }

        func placements(for geometry: RoomGeometry, items: [Item], roomName: String) -> [Placement] {
            let objects = Dictionary(geometry.objects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let floorY = Double(geometry.floorY)
            return items.compactMap { item in
                guard let key = item.scanObjectId, let object = objects[key] else { return nil }
                let center = frame.point(object.transform.position)
                var deg = DollhouseTransform.snap(frame.rotationDeg(worldYaw: Double(object.transform.yaw)))
                if DollhouseTransform.frontFacesWall(center: center, rotationDeg: deg, depthM: Double(object.dimensions.z), polygon: polygon) {
                    deg = DollhouseTransform.normalizeDeg(deg + 180)
                }
                // Off the floor (a wall-mounted TV, an upper cabinet): keep the scanned height.
                let bottom = Double(object.transform.position.y) - Double(object.dimensions.y) / 2 - floorY
                let elevation = bottom > DollhouseTransform.minElevationM ? Self.cm(bottom) : nil
                return Placement(itemId: item.id, room: roomName, x: Self.cm(center.x), y: Self.cm(center.y), rotationDeg: deg,
                                 elevationM: elevation)
            }
        }

        static func cm(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    }

    // MARK: Building the layout

    static func layout(of g: RoomGeometry) -> Layout {
        // 1. Wall segments in world (x, z): center ± local x axis × half width.
        let walls: [(PlanPoint, PlanPoint)] = g.walls.map { segment(of: $0) }
        // 2. Square the room up.
        let phi = alignment(for: walls)
        let rotated = walls.map { squared((rotate($0.0, by: phi), rotate($0.1, by: phi))) }
        // 3. Outline: RoomPlan's own floor polygon when it's sane (keeps L-shaped rooms), else the
        // closed wall loop, else the floor polygon anyway, else a hull, else a default box.
        var polygon = validFloor(g, phi: phi, walls: rotated)
            ?? wallLoop(rotated)
            ?? largestFloor(g, phi: phi)
            ?? hull(rotated.flatMap { [$0.0, $0.1] })
            ?? hull(g.objects.flatMap { o in
                RoomGeometry.footprint(width: o.dimensions.x, depth: o.dimensions.z, o.transform)
                    .map { rotate(PlanPoint(Double($0.x), Double($0.y)), by: phi) }
            })
            ?? [PlanPoint(0, 0), PlanPoint(3, 0), PlanPoint(3, 3), PlanPoint(0, 3)]
        polygon = cleaned(polygon)
        if polygon.count < 3 { polygon = [PlanPoint(0, 0), PlanPoint(3, 0), PlanPoint(3, 3), PlanPoint(0, 3)] }
        // 4. Min corner to (0, 0).
        let minX = polygon.map(\.x).min() ?? 0, minY = polygon.map(\.y).min() ?? 0
        let offset = PlanPoint(-minX, -minY)
        polygon = polygon.map { PlanPoint(Layout.cm($0.x + offset.x), Layout.cm($0.y + offset.y)) }
        let frame = Frame(phi: phi, offset: offset)

        // 5. Openings: their own transform's local x is along the wall; snap onto the nearest edge.
        var doors: [WallOpening] = [], windows: [WallOpening] = []
        for o in g.openings {
            let half = o.dimensions.x / 2
            let a = frame.point(o.transform.apply(SIMD3(-half, 0, 0)))
            let b = frame.point(o.transform.apply(SIMD3(half, 0, 0)))
            guard let span = snapOpening(a, b, to: polygon), span.widthM > 0.1 else { continue }
            switch o.kind {
            case .window: windows.append(span)
            case .door, .opening: doors.append(span)  // an open passage is a gap in the wall, like a door
            case .wall: break
            }
        }

        // 6. Wall height: median, so one odd short wall (a half wall, a soffit) doesn't win.
        let heights = g.walls.map { Double($0.dimensions.y) }.filter { $0 > 1.5 }.sorted()
        let height = heights.isEmpty ? 2.6 : Layout.cm(heights[heights.count / 2])
        return Layout(frame: frame, polygon: polygon, doors: doors, windows: windows, wallHeightM: height)
    }

    /// A wall's centerline in world (x, z), from its center along its local x axis (column 0).
    static func segment(of wall: RoomGeometry.Surface) -> (PlanPoint, PlanPoint) {
        let c = wall.transform.position, axis = wall.transform.columns[0]
        var u = PlanPoint(Double(axis.x), Double(axis.z))
        u = u.length > 1e-9 ? u * (1 / u.length) : PlanPoint(1, 0)
        let center = PlanPoint(Double(c.x), Double(c.z)), half = Double(wall.dimensions.x) / 2
        return (center - u * half, center + u * half)
    }

    // MARK: Pure helpers

    /// Rotates a world (x, z) vector by `phi` radians about +Y (right-handed), as plan (x, y):
    /// `x' = x cos φ + z sin φ`, `y' = −x sin φ + z cos φ`.
    /// A vector at plan angle `a` (atan2(y, x)) ends up at `a − φ`.
    ///
    /// Example: rotate((1, 0), by: −30°) = (cos 30°, −sin(−30°)) = (0.866, 0.5),
    /// the same as rotating world +x by −30° about +Y: (cos(−30°), 0, −sin(−30°)).
    static func rotate(_ p: PlanPoint, by phi: Double) -> PlanPoint {
        let c = cos(phi), s = sin(phi)
        return PlanPoint(p.x * c + p.y * s, -p.x * s + p.y * c)
    }

    /// The rotation that turns the dominant wall direction onto the plan x axis.
    /// Walls are compared modulo 90° by averaging `4a` on the unit circle (weighted by
    /// length), so perpendicular walls agree instead of cancelling. Result in (−45°, 45°].
    ///
    /// Example: a room scanned 30° off: walls at plan angle −30° (4 m) and 60° (3.5 m).
    /// 4a = −120° and 240° (the same direction), so the mean is −120° and
    /// a₀ = −30°. φ = a₀ = −30°, and rotating by φ takes each angle a to a − φ: 0° and 90°.
    /// Rio's demo room (walls at 0° and −90°): 4a = 0° and −360° → φ = 0, no change.
    static func alignment(for walls: [(PlanPoint, PlanPoint)]) -> Double {
        var s = 0.0, c = 0.0
        for (a, b) in walls {
            let d = b - a, len = d.length
            guard len > 1e-6 else { continue }
            let angle = atan2(d.y, d.x)
            s += len * sin(4 * angle)
            c += len * cos(4 * angle)
        }
        guard s * s + c * c > 1e-12 else { return 0 }
        return atan2(s, c) / 4
    }

    /// Makes a nearly axis-aligned segment exactly axis-aligned through its midpoint,
    /// keeping its extent along the axis. Others pass through.
    ///
    /// Example: (0, 0.02)–(4, −0.02) is 0.6° off the x axis → (0, 0)–(4, 0).
    static func squared(_ s: (PlanPoint, PlanPoint)) -> (PlanPoint, PlanPoint) {
        let d = s.1 - s.0
        guard d.length > 1e-9 else { return s }
        let deg = abs(atan2(d.y, d.x) * 180 / .pi).truncatingRemainder(dividingBy: 180)
        let mid = (s.0 + s.1) * 0.5
        let tol = wallSquareToleranceDeg
        if deg < tol || deg > 180 - tol { return (PlanPoint(s.0.x, mid.y), PlanPoint(s.1.x, mid.y)) }
        if abs(deg - 90) < tol { return (PlanPoint(mid.x, s.0.y), PlanPoint(mid.x, s.1.y)) }
        return s
    }

    /// Chains wall segments end to end into a closed outline, starting from the longest,
    /// always taking the wall whose nearer end is closest (flipping it if needed), and
    /// stopping once closing the loop is the best move. Corners are where consecutive
    /// wall lines intersect, which removes RoomPlan's small overlaps and gaps.
    /// Walls that don't fit the loop (an island, a half wall) are ignored.
    /// Returns nil when the walls don't close within `maxCornerGapM`.
    ///
    /// Example: the demo room's walls (4 × 3.5, centered on the origin) give
    /// (−2, −1.75), (2, −1.75), (2, 1.75), (−2, 1.75) in some rotation of that order.
    static func wallLoop(_ walls: [(PlanPoint, PlanPoint)]) -> [PlanPoint]? {
        var remaining = walls.filter { ($0.1 - $0.0).length > 0.05 }
        guard remaining.count >= 3 else { return nil }
        let first = remaining.indices.max { (remaining[$0].1 - remaining[$0].0).length < (remaining[$1].1 - remaining[$1].0).length }!
        var chain = [remaining.remove(at: first)]
        while !remaining.isEmpty {
            let end = chain[chain.count - 1].1
            var best = (index: 0, flip: false, gap: Double.infinity)
            for (i, w) in remaining.enumerated() {
                let g0 = (w.0 - end).length, g1 = (w.1 - end).length
                if g0 < best.gap { best = (i, false, g0) }
                if g1 < best.gap { best = (i, true, g1) }
            }
            let closing = (chain[0].0 - end).length
            if chain.count >= 3, closing <= best.gap { break }
            guard best.gap <= maxCornerGapM else { break }
            let w = remaining.remove(at: best.index)
            chain.append(best.flip ? (w.1, w.0) : w)
        }
        guard chain.count >= 3, (chain[0].0 - chain[chain.count - 1].1).length <= maxCornerGapM else { return nil }
        return chain.indices.map { i in
            let prev = chain[(i + chain.count - 1) % chain.count], cur = chain[i]
            let joint = (prev.1 + cur.0) * 0.5
            if let x = intersect(prev.0, prev.1, cur.0, cur.1), (x - joint).length <= 2 * maxCornerGapM { return x }
            return joint  // parallel (a wall split in two) or a far-off intersection
        }
    }

    /// Where line a1–a2 meets line b1–b2, or nil if they're within ~10° of parallel.
    static func intersect(_ a1: PlanPoint, _ a2: PlanPoint, _ b1: PlanPoint, _ b2: PlanPoint) -> PlanPoint? {
        let r = a2 - a1, s = b2 - b1
        let denom = r.cross(s)
        guard abs(denom) > 0.17 * r.length * s.length else { return nil }  // sin 10°
        let t = (b1 - a1).cross(s) / denom
        return a1 + r * t
    }

    /// RoomPlan's own floor outline (largest floor), rotated into plan axes.
    static func largestFloor(_ g: RoomGeometry, phi: Double) -> [PlanPoint]? {
        let outlines = g.floors.map { $0.outline.map { rotate(PlanPoint(Double($0.x), Double($0.y)), by: phi) } }.filter { $0.count >= 3 }
        return outlines.max { abs(signedArea($0)) < abs(signedArea($1)) }
    }

    /// RoomPlan's floor polygon (largest floor, plan axes), squared up and without collinear
    /// points, when it is a usable outline: at least 3 corners, `minFloorAreaM2` or more, not
    /// self-intersecting, and (when there are walls) within 1 m of the walls' extent so it's
    /// the same room. Nil otherwise, so the wall loop decides.
    static func validFloor(_ g: RoomGeometry, phi: Double, walls: [(PlanPoint, PlanPoint)]) -> [PlanPoint]? {
        guard let raw = largestFloor(g, phi: phi) else { return nil }
        let polygon = withoutCollinear(squaredPolygon(cleaned(raw)))
        guard polygon.count >= 3, abs(signedArea(polygon)) >= minFloorAreaM2, isSimple(polygon) else { return nil }
        let ends = walls.flatMap { [$0.0, $0.1] }
        if !ends.isEmpty {
            let fx = polygon.map(\.x), fy = polygon.map(\.y), wx = ends.map(\.x), wy = ends.map(\.y)
            let off = [fx.min()! - wx.min()!, fx.max()! - wx.max()!, fy.min()! - wy.min()!, fy.max()! - wy.max()!]
            guard off.allSatisfy({ abs($0) <= 1 }) else { return nil }
        }
        return polygon
    }

    /// Makes nearly axis-aligned edges exactly axis-aligned (both ends get their mean
    /// coordinate), like `squared` does for walls. Perpendicular neighbours keep their
    /// other coordinate, so corners stay square.
    static func squaredPolygon(_ p: [PlanPoint]) -> [PlanPoint] {
        guard p.count >= 3 else { return p }
        var q = p
        for i in q.indices {
            let j = (i + 1) % q.count
            let (a, b) = squared((q[i], q[j]))
            q[i] = a
            q[j] = b
        }
        return q
    }

    /// Drops corners where the outline runs straight on (within ~2°).
    static func withoutCollinear(_ p: [PlanPoint]) -> [PlanPoint] {
        var q = p
        var i = 0
        while q.count > 3 && i < q.count {
            let a = q[(i + q.count - 1) % q.count], b = q[i], c = q[(i + 1) % q.count]
            let u = b - a, v = c - b
            if u.length < 1e-9 || v.length < 1e-9 || (abs(u.cross(v)) < 0.035 * u.length * v.length && u.dot(v) > 0) {
                q.remove(at: i)
            } else {
                i += 1
            }
        }
        return q
    }

    /// True when no two non-adjacent edges cross.
    static func isSimple(_ p: [PlanPoint]) -> Bool {
        let n = p.count
        guard n >= 3 else { return false }
        func crosses(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint, _ d: PlanPoint) -> Bool {
            let d1 = (b - a).cross(c - a), d2 = (b - a).cross(d - a)
            let d3 = (d - c).cross(a - c), d4 = (d - c).cross(b - c)
            return d1 * d2 < 0 && d3 * d4 < 0
        }
        for i in 0..<n {
            for j in (i + 1)..<n where j != i + 1 && !(i == 0 && j == n - 1) {
                if crosses(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) { return false }
            }
        }
        return true
    }

    /// Convex hull (monotone chain, counterclockwise), nil for fewer than 3 distinct points.
    static func hull(_ points: [PlanPoint]) -> [PlanPoint]? {
        let p = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard p.count >= 3 else { return nil }
        func turn(_ o: PlanPoint, _ a: PlanPoint, _ b: PlanPoint) -> Double { (a - o).cross(b - o) }
        var lower: [PlanPoint] = [], upper: [PlanPoint] = []
        for q in p {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        let out = Array(lower.dropLast() + upper.dropLast())
        return out.count >= 3 ? out : nil
    }

    /// Drops repeated points (< 2 cm apart) and makes the winding counterclockwise.
    static func cleaned(_ polygon: [PlanPoint]) -> [PlanPoint] {
        var out: [PlanPoint] = []
        for p in polygon where out.last.map({ (p - $0).length >= 0.02 }) ?? true { out.append(p) }
        if out.count > 1, let first = out.first, let last = out.last, (first - last).length < 0.02 { out.removeLast() }
        return signedArea(out) < 0 ? out.reversed() : out
    }

    static func signedArea(_ p: [PlanPoint]) -> Double {
        guard p.count >= 3 else { return 0 }
        return p.indices.reduce(0) { $0 + p[$1].cross(p[($1 + 1) % p.count]) } / 2
    }

    /// Projects an opening's two ends onto the polygon edge nearest its middle, clamped to
    /// that edge, so `FloorPlan.span(of:onEdge:)` (8 cm tolerance) finds it. Nil if no edge
    /// is within `maxOpeningDistanceM`.
    ///
    /// Example: demo door, world x −1.425…−0.575 at z 1.75, plan offset (2, 1.75) →
    /// (0.575, 3.5)–(1.425, 3.5). It already lies on the top edge (4, 3.5) → (0, 3.5), so
    /// projecting leaves it unchanged; a door scanned 5 cm off that wall would be pulled onto it.
    static func snapOpening(_ a: PlanPoint, _ b: PlanPoint, to polygon: [PlanPoint]) -> WallOpening? {
        let mid = (a + b) * 0.5
        var best: (p: PlanPoint, q: PlanPoint, distance: Double)?
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            let d = distance(mid, toSegment: p, q)
            if d < (best?.distance ?? .infinity) { best = (p, q, d) }
        }
        guard let edge = best, edge.distance <= maxOpeningDistanceM else { return nil }
        let dir = edge.q - edge.p, len = dir.length
        guard len > 1e-9 else { return nil }
        let u = dir * (1 / len)
        func onto(_ x: PlanPoint) -> PlanPoint {
            let t = min(len, max(0, (x - edge.p).dot(u)))
            return PlanPoint(Layout.cm(edge.p.x + u.x * t), Layout.cm(edge.p.y + u.y * t))
        }
        return WallOpening(from: onto(a), to: onto(b))
    }

    static func distance(_ x: PlanPoint, toSegment p: PlanPoint, _ q: PlanPoint) -> Double {
        let d = q - p, len2 = d.dot(d)
        guard len2 > 1e-12 else { return (x - p).length }
        let t = min(1, max(0, (x - p).dot(d) / len2))
        return (x - (p + d * t)).length
    }

    /// Normalizes degrees to [0, 360).
    static func normalizeDeg(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        let n = r < 0 ? r + 360 : r
        return n >= 360 - 1e-9 ? 0 : n
    }

    /// Snaps to the nearest multiple of 90° when within `snapToleranceDeg`, else rounds to 0.1°.
    ///
    /// Examples: 93 → 90, 352 → 0, 47 → 47, 279.96 → 270.
    static func snap(_ deg: Double) -> Double {
        let d = normalizeDeg(deg)
        let nearest = (d / 90).rounded() * 90
        if abs(d - nearest) <= snapToleranceDeg { return normalizeDeg(nearest) }
        return normalizeDeg((d * 10).rounded() / 10)
    }

    /// True when a piece's front (local +z, plan `(sin θ, cos θ)`) is within 30 cm of a wall
    /// while its back has at least 60 cm of floor: almost certainly backwards, since furniture
    /// sits with its back to the wall. Only judged for axis-aligned rotations.
    ///
    /// Example: demo desk, plan center (3.65, 2.35), depth 0.7, rotation 90 (front +x):
    /// front gap = (4 − 3.65) − 0.35 = 0, back gap = 3.65 − 0.35 = 3.3 → flip to 270.
    /// Demo wardrobe at (0.15, 2.75), depth 0.3, rotation 90: front gap 3.7 → keep.
    static func frontFacesWall(center: PlanPoint, rotationDeg deg: Double, depthM: Double, polygon: [PlanPoint]) -> Bool {
        guard abs(deg - (deg / 90).rounded() * 90) < 1e-6 else { return false }
        let r = deg * .pi / 180
        let front = PlanPoint(sin(r), cos(r))
        guard let ahead = rayDistance(from: center, along: front, polygon: polygon),
              let behind = rayDistance(from: center, along: front * -1, polygon: polygon) else { return false }
        return ahead - depthM / 2 < 0.3 && behind - depthM / 2 > 0.6
    }

    /// Distance from `o` along unit vector `d` to the first polygon edge, or nil if none is hit.
    static func rayDistance(from o: PlanPoint, along d: PlanPoint, polygon: [PlanPoint]) -> Double? {
        var best: Double?
        for i in polygon.indices {
            let p = polygon[i], e = polygon[(i + 1) % polygon.count] - p
            let denom = d.cross(e)
            guard abs(denom) > 1e-12 else { continue }
            let t = (p - o).cross(e) / denom, s = (p - o).cross(d) / denom
            if t > 1e-9, s >= -1e-9, s <= 1 + 1e-9, t < (best ?? .infinity) { best = t }
        }
        return best
    }
}
