import Foundation
import Testing
@testable import MooveKit

/// Rooms get real names (Lisa: "can you not call every room a bedroom?").
@Suite struct RoomNamesTests {
    private func guess(_ categories: String..., attributes: [String] = []) -> String {
        RoomNames.guess(categories.map { RoomNames.Object(category: $0, attributes: attributes) })
    }

    @Test func guessesFromWhatTheScanFound() {
        #expect(guess("bed", "storage", "lamp") == "Bedroom")
        #expect(guess("crib", "chair") == "Bedroom")
        #expect(guess("sofa", "television", "table") == "Living room")
        #expect(guess("television", "storage") == "Living room")
        #expect(guess("stove", "refrigerator", "sink", "table") == "Kitchen")
        #expect(guess("dishwasher") == "Kitchen")
        #expect(guess("oven", "microwave") == "Kitchen")
        #expect(guess("toilet", "sink") == "Bathroom")
        #expect(guess("bathtub") == "Bathroom")
        #expect(guess("sink") == "Bathroom")
        #expect(guess("washerDryer", "basket") == "Laundry")
        #expect(guess("table", "chair", "chair", "chair", "chair") == "Dining room")
        #expect(guess("table", "chair", "monitor") == "Office")
        #expect(guess("bicycle", "toolbox") == "Garage")
        #expect(guess("lawn mower") == "Garage")
        #expect(guess("plant", "rug") == "Room")
        #expect(RoomNames.guess([]) == "Room")
    }

    @Test func sinkWithCounterIsAKitchenAndBedsWin() {
        #expect(guess("sink", "counter") == "Kitchen")
        // A studio with a kitchenette is still where you sleep; a mini fridge doesn't make a kitchen of it.
        #expect(guess("bed", "refrigerator", "sofa") == "Bedroom")
        // Two chairs at a table aren't a dining room.
        #expect(guess("table", "chair", "chair") == "Room")
    }

    @Test func namesAndAttributesCount() {
        // RoomPlan's swivel chair at a table with a laptop: an office.
        let office = [RoomNames.Object(category: "table"), RoomNames.Object(category: "chair", attributes: ["ChairType.swivel"]),
                      RoomNames.Object(category: "laptop")]
        #expect(RoomNames.guess(office) == "Office")
        // Dining chairs say dining room even with only two of them.
        let dining = [RoomNames.Object(category: "table"), RoomNames.Object(category: "chair", attributes: ["ChairType.dining"])]
        #expect(RoomNames.guess(dining) == "Dining room")
        // A dresser the user named ("storage" to RoomPlan) makes it a bedroom.
        #expect(RoomNames.guess([RoomNames.Object(category: "storage", name: "Tall dresser")]) == "Bedroom")
        #expect(RoomNames.guess([RoomNames.Object(category: "table", name: "Standing desk"), RoomNames.Object(category: "chair")]) == "Office")
    }

    @Test func wordsSplitCamelCase() {
        let words = RoomNames.words(of: RoomNames.Object(category: "washerDryer", attributes: ["ChairType.swivel"]))
        #expect(words.contains("washer") && words.contains("dryer") && words.contains("washerdryer"))
        #expect(words.contains("swivel") && words.contains("chair"))
    }

    @Test func numbersATakenName() {
        #expect(RoomNames.numbered("Bedroom", existing: []) == "Bedroom")
        #expect(RoomNames.numbered("Bedroom", existing: ["Kitchen"]) == "Bedroom")
        #expect(RoomNames.numbered("Bedroom", existing: ["Bedroom"]) == "Bedroom 2")
        #expect(RoomNames.numbered("bedroom ", existing: ["Bedroom", "Bedroom 2"]) == "bedroom 3")
        #expect(RoomNames.numbered("Bedroom 2", existing: ["Bedroom", "Bedroom 2"]) == "Bedroom 3")
        #expect(RoomNames.numbered("  ", existing: []) == "Room")
        #expect(RoomNames.isTaken("living room", in: ["Living room"]))
        #expect(!RoomNames.isTaken("", in: [""]))
        #expect(RoomNames.baseName("Living room 4") == "Living room")
        #expect(RoomNames.baseName("Room 101b") == "Room 101b")
    }

    @Test func cleanTrimsAndCaps() {
        #expect(RoomNames.clean("  Den \n") == "Den")
        #expect(RoomNames.clean("   ") == nil)
        #expect(RoomNames.clean(String(repeating: "x", count: 500))?.count == RoomNames.maxLength)
    }

    @Test func overridesRoundTripApplyAndSettle() {
        let names: [UInt64: String] = [1: "Sam's room", 7: "Den"]
        #expect(RoomNames.decode(RoomNames.encode(names)) == names)
        let junk: [String: Any] = ["x": "bad", "3": 4, "5": "  "]
        #expect(RoomNames.decode(junk).isEmpty)
        #expect(RoomNames.defaultsKey(database: "moove") == "moove.roomNames")
        #expect(RoomNames.defaultsKey(database: "moove-demo") == "moove.roomNames.moove-demo")

        var snap = SyncSnapshot()
        snap.rooms = [Room(id: 1, owner: "me", name: "Bedroom"), Room(id: 2, owner: "me", name: "Bedroom")]
        let shown = snap.renamingRooms(names)
        #expect(shown.rooms.map(\.name) == ["Sam's room", "Bedroom"])

        // Room 1 now has the name on the server (rename_room landed): drop it. Room 7 isn't
        // in this snapshot (still subscribing): keep it.
        snap.rooms[0].name = "Sam's room"
        #expect(RoomNames.pending(names, rooms: snap.rooms) == [7: "Den"])
    }

    @Test func fixtureRenamesOwnRoomsOnly() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.renameRoom(roomId: 1, name: "  Sam's room ")
        #expect(await firstSnapshot(backend).rooms.first { $0.id == 1 }?.name == "Sam's room")

        await #expect(throws: FixtureBackend.Failure.emptyName) { try await backend.renameRoom(roomId: 1, name: "  ") }
        await #expect(throws: FixtureBackend.Failure.nameTooLong) {
            try await backend.renameRoom(roomId: 1, name: String(repeating: "x", count: 121))
        }
        await #expect(throws: FixtureBackend.Failure.noSuchRoom) { try await backend.renameRoom(roomId: 4242, name: "Den") }

        // A room you joined (#10) isn't yours to rename.
        try await backend.joinRoom(code: DemoFixtures.roommateJoinCode)
        await #expect(throws: FixtureBackend.Failure.unauthorized) { try await backend.renameRoom(roomId: 900, name: "Den") }
        #expect(await firstSnapshot(backend).rooms.first { $0.id == 900 }?.name == "Living room")
    }

    @Test func importedRoomsKeepTheirOwnNames() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Kitchen", objects: []))
        let rooms = await firstSnapshot(backend).rooms
        #expect(rooms.map(\.name).sorted() == ["Bedroom", "Kitchen"])
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }
}
