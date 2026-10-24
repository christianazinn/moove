/// Splits a wall into solid boxes around its doors, windows and openings, so
/// renderers can show real holes. Everything is in the wall's local space:
/// x along the wall, y up, both centered on the wall's center.
public struct WallPiece: Equatable, Sendable {
    public var center: SIMD2<Float>
    public var size: SIMD2<Float>
}

public struct WallHole: Equatable, Sendable {
    public var id: String
    public var kind: RoomGeometry.SurfaceKind
    /// Hole rectangle in wall-local (x, y).
    public var center: SIMD2<Float>
    public var size: SIMD2<Float>
}

extension RoomGeometry {
    /// Openings that belong to `wall`: by parent id when RoomPlan set one,
    /// otherwise anything lying in the wall's plane within its extent.
    public func holes(in wall: Surface) -> [WallHole] {
        let halfW = wall.dimensions.x / 2, halfH = wall.dimensions.y / 2
        return openings.compactMap { o in
            let local = wall.transform.inverseApply(o.transform.position)
            let belongs = o.parentId.map { $0 == wall.id }
                ?? (abs(local.z) < 0.15 && abs(local.x) < halfW + 0.05 && abs(local.y) < halfH + 0.05)
            guard belongs else { return nil }
            // Clamp to the wall so a sloppy scan can't punch outside it.
            let x0 = max(-halfW, local.x - o.dimensions.x / 2), x1 = min(halfW, local.x + o.dimensions.x / 2)
            let y0 = max(-halfH, local.y - o.dimensions.y / 2), y1 = min(halfH, local.y + o.dimensions.y / 2)
            guard x1 - x0 > 0.01, y1 - y0 > 0.01 else { return nil }
            return WallHole(id: o.id, kind: o.kind, center: SIMD2((x0 + x1) / 2, (y0 + y1) / 2), size: SIMD2(x1 - x0, y1 - y0))
        }
    }

    public static func pieces(wallSize: SIMD2<Float>, holes: [WallHole]) -> [WallPiece] {
        let halfW = wallSize.x / 2, halfH = wallSize.y / 2
        let eps: Float = 0.005
        var pieces: [WallPiece] = []
        func add(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float) {
            guard x1 - x0 > eps, y1 - y0 > eps else { return }
            pieces.append(WallPiece(center: SIMD2((x0 + x1) / 2, (y0 + y1) / 2), size: SIMD2(x1 - x0, y1 - y0)))
        }
        var cursor = -halfW
        for hole in holes.sorted(by: { $0.center.x < $1.center.x }) {
            let x0 = hole.center.x - hole.size.x / 2, x1 = hole.center.x + hole.size.x / 2
            let y0 = hole.center.y - hole.size.y / 2, y1 = hole.center.y + hole.size.y / 2
            add(cursor, x0, -halfH, halfH)          // solid wall before the hole
            let from = max(cursor, x0)
            add(from, x1, -halfH, y0)                // below (window sill)
            add(from, x1, y1, halfH)                 // above (lintel)
            cursor = max(cursor, x1)
        }
        add(cursor, halfW, -halfH, halfH)
        return pieces
    }
}

extension Transform {
    /// Inverse of `apply` for rigid transforms (rotation + translation).
    public func inverseApply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let d = p - position
        func dot(_ c: SIMD4<Float>) -> Float { c.x * d.x + c.y * d.y + c.z * d.z }
        return SIMD3(dot(columns[0]), dot(columns[1]), dot(columns[2]))
    }
}

extension RoomGeometry {
    /// Walls (and the doors/windows in them) cut off `height` meters above the
    /// floor, for a dollhouse view you can see into from any angle. Assumes the
    /// room is `centered()` (floor at y = 0).
    public func cutaway(at height: Float) -> RoomGeometry {
        func clip(_ s: Surface) -> Surface? {
            let bottom = s.transform.position.y - s.dimensions.y / 2
            let top = min(s.transform.position.y + s.dimensions.y / 2, height)
            guard top - bottom > 0.01 else { return nil }
            var clipped = s
            clipped.dimensions.y = top - bottom
            clipped.transform = s.transform.translated(by: SIMD3(0, (bottom + top) / 2 - s.transform.position.y, 0))
            return clipped
        }
        var g = self
        g.walls = walls.compactMap(clip)
        g.openings = openings.compactMap(clip)
        return g
    }
}
