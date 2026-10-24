import Foundation
import Testing
@testable import MooveKit

/// Inventory's **+ Add item** (take a photo, add your own item): `add_item` / `add_item_photo` /
/// `create_room` parity in `FixtureBackend`, the size chips and the offline "vision".
@Suite struct AddedItemTests {
    private func now(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }

    private func connectedDemo() async throws -> FixtureBackend {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        return backend
    }

    @Test func addItemWithPhotoWaitsForVision() async throws {
        let backend = try await connectedDemo()
        let room = try #require(await now(backend).rooms.first)
        let id = AddedItem.newScanObjectId()
        let object = AddedItem.object(scanObjectId: id, name: AddedItem.placeholderName, size: nil, photoUrl: "https://x/p.jpg")
        try await backend.addItem(roomId: room.id, name: AddedItem.placeholderName, object: object)
        let item = try #require(await now(backend).items.first { $0.scanObjectId == id })
        #expect(item.roomId == room.id && item.owner == room.owner)
        #expect(item.name == "New item" && item.category == "other")
        #expect(item.photoUrls == ["https://x/p.jpg"])
        #expect(item.detailsStatus == .pending && item.pricingStatus == .pending)
        #expect(item.priceState == .identifying)
        #expect(item.origin == .photo)
        #expect(item.originTag(inSharedRoom: false) == .addedByPhoto)
        #expect(item.widthM == 0 && item.heightM == 0 && item.depthM == 0)
    }

    @Test func addItemWithoutPhotoThenAttachIt() async throws {
        let backend = try await connectedDemo()
        let room = try #require(await now(backend).rooms.first)
        let id = AddedItem.newScanObjectId()
        try await backend.addItem(roomId: room.id, name: "Floor lamp",
                                  object: AddedItem.object(scanObjectId: id, name: "Floor lamp", size: .medium, photoUrl: nil))
        var item = try #require(await now(backend).items.first { $0.scanObjectId == id })
        #expect(item.photoUrls.isEmpty && item.name == "Floor lamp")
        // A size chip doesn't make it "scanned": it's still an added-by-photo item.
        #expect(item.heightM > 1 && item.origin == .photo)
        try await backend.addItemPhoto(itemId: item.id, url: "https://x/later.jpg")
        item = try #require(await now(backend).items.first { $0.id == item.id })
        #expect(item.photoUrls == ["https://x/later.jpg"] && item.detailsStatus == .pending)
    }

    @Test func addItemPhotoRequeuesVisionLikeTheModule() async throws {
        let backend = try await connectedDemo()
        let item = try #require(await now(backend).items.first)
        try await backend.addItemPhoto(itemId: item.id, url: "https://x/a.jpg")
        let after = try #require(await now(backend).items.first { $0.id == item.id })
        #expect(after.detailsStatus == .pending)
        #expect(after.photoUrls.last == "https://x/a.jpg")
    }

    @Test func addItemChecksLikeTheModule() async throws {
        let backend = try await connectedDemo()
        let room = try #require(await now(backend).rooms.first)
        let bad = ScanObject(scanObjectId: AddedItem.newScanObjectId(), category: "other", widthM: 31, heightM: 0, depthM: 0)
        await #expect(throws: FixtureBackend.Failure.invalidObject) {
            try await backend.addItem(roomId: room.id, name: "", object: bad)
        }
        let ok = AddedItem.object(scanObjectId: AddedItem.newScanObjectId(), name: "x", size: nil, photoUrl: nil)
        await #expect(throws: FixtureBackend.Failure.noSuchRoom) {
            try await backend.addItem(roomId: 999_999, name: "x", object: ok)
        }
        await #expect(throws: FixtureBackend.Failure.nameTooLong) {
            try await backend.addItem(roomId: room.id, name: String(repeating: "a", count: 121), object: ok)
        }
        // '' means the category, as in the module
        let blank = AddedItem.object(scanObjectId: AddedItem.newScanObjectId(), name: "", size: nil, photoUrl: nil)
        try await backend.addItem(roomId: room.id, name: "", object: blank)
        #expect(await now(backend).items.first { $0.scanObjectId == blank.scanObjectId }?.name == "other")
    }

    @Test func addItemNeedsRoomAccess() async throws {
        let backend = FixtureBackend(seed: DemoFixtures.demo(owner: "someone-else"))
        _ = try await backend.connect(token: nil)
        let room = try #require(await now(backend).rooms.first)
        let ok = AddedItem.object(scanObjectId: AddedItem.newScanObjectId(), name: "x", size: nil, photoUrl: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await backend.addItem(roomId: room.id, name: "x", object: ok)
        }
        // A joined room's members can add to it; the item belongs to the room's owner.
        let joined = FixtureBackend(joinable: DemoFixtures.roommateRoom())
        _ = try await joined.connect(token: nil)
        try await joined.joinRoom(code: DemoFixtures.roommateJoinCode)
        let shared = try #require(await now(joined).rooms.first)
        try await joined.addItem(roomId: shared.id, name: "x", object: ok)
        #expect(await now(joined).items.first { $0.scanObjectId == ok.scanObjectId }?.owner == shared.owner)
    }

    @Test func createRoomThenAddIntoIt() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.createRoom(name: "Garage")
        let room = try #require(await now(backend).rooms.first { $0.name == "Garage" })
        #expect(room.home == .old && room.owner == "fixture-user" && room.joinCode?.count == 6)
        await #expect(throws: FixtureBackend.Failure.nameTooLong) {
            try await backend.createRoom(name: String(repeating: "a", count: 81))
        }
        let o = AddedItem.object(scanObjectId: AddedItem.newScanObjectId(), name: "Bike", size: .large, photoUrl: nil)
        try await backend.addItem(roomId: room.id, name: "Bike", object: o)
        #expect(await now(backend).items.filter { $0.roomId == room.id }.count == 1)
    }

    @Test func offlineVisionNamesAnUnnamedItemAndSaysItsASample() async throws {
        let backend = try await connectedDemo()
        let room = try #require(await now(backend).rooms.first)
        let id = AddedItem.newScanObjectId()
        try await backend.addItem(roomId: room.id, name: AddedItem.placeholderName,
                                  object: AddedItem.object(scanObjectId: id, name: AddedItem.placeholderName, size: nil, photoUrl: "file:///p.jpg"))
        let added = try #require(await now(backend).items.first { $0.scanObjectId == id })
        try await backend.simulateIdentify(itemId: added.id, step: .milliseconds(1))
        let s = await now(backend)
        let item = try #require(s.items.first { $0.id == added.id })
        let sample = DemoFixtures.photoAddSample(for: added.id)
        #expect(item.name == sample.name && item.category == sample.category)
        #expect(item.detailsStatus == .done && item.estValueCents == sample.estValueCents)
        #expect(item.dispositionReason == DemoFixtures.photoAddSampleNote)
        #expect(s.agentEvents.contains { $0.refId == added.id && $0.agent == "vision" && $0.message.hasPrefix("Offline demo") })
    }

    @Test func offlineVisionKeepsATypedNameAndAPrice() async throws {
        let backend = try await connectedDemo()
        let priced = try #require(await now(backend).items.first { $0.estValueCents != nil })
        try await backend.addItemPhoto(itemId: priced.id, url: "file:///p.jpg")
        try await backend.simulateIdentify(itemId: priced.id, step: .milliseconds(1))
        let after = try #require(await now(backend).items.first { $0.id == priced.id })
        #expect(after.name == priced.name && after.estValueCents == priced.estValueCents && after.detailsStatus == .done)
    }

    // MARK: Size chips

    @Test func noChipMeansNoSize() {
        let d = AddedItem.dims(nil, name: "Floor lamp", category: "other")
        #expect(d.widthM == 0 && d.heightM == 0 && d.depthM == 0)
    }

    @Test func chipsScaleTheNamedKindsDefaultSize() {
        // "lamp" default (w 0.4, d 0.4, h 1.6)
        let m = AddedItem.dims(.medium, name: "Floor lamp", category: "other")
        #expect(m.widthM == 0.4 && m.depthM == 0.4 && m.heightM == 1.6)
        let s = AddedItem.dims(.small, name: "Floor lamp", category: "other")
        let l = AddedItem.dims(.large, name: "Floor lamp", category: "other")
        #expect(s.heightM < m.heightM && m.heightM < l.heightM)
        // the category counts too
        #expect(AddedItem.dims(.medium, name: "", category: "sofa").widthM == 2.0)
    }

    @Test func chipsFallBackToAGenericBoxForAnUnknownThing() {
        for name in [AddedItem.placeholderName, "", "thingamajig"] {
            #expect(AddedItem.dims(.small, name: name, category: "other") == (0.3, 0.3, 0.25))
            #expect(AddedItem.dims(.medium, name: name, category: "other") == (0.6, 0.6, 0.45))
            #expect(AddedItem.dims(.large, name: name, category: "other") == (1.2, 0.9, 0.6))
        }
        // every chip passes the module's size check
        for size in AddedItem.Size.allCases {
            let o = AddedItem.object(scanObjectId: AddedItem.newScanObjectId(), name: "Sofa", size: size, photoUrl: nil)
            #expect(FixtureBackend.unimportable(o) == nil)
        }
    }

    // MARK: Names, ids, rooms

    @Test func namesAndIds() {
        #expect(AddedItem.name(typed: "  ") == "New item")
        #expect(AddedItem.name(typed: " Rice cooker ") == "Rice cooker")
        #expect(AddedItem.name(typed: String(repeating: "a", count: 200)).count == 120)
        let id = AddedItem.newScanObjectId()
        #expect(id.hasPrefix("added:") && id.count <= 64)
    }

    @Test func defaultRoomPrefersTheTappedOneThenTheNewest() {
        let rooms = [Room(id: 3, owner: "me", name: "Office"), Room(id: 2, owner: "me", name: "New kitchen", home: .new),
                     Room(id: 1, owner: "me", name: "Bedroom")]
        #expect(AddedItem.defaultRoom(rooms, preferred: 1)?.id == 1)
        #expect(AddedItem.defaultRoom(rooms, preferred: nil)?.id == 3)
        #expect(AddedItem.defaultRoom(rooms, preferred: 2)?.id == 2)  // tapped, even a new-home room
        #expect(AddedItem.defaultRoom([rooms[1], rooms[2]], preferred: nil)?.id == 1)  // newest old-home room first
        #expect(AddedItem.defaultRoom([rooms[1]], preferred: nil)?.id == 2)
        #expect(AddedItem.defaultRoom([], preferred: nil) == nil)
    }
}
