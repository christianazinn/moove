import Foundation
import Testing
@testable import MooveKit

/// "Rooms in this move": one selection for Inventory, Review and Move (replaced Hide room,
/// Inventory focus and "Moving from").
@Suite struct RoomSelectionTests {
    static let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    var snapshot: SyncSnapshot {
        var s = SyncSnapshot(me: "me")
        s.rooms = [Room(id: 1, owner: "me", name: "Bedroom"), Room(id: 2, owner: "me", name: "Bedroom"),
                   Room(id: 3, owner: "me", name: "Bunk room"), Room(id: 4, owner: "me", name: " bedroom ")]
        s.scans = [Scan(id: 11, owner: "me", roomId: 1, createdAt: Self.t0), Scan(id: 12, owner: "me", roomId: 2, createdAt: Self.t0 + 3600),
                   Scan(id: 13, owner: "me", roomId: 3, createdAt: Self.t0 + 7200), Scan(id: 14, owner: "me", roomId: 4, createdAt: Self.t0 + 60)]
        func bed(_ id: UInt64, _ room: UInt64, _ w: Double) -> Item {
            Item(id: id, owner: "me", roomId: room, name: "Bed", category: "bed", widthM: w, heightM: 0.57, depthM: 2.08, disposition: .keep)
        }
        s.items = [bed(101, 1, 1.56), bed(102, 2, 1.58), bed(103, 3, 1.08), bed(104, 4, 1.6),
                   Item(id: 105, owner: "me", roomId: 1, name: "Lamp", category: "lamp", widthM: 0.3, heightM: 0.45, depthM: 0.3, disposition: .keep)]
        return s
    }

    @Test func newestScanOfEachNameIsSelectedByDefault() {
        let choices = RoomSelection.choices(snapshot, overrides: [:])
        #expect(choices.map(\.id) == [3, 2, 4, 1]) // newest scan first
        #expect(choices.filter(\.selected).map(\.id) == [3, 2])
        let selected = snapshot.selectingRooms([:])
        #expect(selected.rooms.map(\.id) == [2, 3])
        #expect(selected.items.map(\.id) == [102, 103])
    }

    @Test func emptyRoomsAreInAndDontClaimTheirName() {
        var s = snapshot
        s.rooms.append(Room(id: 5, owner: "me", name: "Bedroom"))
        s.scans.append(Scan(id: 15, owner: "me", roomId: 5, createdAt: Self.t0 + 9000))
        s.rooms.append(Room(id: 6, owner: "me", name: "Garage"))
        let selected = RoomSelection.choices(s, overrides: [:]).filter(\.selected).map(\.id)
        #expect(Set(selected) == [5, 3, 2, 6])
    }

    @Test func togglingARoomInAndOutPersists() {
        var overrides: [UInt64: Bool] = [:]
        var choices = RoomSelection.choices(snapshot, overrides: overrides)
        overrides = RoomSelection.toggle(1, in: choices, overrides: overrides)
        #expect(overrides == [1: true])
        #expect(RoomSelection.decode(RoomSelection.encode(overrides)) == overrides)
        choices = RoomSelection.choices(snapshot, overrides: overrides)
        // Room 1's bed is a re-scan of room 2's (same name, same size): it doesn't move twice.
        let selected = snapshot.selectingRooms(overrides)
        #expect(selected.items.count == 4)
        #expect(RoomSelection.moving(selected.items, in: selected).map(\.id).sorted() == [102, 103, 105])
        overrides = RoomSelection.toggle(1, in: choices, overrides: overrides)
        #expect(overrides.isEmpty) // back to the default
        overrides = RoomSelection.toggle(3, in: choices, overrides: overrides)
        #expect(RoomSelection.encode(overrides) == ["-3"])
        #expect(RoomSelection.decode(["+7", "-8", "junk", "9"]) == [7: true, 8: false])
    }

    @Test func selectAllNoneAndPrune() {
        let choices = RoomSelection.choices(snapshot, overrides: [:])
        let none = RoomSelection.setAll(false, in: choices)
        #expect(RoomSelection.choices(snapshot, overrides: none).allSatisfy { !$0.selected })
        #expect(snapshot.selectingRooms(none).items.isEmpty)
        let all = RoomSelection.setAll(true, in: choices)
        #expect(RoomSelection.choices(snapshot, overrides: all).allSatisfy { $0.selected })
        #expect(RoomSelection.unselected(RoomSelection.choices(snapshot, overrides: all)).isEmpty)
        #expect(RoomSelection.pruned([1: true, 99: false], rooms: snapshot.rooms) == [1: true])
    }

    @Test func migratesTheThreeOldChoices() {
        // Moving picks first, then focused rooms in, then hidden rooms out.
        let out = RoomSelection.migrate(hidden: ["4", "junk"], focus: "1,x,4", moving: ["-3", "+2"])
        #expect(out == [1: true, 2: true, 3: false, 4: false])
        #expect(RoomSelection.migrate(hidden: nil, focus: nil, moving: nil).isEmpty)
    }

    @Test func loadMigratesOnceAndDropsTheOldKeys() throws {
        let suite = "moove.tests.rooms.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["7"], forKey: RoomSelection.legacyHiddenKey)
        defaults.set("8", forKey: RoomSelection.legacyFocusKey)
        defaults.set(["-9"], forKey: RoomSelection.legacyMovingKey)
        #expect(RoomSelection.load(from: defaults) == [7: false, 8: true, 9: false])
        #expect(defaults.object(forKey: RoomSelection.legacyHiddenKey) == nil)
        #expect(defaults.object(forKey: RoomSelection.legacyFocusKey) == nil)
        #expect(defaults.object(forKey: RoomSelection.legacyMovingKey) == nil)
        // Later launches read the new key only.
        defaults.set(["1"], forKey: RoomSelection.legacyHiddenKey)
        RoomSelection.save([2: true], to: defaults)
        #expect(RoomSelection.load(from: defaults) == [2: true])
    }

    @Test func differentRoomsKeepTheirTwinBeds() {
        let a = Item(id: 1, owner: "me", roomId: 1, name: "Twin bed", category: "bed", widthM: 1.0, heightM: 0.5, depthM: 2.0, disposition: .keep)
        var b = a
        b.id = 2; b.roomId = 2
        let names: [UInt64: String] = [1: "kids room", 2: "guest room"]
        #expect(RoomSelection.dedupe([a, b], roomName: { names[$0] }).count == 2)
        #expect(RoomSelection.dedupe([a, b], roomName: { _ in "bedroom" }).count == 1)
        var c = b
        c.widthM = 1.6 // a different bed
        #expect(RoomSelection.dedupe([a, c], roomName: { _ in "bedroom" }).count == 2)
    }
}
