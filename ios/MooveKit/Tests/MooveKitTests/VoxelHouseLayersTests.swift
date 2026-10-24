import Foundation
import Testing
@testable import MooveKit

/// The dollhouse split (`VoxelHouse.buildLayers`): base up to the cut, plus full-height
/// exterior walls per facing that the app shows only on the side away from the camera.
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

    @Test func baseIsTheCutawayBuild() {
        #expect(Self.layers.base == VoxelHouse.build(Self.plan))
        let colored = VoxelHouse.buildLayers(Self.plan, wallColor: 0x6688AA, floorColor: 0x554433)
        #expect(colored.base == VoxelHouse.build(Self.plan, wallColor: 0x6688AA, floorColor: 0x554433))
    }

    @Test func layersUnionIsTheFullHeightShell() {
        let tall = VoxelHouse.shell(Self.plan, cutawayHeightM: 1.1, fullHeightM: Self.plan.wallHeightM, realism: true,
                                    wallColor: nil, floorColor: nil).grid
        let base = Self.layers.base
        #expect(tall.ny == VoxelHouse.baseVoxels + VoxelGrid.count(2.6))
        for y in 0..<tall.ny {
            for k in 0..<tall.nz {
                for i in 0..<tall.nx {
                    let want = tall[i, y, k]
                    if y < Self.cutY {
                        if base[i, y, k] != want { Issue.record("base differs at \(i),\(y),\(k)"); return }
                        continue
                    }
                    let got = Self.layers.upper.values.compactMap { Self.at($0, i, y, k) }
                    if want == nil ? !got.isEmpty : (got.isEmpty || got.contains { $0 != want }) {
                        Issue.record("upper differs at \(i),\(y),\(k): want \(String(describing: want)) got \(got)"); return
                    }
                }
            }
        }
    }

    @Test func eachFacingHoldsOnlyItsOwnExteriorWall() {
        // The demo house is an 11 x 10.2 m rectangle, so each facing is one side of it.
        let b = Self.plan.bounds
        #expect(Set(Self.layers.upper.keys) == Set(VoxelHouse.Facing.allCases))
        for (f, l) in Self.layers.upper {
            var filled = 0
            for k in 0..<l.grid.nz {
                for i in 0..<l.grid.nx where (0..<l.grid.ny).contains(where: { l.grid[i, $0, k] != nil }) {
                    filled += 1
                    let p = Self.center(i + l.offset.x, k + l.offset.z)
                    let off: Double = switch f {
                    case .plusX: abs(p.x - b.maxX)
                    case .minusX: abs(p.x - b.minX)
                    case .plusZ: abs(p.y - b.maxY)
                    case .minusZ: abs(p.y - b.minY)
                    }
                    #expect(off < Self.V, "\(f) voxel at \(p.x),\(p.y)")
                }
            }
            let side = f == .plusX || f == .minusX ? b.depth : b.width
            #expect(Double(filled) > side / Self.V, "\(f): \(filled) columns")
        }
    }

    @Test func interiorWallsStayLow() {
        // L-shaped plan: the shared wall (y = 2, x 0..2) is interior; the notch walls are exterior.
        let plan = FloorPlan(rooms: [.rectangle("A", x: 0, y: 0, width: 4, depth: 2), .rectangle("B", x: 0, y: 2, width: 2, depth: 2)])
        let l = VoxelHouse.buildLayers(plan, fullHeightM: 2.4)
        func facings(_ x: Double, _ y: Double) -> Set<VoxelHouse.Facing> {
            let (i, k) = Self.column(x, y, plan: plan)
            return Set(l.upper.compactMap { f, layer in
                (0..<layer.grid.ny).contains { Self.at(layer, i, layer.offset.y + $0, k) != nil } ? f : nil
            })
        }
        #expect(facings(1, 2).isEmpty && facings(1, 1.98).isEmpty && facings(1, 2.02).isEmpty)
        #expect(facings(3, 2.02) == [.plusZ])
        #expect(facings(2.02, 3) == [.plusX])
        #expect(facings(4.02, 1) == [.plusX])
        #expect(facings(1, -0.02) == [.minusZ])
        #expect(facings(-0.02, 3) == [.minusX])
        #expect(facings(1, 4.02) == [.plusZ])
        // Interior partitions in the demo house (living/kitchen at x = 6) have nothing above the cut.
        let (i, k) = Self.column(6.0, 0.6)
        #expect(Self.layers.upper.values.allSatisfy { l in (0..<l.grid.ny).allSatisfy { Self.at(l, i, l.offset.y + $0, k) == nil } })
    }

    @Test func heights() {
        for l in Self.layers.upper.values {
            #expect(l.offset.y == Self.cutY)
            #expect(l.offset.y + l.grid.ny == VoxelHouse.baseVoxels + VoxelGrid.count(Self.plan.wallHeightM))
        }
        let short = VoxelHouse.buildLayers(Self.plan, fullHeightM: 2.4)
        #expect(short.upper.values.allSatisfy { $0.offset.y + $0.grid.ny == VoxelHouse.baseVoxels + 48 })
        // Wall top: cap color at full height on a plain stretch of the north (-z) wall.
        let north = short.upper[.minusZ]!
        let (i, k) = Self.column(0.4, 0.0)
        #expect(Self.at(north, i, north.offset.y + north.grid.ny - 1, k) == VoxelHouse.Palette.wallCap)
        #expect((0..<north.grid.ny).allSatisfy { Self.at(north, i, north.offset.y + $0, k) != nil })
        // No upper walls when the full height is the cut.
        #expect(VoxelHouse.buildLayers(Self.plan, fullHeightM: 1.1).upper.isEmpty)
    }

    @Test func openingsInUpperWalls() {
        let north = Self.layers.upper[.minusZ]!, east = Self.layers.upper[.plusX]!
        let top = VoxelHouse.baseVoxels + VoxelGrid.count(VoxelHouse.openingTopM)
        // Front door (x 2.5..3.5 on y = 0): open up to the door head, wall above it.
        let (di, dk) = Self.column(3.0, 0.0)
        for y in Self.cutY..<top { #expect(Self.at(north, di, y, dk) == nil, "door y=\(y)") }
        #expect(Self.at(north, di, top, dk) != nil)
        // Windows: glass from the cut up to a frame under the head, then wall.
        for (layer, x, y) in [(north, 1.4, 0.0), (east, 11.0, 1.75)] {
            let (i, k) = Self.column(x, y)
            #expect(Self.at(layer, i, Self.cutY, k) == VoxelHouse.Palette.glass, "window at \(x),\(y)")
            #expect(Self.at(layer, i, top - 2, k) == VoxelHouse.Palette.glass)
            #expect(Self.at(layer, i, top - 1, k) == VoxelHouse.Palette.windowFrame)
            #expect(Self.at(layer, i, top, k).map { $0 != VoxelHouse.Palette.glass && $0 != VoxelHouse.Palette.windowFrame } == true)
        }
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
        for (f, l) in Self.layers.upper {
            let n = VoxelMesher.mesh(l.grid, centered: false).triangleCount
            #expect(n > 0 && n < 10_000, "\(f): \(n) triangles")
        }
    }
}
