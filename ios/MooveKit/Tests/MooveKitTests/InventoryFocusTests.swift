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

/// Built-ins stay with the building: out of the app's item lists, but drawn in the 3D room.
@Suite struct BuiltInListTests {
    func item(_ id: UInt64, _ name: String, _ category: String) -> Item {
        Item(id: id, owner: "me", roomId: 1, name: name, category: category, widthM: 0.5, heightM: 0.8, depthM: 0.7)
    }

    @Test func snapshotsLeaveFixturesOut() {
        var s = SyncSnapshot()
        s.items = [item(1, "white two-piece elongated toilet", "appliance"), item(2, "office chair", "chair"),
                   item(3, "white alcove bathtub with shower curtain", "appliance"), item(4, "cream fabric shower curtain with rod", "decor")]
        #expect(s.withoutBuiltIns().items.map(\.id) == [2, 4])
    }

    @Test func accessoriesCountOnlyInTheHeadNoun() {
        #expect(item(1, "white alcove bathtub with shower curtain", "appliance").isBuiltInFixture)
        #expect(!item(2, "shower curtain with rod", "decor").isBuiltInFixture)
        #expect(!item(3, "chrome towel rack shelf", "storage").isBuiltInFixture)
    }

    @Test func doorsFansAndWallMountedFixturesStay() {
        for (n, c) in [("white paneled interior door with brass knob", "storage"), ("brown wood-blade ceiling fan with frosted glass light kit", "fan"),
                       ("chrome wall-mounted bathroom towel rack shelf", "storage"), ("white wall-mounted hair dryer", "appliance"),
                       ("white plantation window shutters", "decor"), ("vertical blinds", "decor")] {
            #expect(item(1, n, c).isBuiltInFixture, "\(n)")
        }
        for (n, c) in [("door mat", "decor"), ("window fan", "fan"), ("window AC unit", "appliance"), ("over-the-door hooks", "storage"),
                       ("wall-mounted flat screen TV", "tv"), ("box fan", "fan"), ("shower caddy", "decor"), ("toilet paper", "decor")] {
            #expect(!item(1, n, c).isBuiltInFixture, "\(n)")
        }
    }
}
