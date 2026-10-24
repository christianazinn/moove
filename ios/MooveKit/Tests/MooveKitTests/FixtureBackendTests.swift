import Foundation
import Testing
@testable import MooveKit

@Suite struct FixtureBackendTests {
    @Test func importScanCreatesRoomScanAndItems() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: [
            ScanObject(scanObjectId: "a", category: "chair", widthM: 0.5, heightM: 1, depthM: 0.5, photoUrl: "http://x/a.jpg"),
            ScanObject(scanObjectId: "b", category: "table", widthM: 1, heightM: 0.7, depthM: 0.6),
        ]))
        let snap = await firstSnapshot(backend)
        #expect(snap.rooms.count == 1)
        #expect(snap.scans.first?.roomId == snap.rooms.first?.id)
        #expect(snap.items.map(\.scanObjectId) == ["a", "b"])
        #expect(snap.items.allSatisfy { $0.disposition == .undecided && $0.roomId == snap.rooms[0].id })
        #expect(snap.items[0].photoUrls == ["http://x/a.jpg"])
    }

    @Test func addScanPhotoChecksLikeTheModule() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: []))
        let scanId = try #require(await firstSnapshot(backend).scans.first?.id)
        try await backend.addScanPhoto(scanId: scanId, url: "https://x/room-0.jpg")
        let snap = await firstSnapshot(backend)
        #expect(snap.latestScan(ofRoom: snap.rooms[0].id)?.sweepStatus == .pending)
        await #expect(throws: FixtureBackend.Failure.invalidUrl) { try await backend.addScanPhoto(scanId: scanId, url: "file:///tmp/a.jpg") }
        await #expect(throws: FixtureBackend.Failure.noSuchScan) { try await backend.addScanPhoto(scanId: 9999, url: "https://x/a.jpg") }
        for i in 1..<FixtureBackend.maxScanPhotos { try await backend.addScanPhoto(scanId: scanId, url: "https://x/\(i).jpg") }
        await #expect(throws: FixtureBackend.Failure.tooManyPhotos) { try await backend.addScanPhoto(scanId: scanId, url: "https://x/last.jpg") }
    }

    @Test func importScanStoresRoomPlanAttributes() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Office", objects: [
            ScanObject(scanObjectId: "a", category: "chair", widthM: 0.6, heightM: 1, depthM: 0.6,
                       attributes: ["ChairType.swivel", "ChairLegType.star", "ChairType.swivel"]),
            ScanObject(scanObjectId: "b", category: "other", widthM: 0, heightM: 0, depthM: 0),
        ]))
        let items = await firstSnapshot(backend).items
        #expect(items[0].attributes == ["ChairType.swivel", "ChairLegType.star"])  // de-duplicated, order kept
        #expect(items[1].attributes.isEmpty && items[1].colors == nil)
    }

    @Test func importScanRejectsBadAttributesAtomically() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        for bad in [["<script>"], ["ChairType"], ["Chair Type.swivel"], ["ChairType.sw-ivel"],
                    (0...ScanObject.maxAttributes).map { "T.v\($0)" }] {
            await #expect(throws: FixtureBackend.Failure.invalidAttribute) {
                try await backend.importScan(ScanImport(roomName: "Office", objects: [
                    ScanObject(scanObjectId: "ok", category: "table", widthM: 1, heightM: 0.7, depthM: 0.6),
                    ScanObject(scanObjectId: "a", category: "chair", widthM: 0.6, heightM: 1, depthM: 0.6, attributes: bad),
                ]))
            }
        }
        let snap = await firstSnapshot(backend)
        #expect(snap.rooms.isEmpty && snap.items.isEmpty)
    }

    @Test func attributeRuleMatchesModule() {
        for ok in ["ChairType.swivel", "SofaType.lShapedExtension", "TableShapeType.circularElliptic", "T2.a_b"] {
            #expect(ScanObject.isValidAttribute(ok), "\(ok)")
        }
        for bad in ["", ".x", "Chair.", "2Chair.x", "Chair.x.y", "Chäir.x", "Chair_Type.x", "Chair.\(String(repeating: "x", count: 41))"] {
            #expect(!ScanObject.isValidAttribute(bad), "\(bad)")
        }
    }

    @Test func demoScanCarriesAttributes() {
        let chair = DemoFixtures.scanImport().objects.first { $0.category == "chair" }
        #expect(chair?.attributes.contains("ChairLegType.star") == true)
        #expect(DemoFixtures.scanImport().objects.flatMap(\.attributes).allSatisfy(ScanObject.isValidAttribute))
    }

    @Test func userOverrideSurvivesAgentRerun() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.setDisposition(itemId: 11, disposition: .keep)
        try backend.setAutoDisposition(itemId: 11, disposition: .sell, reason: "rerun")
        let item = await firstSnapshot(backend).items.first { $0.id == 11 }
        #expect(item?.disposition == .keep)
        #expect(item?.dispositionSource == .user)
    }

    @Test func agentNeverDecidesSentimentalItems() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try backend.setAutoDisposition(itemId: 18, disposition: .donate, reason: "rerun")
        #expect(await firstSnapshot(backend).items.first { $0.id == 18 }?.disposition == .undecided)
    }

    @Test func cannotEditSomeoneElsesItem() async throws {
        var seed = DemoFixtures.inventory(owner: "alice")
        seed.me = nil
        let backend = FixtureBackend(identity: "mallory", seed: seed)
        _ = try await backend.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await backend.setDisposition(itemId: 11, disposition: .trash)
        }
    }

    @Test func snapshotsStreamLiveChanges() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        var iterator = backend.snapshots().makeAsyncIterator()
        _ = await iterator.next()
        try await backend.setDisposition(itemId: 12, disposition: .donate)
        let next = await iterator.next()
        #expect(next?.items.first { $0.id == 12 }?.disposition == .donate)
    }

    @Test func demoHasSentimentalItemsNeedingUser() {
        let snap = DemoFixtures.inventory(owner: "me")
        #expect(snap.items.count >= 10)
        #expect(snap.items.filter(\.maybeSentimental).allSatisfy { $0.needsUser })
    }

    // MARK: set_item_colors

    private func backendWithItem() async throws -> (FixtureBackend, UInt64) {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: [
            ScanObject(scanObjectId: "bed", category: "bed", widthM: 1.6, heightM: 0.4, depthM: 2.1),
        ]))
        return (backend, await firstSnapshot(backend).items[0].id)
    }

    @Test func setItemColorsStoresAndClears() async throws {
        let (backend, id) = try await backendWithItem()
        try await backend.setItemColors(itemId: id, colors: ItemColors(primary: 0xB98A5A, secondary: 0xE9E3D6))
        #expect(await firstSnapshot(backend).items[0].colors == ItemColors(primary: 0xB98A5A, secondary: 0xE9E3D6))
        try await backend.setItemColors(itemId: id, colors: ItemColors(primary: 0x00000A))
        #expect(await firstSnapshot(backend).items[0].colors == ItemColors(primary: 0x00000A))
        try await backend.setItemColors(itemId: id, colors: nil)
        #expect(await firstSnapshot(backend).items[0].colors == nil)
    }

    @Test func setItemColorsValidatesLikeTheModule() async throws {
        let (backend, id) = try await backendWithItem()
        // Lowercase is accepted and stored uppercase, as the module does.
        try await backend.setItemColors(itemId: id, colorsJson: ##"{"secondary":"#a0b1c2","primary":"#0f0f0f"}"##)
        #expect(await firstSnapshot(backend).items[0].colors == ItemColors(primary: 0x0F0F0F, secondary: 0xA0B1C2))
        #expect(ItemColors.normalizedJson(##"{"secondary":"#a0b1c2","primary":"#0f0f0f"}"##) == ##"{"primary":"#0F0F0F","secondary":"#A0B1C2"}"##)
        #expect(ItemColors.normalizedJson("") == "")
        for bad in [##"{"primary":"0F0F0F"}"##, ##"{"primary":"#0F0F0"}"##, ##"{"primary":"#GGGGGG"}"##, ##"{"accent":"#0F0F0F"}"##,
                    ##"{"primary":255}"##, ##"["#0F0F0F"]"##, "not json", ##""#0F0F0F""##] {
            await #expect(throws: FixtureBackend.Failure.invalidColors, "\(bad)") {
                try await backend.setItemColors(itemId: id, colorsJson: bad)
            }
        }
        // Out of 24-bit range has no #RRGGBB form.
        await #expect(throws: FixtureBackend.Failure.invalidColors) {
            try await backend.setItemColors(itemId: id, colors: ItemColors(primary: 0x1000000))
        }
        // Rejected writes leave the stored colors alone.
        #expect(await firstSnapshot(backend).items[0].colors == ItemColors(primary: 0x0F0F0F, secondary: 0xA0B1C2))
    }

    @Test func setItemColorsNeedsTheItemAndOwner() async throws {
        let (backend, id) = try await backendWithItem()
        await #expect(throws: FixtureBackend.Failure.noSuchItem) {
            try await backend.setItemColors(itemId: id + 999, colors: ItemColors(primary: 0x123456))
        }
        let other = FixtureBackend(identity: "someone-else", seed: await firstSnapshot(backend))
        _ = try await other.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await other.setItemColors(itemId: id, colors: ItemColors(primary: 0x123456))
        }
    }

    @Test func sampledColorsPersistOntoImportedItems() async throws {
        let (backend, id) = try await backendWithItem()
        let sampled = ScanColors(wallColor: 0xEEEEEE, objectColors: ["bed": .init(primary: 0xB98A5A), "gone": .init(primary: 0x111111)])
        let updates = sampled.itemColorUpdates(for: await firstSnapshot(backend).items)
        #expect(updates == [ItemColorUpdate(itemId: id, colors: ItemColors(primary: 0xB98A5A))])
        for u in updates { try await backend.setItemColors(itemId: u.itemId, colors: u.colors) }
        let items = await firstSnapshot(backend).items
        #expect(items[0].colors?.primary == 0xB98A5A)
        // Already stored: nothing more to write.
        #expect(sampled.itemColorUpdates(for: items).isEmpty)
        // And the new home / thumbnails pick them up from the item alone.
        #expect(LayoutItem(items[0]).primaryColor == 0xB98A5A)
        #expect(VoxelItemSpec(items[0]).primaryColor == 0xB98A5A)
    }

    // MARK: Demo scan

    @Test func demoScanImportsIdentifiedItems() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(DemoFixtures.scanImport())
        let snap = await firstSnapshot(backend)
        let template = DemoFixtures.inventory(owner: "demo").items
        #expect(snap.items.count == template.count)
        let bed = snap.items.first { $0.scanObjectId == "demo-10" }!
        #expect(bed.name == "Full size metal bed frame" && bed.category == "bed" && bed.disposition == .keep && bed.estValueCents == 7_700)
        // Sentimental pieces are still left for the user.
        #expect(snap.items.filter(\.maybeSentimental).allSatisfy { $0.disposition == .undecided })
        // Colors come through set_item_colors, not the import.
        #expect(snap.items.allSatisfy { $0.colors == nil })
    }

    @Test func demoScanColorsCoverTheDemoRoom() {
        let colors = DemoFixtures.scanColors()
        #expect(colors.wallColor != nil && colors.floorColor != nil)
        let objects = Set(DemoFixtures.roomGeometry().objects.map(\.id))
        #expect(Set(colors.objectColors.keys) == objects)
        for item in DemoFixtures.inventory(owner: "demo").items {
            #expect(DemoFixtures.isDemoItem(item))
            #expect(colors.colors(for: item) != nil, "\(item.name)")
            // Consistent with the colors the seeded demo items already store.
            if let stored = item.colors { #expect(ItemColors(colors.colors(for: item)!) == stored) }
        }
        #expect(colors.objectColors.values.allSatisfy { ItemColors($0).isValid })
    }

    @Test func sampledColorsWinOverTheDemoFallback() {
        let sampled = ScanColors(floorColor: 0x101010, objectColors: ["demo-10": .init(primary: 0x202020)])
        let merged = sampled.filling(from: DemoFixtures.scanColors())
        #expect(merged.floorColor == 0x101010 && merged.wallColor == DemoFixtures.scanColors().wallColor)
        #expect(merged.objectColors["demo-10"]?.primary == 0x202020)
        #expect(merged.objectColors["demo-11"] == DemoFixtures.scanColors().objectColors["demo-11"])
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }
}
