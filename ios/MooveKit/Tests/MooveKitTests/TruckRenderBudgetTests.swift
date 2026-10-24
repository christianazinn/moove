import Foundation
import Testing
@testable import MooveKit

/// Render budget for the Pack screen's truck view (RenderBudgetTests style): the truck shell
/// plus every loaded piece as `TruckView` draws it (furniture voxel models, voxel moving boxes),
/// for the demo plan in its own truck and the biggest truck's shell.
@Suite struct TruckRenderBudgetTests {
    // Today (Oct 24, Linux debug): demo load (15 ft truck) ~ see report(); shells 0.6-1.1k.

    /// The biggest shell (26 ft truck).
    static let shellTriangleCap = 4_000
    /// Shell + the demo load.
    static let loadTriangleBudget = 60_000
    static let buildTimeBudget = Duration.seconds(5)

    static func loadTriangles(_ items: [Item]) -> (shell: Int, items: Int, pieces: Int, truck: TruckSize) {
        let plan = PackingPlanner.plan(items: items)
        let load = TruckLoader.load(plan: plan, items: items)
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shell = VoxelMesher.mesh(VoxelTruck.build(load.truck), centered: false).triangleCount
        var n = 0
        for p in load.placements {
            switch p.item.kind {
            case let .box(size):
                n += VoxelMesher.mesh(VoxelMovingBox.build(size, room: p.item.room, fragile: p.item.fragile)).triangleCount
            case .furniture:
                guard let id = p.item.itemId, let item = byId[id] else { continue }
                n += VoxelMesher.mesh(VoxelModels.build(VoxelItemSpec(item))).triangleCount
            }
        }
        return (shell, n, load.placements.count, load.truck)
    }

    @Test func shellsUnderCap() {
        for size in TruckSize.allCases {
            let n = VoxelMesher.mesh(VoxelTruck.build(size), centered: false).triangleCount
            #expect(n > 0 && n <= Self.shellTriangleCap, "\(size): \(n) triangles")
        }
    }

    @Test func demoLoadUnderBudget() {
        let clock = ContinuousClock()
        var result = (shell: 0, items: 0, pieces: 0, truck: TruckSize.cargoVan)
        let t = clock.measure { result = Self.loadTriangles(DemoFixtures.inventory(owner: "budget").items) }
        #expect(result.pieces > 0)
        #expect(result.shell + result.items <= Self.loadTriangleBudget,
                "truck \(result.truck): shell \(result.shell) + \(result.pieces) pieces \(result.items) triangles")
        #expect(t <= Self.buildTimeBudget, "built in \(t)")
        print("truck budget: \(result.truck) shell \(result.shell) + \(result.pieces) pieces \(result.items) = \(result.shell + result.items) triangles in \(t)")
    }
}
