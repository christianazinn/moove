import Foundation
import Testing
@testable import MooveKit

/// The dollhouse split (`VoxelHouse.buildLayers`): a shared base, plus a tall and a low look
/// of the exterior walls per facing (and corner) that the app swaps as the camera orbits.
@Suite struct VoxelHouseLayersTests {
    static let plan = DemoHouse.floorPlan
    static let layers = VoxelHouse.buildLayers(plan)
    static let V = VoxelGrid.voxelSize
    static let cutY = VoxelHouse.baseVoxels + VoxelGrid.count(1.1)

    /// Plan point at the center of house-grid column (i, k).
    static func center(_ i: Int, _ k: Int, plan: FloorPlan = plan) -> PlanPoint {
        let o = VoxelHouse.origin(of: plan)
        return PlanPoint(o.x + (Double(i) + 0.5) * V, o.z + (Double(k) + 0.5) * V)
    }

    /// House-grid column containing plan point (x, y).
    static func column(_ x: Double, _ y: Double, plan: FloorPlan = plan) -> (Int, Int) {
        let o = VoxelHouse.origin(of: plan)
        return (Int(((x - o.x) / V + 1e-6).rounded(.down)), Int(((y - o.z) / V + 1e-6).rounded(.down)))
    }

    /// Voxel at house-grid (i, y, k) in a layer, nil when outside it or empty.
    static func at(_ l: VoxelHouse.Layer, _ i: Int, _ y: Int, _ k: Int) -> VoxelColor? {
        l.grid[i - l.offset.x, y - l.offset.y, k - l.offset.z]
    }

    static let tallShell = VoxelHouse.shell(plan, cutawayHeightM: 1.1, fullHeightM: plan.wallHeightM, realism: true,
                                            wallColor: nil, floorColor: nil).grid

    /// Tall pieces whose facings include `f`.
    static func tallPieces(_ f: VoxelHouse.Facing, _ r: (base: VoxelGrid, layers: [VoxelHouse.Layer]) = layers) -> [VoxelHouse.Layer] {
        r.layers.filter { $0.tall && $0.facings.contains(f) }
    }

    /// The base plus the given pieces in one grid of `size`, and the number of voxels drawn twice.
    static func compose(_ base: VoxelGrid, _ pieces: [VoxelHouse.Layer], size: VoxelGrid) -> (grid: VoxelGrid, doubled: Int) {
        var g = VoxelGrid(nx: size.nx, ny: size.ny, nz: size.nz), doubled = 0
        func put(_ i: Int, _ y: Int, _ k: Int, _ c: VoxelColor?) {
            guard let c else { return }
            if g[i, y, k] != nil { doubled += 1 }
            g[i, y, k] = c
        }
        for y in 0..<base.ny { for k in 0..<base.nz { for i in 0..<base.nx { put(i, y, k, base[i, y, k]) } } }
        for l in pieces {
            for y in 0..<l.grid.ny { for k in 0..<l.grid.nz { for i in 0..<l.grid.nx {
                put(i + l.offset.x, y + l.offset.y, k + l.offset.z, l.grid[i, y, k])
            } } }
        }
        return (g, doubled)
    }

    /// The shell as seen with every facing low / every facing tall.
    static func lowLook(_ r: (base: VoxelGrid, layers: [VoxelHouse.Layer]) = layers, size: VoxelGrid = tallShell) -> VoxelGrid {
        compose(r.base, r.layers.filter { !$0.tall }, size: size).grid
    }
    static func tallLook(_ r: (base: VoxelGrid, layers: [VoxelHouse.Layer]) = layers, size: VoxelGrid = tallShell) -> VoxelGrid {
        compose(r.base, r.layers.filter(\.tall), size: size).grid
    }

    static func sameVoxels(_ a: VoxelGrid, _ b: VoxelGrid) -> Bool {
        let ny = max(a.ny, b.ny)
        for y in 0..<ny { for k in 0..<a.nz { for i in 0..<a.nx where a[i, y, k] != b[i, y, k] { return false } } }
        return true
    }

    @Test func baseAndLowPiecesAreTheCutawayBuild() {
        #expect(Self.sameVoxels(Self.lowLook(), VoxelHouse.build(Self.plan)))
        let colored = VoxelHouse.buildLayers(Self.plan, wallColor: 0x6688AA, floorColor: 0x554433)
        #expect(Self.sameVoxels(Self.lowLook(colored), VoxelHouse.build(Self.plan, wallColor: 0x6688AA, floorColor: 0x554433)))
    }

    @Test func baseAndTallPiecesAreTheFullHeightShell() {
        #expect(Self.tallShell.ny == VoxelHouse.baseVoxels + VoxelGrid.count(2.6))
        #expect(Self.sameVoxels(Self.tallLook(), Self.tallShell))
        // Nothing above the cut is in the base.
        #expect(Self.layers.base.ny == Self.cutY)
    }

    /// Plans to check the split on: the demo house and an L (with an inside corner).
    static let lPlan = FloorPlan(rooms: [.rectangle("A", x: 0, y: 0, width: 4, depth: 2), .rectangle("B", x: 0, y: 2, width: 2, depth: 2)],
                                 windows: [WallOpening(from: PlanPoint(1, 4), to: PlanPoint(1.8, 4)),
                                           WallOpening(from: PlanPoint(4, 0.5), to: PlanPoint(4, 1.5))],
                                 wallHeightM: 2.4)

    @Test func noVoxelDrawnTwiceAtAnyYaw() {
        for plan in [Self.plan, Self.lPlan] {
            let r = VoxelHouse.buildLayers(plan)
            let size = VoxelHouse.shell(plan, cutawayHeightM: 1.1, fullHeightM: plan.wallHeightM, realism: true,
                                        wallColor: nil, floorColor: nil).grid
            for step in 0..<72 {
                let a = Double(step) * 5 * .pi / 180
                let v = SIMD2(sin(a), cos(a))
                let shown = r.layers.filter { $0.isShown(viewFromTarget: v) }
                let (_, doubled) = Self.compose(r.base, shown, size: size)
                #expect(doubled == 0, "yaw \(step * 5)°: \(doubled) voxels drawn twice")
                // Each facing set shows exactly one look.
                for fs in Set(r.layers.map(\.facings)) {
                    let looks = Set(shown.filter { $0.facings == fs }.map(\.tall))
                    #expect(looks.count <= 1, "yaw \(step * 5)°: \(fs) shows both looks")
                }
            }
            // Corners of two facings are their own pieces, never also in a single-facing piece.
            var owner: [SIMD3<Int>: Set<VoxelHouse.Facing>] = [:]
            for l in r.layers where l.tall {
                for y in 0..<l.grid.ny { for k in 0..<l.grid.nz { for i in 0..<l.grid.nx where l.grid[i, y, k] != nil {
                    let p = SIMD3(i, y, k) &+ l.offset
                    #expect(owner[p] == nil, "\(p) in \(String(describing: owner[p])) and \(l.facings)")
                    owner[p] = l.facings
                } } }
            }
            #expect(r.layers.contains { $0.facings.count == 2 }, "no corner pieces")
        }
    }

    @Test func eachFacingHoldsOnlyItsOwnExteriorWall() {
        // The demo house is an 11 x 10.2 m rectangle, so each facing is one side of it
        // (curtains reach a few voxels into the room).
        let b = Self.plan.bounds
        for f in VoxelHouse.Facing.allCases {
            var filled = Set<Int>()
            for l in Self.tallPieces(f) where l.facings == [f] {
                for k in 0..<l.grid.nz {
                    for i in 0..<l.grid.nx where (0..<l.grid.ny).contains(where: { l.grid[i, $0, k] != nil }) {
                        let p = Self.center(i + l.offset.x, k + l.offset.z)
                        let off: Double = switch f {
                        case .plusX: abs(p.x - b.maxX)
                        case .minusX: abs(p.x - b.minX)
                        case .plusZ: abs(p.y - b.maxY)
                        case .minusZ: abs(p.y - b.minY)
                        }
                        #expect(off < 4 * Self.V, "\(f) voxel at \(p.x),\(p.y)")
                        if off < Self.V { filled.insert(f == .plusX || f == .minusX ? k + l.offset.z : i + l.offset.x) }
                    }
                }
            }
            let side = f == .plusX || f == .minusX ? b.depth : b.width
            #expect(Double(filled.count) > side / Self.V - 4, "\(f): \(filled.count) columns")
        }
    }

    @Test func interiorWallsStayLow() {
        // L-shaped plan: the shared wall (y = 2, x 0..2) is interior; the notch walls are exterior.
        let plan = FloorPlan(rooms: [.rectangle("A", x: 0, y: 0, width: 4, depth: 2), .rectangle("B", x: 0, y: 2, width: 2, depth: 2)])
        let r = VoxelHouse.buildLayers(plan, fullHeightM: 2.4)
        let cutY = Self.cutY
        func facings(_ x: Double, _ y: Double) -> Set<VoxelHouse.Facing> {
            let (i, k) = Self.column(x, y, plan: plan)
            return r.layers.filter { l in l.tall && (cutY..<(VoxelHouse.baseVoxels + 48)).contains { Self.at(l, i, $0, k) != nil } }
                .reduce(into: Set()) { $0.formUnion($1.facings) }
        }
        #expect(facings(1, 2).isEmpty && facings(1, 1.98).isEmpty && facings(1, 2.02).isEmpty)
        #expect(facings(3, 2.02) == [.plusZ])
        #expect(facings(2.02, 3) == [.plusX])
        #expect(facings(4.02, 1) == [.plusX])
        #expect(facings(1, -0.02) == [.minusZ])
        #expect(facings(-0.02, 3) == [.minusX])
        #expect(facings(1, 4.02) == [.plusZ])
        // Interior partitions in the demo house (living/kitchen at x = 6) are only in the base.
        let (i, k) = Self.column(6.0, 0.6)
        #expect(Self.layers.layers.allSatisfy { l in (0..<(l.offset.y + l.grid.ny)).allSatisfy { Self.at(l, i, $0, k) == nil } })
        #expect(Self.layers.base[i, Self.cutY - 1, k] == VoxelHouse.Palette.wallCap)
    }

    @Test func heights() {
        let top = VoxelHouse.baseVoxels + VoxelGrid.count(Self.plan.wallHeightM)
        #expect(Self.layers.layers.filter(\.tall).map { $0.offset.y + $0.grid.ny }.max() == top)
        #expect(Self.layers.layers.filter { !$0.tall }.allSatisfy { $0.offset.y + $0.grid.ny <= Self.cutY })
        let short = VoxelHouse.buildLayers(Self.plan, fullHeightM: 2.4)
        #expect(short.layers.filter(\.tall).map { $0.offset.y + $0.grid.ny }.max() == VoxelHouse.baseVoxels + 48)
        // Wall top: cap color at full height on a plain stretch of the north (-z) wall, wall all the way up.
        let tall = Self.tallLook(short, size: VoxelHouse.shell(Self.plan, cutawayHeightM: 1.1, fullHeightM: 2.4, realism: true,
                                                               wallColor: nil, floorColor: nil).grid)
        let (i, k) = Self.column(0.4, 0.0)
        #expect(tall[i, VoxelHouse.baseVoxels + 47, k] == VoxelHouse.Palette.wallCap)
        #expect((VoxelHouse.baseVoxels..<(VoxelHouse.baseVoxels + 48)).allSatisfy { tall[i, $0, k] != nil })
        // No pieces when the full height is the cut.
        #expect(VoxelHouse.buildLayers(Self.plan, fullHeightM: 1.1).layers.isEmpty)
    }

    @Test func displayHeightClampsTallScans() {
        func plan(_ h: Double) -> FloorPlan { FloorPlan(rooms: Self.plan.rooms, wallHeightM: h) }
        #expect(VoxelHouse.displayWallHeightM(Self.plan) == 2.6)
        #expect(VoxelHouse.displayWallHeightM(plan(2.9)) == 2.9)
        #expect(VoxelHouse.displayWallHeightM(plan(3.0)) == 3.0)
        #expect(VoxelHouse.displayWallHeightM(plan(3.6)) == 2.8)
        let r = VoxelHouse.buildLayers(plan(4.2), realism: false)
        #expect(r.layers.filter(\.tall).map { $0.offset.y + $0.grid.ny }.max() == VoxelHouse.baseVoxels + VoxelGrid.count(2.8))
    }

    @Test func tallWallHasNoCapAtTheCutLowWallDoes() {
        let low = Self.lowLook(), tall = Self.tallLook()
        let capY = Self.cutY - 1
        // Plain stretches of every side: capped when low, tiles straight through when tall.
        for (x, y) in [(0.4, 0.0), (11.0, 0.4), (0.0, 0.4), (0.4, 10.2)] {
            let (i, k) = Self.column(x, y)
            #expect(low[i, capY, k] == VoxelHouse.Palette.wallCap, "low cap at \(x),\(y)")
            #expect(tall[i, capY, k] != nil && tall[i, capY, k] != VoxelHouse.Palette.wallCap, "tall cap row at \(x),\(y)")
        }
        // The whole tall look has no cap color at the cut on any exterior wall column.
        for l in Self.layers.layers where l.tall {
            for k in 0..<l.grid.nz { for i in 0..<l.grid.nx {
                #expect(tall[i + l.offset.x, capY, k + l.offset.z] != VoxelHouse.Palette.wallCap || l.grid[i, capY - l.offset.y, k] == nil)
            } }
        }
    }

    @Test func openingsInTallWalls() {
        let tall = Self.tallLook(), low = Self.lowLook()
        let top = VoxelHouse.baseVoxels + VoxelGrid.count(VoxelHouse.openingTopM)
        let sill = VoxelHouse.baseVoxels + Int(VoxelHouse.sillHeightM / Self.V)
        // Front door (x 2.5..3.5 on y = 0): open up to the door head, wall above it.
        let (di, dk) = Self.column(3.0, 0.0)
        for y in VoxelHouse.baseVoxels..<top { #expect(tall[di, y, dk] == nil, "door y=\(y)") }
        #expect(tall[di, top, dk] != nil)
        // Windows: one run of glass from the sill to a single frame under the head, then wall.
        for (x, y) in [(1.4, 0.0), (11.0, 1.75)] {
            let (i, k) = Self.column(x, y)
            #expect(tall[i, sill, k] == VoxelHouse.Palette.sill)
            for yy in (sill + 1)..<(top - 1) { #expect(tall[i, yy, k] == VoxelHouse.Palette.glass, "window at \(x),\(y) y=\(yy)") }
            #expect(tall[i, top - 1, k] == VoxelHouse.Palette.windowFrame)
            #expect(tall[i, top, k].map { $0 != VoxelHouse.Palette.glass && $0 != VoxelHouse.Palette.windowFrame } == true)
            // Low: framed under the cap.
            #expect(low[i, Self.cutY - 2, k] == VoxelHouse.Palette.windowFrame)
            #expect(low[i, Self.cutY - 1, k] == VoxelHouse.Palette.wallCap)
        }
    }

    @Test func curtainsHangFromTheWindowHeadOnTallWalls() {
        func rodRows(_ g: VoxelGrid) -> Set<Int> {
            var rows = Set<Int>()
            for y in 0..<g.ny { for k in 0..<g.nz { for i in 0..<g.nx where g[i, y, k] == VoxelHouse.Palette.curtainRod { rows.insert(y) } } }
            return rows
        }
        let top = VoxelHouse.baseVoxels + VoxelGrid.count(VoxelHouse.openingTopM)
        // Every demo window is on an exterior wall.
        #expect(rodRows(Self.tallLook()) == [top])
        #expect(rodRows(Self.lowLook()) == [Self.cutY - 1])
        // Curtain fabric runs up past the cut in the tall look.
        let tall = Self.tallLook()
        var fabric = 0
        for k in 0..<tall.nz { for i in 0..<tall.nx where tall[i, top - 1, k] == VoxelHouse.Palette.curtain { fabric += 1 } }
        #expect(fabric > 0)
        // And they belong to their wall's facing: shown and hidden with it.
        func hasRod(_ l: VoxelHouse.Layer) -> Bool {
            for y in 0..<l.grid.ny { for k in 0..<l.grid.nz { for i in 0..<l.grid.nx where l.grid[i, y, k] == VoxelHouse.Palette.curtainRod { return true } } }
            return false
        }
        #expect(Self.layers.layers.contains { $0.tall && $0.facings == [.minusZ] && hasRod($0) })
        #expect(Self.layers.layers.contains { !$0.tall && $0.facings == [.minusZ] && hasRod($0) })
    }

    @Test func backFacingsFollowTheCamera() {
        // Default dollhouse camera: front-right (+x, +z), yaw 40°.
        let yaw = 40 * Double.pi / 180
        let view = SIMD2(sin(yaw), cos(yaw))
        let back = Set(VoxelHouse.Facing.allCases.filter { $0.isBack(viewFromTarget: view) })
        #expect(back == [.minusX, .minusZ])
        // Half a turn later the other two are up; looking straight down an axis, only one.
        #expect(Set(VoxelHouse.Facing.allCases.filter { $0.isBack(viewFromTarget: -view) }) == [.plusX, .plusZ])
        #expect(Set(VoxelHouse.Facing.allCases.filter { $0.isBack(viewFromTarget: SIMD2(0, 1)) }) == [.minusZ])
        // Never two opposite facings at once.
        for step in 0..<72 {
            let a = Double(step) * 5 * .pi / 180
            let up = VoxelHouse.Facing.allCases.filter { $0.isBack(viewFromTarget: SIMD2(sin(a), cos(a))) }
            #expect(!(up.contains(.plusX) && up.contains(.minusX)) && !(up.contains(.plusZ) && up.contains(.minusZ)))
            #expect(!up.isEmpty)
        }
    }

    @Test func meshesAreSmall() {
        for l in Self.layers.layers {
            let n = VoxelMesher.mesh(l.grid, centered: false).triangleCount
            #expect(n > 0 && n < 10_000, "\(l.facings) tall=\(l.tall): \(n) triangles")
        }
    }
}
