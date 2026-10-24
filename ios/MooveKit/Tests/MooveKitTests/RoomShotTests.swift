import Foundation
import Testing
@testable import MooveKit

@Suite struct RoomShotTests {
    @Test func isolatingKeepsOnlyTheRoomAndItsOpenings() throws {
        let plan = DemoHouse.floorPlan
        for room in plan.rooms {
            let one = try #require(plan.isolating(room.name))
            #expect(one.rooms == [room])
            #expect(one.wallHeightM == plan.wallHeightM)
            for o in one.doors + one.windows {
                #expect(room.edges.contains { a, b in FloorPlan.span(of: o, onEdge: a, b) != nil })
            }
        }
        #expect(plan.isolating("Nope") == nil)
    }

    @Test func backWallsAreTheSolidOnes() {
        // 4 m along x, 3 m along z. A wide door in the +z wall (the long one) makes -z the solid long wall.
        let room = FloorPlanRoom.rectangle("Bedroom", x: 0, y: 0, width: 4, depth: 3)
        let plan = FloorPlan(rooms: [room], doors: [WallOpening(from: PlanPoint(1, 3), to: PlanPoint(3, 3))])
        let backs = RoomShot.backFacings(for: room, in: plan)
        #expect(backs.contains(.minusZ))
        #expect(backs.count == 2)
        // Both chosen facings stand tall from the shot's camera; the other two stay low.
        let v = RoomShot.viewDirection(for: room, in: plan)
        for f in VoxelHouse.Facing.allCases {
            #expect(f.isBack(viewFromTarget: v) == backs.contains(f))
        }
        #expect(abs((v.x * v.x + v.y * v.y).squareRoot() - 1) < 1e-9)
    }

    @Test func everyDemoRoomGetsATwoWallThreeQuarterView() {
        let plan = DemoHouse.floorPlan
        for room in plan.rooms {
            let v = RoomShot.viewDirection(for: room, in: plan)
            let tall = VoxelHouse.Facing.allCases.filter { $0.isBack(viewFromTarget: v) }
            #expect(tall.count == 2, "\(room.name)")
            // Within 30-60° of each axis.
            #expect(abs(v.x) >= 0.5 - 1e-9 && abs(v.y) >= 0.5 - 1e-9, "\(room.name)")
            let yaw = RoomShot.yaw(for: room, in: plan)
            #expect(abs(sin(yaw) - v.x) < 1e-9 && abs(cos(yaw) - v.y) < 1e-9)
        }
    }

    @Test func exteriorWallsWinTies() {
        // Two equal rooms side by side: the left room's shared wall is its +x wall,
        // so its tall x wall should be the outside -x one.
        let left = FloorPlanRoom.rectangle("Left", x: 0, y: 0, width: 3, depth: 3)
        let right = FloorPlanRoom.rectangle("Right", x: 3, y: 0, width: 3, depth: 3)
        let plan = FloorPlan(rooms: [left, right])
        #expect(RoomShot.backFacings(for: left, in: plan).contains(.minusX))
        #expect(RoomShot.backFacings(for: right, in: plan).contains(.plusX))
    }

    @Test func placementsFilterByRoom() {
        let ps = [Placement(itemId: 1, room: "A", x: 0, y: 0), Placement(itemId: 2, room: "B", x: 0, y: 0)]
        #expect(RoomShot.placements(ps, in: "B").map(\.itemId) == [2])
    }
}
