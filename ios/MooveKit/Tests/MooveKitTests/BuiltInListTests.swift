import Testing
@testable import MooveKit

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
