import Foundation
import Testing
@testable import MooveKit

@Suite struct LayoutSolverTests {
    let plan = DemoHouse.floorPlan
    var kept: [LayoutItem] {
        DemoFixtures.inventory(owner: "me").items.map(LayoutItem.init)
    }

    @Test func everyStyleIsValid() {
        let solver = LayoutSolver(plan: plan)
        for option in solver.solveAll(kept) {
            #expect(option.unplaced.isEmpty, "\(option.name) left \(option.unplaced) unplaced")
            let rects = rects(option)
            for (i, a) in rects.enumerated() {
                let room = plan.room(named: option.placements[i].room)!
                #expect(a.corners.allSatisfy { room.contains($0) || onEdge($0, room) }, "\(option.name): item \(option.placements[i].itemId) pokes out of \(room.name)")
                for b in rects[(i + 1)...] { #expect(!a.overlaps(b), "\(option.name): overlap") }
                for door in solver.doorKeepOuts() { #expect(!a.overlaps(door), "\(option.name): blocks a door") }
            }
        }
    }

    @Test func layoutsAreDistinct() {
        let options = LayoutSolver(plan: plan).solveAll(kept)
        #expect(options.count >= 2)
        let signatures = Set(options.map { $0.placements.map { "\($0.itemId)@\($0.room):\(Int($0.x * 10)),\(Int($0.y * 10))" } })
        #expect(signatures.count == options.count)
    }

    @Test func byFunctionPutsThingsInTheRightRooms() {
        let option = LayoutSolver(plan: plan).solve(kept, style: .byFunction)
        let room = Dictionary(uniqueKeysWithValues: option.placements.map { ($0.itemId, $0.room) })
        #expect(room[10] == "Bedroom") // bed goes in the primary (bigger) bedroom
        #expect(room[21] == "Kitchen") // mini fridge
        #expect(plan.room(named: room[11]!)?.kind != .bathroom)
    }

    @Test func compactUsesFewerRooms() {
        let solver = LayoutSolver(plan: plan)
        let compact = Set(solver.solve(kept, style: .compact).placements.map(\.room))
        let open = Set(solver.solve(kept, style: .open).placements.map(\.room))
        #expect(compact.count < open.count)
    }

    @Test func neverUsesTheHallway() {
        for option in LayoutSolver(plan: plan).solveAll(kept) {
            #expect(!option.placements.contains { $0.room == "Hallway" })
        }
    }

    @Test func itemsBackOntoWallsAndFaceIn() {
        let option = LayoutSolver(plan: plan).solve(kept, style: .byFunction)
        let bed = option.placements.first { $0.itemId == 10 }!
        let room = plan.room(named: bed.room)!
        let r = rect(bed)
        // The bed's back (−z side) is against a wall: a point just behind it is outside the room.
        let behind = r.center - r.axes.z * (r.halfDepth + 0.1)
        #expect(!room.contains(behind))
        // And its front faces in.
        #expect(room.contains(r.center + r.axes.z * (r.halfDepth + 0.1)))
    }

    @Test func tooBigItemIsReportedNotForced() {
        let huge = LayoutItem(id: 99, name: "Grand piano", category: "other", widthM: 30, depthM: 30, heightM: 1)
        let option = LayoutSolver(plan: plan).solve(kept + [huge], style: .byFunction)
        #expect(option.unplaced == [99])
        #expect(option.placements.count == kept.count)
    }

    @Test func deterministic() {
        let solver = LayoutSolver(plan: plan)
        #expect(solver.solveAll(kept) == solver.solveAll(kept.reversed()))
    }

    @Test func worksOnManualPlans() {
        let manual = ManualFloorPlan.build(ManualFloorPlan.starter)
        for option in LayoutSolver(plan: manual).solveAll(kept) {
            #expect(option.unplaced.isEmpty, "\(option.name) left \(option.unplaced)")
        }
    }

    @Test func rotationMatchesWorldConvention() {
        // Facing plan +y (world +z) is 0°, facing +x is 90°.
        #expect(LayoutSolver.rotationDeg(facing: PlanPoint(0, 1)) == 0)
        #expect(LayoutSolver.rotationDeg(facing: PlanPoint(1, 0)) == 90)
        #expect(LayoutSolver.rotationDeg(facing: PlanPoint(0, -1)) == 180)
        #expect(LayoutSolver.rotationDeg(facing: PlanPoint(-1, 0)) == 270)
    }

    @Test func orientedRectOverlap() {
        let a = OrientedRect(center: PlanPoint(0, 0), halfWidth: 1, halfDepth: 1, rotationDeg: 0)
        #expect(a.overlaps(OrientedRect(center: PlanPoint(1.5, 0), halfWidth: 1, halfDepth: 1, rotationDeg: 0)))
        #expect(!a.overlaps(OrientedRect(center: PlanPoint(2, 0), halfWidth: 1, halfDepth: 1, rotationDeg: 0))) // touching
        #expect(!a.overlaps(OrientedRect(center: PlanPoint(2.5, 0), halfWidth: 1, halfDepth: 1, rotationDeg: 45)))
        #expect(a.overlaps(OrientedRect(center: PlanPoint(2.3, 0), halfWidth: 1, halfDepth: 1, rotationDeg: 45)))
    }

    // MARK: Helpers

    private func rect(_ p: Placement) -> OrientedRect {
        let item = kept.first { $0.id == p.itemId }!
        return OrientedRect(center: PlanPoint(p.x, p.y), halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: p.rotationDeg)
    }

    private func rects(_ o: LayoutOption) -> [OrientedRect] { o.placements.map(rect) }

    private func onEdge(_ p: PlanPoint, _ room: FloorPlanRoom) -> Bool {
        room.edges.contains { a, b in
            let len = (b - a).length, d = (b - a) * (1 / len), v = p - a, t = v.dot(d)
            return abs(d.cross(v)) < 1e-6 && t >= -1e-6 && t <= len + 1e-6
        }
    }
}
