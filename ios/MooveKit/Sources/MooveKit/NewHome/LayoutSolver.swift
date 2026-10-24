import Foundation

/// Something to place in the new home: a kept item or a bought one.
public struct LayoutItem: Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var name: String
    public var category: String
    /// Footprint along the item's own x (width) and z (depth); its back is the -z side.
    public var widthM: Double
    public var depthM: Double
    public var heightM: Double
    /// Measured from the scan's photos (`ScanColors`); the voxel model uses them over its keyword palette.
    public var primaryColor: VoxelColor?
    public var secondaryColor: VoxelColor?

    public init(id: UInt64, name: String, category: String, widthM: Double, depthM: Double, heightM: Double,
                primaryColor: VoxelColor? = nil, secondaryColor: VoxelColor? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.widthM = widthM
        self.depthM = depthM
        self.heightM = heightM
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }

    /// The item with its stored colors (`item.colors`, from `set_item_colors`), if any.
    public init(_ item: Item) {
        self.init(item, colors: nil)
    }

    /// The item with its scanned colors (matched by `scanObjectId`) if `colors` has any for it,
    /// else its stored colors (`item.colors`).
    public init(_ item: Item, colors: ScanColors?) {
        let primary: VoxelColor?, secondary: VoxelColor?
        if let c = colors?.colors(for: item) {
            (primary, secondary) = (c.primary, c.secondary)
        } else {
            (primary, secondary) = (item.colors?.primary, item.colors?.secondary)
        }
        self.init(id: item.id, name: item.name, category: item.category, widthM: item.widthM, depthM: item.depthM, heightM: item.heightM,
                  primaryColor: primary, secondaryColor: secondary)
    }
}

public struct LayoutOption: Sendable, Hashable, Identifiable {
    public var style: LayoutSolver.Style
    public var placements: [Placement]
    /// Items that didn't fit anywhere.
    public var unplaced: [UInt64]

    public var id: LayoutSolver.Style { style }
    public var name: String { style.label }
}

/// Places items along the walls of a floor plan: no overlaps, nothing in front
/// of a door, and each item in a room that suits it. Deterministic, so the
/// same inputs always give the same layout (handy for the demo).
public struct LayoutSolver: Sendable {
    public enum Style: String, CaseIterable, Sendable, Hashable {
        /// Each item in the room its category belongs in.
        case byFunction
        /// Everything in as few rooms as possible, leaving spare rooms empty.
        case compact
        /// Spread out so no room is crowded; big pieces away from corners.
        case open

        public var label: String {
            switch self {
            case .byFunction: "By function"
            case .compact: "Compact"
            case .open: "Open"
            }
        }
    }

    /// Gap between an item and the wall behind it.
    public var wallGapM = 0.05
    /// Gap between neighbouring items.
    public var itemGapM = 0.1
    /// Space kept clear in front of each door, on both sides.
    public var doorClearanceM = 0.9

    public let plan: FloorPlan

    public init(plan: FloorPlan) { self.plan = plan }

    public func solveAll(_ items: [LayoutItem]) -> [LayoutOption] {
        Style.allCases.map { solve(items, style: $0) }
    }

    public func solve(_ items: [LayoutItem], style: Style) -> LayoutOption {
        let rooms = plan.rooms.filter { $0.kind != .hallway && $0.polygon.count >= 3 }
        var obstacles = doorKeepOuts()
        var used: [String: Double] = [:] // footprint area placed per room
        var placements: [Placement] = []
        var unplaced: [UInt64] = []

        // Big things first: they're the hardest to fit.
        let ordered = items.sorted { ($0.widthM * $0.depthM, $1.id) > ($1.widthM * $1.depthM, $0.id) }
        for item in ordered {
            let candidates = roomOrder(for: item, rooms: rooms, style: style, used: used)
            var placed = false
            for room in candidates {
                if let spot = fit(item, in: room, obstacles: obstacles, style: style) {
                    placements.append(Placement(itemId: item.id, room: room.name, x: spot.center.x, y: spot.center.y, rotationDeg: spot.rotationDeg))
                    obstacles.append(spot.inflated(by: itemGapM / 2))
                    used[room.name, default: 0] += item.widthM * item.depthM
                    placed = true
                    break
                }
            }
            if !placed { unplaced.append(item.id) }
        }
        placements.sort { $0.itemId < $1.itemId }
        return LayoutOption(style: style, placements: placements, unplaced: unplaced.sorted())
    }

    // MARK: Room choice

    /// Rooms in the order to try them for this item.
    func roomOrder(for item: LayoutItem, rooms: [FloorPlanRoom], style: Style, used: [String: Double]) -> [FloorPlanRoom] {
        let preferred = Self.preferredKinds(for: item)
        func affinity(_ r: FloorPlanRoom) -> Int { preferred.firstIndex(of: r.kind).map { preferred.count - $0 } ?? 0 }
        func fill(_ r: FloorPlanRoom) -> Double { (used[r.name] ?? 0) / max(r.areaM2, 0.01) }
        // Primary rooms (biggest of each kind) first, so "Bedroom" gets the bed before "Bedroom 2".
        func rank(_ r: FloorPlanRoom) -> Int { rooms.filter { $0.kind == r.kind && $0.areaM2 > r.areaM2 }.count }

        switch style {
        case .byFunction:
            return rooms.sorted { (affinity($0), -rank($0), -fill($0)) > (affinity($1), -rank($1), -fill($1)) }
        case .compact:
            // Prefer rooms already in use, then the main living spaces.
            let core: Set<RoomKind> = [.living, .bedroom, .kitchen]
            func score(_ r: FloorPlanRoom) -> Double {
                (used[r.name] ?? 0 > 0 ? 4 : 0) + (core.contains(r.kind) ? 2 : 0) + Double(affinity(r)) * 0.5 - Double(rank(r)) * 3
            }
            return rooms.sorted { (score($0), $0.name) > (score($1), $1.name) }
        case .open:
            // Least-crowded suitable room first.
            return rooms.sorted {
                let a = affinity($0) > 0, b = affinity($1) > 0
                if a != b { return a }
                return (fill($0), $0.name) < (fill($1), $1.name)
            }
        }
    }

    /// Room kinds for an item: by category, except low media cabinets (category "dresser", but
    /// named "TV stand"/"media console") go where the TV goes.
    static func preferredKinds(for item: LayoutItem) -> [RoomKind] {
        if VName(item.name.lowercased()).has("tv stand", "television stand", "media console", "tv console", "entertainment center") {
            return preferredKinds(for: "tv")
        }
        return preferredKinds(for: item.category)
    }

    static func preferredKinds(for category: String) -> [RoomKind] {
        switch category.lowercased() {
        case "bed", "mattress": [.bedroom]
        case "sofa", "couch", "television", "tv": [.living, .office]
        case "table", "desk": [.office, .dining, .living, .bedroom]
        case "chair": [.office, .dining, .living, .bedroom]
        case "storage", "dresser", "nightstand", "bookshelf": [.bedroom, .living, .office]
        case "lamp": [.living, .bedroom, .office]
        case "appliance", "kitchenware", "refrigerator", "oven", "stove", "dishwasher", "washer", "dryer": [.kitchen]
        case "toilet", "bathtub", "sink": [.bathroom]
        case "decor", "plant": [.living, .bedroom, .dining]
        default: [.living, .bedroom, .office]
        }
    }

    // MARK: Fitting

    /// The first free spot along the room's walls, then anywhere in the room.
    func fit(_ item: LayoutItem, in room: FloorPlanRoom, obstacles: [OrientedRect], style: Style) -> OrientedRect? {
        let ccw = room.signedArea >= 0 ? room.polygon : room.polygon.reversed()
        let walls = ccw.indices.map { (ccw[$0], ccw[($0 + 1) % ccw.count]) }
        // Longest walls first; in the open style, start mid-wall instead of in a corner.
        let byLength = walls.sorted { (($0.1 - $0.0).length, $0.0.x, $0.0.y) > (($1.1 - $1.0).length, $1.0.x, $1.0.y) }
        let step = 0.1
        for (a, b) in byLength {
            let len = (b - a).length
            guard len >= item.widthM else { continue }
            let dir = (b - a) * (1 / len)
            let inward = PlanPoint(-dir.y, dir.x)
            let back = wallGapM + item.depthM / 2
            var offsets = Array(stride(from: item.widthM / 2, through: len - item.widthM / 2, by: step))
            if style == .open { offsets.sort { abs($0 - len / 2) < abs($1 - len / 2) } }
            for t in offsets {
                let center = a + dir * t + inward * back
                // Item faces into the room: its +z is `inward`.
                let rect = OrientedRect(center: center, halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: Self.rotationDeg(facing: inward))
                if isFree(rect, in: room, obstacles: obstacles) { return rect }
            }
        }
        // Interior grid, for things like a table in the middle of the room.
        let b = room.bounds
        for y in stride(from: b.minY + item.depthM / 2, through: b.maxY - item.depthM / 2, by: 0.2) {
            for x in stride(from: b.minX + item.widthM / 2, through: b.maxX - item.widthM / 2, by: 0.2) {
                let rect = OrientedRect(center: PlanPoint(x, y), halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: 0)
                if isFree(rect, in: room, obstacles: obstacles) { return rect }
            }
        }
        return nil
    }

    func isFree(_ rect: OrientedRect, in room: FloorPlanRoom, obstacles: [OrientedRect]) -> Bool {
        rect.corners.allSatisfy { room.contains($0) || Self.onBoundary($0, of: room) } && !obstacles.contains { $0.overlaps(rect) }
    }

    private static func onBoundary(_ p: PlanPoint, of room: FloorPlanRoom) -> Bool {
        room.edges.contains { a, b in
            let len = (b - a).length
            guard len > 0 else { return false }
            let d = (b - a) * (1 / len), v = p - a
            let t = v.dot(d)
            return abs(d.cross(v)) < 1e-6 && t >= -1e-6 && t <= len + 1e-6
        }
    }

    /// Rotation about +Y (degrees) that turns the item's +z toward `facing` (plan vector).
    /// Uses the same convention as `WallSegment.yawRadians`: plan y is world z.
    static func rotationDeg(facing f: PlanPoint) -> Double {
        // Rotating +z = (0, 1) in plan by θ about +Y gives (sin θ, cos θ).
        let deg = atan2(f.x, f.y) * 180 / .pi
        return ((deg.rounded() + 360).truncatingRemainder(dividingBy: 360))
    }

    /// A box in front of each door, reaching into the rooms on both sides.
    func doorKeepOuts() -> [OrientedRect] {
        plan.doors.map { d in
            let seg = WallSegment(from: d.from, to: d.to, room: "")
            return OrientedRect(center: seg.center, halfWidth: seg.lengthM / 2 + 0.05, halfDepth: doorClearanceM,
                                rotationDeg: Self.rotationDeg(facing: seg.inward))
        }
    }
}

/// A rectangle on the floor plan, rotated about its center.
public struct OrientedRect: Sendable, Hashable {
    public var center: PlanPoint
    /// Half extents along the rectangle's own x and z axes.
    public var halfWidth: Double
    public var halfDepth: Double
    public var rotationDeg: Double

    public init(center: PlanPoint, halfWidth: Double, halfDepth: Double, rotationDeg: Double) {
        self.center = center
        self.halfWidth = halfWidth
        self.halfDepth = halfDepth
        self.rotationDeg = rotationDeg
    }

    /// The rectangle's own x and z axes in plan coordinates.
    var axes: (x: PlanPoint, z: PlanPoint) {
        let r = rotationDeg * .pi / 180
        // Local +z → (sin, cos); local +x is +z rotated −90° → (cos, −sin).
        return (PlanPoint(cos(r), -sin(r)), PlanPoint(sin(r), cos(r)))
    }

    public var corners: [PlanPoint] {
        let (ax, az) = axes
        let x = ax * halfWidth, z = az * halfDepth
        return [center + x + z, center - x + z, center - x - z, center + x - z]
    }

    func inflated(by m: Double) -> OrientedRect {
        OrientedRect(center: center, halfWidth: halfWidth + m, halfDepth: halfDepth + m, rotationDeg: rotationDeg)
    }

    /// Separating axis test; touching edges don't count as overlap.
    public func overlaps(_ o: OrientedRect) -> Bool {
        let a = corners, b = o.corners
        for axis in [axes.x, axes.z, o.axes.x, o.axes.z] {
            let pa = a.map { $0.dot(axis) }, pb = b.map { $0.dot(axis) }
            if pa.max()! <= pb.min()! + 1e-9 || pb.max()! <= pa.min()! + 1e-9 { return false }
        }
        return true
    }
}
