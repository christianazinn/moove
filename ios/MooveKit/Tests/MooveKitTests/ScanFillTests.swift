import Foundation
import Testing
@testable import MooveKit

/// Lisa's "Bathroom" scan (2026-10-25, a hotel room): RoomPlan boxed the desk and the gray cube
/// ottoman under it as one "table", and vision added the ottoman and a wall TV with no scanned spot.
@Suite struct ScanFillTests {
    // A 4 x 3.5 m room named Bathroom (it has a toilet and tub); the desk against the y = 0 wall.
    let plan = FloorPlan(rooms: [FloorPlanRoom(name: "Bathroom", polygon: [PlanPoint(0, 0), PlanPoint(4, 0), PlanPoint(4, 3.5), PlanPoint(0, 3.5)])])
    let desk = LayoutItem(id: 1, name: "light wood laminate desk with gray panel legs", category: "table", widthM: 0.93, depthM: 0.71, heightM: 0.84)
    let ottoman = LayoutItem(id: 2, name: "gray cube ottoman", category: "ottoman", widthM: 0.45, depthM: 0.45, heightM: 0.42)
    let tv = LayoutItem(id: 3, name: "black wall-mounted flat screen TV", category: "tv", widthM: 0.77, depthM: 0.06, heightM: 0.45)
    let toilet = LayoutItem(id: 4, name: "Toilet", category: "toilet", widthM: 0.41, depthM: 0.66, heightM: 0.78)
    // The desk's scanned spot: against the wall, facing into the room.
    var scanned: [Placement] { [Placement(itemId: 1, room: "Bathroom", x: 2.8, y: 0.4, rotationDeg: 0),
                                Placement(itemId: 4, room: "Bathroom", x: 0.4, y: 3.0, rotationDeg: 180)] }
    var items: [LayoutItem] { [desk, ottoman, tv, toilet] }

    @Test func theOttomanTucksUnderTheDesk() {
        let spots = ScanFill.anchored([ottoman, tv], around: scanned, items: items, room: "Bathroom")
        let o = spots.first { $0.itemId == 2 }
        #expect(o?.x == 2.8 && o?.y == 0.4, "under the desk, not on it or by another wall")
        #expect(o?.onTopOf == nil && o?.elevationM == nil)
        // And PropPlacer leaves it on the floor there.
        let after = PropPlacer(plan: plan).place(scanned + spots, items: items, scanned: [1, 4])
        let placed = after.first { $0.itemId == 2 }!
        #expect(placed.onTopOf == nil && (placed.elevationM ?? 0) == 0 && placed.x == 2.8 && placed.y == 0.4)
    }

    @Test func theWallTVHangsAboveTheDesk() {
        let spots = ScanFill.anchored([ottoman, tv], around: scanned, items: items, room: "Bathroom")
        let after = PropPlacer(plan: plan).place(scanned + spots, items: items, scanned: [1, 4])
        let t = after.first { $0.itemId == 3 }!
        #expect(t.wallMounted == true)
        #expect(abs(t.y) < 0.2, "on the wall the desk is against (y = 0), got y \(t.y)")
        #expect(abs(t.x - 2.8) < 0.5, "over the desk, got x \(t.x)")
        #expect((t.elevationM ?? 0) > 0.84, "above the desk top")
    }

    @Test func theScannedTVStaysOnTheWallAboveTheDesk() {
        // The scan saw it 1.06 m up, over the desk: it used to be dropped for not fitting under the 1.1 m cut.
        let scannedTV = Placement(itemId: 3, room: "Bathroom", x: 2.9, y: 0.1, rotationDeg: 0, elevationM: 1.06)
        let after = PropPlacer(plan: plan).place(scanned + [scannedTV], items: items, scanned: [1, 3, 4])
        let t = after.first { $0.itemId == 3 }!
        #expect(t.wallMounted == true)
        #expect(abs((t.elevationM ?? 0) - 1.06) < 0.01, "at its scanned height, got \(t.elevationM ?? -1)")
        #expect(abs(t.x - 2.9) < 0.05 && abs(t.y) < 0.2)
    }

    @Test func onlyWhatFitsUnderneath() {
        let tall = LayoutItem(id: 5, name: "tall ottoman", category: "ottoman", widthM: 0.45, depthM: 0.45, heightM: 0.8)
        let wide = LayoutItem(id: 6, name: "storage ottoman", category: "ottoman", widthM: 1.2, depthM: 0.45, heightM: 0.42)
        let spots = ScanFill.anchored([tall, wide], around: scanned, items: items + [tall, wide], room: "Bathroom")
        #expect(spots.isEmpty, "too tall or too wide for the desk: left to the layout")
        // One per desk.
        let second = LayoutItem(id: 7, name: "footstool", category: "ottoman", widthM: 0.4, depthM: 0.4, heightM: 0.4)
        let two = ScanFill.anchored([ottoman, second], around: scanned, items: items + [second], room: "Bathroom")
        #expect(two.map(\.itemId) == [2])
    }
}
