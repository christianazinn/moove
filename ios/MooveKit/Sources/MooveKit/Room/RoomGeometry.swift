import Foundation

/// A scanned room in plain numbers, converted from RoomPlan's `CapturedRoom`
/// (meters, Y up, RoomPlan's world space). Renderers (3D model, 2D plan) and
/// the new-home lane read this instead of RoomPlan types, so it works in
/// previews, tests and on Linux.
public struct RoomGeometry: Codable, Sendable, Equatable {
    public enum SurfaceKind: String, Codable, Sendable {
        case wall, door, window, opening
    }

    public struct Surface: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: SurfaceKind
        /// The wall a door, window or opening sits in.
        public var parentId: String?
        /// Width (x), height (y), thickness (z) in meters.
        public var dimensions: SIMD3<Float>
        public var transform: Transform

        public init(id: String, kind: SurfaceKind, parentId: String? = nil, dimensions: SIMD3<Float>, transform: Transform) {
            self.id = id
            self.kind = kind
            self.parentId = parentId
            self.dimensions = dimensions
            self.transform = transform
        }
    }

    public struct Floor: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// Outline in world space, as (x, z) points. Y is `elevation`.
        public var outline: [SIMD2<Float>]
        public var elevation: Float

        public init(id: String, outline: [SIMD2<Float>], elevation: Float) {
            self.id = id
            self.outline = outline
            self.elevation = elevation
        }
    }

    public struct Object: Codable, Sendable, Equatable, Identifiable {
        /// RoomPlan's object UUID; matches `Item.scanObjectId`.
        public var id: String
        public var category: String
        /// Width (x), height (y), depth (z) in meters.
        public var dimensions: SIMD3<Float>
        /// Transform of the object's center.
        public var transform: Transform

        public init(id: String, category: String, dimensions: SIMD3<Float>, transform: Transform) {
            self.id = id
            self.category = category
            self.dimensions = dimensions
            self.transform = transform
        }
    }

    public var walls: [Surface]
    public var openings: [Surface]
    public var floors: [Floor]
    public var objects: [Object]

    public init(walls: [Surface] = [], openings: [Surface] = [], floors: [Floor] = [], objects: [Object] = []) {
        self.walls = walls
        self.openings = openings
        self.floors = floors
        self.objects = objects
    }
}

/// A rigid transform as a column-major 4x4 matrix (same layout as `simd_float4x4`),
/// kept as plain floats so MooveKit doesn't need the simd module.
public struct Transform: Codable, Sendable, Equatable {
    public var columns: [SIMD4<Float>]

    public init(columns: [SIMD4<Float>]) {
        precondition(columns.count == 4)
        self.columns = columns
    }

    public static let identity = Transform(columns: [
        SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1),
    ])

    /// A transform at `position`, rotated `yaw` radians about +Y.
    public static func at(_ position: SIMD3<Float>, yaw: Float = 0) -> Transform {
        let c = Float(cos(Double(yaw))), s = Float(sin(Double(yaw)))
        return Transform(columns: [
            SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(position.x, position.y, position.z, 1),
        ])
    }

    public var position: SIMD3<Float> { SIMD3(columns[3].x, columns[3].y, columns[3].z) }

    /// Rotation about +Y, from the local x axis. RoomPlan objects and walls are upright.
    public var yaw: Float { Float(atan2(Double(-columns[0].z), Double(columns[0].x))) }

    /// Applies the transform to a point.
    public func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = columns[0] * p.x + columns[1] * p.y + columns[2] * p.z + columns[3]
        return SIMD3(r.x, r.y, r.z)
    }

    public func translated(by d: SIMD3<Float>) -> Transform {
        var t = self
        t.columns[3] += SIMD4(d.x, d.y, d.z, 0)
        return t
    }
}

// MARK: - Derived geometry

extension RoomGeometry {
    /// Axis-aligned bounds of everything, in world space.
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var points: [SIMD3<Float>] = []
        for f in floors { points += f.outline.map { SIMD3($0.x, f.elevation, $0.y) } }
        for s in walls + openings { points += Self.corners(of: s.dimensions, s.transform) }
        for o in objects { points += Self.corners(of: o.dimensions, o.transform) }
        guard var lo = points.first else { return nil }
        var hi = lo
        for p in points {
            lo = pointwiseMin(lo, p)
            hi = pointwiseMax(hi, p)
        }
        return (lo, hi)
    }

    /// The floor's height (lowest floor, or the bottom of the walls when RoomPlan found no floor).
    public var floorY: Float {
        if let y = floors.map(\.elevation).min() { return y }
        return walls.map { $0.transform.position.y - $0.dimensions.y / 2 }.min() ?? 0
    }

    /// Moves the room so it is centered on the origin in XZ and the floor sits at y = 0.
    public func centered() -> RoomGeometry {
        guard let b = bounds else { return self }
        let shift = SIMD3<Float>(-(b.min.x + b.max.x) / 2, -floorY, -(b.min.z + b.max.z) / 2)
        var g = self
        g.walls = walls.map { var s = $0; s.transform = s.transform.translated(by: shift); return s }
        g.openings = openings.map { var s = $0; s.transform = s.transform.translated(by: shift); return s }
        g.objects = objects.map { var o = $0; o.transform = o.transform.translated(by: shift); return o }
        g.floors = floors.map { f in
            Floor(id: f.id, outline: f.outline.map { $0 + SIMD2(shift.x, shift.z) }, elevation: f.elevation + shift.y)
        }
        return g
    }

    /// Floor outlines to draw. Falls back to the walls' footprint hull when RoomPlan found no floor.
    public var floorOutlines: [[SIMD2<Float>]] {
        if !floors.isEmpty { return floors.map(\.outline) }
        let points = walls.flatMap { Self.footprint(width: $0.dimensions.x, depth: max($0.dimensions.z, 0.01), $0.transform) }
        return points.count >= 3 ? [Self.convexHull(points)] : []
    }

    /// Top-down rectangle (4 corners, x/z) of a surface or object.
    public static func footprint(width: Float, depth: Float, _ t: Transform) -> [SIMD2<Float>] {
        [SIMD3<Float>(-width / 2, 0, -depth / 2), SIMD3(width / 2, 0, -depth / 2), SIMD3(width / 2, 0, depth / 2), SIMD3(-width / 2, 0, depth / 2)]
            .map { let p = t.apply($0); return SIMD2(p.x, p.z) }
    }

    static func corners(of d: SIMD3<Float>, _ t: Transform) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for x in [-d.x / 2, d.x / 2] { for y in [-d.y / 2, d.y / 2] { for z in [-d.z / 2, d.z / 2] { out.append(t.apply(SIMD3(x, y, z))) } } }
        return out
    }

    /// Andrew's monotone chain, counter-clockwise.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let p = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [SIMD2<Float>] = [], upper: [SIMD2<Float>] = []
        for pt in p {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], pt) <= 0 { lower.removeLast() }
            lower.append(pt)
        }
        for pt in p.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], pt) <= 0 { upper.removeLast() }
            upper.append(pt)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
