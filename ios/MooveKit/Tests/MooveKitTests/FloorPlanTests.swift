import Foundation
import Testing
@testable import MooveKit

@Suite struct FloorPlanTests {
    @Test func demoHouseLoadsAndIsValid() {
        let plan = DemoHouse.floorPlan
        #expect(plan.rooms.count == 6)
        #expect(plan.rooms.filter { $0.kind == .bedroom }.count == 2)
        #expect(Set(plan.rooms.map(\.kind)).isSuperset(of: [.living, .kitchen, .bathroom]))
        #expect(plan.issues().isEmpty)
        #expect(abs(plan.bounds.width - 11) < 1e-9 && abs(plan.bounds.depth - 10.2) < 1e-9)
        #expect(DemoHouse.name.contains("Demo"))
    }

    @Test func roundTripsThroughJSON() throws {
        let plan = DemoHouse.floorPlan
        let again = try FloorPlan(json: plan.jsonString())
        #expect(again == plan)
    }

    @Test func decodesContractOnlyJSON() throws {
        // What a worker or Zillow import might send: just the contract fields.
        let json = #"{"rooms":[{"name":"Primary Bedroom","polygon":[[0,0],[3,0],[3,4],[0,4]],"widthM":3,"depthM":4}]}"#
        let plan = try FloorPlan(json: json)
        #expect(plan.rooms[0].kind == .bedroom)
        #expect(plan.doors.isEmpty && plan.windows.isEmpty)
        #expect(plan.wallHeightM == 2.6)
        #expect(plan.rooms[0].areaM2 == 12)
    }

    @Test func pointsEncodeAsPairs() throws {
        let json = try FloorPlan(rooms: [.rectangle("A", x: 0, y: 0, width: 1, depth: 2)]).jsonString()
        #expect(json.contains(#""polygon":[[0,0],[1,0],[1,2],[0,2]]"#))
        #expect(json.contains(#""widthM":1"#) && json.contains(#""depthM":2"#))
    }

    @Test func areaCentroidAndContains() {
        let r = FloorPlanRoom.rectangle("Bedroom", x: 1, y: 2, width: 4, depth: 3)
        #expect(r.areaM2 == 12)
        #expect(r.centroid == PlanPoint(3, 3.5))
        #expect(r.contains(PlanPoint(2, 3)))
        #expect(!r.contains(PlanPoint(0.5, 3)))
        #expect(!r.contains(PlanPoint(2, 5.5)))
    }

    @Test func triangulatesLShapeInEitherWinding() {
        let pts = [PlanPoint(0, 0), PlanPoint(4, 0), PlanPoint(4, 2), PlanPoint(2, 2), PlanPoint(2, 4), PlanPoint(0, 4)]
        for polygon in [pts, pts.reversed()] {
            let room = FloorPlanRoom(name: "L", polygon: polygon)
            let tris = room.triangulate()
            #expect(tris.count == (polygon.count - 2) * 3)
            var area = 0.0
            for t in stride(from: 0, to: tris.count, by: 3) {
                let a = polygon[Int(tris[t])], b = polygon[Int(tris[t + 1])], c = polygon[Int(tris[t + 2])]
                let signed = (b - a).cross(c - a) / 2
                #expect(signed > 0, "triangles should be counterclockwise in plan coordinates")
                area += signed
            }
            #expect(abs(area - 12) < 1e-9)
        }
    }

    @Test func doorsCutWallsOnBothSides() {
        let plan = FloorPlan(
            rooms: [.rectangle("A", x: 0, y: 0, width: 4, depth: 3), .rectangle("B", x: 4, y: 0, width: 3, depth: 3)],
            doors: [WallOpening(from: PlanPoint(4, 1), to: PlanPoint(4, 2))]
        )
        let walls = plan.wallSegments()
        // Each room: 4 edges, the shared one split in two.
        #expect(walls.filter { $0.room == "A" }.count == 5)
        #expect(walls.filter { $0.room == "B" }.count == 5)
        let shared = walls.filter { abs($0.from.x - 4) < 1e-9 && abs($0.to.x - 4) < 1e-9 }
        #expect(abs(shared.reduce(0) { $0 + $1.lengthM } - 4) < 1e-9) // 2 rooms × (3 m − 1 m door)
        #expect(!shared.contains { $0.center.y > 1 && $0.center.y < 2 })
    }

    @Test func demoHouseWallsLeaveDoorGaps() {
        let plan = DemoHouse.floorPlan
        let total = plan.wallSegments().reduce(0) { $0 + $1.lengthM }
        let perimeter = plan.rooms.reduce(0.0) { sum, r in sum + r.edges.reduce(0) { $0 + ($1.1 - $1.0).length } }
        // Exterior doors cut one wall, interior doors cut two.
        let cut = plan.doors.reduce(0.0) { sum, d in
            sum + d.widthM * Double(plan.rooms.filter { r in r.edges.contains { FloorPlan.span(of: d, onEdge: $0.0, $0.1) != nil } }.count)
        }
        #expect(abs(perimeter - total - cut) < 1e-6)
        #expect(plan.windows(in: plan.room(named: "Kitchen")!).count == 1)
    }

    @Test func wallYawMapsBoxXOntoWall() {
        // Box local +X rotated by yaw about +Y is (cos, 0, -sin) in world; plan y is world z.
        for (dx, dy) in [(1.0, 0.0), (0, 1), (-1, 0), (0, -1), (3, 4)] {
            let w = WallSegment(from: PlanPoint(0, 0), to: PlanPoint(dx, dy), room: "r")
            let len = (dx * dx + dy * dy).squareRoot()
            #expect(abs(cos(w.yawRadians) - dx / len) < 1e-9)
            #expect(abs(-sin(w.yawRadians) - dy / len) < 1e-9)
        }
    }

    @Test func wallsPointIntoTheirRoom() {
        for room in DemoHouse.floorPlan.rooms {
            let plan = FloorPlan(rooms: [room, FloorPlanRoom(name: "rev", polygon: room.polygon.reversed())])
            for w in plan.wallSegments() {
                let probe = w.center + w.inward * 0.05
                #expect(room.contains(probe), "\(w.room) wall at \(w.center) should face inward")
            }
        }
    }

    @Test func roomAtPoint() {
        let plan = DemoHouse.floorPlan
        #expect(plan.room(at: PlanPoint(2, 2))?.name == "Living room")
        #expect(plan.room(at: PlanPoint(9, 8))?.name == "Bedroom 2")
        #expect(plan.room(at: PlanPoint(20, 20)) == nil)
    }

    @Test func validationFindsProblems() {
        let plan = FloorPlan(rooms: [
            .rectangle("A", x: 0, y: 0, width: 4, depth: 4),
            .rectangle("B", x: 1, y: 1, width: 2, depth: 2),
            .rectangle("A", x: 10, y: 0, width: 0.1, depth: 0.1),
            FloorPlanRoom(name: "Line", polygon: [PlanPoint(0, 0), PlanPoint(1, 0)]),
        ])
        let issues = plan.issues()
        #expect(issues.contains(.overlap("A", "B")))
        #expect(issues.contains(.duplicateName("A")))
        #expect(issues.contains(.zeroArea(room: "A")))
        #expect(issues.contains(.tooFewPoints(room: "Line")))
        #expect(FloorPlan(rooms: []).issues() == [.noRooms])
    }

    @Test func roomKindGuesses() {
        #expect(RoomKind.guess(from: "Primary Bedroom") == .bedroom)
        #expect(RoomKind.guess(from: "Half bath") == .bathroom)
        #expect(RoomKind.guess(from: "Great Room") == .living)
        #expect(RoomKind.guess(from: "Garage") == .other)
    }
}

@Suite struct ManualFloorPlanTests {
    @Test func starterBuildsAValidPlanWithHallwayAndDoors() {
        let plan = ManualFloorPlan.build(ManualFloorPlan.starter)
        #expect(plan.issues().isEmpty)
        #expect(plan.rooms.count == ManualFloorPlan.starter.count + 1)
        #expect(plan.rooms.contains { $0.kind == .hallway })
        #expect(plan.doors.count == ManualFloorPlan.starter.count)
        // Every room's door opens onto the hallway.
        let hall = plan.rooms.first { $0.kind == .hallway }!
        for door in plan.doors {
            #expect(hall.edges.contains { FloorPlan.span(of: door, onEdge: $0.0, $0.1) != nil })
        }
        // Typed sizes survive.
        let living = plan.room(named: "Living room")!
        #expect(living.widthM == 5 && living.depthM == 4)
    }

    @Test func duplicateAndBlankNamesAreMadeUnique() {
        let plan = ManualFloorPlan.build([
            ManualRoom(name: "Bedroom", kind: .bedroom, widthM: 3, depthM: 3),
            ManualRoom(name: "Bedroom", kind: .bedroom, widthM: 3, depthM: 3),
            ManualRoom(name: "  ", kind: .other, widthM: 2, depthM: 2),
        ])
        #expect(Set(plan.rooms.map(\.name)).count == plan.rooms.count)
        #expect(plan.room(named: "Bedroom 2") != nil)
        #expect(plan.room(named: "Room") != nil)
        #expect(plan.issues().isEmpty)
    }

    @Test func singleRoomHasNoHallway() {
        let plan = ManualFloorPlan.build([ManualRoom(name: "Studio", kind: .living, widthM: 5, depthM: 6)])
        #expect(plan.rooms.map(\.name) == ["Studio"])
        #expect(plan.issues().isEmpty)
    }

    @Test func skipsEmptyRooms() {
        #expect(ManualFloorPlan.build([ManualRoom(name: "X", kind: .other, widthM: 0, depthM: 3)]).rooms.isEmpty)
    }
}

@Suite struct NewHomeBackendTests {
    @Test func createNewHomeAndSaveLayout() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.createNewHome(name: DemoHouse.name, source: .demo, floorPlanJson: DemoHouse.json)
        var snap = await firstSnapshot(backend)
        let home = try #require(snap.myNewHome)
        #expect(home.source == .demo)
        #expect(home.floorPlan == DemoHouse.floorPlan)

        let placements = [Placement(itemId: 10, room: "Bedroom", x: 2, y: 8, rotationDeg: 90)]
        try await backend.saveLayout(newHomeId: home.id, name: "Compact", placementsJson: Layout.encode(placements))
        snap = await firstSnapshot(backend)
        #expect(snap.layouts(for: home.id).first?.placements == placements)
    }

    @Test func newestHomeWins() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.createNewHome(name: "First", source: .demo, floorPlanJson: DemoHouse.json)
        let manual = try ManualFloorPlan.build(ManualFloorPlan.starter).jsonString()
        try await backend.createNewHome(name: "Second", source: .manual, floorPlanJson: manual)
        let snap = await firstSnapshot(backend)
        #expect(snap.myNewHome?.name == "Second")
        #expect(snap.myNewHome?.floorPlan?.rooms.count == 5)
    }

    @Test func cannotSaveLayoutOnSomeoneElsesHome() async throws {
        var seed = SyncSnapshot()
        seed.newHomes = [NewHome(id: 1, owner: "alice", name: "Alice's", source: .demo, floorPlanJson: DemoHouse.json)]
        let backend = FixtureBackend(identity: "mallory", seed: seed)
        _ = try await backend.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await backend.saveLayout(newHomeId: 1, name: "x", placementsJson: "[]")
        }
        #expect(await firstSnapshot(backend).myNewHome == nil)
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }
}
