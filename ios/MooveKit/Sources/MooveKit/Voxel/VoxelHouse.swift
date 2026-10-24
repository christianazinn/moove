import Foundation

// OWNER: scene agent. The voxel shell of the whole home, ported from MoveWise's
// buildHomeShell / buildFloor (static/scene/scene.js): a wooden plinth with a visible
// ledge, oak plank floors (pale tile in wet rooms), cream tiled cut-away walls two voxels
// thick with darker wood baseboards, door gaps and windows with a sill and glass.

public enum VoxelHouse {
    /// Thickness of the wooden base under the floor, in voxels; furniture stands on top of it.
    /// Layer 0 is the plinth (it also covers the margin); layer 1 is the floor surface.
    public static let baseVoxels = 2
    public static var floorTopM: Double { Double(baseVoxels) * VoxelGrid.voxelSize }
    /// Margin around the plan, in meters, so the base shows an edge. Walls sit centered on
    /// room edges, so one voxel of this goes under the exterior walls and the rest is ledge.
    public static let marginM = 0.15

    /// Colors used by the shell, 0xRRGGBB (from MoveWise's COLORS / FLOORS).
    public enum Palette {
        public static let plinth: VoxelColor = 0x8A6F55
        public static let plinthLedge: VoxelColor = 0x7E654D
        public static let oak: [VoxelColor] = [0xC89F6E, 0xD2AC7C, 0xBE9262, 0xCBA474, 0xB98D5D, 0xD6B385]
        public static let plankSeam: VoxelColor = 0xA9825A
        public static let floorTile: [VoxelColor] = [0xE8E3D9, 0xE1DBD0, 0xECE7DE]
        public static let floorGrout: VoxelColor = 0xCFC6B8
        public static let wallTile: [VoxelColor] = [0xF1E9DC, 0xEDE4D5, 0xF3ECE1]
        public static let wallGrout: VoxelColor = 0xE2D8C8
        public static let wallCap: VoxelColor = 0xE2D6C3
        public static let baseboard: VoxelColor = 0xA9865F
        public static let threshold: VoxelColor = 0xA57E58
        public static let sill: VoxelColor = 0xC9A273
        public static let windowFrame: VoxelColor = 0xF7F3EB
        /// Renderers draw this color translucent.
        public static let glass: VoxelColor = 0xBFDCEA
    }

    /// Height of the window sill above the floor; glass fills the wall above it.
    static let sillHeightM = 0.7
    /// Plank width across the run (planks run along x), in voxels.
    static let plankWidth = 3
    /// Wall and floor tile size, in voxels.
    static let wallTileSize = 6
    static let floorTileSize = 6

    /// The whole home as one grid: base, plank floors per room, cut-away tiled walls with
    /// door gaps and windows, baseboards. Grid voxel (0,0,0) sits at world
    /// (plan.bounds.minX - marginM, 0, plan.bounds.minY - marginM).
    public static func build(_ plan: FloorPlan, cutawayHeightM: Double = 1.1) -> VoxelGrid {
        let b = plan.bounds
        let V = VoxelGrid.voxelSize
        let wallRows = VoxelGrid.count(cutawayHeightM)
        var g = VoxelGrid(nx: VoxelGrid.count(b.width + 2 * marginM), ny: wallRows + baseVoxels,
                          nz: VoxelGrid.count(b.depth + 2 * marginM))
        let nx = g.nx, nz = g.nz
        let o = origin(of: plan)
        let ox = o.x, oz = o.z
        /// Plan point at the center of column (i, k).
        func center(_ i: Int, _ k: Int) -> PlanPoint { PlanPoint(ox + (Double(i) + 0.5) * V, oz + (Double(k) + 0.5) * V) }
        func col(_ p: Double, _ o: Double, _ n: Int) -> Int { min(n - 1, max(0, Int(((p - o) / V).rounded(.down)))) }

        /// Visits columns whose centers lie within `half` of segment a→b (perpendicular), with
        /// the along-segment distance `t` in `range(len)`.
        func stamp(_ a: PlanPoint, _ bb: PlanPoint, half: Double, _ visit: (Int, Int, Double, Double) -> Void) {
            let d = bb - a, len = d.length
            guard len > 1e-9 else { return }
            let dir = d * (1 / len)
            let pad = half + V
            let i0 = col(min(a.x, bb.x) - pad, ox, nx), i1 = col(max(a.x, bb.x) + pad, ox, nx)
            let k0 = col(min(a.y, bb.y) - pad, oz, nz), k1 = col(max(a.y, bb.y) + pad, oz, nz)
            for k in k0...k1 {
                for i in i0...i1 {
                    let v = center(i, k) - a
                    guard abs(dir.cross(v)) < half else { continue }
                    visit(i, k, v.dot(dir), len)
                }
            }
        }

        // 1. Which room each column is in.
        var roomAt = [Int](repeating: -1, count: nx * nz)
        for (r, room) in plan.rooms.enumerated() where room.polygon.count >= 3 {
            let rb = room.bounds
            for k in col(rb.minY, oz, nz)...col(rb.maxY, oz, nz) {
                for i in col(rb.minX, ox, nx)...col(rb.maxX, ox, nx) where roomAt[k * nx + i] < 0 {
                    if room.contains(center(i, k)) { roomAt[k * nx + i] = r }
                }
            }
        }

        // 2. Walls: two voxels centered on every room edge. One grid, so shared walls merge.
        // wallAxis: 0 = none, 1 = runs along x, 2 = runs along z (for the tile pattern).
        var wallAxis = [UInt8](repeating: 0, count: nx * nz)
        for room in plan.rooms where room.polygon.count >= 3 {
            for (a, e) in room.edges {
                let axis: UInt8 = abs(e.x - a.x) >= abs(e.y - a.y) ? 1 : 2
                stamp(a, e, half: V) { i, k, t, len in
                    guard t >= -V, t <= len + V else { return }
                    wallAxis[k * nx + i] = axis
                }
            }
        }

        // 3. Openings. Doors clear the wall full height; windows get glass, frame and a sill.
        enum Opening { case none, door, window(frame: Bool) }
        var opening = [Opening](repeating: .none, count: nx * nz)
        var sillLip = [Bool](repeating: false, count: nx * nz)
        for door in plan.doors {
            stamp(door.from, door.to, half: 2 * V) { i, k, t, len in
                guard t > 0, t < len, wallAxis[k * nx + i] != 0 else { return }
                opening[k * nx + i] = .door
            }
        }
        for window in plan.windows {
            stamp(window.from, window.to, half: 2 * V) { i, k, t, len in
                guard t > 0, t < len else { return }
                let c = k * nx + i
                if wallAxis[c] != 0 {
                    if case .door = opening[c] { return }
                    opening[c] = .window(frame: t < V || t > len - V)
                } else {
                    sillLip[c] = true
                }
            }
        }

        // 4. Floor patterns. Planks run along x in rows `plankWidth` deep, with deterministic lengths.
        let plankRows = (nz + plankWidth - 1) / plankWidth
        var plankId = [Int32](repeating: 0, count: plankRows * nx) // plank index within the row
        var plankEnd = [Bool](repeating: false, count: plankRows * nx)
        for j in 0..<plankRows {
            var i = 0, p = 0
            while i < nx {
                let len = p == 0 ? 3 + Int(hash(j, 7) * 18) : 12 + Int(hash(j, p, 3) * 19)
                let end = min(nx, i + len)
                for x in i..<end { plankId[j * nx + x] = Int32(p) }
                plankEnd[j * nx + end - 1] = true
                i = end
                p += 1
            }
        }
        func floorColor(_ i: Int, _ k: Int, room r: Int) -> VoxelColor {
            let room = plan.rooms[r]
            switch room.kind {
            case .bathroom, .kitchen:
                let rb = room.bounds
                let u = i - col(rb.minX, ox, nx), w = k - col(rb.minY, oz, nz)
                let s = floorTileSize
                if u % s == 0 || w % s == 0 { return Palette.floorGrout }
                return Palette.floorTile[Int(hash(u / s, w / s, 13) * Double(Palette.floorTile.count))]
            default:
                let j = k / plankWidth, c = j * nx + i
                if plankEnd[c] { return Palette.plankSeam }
                return Palette.oak[Int(hash(j, Int(plankId[c]), 11) * Double(Palette.oak.count))]
            }
        }

        // 5. Fill.
        let sillK = min(wallRows - 4, Int(sillHeightM / V))
        let hasWindows = sillK >= 1
        for k in 0..<nz {
            for i in 0..<nx {
                let c = k * nx + i
                let axis = wallAxis[c], r = roomAt[c]
                g[i, 0, k] = axis == 0 && r < 0 ? Palette.plinthLedge : Palette.plinth
                if axis != 0 {
                    if case .door = opening[c] {
                        g[i, 1, k] = Palette.threshold
                        continue
                    }
                    g[i, 1, k] = Palette.plinth
                } else if r >= 0 {
                    g[i, 1, k] = floorColor(i, k, room: r)
                }
                if sillLip[c], hasWindows { g[i, baseVoxels + sillK, k] = Palette.sill }
                guard axis != 0 else { continue }
                let along = axis == 1 ? i : k
                for row in 0..<wallRows {
                    let y = baseVoxels + row
                    var color: VoxelColor
                    if row < 2 {
                        color = Palette.baseboard
                    } else if row == wallRows - 1 {
                        color = Palette.wallCap
                    } else {
                        let t = row - 2, s = wallTileSize
                        color = along % s == 0 || t % s == 0
                            ? Palette.wallGrout
                            : Palette.wallTile[Int(hash(along / s, t / s, Int(axis)) * Double(Palette.wallTile.count))]
                    }
                    if hasWindows, case let .window(frame) = opening[c] {
                        if row == sillK {
                            color = Palette.sill
                        } else if row > sillK, row < wallRows - 1 {
                            color = frame || row == wallRows - 2 ? Palette.windowFrame : Palette.glass
                        }
                    }
                    g[i, y, k] = color
                }
            }
        }
        return g
    }

    /// World position (meters) of grid voxel (0,0,0)'s corner.
    public static func origin(of plan: FloorPlan) -> SIMD3<Double> {
        SIMD3(plan.bounds.minX - marginM, 0, plan.bounds.minY - marginM)
    }

    /// Deterministic hash of a few ints to [0, 1) (MoveWise's `hash`).
    static func hash(_ n: Int...) -> Double {
        var h: UInt32 = 0x9E37_79B1
        for v in n {
            h = (h ^ UInt32(truncatingIfNeeded: v)) &* 0x85EB_CA6B
            h ^= h >> 13
            h = h &* 0xC2B2_AE35
            h ^= h >> 16
        }
        return Double(h) / 4_294_967_296
    }
}
