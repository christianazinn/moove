import Foundation

// OWNER: mesher agent.

public enum VoxelMesher {
    /// Merges a grid into one mesh: only faces between a filled voxel and empty space,
    /// coplanar same-color faces merged (greedy meshing). `centered`: x/z centered on the
    /// grid (furniture); otherwise voxel (0,0,0)'s corner is the origin (the house).
    ///
    /// For each axis `d` and each side (+/-), every slice perpendicular to `d` gets a 2D mask
    /// of exposed face colors; the mask is then covered greedily by maximal same-color
    /// rectangles (widest run first, then grown along the second axis). One quad = 4 vertices
    /// with a flat normal and 2 counterclockwise triangles.
    public static func mesh(_ grid: VoxelGrid, centered: Bool = true) -> VoxelMesh {
        let nx = grid.nx, ny = grid.ny, nz = grid.nz
        let dims = SIMD3<Int>(nx, ny, nz)
        // Cell strides for x, y, z (cells are x fastest, then z, then y).
        let strides = SIMD3<Int>(1, nx * nz, nx)
        let s = Float(VoxelGrid.voxelSize)
        let origin = centered ? SIMD3<Float>(-Float(nx) * s / 2, 0, -Float(nz) * s / 2) : .zero

        var out = VoxelMesh()
        var paletteIndex: [VoxelColor: UInt32] = [:]
        var lastColor: VoxelColor = 0, lastIndex: UInt32 = 0

        let maxMask = max(nx * ny, ny * nz, nz * nx)
        var mask = [UInt32](repeating: 0, count: maxMask)

        grid.cells.withUnsafeBufferPointer { cells in
            mask.withUnsafeMutableBufferPointer { mask in
                for d in 0..<3 {
                    let u = (d + 1) % 3, v = (d + 2) % 3
                    let nd = dims[d], nu = dims[u], nv = dims[v]
                    let sd = strides[d], su = strides[u], sv = strides[v]
                    for sign in [1, -1] {
                        var normal = SIMD3<Float>.zero
                        normal[d] = Float(sign)
                        for i in 0..<nd {
                            // 1. Mask of exposed faces in this slice.
                            let hasNeighbor = sign > 0 ? i + 1 < nd : i > 0
                            let nOff = sign * sd
                            var any = false
                            for b in 0..<nv {
                                let rowBase = i * sd + b * sv
                                let mRow = b * nu
                                for a in 0..<nu {
                                    let idx = rowBase + a * su
                                    let c = cells[idx]
                                    var m: UInt32 = 0
                                    if c != 0, !hasNeighbor || cells[idx + nOff] == 0 { m = c; any = true }
                                    mask[mRow + a] = m
                                }
                            }
                            guard any else { continue }
                            let plane = Float(sign > 0 ? i + 1 : i)

                            // 2. Greedy rectangles.
                            for b in 0..<nv {
                                var a = 0
                                while a < nu {
                                    let m = mask[b * nu + a]
                                    if m == 0 { a += 1; continue }
                                    var w = 1
                                    while a + w < nu, mask[b * nu + a + w] == m { w += 1 }
                                    var h = 1
                                    grow: while b + h < nv {
                                        let row = (b + h) * nu + a
                                        for k in 0..<w where mask[row + k] != m { break grow }
                                        h += 1
                                    }
                                    for hh in 0..<h {
                                        let row = (b + hh) * nu + a
                                        for k in 0..<w { mask[row + k] = 0 }
                                    }

                                    // 3. Emit the quad.
                                    let color = m & 0xFFFFFF
                                    if color != lastColor || out.palette.isEmpty {
                                        if let pi = paletteIndex[color] {
                                            lastIndex = pi
                                        } else {
                                            lastIndex = UInt32(out.palette.count)
                                            paletteIndex[color] = lastIndex
                                            out.palette.append(color)
                                        }
                                        lastColor = color
                                    }
                                    var p0 = SIMD3<Float>.zero
                                    p0[d] = plane; p0[u] = Float(a); p0[v] = Float(b)
                                    var du = SIMD3<Float>.zero; du[u] = Float(w)
                                    var dv = SIMD3<Float>.zero; dv[v] = Float(h)
                                    let base = UInt32(out.positions.count)
                                    out.positions.append(origin + p0 * s)
                                    out.positions.append(origin + (p0 + du) * s)
                                    out.positions.append(origin + (p0 + du + dv) * s)
                                    out.positions.append(origin + (p0 + dv) * s)
                                    out.normals.append(normal); out.normals.append(normal)
                                    out.normals.append(normal); out.normals.append(normal)
                                    // e_u × e_v = e_d, so 0-1-2-3 is counterclockwise seen from +d.
                                    if sign > 0 {
                                        out.indices.append(base); out.indices.append(base + 1); out.indices.append(base + 2)
                                        out.indices.append(base); out.indices.append(base + 2); out.indices.append(base + 3)
                                    } else {
                                        out.indices.append(base); out.indices.append(base + 2); out.indices.append(base + 1)
                                        out.indices.append(base); out.indices.append(base + 3); out.indices.append(base + 2)
                                    }
                                    out.triangleColors.append(lastIndex)
                                    out.triangleColors.append(lastIndex)
                                    a += w
                                }
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}

extension IsoSprite {
    /// Grids larger than this on any axis are downsampled for thumbnails.
    static let maxSide = 48

    /// A dimetric thumbnail of the grid as seen from front-right and above, fitted to the unit square.
    ///
    /// Projection: screen X = x - z, screen Y (down) = (x + z) / 2 - y, so x runs down-right,
    /// z down-left and y up; the view ray is (1, 1, 1). Every face edge and face diagonal lands on
    /// the same triangular screen lattice, so each top/right/front face splits into two lattice
    /// triangles whose visibility is exact from one ray cast through its centroid. Fully visible
    /// faces are greedily merged into rectangles; half-visible faces become triangles. Nothing
    /// overlaps, and faces are still emitted back to front.
    public static func render(_ grid: VoxelGrid) -> IsoSprite {
        let g = Sampled(grid)
        guard g.anyFilled else { return IsoSprite() }
        let dims = SIMD3<Int>(g.nx, g.ny, g.nz)

        struct Pending { var corners: [SIMD3<Int>]; var color: VoxelColor; var depth: Int }
        var pending: [Pending] = []
        // Visible directions: right (+x), top (+y), front (+z).
        let shade: [Float] = [0.82, 1.0, 0.68]

        for d in 0..<3 {
            // In-plane axes p, q with e_p × e_q = e_d.
            let p = (d + 1) % 3, q = (d + 2) % 3
            let np = dims[p], nq = dims[q]
            var full = [UInt32](repeating: 0, count: np * nq)
            for i in 0..<dims[d] {
                var any = false
                for b in 0..<nq {
                    for a in 0..<np {
                        var c = SIMD3<Int>.zero
                        c[d] = i; c[p] = a; c[q] = b
                        let col = g.at(c)
                        full[b * np + a] = 0
                        guard col != 0 else { continue }
                        var n = c; n[d] += 1
                        guard g.at(n) == 0 else { continue }
                        // Half A: corners (0,0),(1,0),(1,1) in (p,q); ray crosses p, q, d in turn.
                        // Half B: corners (0,0),(1,1),(0,1); ray crosses q, p, d.
                        let visA = g.rayClear(from: n, order: (p, q, d))
                        let visB = g.rayClear(from: n, order: (q, p, d))
                        if visA && visB {
                            full[b * np + a] = col; any = true
                            continue
                        }
                        var o = c; o[d] += 1
                        var ep = SIMD3<Int>.zero; ep[p] = 1
                        var eq = SIMD3<Int>.zero; eq[q] = 1
                        let depth = 3 * (c.x + c.y + c.z) + 4
                        if visA { pending.append(Pending(corners: [o, o &+ ep, o &+ ep &+ eq], color: Self.shaded(col, shade[d]), depth: depth)) }
                        if visB { pending.append(Pending(corners: [o, o &+ ep &+ eq, o &+ eq], color: Self.shaded(col, shade[d]), depth: depth)) }
                    }
                }
                guard any else { continue }
                for b in 0..<nq {
                    var a = 0
                    while a < np {
                        let m = full[b * np + a]
                        if m == 0 { a += 1; continue }
                        var w = 1
                        while a + w < np, full[b * np + a + w] == m { w += 1 }
                        var h = 1
                        grow: while b + h < nq {
                            for k in 0..<w where full[(b + h) * np + a + k] != m { break grow }
                            h += 1
                        }
                        for hh in 0..<h { for k in 0..<w { full[(b + hh) * np + a + k] = 0 } }
                        var o = SIMD3<Int>.zero
                        o[d] = i + 1; o[p] = a; o[q] = b
                        var ep = SIMD3<Int>.zero; ep[p] = w
                        var eq = SIMD3<Int>.zero; eq[q] = h
                        // Depth of the rectangle's nearest cell (back-to-front sort key).
                        let near = o &+ ep &+ eq
                        let depth = 3 * (near.x + near.y + near.z - 3) + 4
                        pending.append(Pending(corners: [o, o &+ ep, o &+ ep &+ eq, o &+ eq], color: Self.shaded(m, shade[d]), depth: depth))
                        a += w
                    }
                }
            }
        }

        // Back to front (the viewer sits toward +x+y+z). Stable for equal keys.
        let order = pending.indices.sorted { (pending[$0].depth, $0) < (pending[$1].depth, $1) }
        func project(_ v: SIMD3<Int>) -> SIMD2<Float> {
            SIMD2(Float(v.x - v.z), Float(v.x + v.z) / 2 - Float(v.y))
        }
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        var faces: [Face] = []
        faces.reserveCapacity(order.count)
        for k in order {
            let pts = pending[k].corners.map(project)
            for pt in pts { lo = pointwiseMin(lo, pt); hi = pointwiseMax(hi, pt) }
            faces.append(Face(points: pts, color: pending[k].color))
        }
        let size = hi - lo
        let scale = 1 / max(size.x, size.y, 1e-6)
        let pad = (SIMD2<Float>(repeating: 1) - size * scale) / 2
        for f in faces.indices {
            faces[f].points = faces[f].points.map { pt in
                let n = (pt - lo) * scale + pad
                return SIMD2(min(max(n.x, 0), 1), min(max(n.y, 0), 1))
            }
        }
        var sprite = IsoSprite()
        sprite.faces = faces
        return sprite
    }

    static func shaded(_ c: VoxelColor, _ k: Float) -> VoxelColor {
        func ch(_ shift: UInt32) -> UInt32 {
            let v = Float((c >> shift) & 0xFF) * k
            return UInt32(min(255, max(0, v.rounded()))) << shift
        }
        return ch(16) | ch(8) | ch(0)
    }

    /// The grid as plain colors (0 = empty), downsampled to at most `maxSide` per axis.
    private struct Sampled {
        let nx: Int, ny: Int, nz: Int
        var cells: [UInt32]
        var anyFilled: Bool

        init(_ grid: VoxelGrid) {
            let f = max(1, (max(grid.nx, grid.ny, grid.nz) + IsoSprite.maxSide - 1) / IsoSprite.maxSide)
            nx = (grid.nx + f - 1) / f
            ny = (grid.ny + f - 1) / f
            nz = (grid.nz + f - 1) / f
            cells = [UInt32](repeating: 0, count: nx * ny * nz)
            anyFilled = false
            let src = grid.cells
            let gnx = grid.nx, gnz = grid.nz
            func srcAt(_ x: Int, _ y: Int, _ z: Int) -> UInt32 { src[(y * gnz + z) * gnx + x] }
            for y in 0..<ny {
                for z in 0..<nz {
                    for x in 0..<nx {
                        let x0 = x * f, y0 = y * f, z0 = z * f
                        let x1 = min(x0 + f, grid.nx), y1 = min(y0 + f, grid.ny), z1 = min(z0 + f, grid.nz)
                        // Center sample first; otherwise the topmost filled voxel in the block,
                        // so thin parts (legs, panels) survive.
                        var c = srcAt(min(x0 + f / 2, x1 - 1), min(y0 + f / 2, y1 - 1), min(z0 + f / 2, z1 - 1))
                        if c == 0, f > 1 {
                            search: for yy in stride(from: y1 - 1, through: y0, by: -1) {
                                for zz in z0..<z1 { for xx in x0..<x1 {
                                    let s = srcAt(xx, yy, zz)
                                    if s != 0 { c = s; break search }
                                } }
                            }
                        }
                        if c != 0 { cells[(y * nz + z) * nx + x] = c & 0xFFFFFF | 0x1000000; anyFilled = true }
                    }
                }
            }
        }

        @inline(__always) func at(_ c: SIMD3<Int>) -> UInt32 {
            guard c.x >= 0, c.y >= 0, c.z >= 0, c.x < nx, c.y < ny, c.z < nz else { return 0 }
            return cells[(c.y * nz + c.z) * nx + c.x] & 0xFFFFFF
        }

        /// Walks the view ray (1,1,1) from `start`, stepping axes in the given cyclic order,
        /// until it leaves the grid. True when no filled cell is hit.
        func rayClear(from start: SIMD3<Int>, order: (Int, Int, Int)) -> Bool {
            var c = start
            let axes = [order.0, order.1, order.2]
            var k = 0
            while c.x < nx, c.y < ny, c.z < nz {
                if at(c) != 0 { return false }
                c[axes[k]] += 1
                k = k == 2 ? 0 : k + 1
            }
            return true
        }
    }
}
