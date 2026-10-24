import Foundation
import Testing
@testable import MooveKit

@Suite struct VoxelHouseTests {
    static let plan = DemoHouse.floorPlan
    static let grid = VoxelHouse.build(plan)
    static let V = VoxelGrid.voxelSize

    /// Grid column (i, k) containing plan point (x, y).
    static func column(_ x: Double, _ y: Double) -> (Int, Int) {
        let o = VoxelHouse.origin(of: plan)
        return (Int(((x - o.x) / V + 1e-6).rounded(.down)), Int(((y - o.z) / V + 1e-6).rounded(.down)))
    }

    static var wallYs: Range<Int> { VoxelHouse.baseVoxels..<grid.ny }

    @Test func demoHouseSize() {
        let g = Self.grid
        // 11 x 10.2 m plus a 15 cm margin each side, 1.1 m walls on a 2-voxel base.
        #expect(g.nx == 226 && g.nz == 208 + 2)
        #expect(g.ny == 22 + VoxelHouse.baseVoxels)
        #expect(abs(VoxelHouse.floorTopM - 0.1) < 1e-9)
        let o = VoxelHouse.origin(of: Self.plan)
        #expect(abs(o.x + 0.15) < 1e-9 && o.y == 0 && abs(o.z + 0.15) < 1e-9)
    }

    @Test func baseUnderWholeFootprint() {
        let g = Self.grid
        for k in 0..<g.nz {
            for i in 0..<g.nx { #expect(g[i, 0, k] != nil) }
        }
        // Every room column has a floor voxel on layer 1, and nothing above it inside the room.
        for room in Self.plan.rooms {
            let c = room.centroid
            let (i, k) = Self.column(c.x, c.y)
            #expect(g[i, 1, k] != nil)
            #expect(g[i, VoxelHouse.baseVoxels, k] == nil)
        }
        // The margin is a one-layer ledge: plinth only.
        #expect(g[0, 0, 0] != nil && g[0, 1, 0] == nil)
    }

    @Test func wallsOnRoomEdges() {
        let g = Self.grid
        // Exterior north wall (y = 0) away from openings, the shared living/kitchen wall (x = 6), and its two voxels.
        for (x, y) in [(0.4, 0.0), (6.0, 0.6), (6.0, 4.2), (11.0, 3.5), (2.0, 5.0), (4.5, 8.0)] {
            let (i, k) = Self.column(x, y)
            for yy in Self.wallYs { #expect(g[i, yy, k] != nil, "wall at \(x),\(y) y=\(yy)") }
        }
        let (i, k) = Self.column(6.0, 0.6)
        #expect(g[i - 1, VoxelHouse.baseVoxels + 5, k] != nil) // 2 thick, centered on the edge
        #expect(g[i - 2, VoxelHouse.baseVoxels + 5, k] == nil)
        #expect(g[i + 1, VoxelHouse.baseVoxels + 5, k] == nil)
        // Baseboard differs from the tiles above it.
        #expect(g[i, VoxelHouse.baseVoxels, k] == VoxelHouse.Palette.baseboard)
        #expect(g[i, VoxelHouse.baseVoxels + 8, k] != VoxelHouse.Palette.baseboard)
    }

    @Test func doorSpansHaveNoWall() {
        let g = Self.grid
        for door in Self.plan.doors {
            let d = door.to - door.from
            for f in stride(from: 0.1, through: 0.9, by: 0.1) {
                let p = door.from + d * f
                let (i, k) = Self.column(p.x, p.y)
                // Both voxels of the wall thickness, full height.
                let horizontal = abs(d.x) > abs(d.y)
                for n in [-1, 0] {
                    let (ii, kk) = horizontal ? (i, k + n) : (i + n, k)
                    for yy in Self.wallYs { #expect(g[ii, yy, kk] == nil, "door at \(p.x),\(p.y)") }
                    #expect(g[ii, 1, kk] == VoxelHouse.Palette.threshold)
                }
            }
        }
    }

    @Test func windowSpansHaveGlassAndSill() {
        let g = Self.grid
        for window in Self.plan.windows {
            let mid = (window.from + window.to) * 0.5
            let (i, k) = Self.column(mid.x, mid.y)
            let column = (0..<g.ny).compactMap { g[i, $0, k] }
            #expect(column.contains(VoxelHouse.Palette.glass), "glass at \(mid.x),\(mid.y)")
            #expect(column.contains(VoxelHouse.Palette.sill))
            #expect(g[i, VoxelHouse.baseVoxels, k] == VoxelHouse.Palette.baseboard) // wall below the sill
        }
        // No glass anywhere off a window: count glass columns roughly matches window lengths.
        var glassColumns = 0
        for k in 0..<g.nz {
            for i in 0..<g.nx where (0..<g.ny).contains(where: { g[i, $0, k] == VoxelHouse.Palette.glass }) { glassColumns += 1 }
        }
        let expected = Self.plan.windows.reduce(0.0) { $0 + $1.widthM } / Self.V * 2 // two voxels thick
        #expect(Double(glassColumns) > expected * 0.8 && Double(glassColumns) <= expected)
    }

    @Test func floorsArePlanksOrTile() {
        let g = Self.grid
        let oak = Set(VoxelHouse.Palette.oak + [VoxelHouse.Palette.plankSeam])
        let tile = Set(VoxelHouse.Palette.floorTile + [VoxelHouse.Palette.floorGrout])
        for room in Self.plan.rooms {
            let c = room.centroid
            let (i, k) = Self.column(c.x, c.y)
            var colors = Set<VoxelColor>()
            for dk in -6...6 { for di in -12...12 { if let v = g[i + di, 1, k + dk] { colors.insert(v) } } }
            let wet = room.kind == .bathroom || room.kind == .kitchen
            #expect(colors.isSubset(of: wet ? tile : oak), "\(room.name)")
            #expect(colors.count >= 2, "\(room.name) has variation")
        }
    }

    @Test func deterministic() {
        #expect(VoxelHouse.build(Self.plan) == Self.grid)
        let low = VoxelHouse.build(Self.plan, cutawayHeightM: 0.5)
        #expect(low.ny == 10 + VoxelHouse.baseVoxels)
    }

    @Test func simpleRoomAndEmptyPlan() {
        let plan = FloorPlan(rooms: [.rectangle("Room", x: 1, y: 2, width: 3, depth: 2)])
        let g = VoxelHouse.build(plan)
        #expect(g.nx == 66 && g.nz == 46)
        _ = VoxelHouse.build(FloorPlan(rooms: []))
    }
}
