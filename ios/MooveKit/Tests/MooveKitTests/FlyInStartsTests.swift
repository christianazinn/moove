import Foundation
import Testing
@testable import MooveKit

@Suite struct FlyInStartsTests {
    /// A 4 × 3.5 m old room with its corner at (0, 0), as `RoomGeometry.dollhouse` makes it.
    static let oldPlan = FloorPlan(
        rooms: [.rectangle("Bedroom", x: 0, y: 0, width: 4, depth: 3.5)],
        doors: [WallOpening(from: PlanPoint(1, 3.5), to: PlanPoint(1.85, 3.5))]
    )
    static let house = PlanBounds([PlanPoint(0, 0), PlanPoint(12, 8)])

    @Test func startsAtTheScannedSpotBesideTheHouse() {
        let placements = [
            Placement(itemId: 10, room: "Bedroom", x: 1.1, y: 1.05, rotationDeg: 90),
            Placement(itemId: 19, room: "Bedroom", x: 2.2, y: 0.15, rotationDeg: 180, elevationM: 0.55),
        ]
        let starts = FlyInStarts.compute(oldPlan: Self.oldPlan, oldPlacements: placements, beside: Self.house)
        #expect(starts.count == 2)
        // Right edge 1 m left of the house (x = -1), centered on the house's depth (y 2.25 ... 5.75).
        let dx = -FlyInStarts.gapM - 4, dy = 4 - 3.5 / 2
        let bed = starts[10]!
        #expect(abs(bed.x - (1.1 + dx)) < 1e-9 && abs(bed.y - (1.05 + dy)) < 1e-9)
        #expect(bed.rotationDeg == 90 && bed.room == "Bedroom" && bed.elevationM == nil)
        let photos = starts[19]!
        #expect(photos.rotationDeg == 180 && photos.elevationM == 0.55)
        #expect(abs(photos.x - (2.2 + dx)) < 1e-9)
        // Every start is left of the house, off its footprint.
        #expect(starts.values.allSatisfy { $0.x < Self.house.minX })
    }

    @Test func movesTheRoomFootprintWithTheStarts() {
        let result = FlyInStarts.layout(
            oldRooms: [.init(plan: Self.oldPlan, placements: [Placement(itemId: 1, room: "Bedroom", x: 2, y: 2)])],
            beside: Self.house)
        let b = result.bounds!
        #expect(abs(b.maxX - (Self.house.minX - FlyInStarts.gapM)) < 1e-9)
        #expect(abs(b.width - 4) < 1e-9 && abs(b.depth - 3.5) < 1e-9)
        #expect(abs(b.center.y - Self.house.center.y) < 1e-9)
        // Doors move too, and the start is inside the moved room.
        let door = result.rooms[0].doors[0]
        #expect(abs(door.from.y - b.maxY) < 1e-9)
        let start = result.placements[1]!
        #expect(result.rooms[0].room(at: PlanPoint(start.x, start.y)) != nil)
    }

    @Test func stacksSeveralRoomsWithoutOverlap() {
        let office = FloorPlan(rooms: [.rectangle("Office", x: 5, y: -2, width: 3, depth: 3)])
        let result = FlyInStarts.layout(oldRooms: [
            .init(plan: Self.oldPlan, placements: [Placement(itemId: 1, room: "Bedroom", x: 2, y: 2)]),
            .init(plan: office, placements: [Placement(itemId: 2, room: "Office", x: 6, y: -1),
                                             Placement(itemId: 1, room: "Office", x: 7, y: 0)]),
        ], beside: Self.house)
        #expect(result.rooms.count == 2)
        let a = result.rooms[0].bounds, c = result.rooms[1].bounds
        #expect(c.minY >= a.maxY + FlyInStarts.stackGapM - 1e-9)
        #expect(abs(a.maxX - c.maxX) < 1e-9 && a.maxX < Self.house.minX)
        // Item 1 keeps its first (bedroom) start.
        #expect(result.rooms[0].room(at: PlanPoint(result.placements[1]!.x, result.placements[1]!.y)) != nil)
        // The office keeps its shape: item 2 sits 1 m in from its moved corner.
        #expect(abs(result.placements[2]!.x - (c.minX + 1)) < 1e-9 && abs(result.placements[2]!.y - (c.minY + 1)) < 1e-9)
        // Centered as a stack on the house's depth.
        #expect(abs((a.minY + c.maxY) / 2 - Self.house.center.y) < 1e-9)
    }

    @Test func nothingToStartFrom() {
        #expect(FlyInStarts.compute(oldPlan: Self.oldPlan, oldPlacements: [], beside: Self.house).isEmpty)
        let empty = FlyInStarts.layout(oldRooms: [.init(plan: FloorPlan(rooms: []), placements: [Placement(itemId: 1, room: "", x: 0, y: 0)])],
                                       beside: Self.house)
        #expect(empty.placements.isEmpty && empty.rooms.isEmpty && empty.bounds == nil)
    }
}
