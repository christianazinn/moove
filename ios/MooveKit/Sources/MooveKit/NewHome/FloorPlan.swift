import Foundation

// The new home's floor plan, stored as `newHome.floorPlanJson`.
//
// Coordinates are meters on the floor plane, matching RoomPlan / RealityKit
// (Y-up): a plan point (x, y) is the world point (x, 0, y). So plan `y` is
// world `z`, and #14 can place scanned items directly.
//
// JSON shape (the contract fields are `rooms[].name/polygon/widthM/depthM`;
// everything else is optional so worker- or Zillow-made plans still decode):
// { "rooms": [{ "name", "kind"?, "polygon": [[x, y], ...], "widthM", "depthM" }],
//   "doors"?: [{ "from": [x, y], "to": [x, y] }], "windows"?: [...], "wallHeightM"? }

public struct PlanPoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(a.x + b.x, a.y + b.y) }
    public static func - (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(a.x - b.x, a.y - b.y) }
    public static func * (a: PlanPoint, k: Double) -> PlanPoint { PlanPoint(a.x * k, a.y * k) }
    public func dot(_ o: PlanPoint) -> Double { x * o.x + y * o.y }
    public func cross(_ o: PlanPoint) -> Double { x * o.y - y * o.x }
    public var length: Double { (x * x + y * y).squareRoot() }
}

extension PlanPoint: Codable {
    /// Encoded as `[x, y]`, per the contract.
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(try c.decode(Double.self), try c.decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

public enum RoomKind: String, Codable, Sendable, CaseIterable {
    case bedroom, living, kitchen, dining, bathroom, office, hallway, other

    public var label: String {
        switch self {
        case .bedroom: "Bedroom"
        case .living: "Living room"
        case .kitchen: "Kitchen"
        case .dining: "Dining room"
        case .bathroom: "Bathroom"
        case .office: "Office"
        case .hallway: "Hallway"
        case .other: "Room"
        }
    }

    /// Best guess from a room name, for plans that don't say ("Primary Bedroom" -> bedroom).
    public static func guess(from name: String) -> RoomKind {
        let n = name.lowercased()
        let rules: [(RoomKind, [String])] = [
            (.bedroom, ["bed", "nursery", "guest"]),
            (.bathroom, ["bath", "wc", "toilet", "powder"]),
            (.kitchen, ["kitchen", "pantry"]),
            (.dining, ["dining"]),
            (.living, ["living", "lounge", "family", "great room", "den"]),
            (.office, ["office", "study"]),
            (.hallway, ["hall", "corridor", "entry", "foyer"]),
        ]
        return rules.first { _, words in words.contains { n.contains($0) } }?.0 ?? .other
    }
}

public struct FloorPlanRoom: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var kind: RoomKind
    /// Outline in plan meters, either winding order, not closed (first point isn't repeated).
    public var polygon: [PlanPoint]
    public var widthM: Double
    public var depthM: Double

    public var id: String { name }

    public init(name: String, kind: RoomKind? = nil, polygon: [PlanPoint]) {
        self.name = name
        self.kind = kind ?? RoomKind.guess(from: name)
        self.polygon = polygon
        let b = PlanBounds(polygon)
        self.widthM = b.width
        self.depthM = b.depth
    }

    /// An axis-aligned rectangle with its corner at (x, y).
    public static func rectangle(_ name: String, kind: RoomKind? = nil, x: Double, y: Double, width: Double, depth: Double) -> FloorPlanRoom {
        FloorPlanRoom(name: name, kind: kind, polygon: [
            PlanPoint(x, y), PlanPoint(x + width, y), PlanPoint(x + width, y + depth), PlanPoint(x, y + depth),
        ])
    }

    enum CodingKeys: String, CodingKey { case name, kind, polygon, widthM, depthM }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        polygon = try c.decode([PlanPoint].self, forKey: .polygon)
        kind = try c.decodeIfPresent(RoomKind.self, forKey: .kind) ?? RoomKind.guess(from: name)
        let b = PlanBounds(polygon)
        widthM = try c.decodeIfPresent(Double.self, forKey: .widthM) ?? b.width
        depthM = try c.decodeIfPresent(Double.self, forKey: .depthM) ?? b.depth
    }

    public var bounds: PlanBounds { PlanBounds(polygon) }

    /// Shoelace formula; positive when the polygon winds counterclockwise in plan (x right, y up).
    public var signedArea: Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for (a, b) in edges { sum += a.cross(b) }
        return sum / 2
    }

    public var areaM2: Double { abs(signedArea) }

    /// Area-weighted centroid; where the room label goes.
    public var centroid: PlanPoint {
        let a = signedArea
        guard abs(a) > 1e-9 else { return bounds.center }
        var cx = 0.0, cy = 0.0
        for (p, q) in edges {
            let f = p.cross(q)
            cx += (p.x + q.x) * f
            cy += (p.y + q.y) * f
        }
        return PlanPoint(cx / (6 * a), cy / (6 * a))
    }

    /// Consecutive point pairs, wrapping around.
    public var edges: [(PlanPoint, PlanPoint)] {
        polygon.indices.map { (polygon[$0], polygon[($0 + 1) % polygon.count]) }
    }

    /// Ray casting; points exactly on the boundary may go either way.
    public func contains(_ p: PlanPoint) -> Bool {
        var inside = false
        for (a, b) in edges where (a.y > p.y) != (b.y > p.y) {
            let xCross = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
            if p.x < xCross { inside.toggle() }
        }
        return inside
    }

    /// Floor triangles as indices into `polygon`, wound counterclockwise in plan
    /// coordinates (ear clipping; fine for the simple polygons rooms are).
    public func triangulate() -> [UInt32] {
        let n = polygon.count
        guard n >= 3 else { return [] }
        var order = Array(0..<n)
        if signedArea < 0 { order.reverse() }
        var out: [UInt32] = []
        var guardCount = 0
        while order.count > 3, guardCount < n * n {
            guardCount += 1
            var clipped = false
            for i in order.indices {
                let ia = order[(i + order.count - 1) % order.count], ib = order[i], ic = order[(i + 1) % order.count]
                let a = polygon[ia], b = polygon[ib], c = polygon[ic]
                guard (b - a).cross(c - b) > 1e-12 else { continue } // reflex or collinear
                let blocked = order.contains { j in
                    j != ia && j != ib && j != ic && Self.inTriangle(polygon[j], a, b, c)
                }
                if blocked { continue }
                out += [UInt32(ia), UInt32(ib), UInt32(ic)]
                order.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break } // degenerate polygon; emit what we have
        }
        if order.count == 3 { out += order.map(UInt32.init) }
        return out
    }

    private static func inTriangle(_ p: PlanPoint, _ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint) -> Bool {
        (b - a).cross(p - a) >= 0 && (c - b).cross(p - b) >= 0 && (a - c).cross(p - c) >= 0
    }
}

public struct PlanBounds: Sendable, Hashable {
    public var minX: Double, minY: Double, maxX: Double, maxY: Double

    public init(_ points: [PlanPoint]) {
        minX = points.map(\.x).min() ?? 0
        minY = points.map(\.y).min() ?? 0
        maxX = points.map(\.x).max() ?? 0
        maxY = points.map(\.y).max() ?? 0
    }

    public var width: Double { maxX - minX }
    public var depth: Double { maxY - minY }
    public var center: PlanPoint { PlanPoint((minX + maxX) / 2, (minY + maxY) / 2) }
}

/// A door or window: a span along a wall, from one plan point to another.
public struct WallOpening: Codable, Sendable, Hashable {
    public var from: PlanPoint
    public var to: PlanPoint

    public init(from: PlanPoint, to: PlanPoint) {
        self.from = from
        self.to = to
    }

    public var widthM: Double { (to - from).length }
}

/// One straight piece of wall, ready to render as a box.
public struct WallSegment: Sendable, Hashable {
    public var from: PlanPoint
    public var to: PlanPoint
    /// Room whose outline this wall belongs to.
    public var room: String
    /// Unit vector pointing into that room.
    public var inward: PlanPoint

    public init(from: PlanPoint, to: PlanPoint, room: String, inward: PlanPoint? = nil) {
        self.from = from
        self.to = to
        self.room = room
        let d = to - from, len = d.length
        // Left of the direction of travel; correct for counterclockwise rooms.
        self.inward = inward ?? (len > 0 ? PlanPoint(-d.y / len, d.x / len) : PlanPoint(0, 0))
    }

    public var lengthM: Double { (to - from).length }
    public var center: PlanPoint { (from + to) * 0.5 }
    /// Rotation about +Y (radians) that turns a box's local +X onto this wall,
    /// in RealityKit/RoomPlan world space where plan y is world z.
    public var yawRadians: Double { atan2(-(to.y - from.y), to.x - from.x) }
}

public struct FloorPlan: Codable, Sendable, Hashable {
    public var rooms: [FloorPlanRoom]
    public var doors: [WallOpening]
    public var windows: [WallOpening]
    public var wallHeightM: Double

    public init(rooms: [FloorPlanRoom], doors: [WallOpening] = [], windows: [WallOpening] = [], wallHeightM: Double = 2.6) {
        self.rooms = rooms
        self.doors = doors
        self.windows = windows
        self.wallHeightM = wallHeightM
    }

    enum CodingKeys: String, CodingKey { case rooms, doors, windows, wallHeightM }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rooms = try c.decode([FloorPlanRoom].self, forKey: .rooms)
        doors = try c.decodeIfPresent([WallOpening].self, forKey: .doors) ?? []
        windows = try c.decodeIfPresent([WallOpening].self, forKey: .windows) ?? []
        wallHeightM = try c.decodeIfPresent(Double.self, forKey: .wallHeightM) ?? 2.6
    }

    // MARK: JSON

    public init(json: String) throws {
        self = try JSONDecoder().decode(FloorPlan.self, from: Data(json.utf8))
    }

    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    // MARK: Geometry

    public var bounds: PlanBounds { PlanBounds(rooms.flatMap(\.polygon)) }
    public var totalAreaM2: Double { rooms.reduce(0) { $0 + $1.areaM2 } }

    public func room(named name: String) -> FloorPlanRoom? { rooms.first { $0.name == name } }

    /// The room containing a plan point, if any.
    public func room(at p: PlanPoint) -> FloorPlanRoom? { rooms.first { $0.contains(p) } }

    /// Every room edge with door openings cut out. Adjacent rooms each keep
    /// their own copy of a shared wall; the renderer insets them so they don't z-fight.
    public func wallSegments() -> [WallSegment] {
        rooms.flatMap { room in
            let flip = room.signedArea < 0 ? -1.0 : 1.0
            return room.edges.flatMap { a, b in
                Self.cut(from: a, to: b, openings: doors).map { piece in
                    let left = WallSegment(from: piece.0, to: piece.1, room: room.name).inward
                    return WallSegment(from: piece.0, to: piece.1, room: room.name, inward: left * flip)
                }
            }
        }
    }

    /// Windows that lie on a room's wall, for rendering glass on that wall.
    public func windows(in room: FloorPlanRoom) -> [WallOpening] {
        windows.filter { w in room.edges.contains { a, b in Self.span(of: w, onEdge: a, b) != nil } }
    }

    /// Splits edge a→b around any openings lying on it; drops slivers under 5 cm.
    static func cut(from a: PlanPoint, to b: PlanPoint, openings: [WallOpening]) -> [(PlanPoint, PlanPoint)] {
        let len = (b - a).length
        guard len > 1e-9 else { return [] }
        let gaps = openings.compactMap { span(of: $0, onEdge: a, b) }.sorted { $0.0 < $1.0 }
        var pieces: [(Double, Double)] = []
        var cursor = 0.0
        for (s, e) in gaps {
            if s > cursor { pieces.append((cursor, s)) }
            cursor = max(cursor, e)
        }
        if cursor < len { pieces.append((cursor, len)) }
        let dir = (b - a) * (1 / len)
        return pieces.filter { $0.1 - $0.0 > 0.05 }.map { (a + dir * $0.0, a + dir * $0.1) }
    }

    /// The opening's span along edge a→b as distances from `a`, or nil if it isn't on that edge.
    static func span(of o: WallOpening, onEdge a: PlanPoint, _ b: PlanPoint, tolerance: Double = 0.08) -> (Double, Double)? {
        let len = (b - a).length
        guard len > 1e-9 else { return nil }
        let dir = (b - a) * (1 / len)
        func along(_ p: PlanPoint) -> Double? {
            let v = p - a
            guard abs(dir.cross(v)) <= tolerance else { return nil }
            return v.dot(dir)
        }
        guard let t0 = along(o.from), let t1 = along(o.to) else { return nil }
        let s = max(0, min(t0, t1)), e = min(len, max(t0, t1))
        return e - s > 1e-6 ? (s, e) : nil
    }

    // MARK: Validation

    public enum Issue: Equatable, Sendable {
        case noRooms
        case tooFewPoints(room: String)
        case zeroArea(room: String)
        case duplicateName(String)
        case overlap(String, String)
    }

    /// Problems that would make the plan unrenderable or confuse the layout solver.
    public func issues() -> [Issue] {
        guard !rooms.isEmpty else { return [.noRooms] }
        var found: [Issue] = []
        var seen = Set<String>()
        for r in rooms {
            if r.polygon.count < 3 { found.append(.tooFewPoints(room: r.name)) } else if r.areaM2 < 0.25 { found.append(.zeroArea(room: r.name)) }
            if !seen.insert(r.name).inserted { found.append(.duplicateName(r.name)) }
        }
        // Rooms overlap if one's interior contains a point just inside the other's centroid.
        for i in rooms.indices {
            for j in rooms.indices where j > i {
                let a = rooms[i], b = rooms[j]
                if a.polygon.count >= 3, b.polygon.count >= 3, a.contains(b.centroid) || b.contains(a.centroid) {
                    found.append(.overlap(a.name, b.name))
                }
            }
        }
        return found
    }
}
