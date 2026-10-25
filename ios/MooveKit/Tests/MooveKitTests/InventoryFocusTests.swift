import Testing
@testable import MooveKit

@Suite struct InventoryFocusTests {
    let rooms = [Room(id: 1, owner: "me", name: "Bunk room"), Room(id: 2, owner: "me", name: "Bathroom"), Room(id: 3, owner: "me", name: "Old bedroom")]
    func item(_ id: UInt64, _ room: UInt64) -> Item {
        Item(id: id, owner: "me", roomId: room, name: "thing", category: "chair", widthM: 0.5, heightM: 0.9, depthM: 0.5)
    }

    @Test func noFocusShowsEverything() {
        let items = [item(1, 1), item(2, 2), item(3, 3)]
        #expect(InventoryFocus.items(items, focus: []).count == 3)
    }

    @Test func focusShowsOnlyThoseRooms() {
        let items = [item(1, 1), item(2, 2), item(3, 3), item(4, 1)]
        #expect(InventoryFocus.items(items, focus: [1, 2]).map(\.id) == [1, 2, 4])
    }

    @Test func toggleAndRoundTrip() {
        var f: Set<UInt64> = []
        f = InventoryFocus.toggling(2, in: f)
        f = InventoryFocus.toggling(3, in: f)
        f = InventoryFocus.toggling(2, in: f)
        #expect(f == [3])
        #expect(InventoryFocus.decode(InventoryFocus.encode([3, 1])) == [1, 3])
        #expect(InventoryFocus.decode("") == [] && InventoryFocus.decode("x,2") == [2])
    }

    @Test func goneRoomsDropOutOfTheFocus() {
        #expect(InventoryFocus.active([2, 9], rooms: rooms) == [2])
        #expect(InventoryFocus.active([9], rooms: rooms).isEmpty, "focus on nothing that exists shows everything")
    }
}
