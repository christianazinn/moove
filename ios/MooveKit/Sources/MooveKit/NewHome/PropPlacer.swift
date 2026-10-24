import Foundation

/// The "lived-in" pass after `LayoutSolver` (MoveWise's `placeProps` + wall mounts, scene.js):
/// small things (lamps, books, photos, decor, a monitor) move off the floor onto a free
/// furniture top in the same room (the nightstand gets the lamp, the shelf gets the photos),
/// and art, mirrors, framed photos and wall-mounted TVs hang on the nearest wall, facing into
/// the room. Pure and deterministic.
///
/// Heights: `Placement.elevationM` is the item's bottom above the floor top. Surfaces come from
/// `VoxelModels.surfaces`, so a prop lands exactly on the voxel top it sits on.
public struct PropPlacer: Sendable {
    public let plan: FloorPlan
    /// Height of the walls you can always see (the dollhouse cuts every wall at 1.1 m, and only
    /// the exterior walls on the far side of the camera rise to full height, which changes as
    /// the camera orbits): hung items stay below it on every wall, so art never floats above a
    /// low wall, and anything too tall to hang there leans against the wall on the floor.
    public var wallTopM: Double
    /// Gallery height for the center of hung items (MoveWise's 1.45 m), when the walls allow.
    public var hangCenterM = 1.45
    /// Gap between props sharing a surface.
    public var propGapM = 0.03

    static let V = VoxelGrid.voxelSize
    /// Hung items keep their bottom above the baseboard.
    static let minHangBottomM = 0.12

    public init(plan: FloorPlan, wallTopM: Double = 1.1) {
        self.plan = plan
        self.wallTopM = wallTopM
    }

    /// How a piece takes part in the pass.
    public enum Role: Sendable, Hashable {
        /// Stays where the layout put it; its surfaces can hold props.
        case furniture
        /// Small enough to sit on a surface.
        case prop
        /// Hangs on a wall.
        case wall
    }

    /// Categories that are props whenever they're small enough.
    static let propCategories: Set<String> = ["decor", "lamp", "light", "lighting", "books", "book", "photos", "electronics", "trading_cards", "plant", "plants"]
    /// Builders that are furniture (or floor things) at any size.
    static let floorKinds: Set<VoxelModels.Kind> = [.sofa, .bed, .mattress, .desk, .chair, .table, .dresser, .bookshelf, .rug, .appliance, .beanBag, .quiltRack, .box,
                                                         .guitar, .piano, .keyboard, .drums, .vacuum, .scooter, .bag, .fitness, .board]

    /// `elevationM`: a known height (a scanned wall-mounted TV is a wall item whatever its name).
    public static func role(of spec: VoxelItemSpec, elevationM: Double? = nil) -> Role {
        let kind = VoxelModels.kind(spec)
        let name = VName(spec.name.lowercased())
        let h = spec.heightM.isFinite && spec.heightM > 0 ? spec.heightM : kind.defaultSize.2
        let w = spec.widthM.isFinite && spec.widthM > 0 ? spec.widthM : kind.defaultSize.0
        let d = spec.depthM.isFinite && spec.depthM > 0 ? spec.depthM : kind.defaultSize.1
        switch kind {
        case .art, .mirror: return .wall
        case .framedPhotos where h > 0.3: return .wall
        case .tv where name.word("wall") || name.has("mounted", "wall-mount") || (elevationM ?? 0) > 0.3: return .wall
        default: break
        }
        let cat = VoxelModels.trimmed(spec.category.lowercased())
        let small = h < 0.7 && w * d < 0.4
        if small && (propCategories.contains(cat) || !floorKinds.contains(kind)) { return .prop }
        return .furniture
    }

    public func place(_ placements: [Placement], items: [LayoutItem], extraRoom: String? = nil, scanned: Set<UInt64> = []) -> [Placement] {
        place(placements, specs: Dictionary(items.map { ($0.id, VoxelItemSpec($0)) }, uniquingKeysWith: { a, _ in a }), extraRoom: extraRoom, scanned: scanned)
    }

    /// Returns `placements` with props moved onto surfaces and wall items hung (other placements
    /// unchanged, same order). Items in `specs` with no placement are added when `extraRoom`
    /// names a room (a scan's props, which RoomPlan doesn't locate) and they find a spot there.
    /// Props that fit no surface keep their floor spot; wall items with no free wall do too.
    ///
    /// `scanned`: ids whose placement is where a scan saw them. They keep their x/y: a scanned
    /// prop only goes up onto a surface whose footprint holds its spot (within
    /// `scannedReachM`), else it stays put; a scanned wall item stays on its nearest wall at
    /// the same spot along it (only its height is adjusted). Empty for solver-made layouts.
    public func place(_ placements: [Placement], specs: [UInt64: VoxelItemSpec], extraRoom: String? = nil,
                      scanned: Set<UInt64> = []) -> [Placement] {
        var out = placements
        var built: [UInt64: (grid: VoxelGrid, surfaces: [VoxelSurface])] = [:]
        func model(_ id: UInt64, wall: Bool = false) -> (grid: VoxelGrid, surfaces: [VoxelSurface])? {
            guard let s = specs[id] else { return nil }
            if wall { return VoxelModels.buildWithSurfaces(VoxelModels.wallVariant(s)) }
            if let m = built[id] { return m }
            let m = VoxelModels.buildWithSurfaces(s)
            built[id] = m
            return m
        }

        // Missing items join as candidates in `extraRoom`, starting at its center.
        var missing: [UInt64] = []
        if let extraRoom, let room = plan.room(named: extraRoom) {
            let placed = Set(placements.map(\.itemId))
            for id in specs.keys.sorted() where !placed.contains(id) && Self.role(of: specs[id]!) != .furniture {
                let c = room.centroid
                out.append(Placement(itemId: id, room: extraRoom, x: c.x, y: c.y))
                missing.append(id)
            }
        }

        var roles: [Int: Role] = [:]
        for (i, p) in out.enumerated() {
            guard let s = specs[p.itemId] else { continue }
            roles[i] = Self.role(of: s, elevationM: p.elevationM)
        }

        // Furniture in each room: surfaces and solid boxes (for hung items to clear).
        var surfaces: [Surface] = []
        var solids: [String: [(rect: OrientedRect, bottom: Double, top: Double)]] = [:]
        for (i, p) in out.enumerated() where roles[i] == .furniture {
            guard let m = model(p.itemId), let spec = specs[p.itemId] else { continue }
            let g = m.grid, base = p.elevationM ?? 0
            let rect = OrientedRect(center: PlanPoint(p.x, p.y), halfWidth: Double(g.nx) * Self.V / 2,
                                    halfDepth: Double(g.nz) * Self.V / 2, rotationDeg: p.rotationDeg)
            if VoxelModels.kind(spec) != .rug { solids[p.room, default: []].append((rect, base, base + Double(g.ny) * Self.V)) }
            for s in m.surfaces {
                surfaces.append(Surface(parent: p, parentType: Self.parentType(spec, s, grid: g), grid: g, s: s))
            }
        }

        // 1. Props, lamps first (they want the nightstand), then electronics, then biggest first.
        let propIdx = out.indices.filter { roles[$0] == .prop }.sorted { a, b in
            let ka = Self.propOrder(specs[out[a].itemId]!), kb = Self.propOrder(specs[out[b].itemId]!)
            if ka != kb { return ka < kb }
            let sa = specs[out[a].itemId]!, sb = specs[out[b].itemId]!
            if sa.widthM * sa.depthM != sb.widthM * sb.depthM { return sa.widthM * sa.depthM > sb.widthM * sb.depthM }
            return out[a].itemId < out[b].itemId
        }
        var unplacedMissing = Set(missing)
        // Scanned props first, so the others make room around them.
        for i in propIdx where scanned.contains(out[i].itemId) {
            guard let m = model(out[i].itemId) else { continue }
            if let q = scannedSpot(out[i], grid: m.grid, surfaces: &surfaces) { out[i] = q }
        }
        for i in propIdx where !scanned.contains(out[i].itemId) {
            let p = out[i]
            guard let spec = specs[p.itemId], let m = model(p.itemId) else { continue }
            let kind = VoxelModels.kind(spec)
            let candidates = surfaces.indices
                .filter { surfaces[$0].parent.room == p.room && surfaces[$0].parent.itemId != p.itemId }
                .compactMap { j -> (Int, Int)? in Self.preference(kind, surfaces[j].parentType).map { (j, $0) } }
                .sorted { a, b in
                    let sa = surfaces[a.0], sb = surfaces[b.0]
                    if a.1 != b.1 { return a.1 < b.1 }
                    if sa.areaM2 != sb.areaM2 { return sa.areaM2 > sb.areaM2 }
                    return (sa.parent.itemId, sa.s.y) < (sb.parent.itemId, sb.s.y)
                }
            for (j, _) in candidates {
                if let spot = fit(m.grid, on: &surfaces[j]) {
                    out[i] = spot.placement(for: p)
                    unplacedMissing.remove(p.itemId)
                    break
                }
            }
        }

        // 2. Wall items.
        var hung: [String: [(rect: OrientedRect, bottom: Double, top: Double)]] = [:]
        for i in out.indices where roles[i] == .wall {
            let p = out[i]
            guard let m = model(p.itemId, wall: true), let room = plan.room(named: p.room) ?? plan.room(at: PlanPoint(p.x, p.y)) else { continue }
            if let done = hang(p, grid: m.grid, in: room, solids: solids[room.name] ?? [], hung: hung[room.name] ?? [],
                               keepSpot: scanned.contains(p.itemId)) {
                out[i] = done.placement
                hung[room.name, default: []].append((done.rect, done.bottom, done.top))
                unplacedMissing.remove(p.itemId)
            }
        }
        return out.filter { !unplacedMissing.contains($0.itemId) }
    }

    // MARK: Props on surfaces

    enum ParentType { case nightstand, dresser, desk, table, shelf, shelfTop, tvStand }

    struct Surface {
        var parent: Placement
        var parentType: ParentType
        var grid: VoxelGrid
        var s: VoxelSurface
        /// Taken rectangles in the parent's local meters (x0, z0, x1, z1).
        var used: [(Double, Double, Double, Double)] = []

        var areaM2: Double { Double(s.width * s.depth) * PropPlacer.V * PropPlacer.V }
        /// Surface rect in the parent's local meters (model centered on x/z).
        var local: (x0: Double, z0: Double, x1: Double, z1: Double) {
            let V = PropPlacer.V, hx = Double(grid.nx) / 2, hz = Double(grid.nz) / 2
            return ((Double(s.x0) - hx) * V, (Double(s.z0) - hz) * V, (Double(s.x1) - hx) * V, (Double(s.z1) - hz) * V)
        }
    }

    struct Spot {
        var center: PlanPoint
        var rotationDeg: Double
        var elevationM: Double
        var parent: UInt64

        func placement(for p: Placement) -> Placement {
            var q = p
            q.x = center.x; q.y = center.y; q.rotationDeg = rotationDeg
            q.elevationM = elevationM; q.onTopOf = parent; q.wallMounted = nil
            return q
        }
    }

    static func parentType(_ spec: VoxelItemSpec, _ s: VoxelSurface, grid: VoxelGrid) -> ParentType {
        switch VoxelModels.kind(spec) {
        case .dresser:
            let n = VName(spec.name.lowercased())
            let small = Double(grid.nx) * V <= 0.65 && Double(grid.ny) * V <= 0.8
            return n.has("nightstand", "night stand", "bedside") || small ? .nightstand : .dresser
        case .desk: return .desk
        case .bookshelf: return s.clearance != nil ? .shelf : .shelfTop
        case .tv: return .tvStand
        default: return .table
        }
    }

    /// Lower is placed first.
    static func propOrder(_ spec: VoxelItemSpec) -> Int {
        switch VoxelModels.kind(spec) {
        case .lamp: 0
        case .tv, .electronics: 1
        default: 2
        }
    }

    /// Rank of a surface type for a prop (lower is better), nil when it never goes there.
    static func preference(_ kind: VoxelModels.Kind, _ t: ParentType) -> Int? {
        let order: [ParentType]
        switch kind {
        case .lamp: order = [.nightstand, .desk, .dresser, .table, .tvStand, .shelfTop, .shelf]
        case .photos, .framedPhotos, .books, .binder: order = [.shelf, .nightstand, .dresser, .desk, .shelfTop, .table, .tvStand]
        case .tv: order = [.tvStand, .dresser, .table, .desk]
        case .electronics: order = [.desk, .tvStand, .dresser, .table, .nightstand, .shelf]
        case .plant, .decor: order = [.dresser, .shelf, .table, .nightstand, .tvStand, .desk, .shelfTop]
        default: order = [.dresser, .desk, .table, .nightstand, .shelf, .tvStand, .shelfTop]
        }
        return order.firstIndex(of: t)
    }

    /// The free spot nearest the surface's center for a prop model, facing the parent's front
    /// (or turned 90° when only that fits). Marks it used.
    func fit(_ prop: VoxelGrid, on sf: inout Surface) -> Spot? {
        if let c = sf.s.clearance, prop.ny > c { return nil }
        let V = Self.V, eps = 1e-9
        let r = sf.local
        let cx = (r.x0 + r.x1) / 2, cz = (r.z0 + r.z1) / 2
        for turn in [0.0, 90.0] {
            let fw = (turn == 0 ? Double(prop.nx) : Double(prop.nz)) * V
            let fd = (turn == 0 ? Double(prop.nz) : Double(prop.nx)) * V
            guard fw <= r.x1 - r.x0 + eps, fd <= r.z1 - r.z0 + eps else { continue }
            // Candidate centers on a 2.5 cm lattice, nearest the surface center first.
            let step = V / 2
            var xs: [Double] = [], zs: [Double] = []
            var x = r.x0 + fw / 2
            while x <= r.x1 - fw / 2 + eps { xs.append(x); x += step }
            var z = r.z0 + fd / 2
            while z <= r.z1 - fd / 2 + eps { zs.append(z); z += step }
            var cands: [(Double, Double)] = []
            for z in zs { for x in xs { cands.append((x, z)) } }
            cands.sort { a, b in
                let da = (a.0 - cx) * (a.0 - cx) + (a.1 - cz) * (a.1 - cz), db = (b.0 - cx) * (b.0 - cx) + (b.1 - cz) * (b.1 - cz)
                return da != db ? da < db : (a.1, a.0) < (b.1, b.0)
            }
            let g = propGapM
            for (x, z) in cands {
                let rect = (x - fw / 2, z - fd / 2, x + fw / 2, z + fd / 2)
                let hit = sf.used.contains { u in
                    rect.0 < u.2 + g - eps && u.0 < rect.2 + g - eps && rect.1 < u.3 + g - eps && u.1 < rect.3 + g - eps
                }
                if hit { continue }
                sf.used.append(rect)
                let p = sf.parent
                let axes = OrientedRect(center: .init(0, 0), halfWidth: 0, halfDepth: 0, rotationDeg: p.rotationDeg).axes
                let center = PlanPoint(p.x, p.y) + axes.x * x + axes.z * z
                let rot = (p.rotationDeg + turn).truncatingRemainder(dividingBy: 360)
                return Spot(center: center, rotationDeg: rot, elevationM: Self.mm((p.elevationM ?? 0) + Double(sf.s.y) * V), parent: p.itemId)
            }
        }
        return nil
    }

    /// How far outside a surface's footprint a scanned prop's spot may be and still sit on it.
    static let scannedReachM = 0.15

    /// A scanned prop on the surface whose footprint holds its scanned (x, y), at that x/y and
    /// rotation (the surface nearest its scanned height, or the lowest one when the scan put
    /// it near the floor). Nil when no surface is under it. Marks the spot used.
    func scannedSpot(_ p: Placement, grid: VoxelGrid, surfaces: inout [Surface]) -> Placement? {
        let V = Self.V, reach = Self.scannedReachM
        let target = p.elevationM ?? 0
        var best: (j: Int, local: (Double, Double), height: Double)?
        for j in surfaces.indices where surfaces[j].parent.room == p.room && surfaces[j].parent.itemId != p.itemId {
            let sf = surfaces[j]
            if let c = sf.s.clearance, grid.ny > c { continue }
            let axes = OrientedRect(center: .init(0, 0), halfWidth: 0, halfDepth: 0, rotationDeg: sf.parent.rotationDeg).axes
            let rel = PlanPoint(p.x, p.y) - PlanPoint(sf.parent.x, sf.parent.y)
            let lx = rel.dot(axes.x), lz = rel.dot(axes.z)
            let r = sf.local
            guard lx >= r.x0 - reach, lx <= r.x1 + reach, lz >= r.z0 - reach, lz <= r.z1 + reach else { continue }
            let h = (sf.parent.elevationM ?? 0) + Double(sf.s.y) * V
            if let b = best, abs(b.height - target) <= abs(h - target) { continue }
            best = (j, (lx, lz), h)
        }
        guard let best else { return nil }
        let hw = Double(grid.nx) * V / 2, hd = Double(grid.nz) * V / 2
        surfaces[best.j].used.append((best.local.0 - hw, best.local.1 - hd, best.local.0 + hw, best.local.1 + hd))
        var q = p
        q.elevationM = Self.mm(best.height)
        q.onTopOf = surfaces[best.j].parent.itemId
        q.wallMounted = nil
        return q
    }

    // MARK: Wall items

    struct Hung {
        var placement: Placement
        var rect: OrientedRect
        var bottom: Double
        var top: Double
    }

    /// Hangs a (wall-variant) model on the room wall nearest `p`, facing in: centered at
    /// `hangCenterM` (or `p.elevationM`, a scanned height), kept under `wallTopM`, clear of doors,
    /// windows, furniture below and other hung items; slides along the wall when blocked.
    /// Too tall to hang under the visible wall: leans on the floor against it.
    func hang(_ p: Placement, grid: VoxelGrid, in room: FloorPlanRoom, solids: [(rect: OrientedRect, bottom: Double, top: Double)],
              hung: [(rect: OrientedRect, bottom: Double, top: Double)], keepSpot: Bool = false) -> Hung? {
        let V = Self.V
        let w = Double(grid.nx) * V, d = Double(grid.nz) * V, h = Double(grid.ny) * V
        let ccw = room.signedArea >= 0 ? room.polygon : room.polygon.reversed()
        let n = ccw.count
        guard n >= 3 else { return nil }
        let center = PlanPoint(p.x, p.y)
        var edges: [(PlanPoint, PlanPoint)] = []
        for i in 0..<n {
            let a = ccw[i], b = ccw[(i + 1) % n]
            if (b - a).length >= w + 2 * V { edges.append((a, b)) }
        }
        edges.sort { (e1: (PlanPoint, PlanPoint), e2: (PlanPoint, PlanPoint)) -> Bool in
            Self.distance(center, e1.0, e1.1) < Self.distance(center, e2.0, e2.1)
        }
        let lean = wallTopM - h < Self.minHangBottomM
        let wanted = p.elevationM ?? (hangCenterM - h / 2)
        let bottom0 = lean ? 0 : min(max(wanted, Self.minHangBottomM), wallTopM - h)
        // A scanned piece: its own (nearest) wall, at its spot along it.
        if keepSpot { edges = Array(edges.prefix(1)) }
        for (a, b) in edges {
            let len = (b - a).length
            let dir = (b - a) * (1 / len)
            let inward = PlanPoint(-dir.y, dir.x)
            let blocked = (plan.doors + plan.windows).compactMap { Self.span(of: $0, a, dir, len) }
            // Walls are two voxels centered on the edge: hang on the inner face (in front of the
            // baseboard when leaning).
            let off = (lean ? 2 * V : V) + 0.005 + d / 2
            let tMin = w / 2 + V, tMax = len - w / 2 - V
            let t0 = min(max((center - a).dot(dir), tMin), tMax)
            var ts: [Double] = [t0]
            var k = 1.0
            while !keepSpot && (t0 - k * V >= tMin - 1e-9 || t0 + k * V <= tMax + 1e-9) {
                if t0 + k * V <= tMax + 1e-9 { ts.append(t0 + k * V) }
                if t0 - k * V >= tMin - 1e-9 { ts.append(t0 - k * V) }
                k += 1
            }
            for t in ts {
                let lo: Double = t - w / 2 - V, hi: Double = t + w / 2 + V
                if !keepSpot && blocked.contains(where: { (s: (Double, Double)) -> Bool in hi > s.0 && lo < s.1 }) { continue }
                let c = a + dir * t + inward * off
                let rect = OrientedRect(center: c, halfWidth: w / 2, halfDepth: d / 2, rotationDeg: LayoutSolver.rotationDeg(facing: inward))
                var bottom = bottom0
                var ok = true
                for s in solids where s.rect.overlaps(rect.inflated(by: 0.02)) {
                    if lean { ok = false; break }
                    if s.top > bottom - 0.03 && s.bottom < bottom + h { bottom = s.top + 0.05 }
                }
                guard ok, bottom + h <= wallTopM + 1e-9 || lean else { continue }
                if !keepSpot, hung.contains(where: { $0.rect.overlaps(rect.inflated(by: 0.04)) && $0.bottom < bottom + h && bottom < $0.top }) { continue }
                var q = p
                q.x = c.x; q.y = c.y
                q.rotationDeg = rect.rotationDeg
                q.elevationM = Self.mm(bottom)
                q.wallMounted = true
                q.onTopOf = nil
                q.room = room.name
                return Hung(placement: q, rect: rect, bottom: bottom, top: bottom + h)
            }
        }
        return nil
    }

    /// Rounded to the millimeter, so saved layouts don't carry float noise.
    static func mm(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    /// An opening's span (t0, t1) along edge a + dir·t, if it lies on that edge.
    static func span(of o: WallOpening, _ a: PlanPoint, _ dir: PlanPoint, _ len: Double) -> (Double, Double)? {
        let tol = 0.1
        let f = o.from - a, e = o.to - a
        guard abs(dir.cross(f)) < tol, abs(dir.cross(e)) < tol else { return nil }
        let t0 = min(f.dot(dir), e.dot(dir)), t1 = max(f.dot(dir), e.dot(dir))
        guard t1 > -tol, t0 < len + tol else { return nil }
        return (t0, t1)
    }

    static func distance(_ x: PlanPoint, _ p: PlanPoint, _ q: PlanPoint) -> Double {
        let d = q - p, len2 = d.dot(d)
        guard len2 > 1e-12 else { return (x - p).length }
        let t = min(1, max(0, (x - p).dot(d) / len2))
        return (x - (p + d * t)).length
    }
}
