/// Ear-clipping triangulation for simple polygons (convex or not, e.g. an
/// L-shaped floor). Returns triangle indices, counter-clockwise in (x, y).
public enum Triangulation {
    public static func triangulate(_ polygon: [SIMD2<Float>]) -> [UInt32] {
        guard polygon.count >= 3 else { return [] }
        var indices = Array(0..<polygon.count)
        if signedArea(polygon) < 0 { indices.reverse() }

        var triangles: [UInt32] = []
        var guardCount = 0
        while indices.count > 3, guardCount < polygon.count * polygon.count {
            guardCount += 1
            var clipped = false
            for i in 0..<indices.count {
                let prev = indices[(i + indices.count - 1) % indices.count]
                let cur = indices[i]
                let next = indices[(i + 1) % indices.count]
                let a = polygon[prev], b = polygon[cur], c = polygon[next]
                guard cross(a, b, c) > 1e-9 else { continue }  // reflex or degenerate
                let containsOther = indices.contains { j in
                    j != prev && j != cur && j != next && pointInTriangle(polygon[j], a, b, c)
                }
                if containsOther { continue }
                triangles += [UInt32(prev), UInt32(cur), UInt32(next)]
                indices.remove(at: i)
                clipped = true
                break
            }
            if !clipped { break }  // self-intersecting input; return what we have
        }
        if indices.count == 3 { triangles += indices.map(UInt32.init) }
        return triangles
    }

    public static func signedArea(_ p: [SIMD2<Float>]) -> Float {
        var a: Float = 0
        for i in p.indices {
            let j = (i + 1) % p.count
            a += p[i].x * p[j].y - p[j].x * p[i].y
        }
        return a / 2
    }

    static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    static func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        cross(a, b, p) >= 0 && cross(b, c, p) >= 0 && cross(c, a, p) >= 0
    }
}
