import Foundation

/// Sanity checks for detector finds against the room RoomPlan measured (#73).
///
/// The open-vocabulary detector happily labels room *structure*: in a real scan
/// it reported an interior window as two "mirrors", a wall-hung backdrop and a bare
/// wall as "refrigerators", a door frame as a "basket", a baseboard as a "vacuum",
/// and photo light stands as 2 m tall "vacuums". RoomPlan already knows where the
/// walls, doors, windows and floor are, so most of that is easy to reject.
public enum StructureCheck {
    public enum Verdict: Equatable, Sendable {
        case keep
        /// A real thing with the wrong label (its size can't be that category): keep
        /// it as an unnamed item so the vision agent names it from its photo.
        case unknown(reason: String)
        case drop(reason: String)
    }

    /// Category used for `.unknown` finds. The vision agent replaces it.
    public static let unknownCategory = "other"

    /// Typical height range (m) per category. Far below the range is a phantom;
    /// above it is something else wearing that label.
    public static let heightRange: [String: ClosedRange<Float>] = [
        "vacuum": 0.08...1.4, "refrigerator": 0.45...2.1, "bicycle": 0.5...1.4, "scooter": 0.3...1.45,
        "motorcycle": 0.8...1.7, "bench": 0.3...1.1, "bean bag": 0.25...1.2, "suitcase": 0.3...1.1,
        "backpack": 0.2...0.75, "plant": 0.1...2.6, "microwave": 0.18...0.55, "laptop": 0.01...0.45,
        "lamp": 0.2...2.2, "basket": 0.08...0.8, "box": 0.05...1.2, "bin": 0.1...1.0, "trash can": 0.2...1.2,
        "chair": 0.4...1.4, "stool": 0.3...1.0, "table": 0.35...1.2, "monitor": 0.2...0.8, "printer": 0.1...0.7,
        "fan": 0.2...1.6, "heater": 0.2...1.0, "guitar": 0.6...1.4, "piano": 0.8...1.6, "treadmill": 0.9...1.8,
        "exercise bike": 0.8...1.6, "stroller": 0.6...1.3, "room divider": 1.0...2.2, "coat rack": 1.2...2.0,
        "clothes rack": 1.0...2.0, "shoe rack": 0.2...1.2, "speaker": 0.1...1.3, "toy": 0.05...1.2,
    ]

    /// Flat by nature (very thin is fine) and usually hung on a wall.
    public static let wallMountable: Set<String> = ["mirror", "art", "clock", "television", "monitor"]
    /// Flat by nature but free-standing or lying down.
    public static let flatAllowed: Set<String> = ["rug", "yoga mat", "skis", "snowboard", "surfboard", "skateboard", "ironing board", "laptop"]
    /// Things that stand on the floor; one hovering a meter up isn't that.
    public static let floorStanding: Set<String> = [
        "refrigerator", "vacuum", "bicycle", "scooter", "motorcycle", "bench", "bean bag", "piano", "treadmill",
        "exercise bike", "rowing machine", "stroller", "room divider", "coat rack", "clothes rack", "washerDryer",
        "trash can", "suitcase", "chair", "table", "stool", "plant stand", "drums",
    ]

    public static func verdict(for o: RoomGeometry.Object, in room: RoomGeometry) -> Verdict {
        let c = o.transform.position
        let size = o.dimensions
        let category = o.category
        let floorY = room.floorY

        // 1. Outside the room: seen through a window or doorway into another room.
        // RoomPlan's floor outline can be partial, so use the hull of the floor
        // and the wall ends instead.
        let footprint = roomFootprint(room)
        if footprint.count >= 3, !contains(footprint, SIMD2(c.x, c.z), margin: 0.15) {
            return .drop(reason: "outside the room")
        }
        // 2. In the plane of a door or window: the opening itself, or what's beyond it.
        for opening in room.openings {
            let l = opening.transform.inverseApply(c)
            if abs(l.z) < 0.15, abs(l.x) < opening.dimensions.x / 2, abs(l.y) < opening.dimensions.y / 2 {
                return .drop(reason: "in a \(opening.kind.rawValue)")
            }
        }
        let isFlatKind = wallMountable.contains(category) || flatAllowed.contains(category)
        // 3. Flat against a wall and not something that hangs on walls: wall, trim, backdrop.
        if size.z < 0.12, !wallMountable.contains(category), isAgainstWall(o, room: room) {
            return .drop(reason: "flat against a wall")
        }
        // 4. Too thin for anything but flat kinds: a door frame or a wall edge.
        if size.z < 0.08, !isFlatKind {
            return .drop(reason: "too thin")
        }
        // 5. A "mirror" or picture with real depth is a view through glass, not a mirror.
        if wallMountable.contains(category), category != "television", category != "monitor", size.z > 0.2 {
            return .drop(reason: "too deep for a \(category)")
        }
        // 6. Floor-standing things don't float.
        let bottom = c.y - size.y / 2 - floorY
        if floorStanding.contains(category), bottom > 0.6 {
            return .drop(reason: "floating \(String(format: "%.1f", bottom)) m up")
        }
        // 7. Height has to make sense for the label.
        if let range = heightRange[category] {
            if size.y < range.lowerBound * 0.9 { return .drop(reason: "too small for a \(category)") }
            if size.y > range.upperBound * 1.1 { return .unknown(reason: "too tall for a \(category)") }
        }
        return .keep
    }

    /// Keeps plausible finds, renames mislabeled ones to `unknownCategory`.
    public static func apply(_ objects: [RoomGeometry.Object], in room: RoomGeometry) -> (kept: [RoomGeometry.Object], dropped: [(RoomGeometry.Object, String)]) {
        var kept: [RoomGeometry.Object] = []
        var dropped: [(RoomGeometry.Object, String)] = []
        for o in objects {
            switch verdict(for: o, in: room) {
            case .keep: kept.append(o)
            case .unknown:
                var renamed = o
                renamed.category = unknownCategory
                kept.append(renamed)
            case .drop(let reason): dropped.append((o, reason))
            }
        }
        return (kept, dropped)
    }

    /// Convex hull of the floor outline(s) and every wall's two ends, in (x, z).
    static func roomFootprint(_ room: RoomGeometry) -> [SIMD2<Float>] {
        var points = room.floorOutlines.flatMap { $0 }
        for w in room.walls {
            points += RoomGeometry.footprint(width: w.dimensions.x, depth: 0.01, w.transform)
        }
        return points.count >= 3 ? RoomGeometry.convexHull(points) : points
    }

    static func isAgainstWall(_ o: RoomGeometry.Object, room: RoomGeometry) -> Bool {
        let c = o.transform.position
        let ox = o.transform.columns[0]
        return room.walls.contains { w in
            let l = w.transform.inverseApply(c)
            guard abs(l.x) <= w.dimensions.x / 2 + 0.2, abs(l.z) < 0.2 else { return false }
            let wx = w.transform.columns[0]
            let parallel = abs(ox.x * wx.x + ox.z * wx.z) / max(1e-6, (ox.x * ox.x + ox.z * ox.z).squareRoot() * (wx.x * wx.x + wx.z * wx.z).squareRoot())
            return parallel > 0.9
        }
    }

    /// Point in polygon, counting points within `margin` of the outline as inside.
    static func contains(_ polygon: [SIMD2<Float>], _ p: SIMD2<Float>, margin: Float) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        if inside { return true }
        // Near an edge (scan outlines are a little tight)?
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let ab = b - a, ap = p - a
            let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / max(1e-6, ab.x * ab.x + ab.y * ab.y)))
            let d = ap - ab * t
            if (d.x * d.x + d.y * d.y).squareRoot() <= margin { return true }
        }
        return false
    }
}
