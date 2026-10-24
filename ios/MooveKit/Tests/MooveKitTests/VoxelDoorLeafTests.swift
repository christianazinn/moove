import Testing
@testable import MooveKit

/// Doors stand open in the dollhouse (Rio: "add doors where they exist"): a leaf swung 90° into a
/// room from the hinge jamb, the gap itself still clear, and no leaf on a wide open passage.
@Suite struct VoxelDoorLeafTests {
    static let doorColors: Set<VoxelColor> = [VoxelHouse.Palette.door, VoxelHouse.Palette.doorPanel, VoxelHouse.Palette.doorKnob]

    func leafColumns(_ g: VoxelGrid) -> Int {
        let y = VoxelHouse.baseVoxels + 4
        var n = 0
        for k in 0..<g.nz { for i in 0..<g.nx where g[i, y, k].map({ Self.doorColors.contains($0) }) == true { n += 1 } }
        return n
    }

    func room(doorWidth w: Double) -> FloorPlan {
        let square = [PlanPoint(0, 0), PlanPoint(4, 0), PlanPoint(4, 3), PlanPoint(0, 3)]
        return FloorPlan(rooms: [FloorPlanRoom(name: "Bedroom", polygon: square)],
                         doors: [WallOpening(from: PlanPoint(1, 0), to: PlanPoint(1 + w, 0))], windows: [], wallHeightM: 2.5)
    }

    @Test func aDoorGetsAnOpenLeafInsideTheRoom() {
        let g = VoxelHouse.build(room(doorWidth: 0.85))
        let cols = leafColumns(g)
        // about the door's width minus the casing, one voxel thick
        #expect(cols >= Int(0.6 / VoxelGrid.voxelSize) && cols <= Int(0.9 / VoxelGrid.voxelSize), "\(cols) leaf columns")
        // every leaf voxel is inside the room (z > 0 in plan terms), none outside the wall
        let y = VoxelHouse.baseVoxels + 4
        let o = VoxelHouse.origin(of: room(doorWidth: 0.85))
        for k in 0..<g.nz { for i in 0..<g.nx where g[i, y, k].map({ Self.doorColors.contains($0) }) == true {
            #expect(o.z + (Double(k) + 0.5) * VoxelGrid.voxelSize > 0.05)
        } }
    }

    @Test func aWidePassageHasNoLeaf() {
        #expect(leafColumns(VoxelHouse.build(room(doorWidth: 2.0))) == 0)
    }

    @Test func theDemoHouseDoorsAllHaveLeaves() {
        // 7 doors, one of them the 2 m living-room passage
        #expect(leafColumns(VoxelHouse.build(DemoHouse.floorPlan)) > 6 * Int(0.6 / VoxelGrid.voxelSize))
    }
}
