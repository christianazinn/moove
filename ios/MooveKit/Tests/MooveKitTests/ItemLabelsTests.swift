import Foundation
import Testing
@testable import MooveKit

@Suite struct ItemLabelsTests {
    private func item(_ id: UInt64, _ name: String, _ category: String = "other", status: AgentStage? = nil,
                      photos: [String] = [], scanObjectId: String? = nil) -> Item {
        Item(id: id, owner: "me", roomId: 1, scanObjectId: scanObjectId, name: name, category: category,
             widthM: 0.5, heightM: 0.5, depthM: 0.5, photoUrls: photos, detailsStatus: status)
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }

    // MARK: Placeholder names

    @Test func placeholderNames() {
        #expect(ItemLabels.isPlaceholderName("", category: "chair"))
        #expect(ItemLabels.isPlaceholderName("other", category: "other"))
        #expect(ItemLabels.isPlaceholderName("Other", category: "other"))
        #expect(ItemLabels.isPlaceholderName("  Unidentified item ", category: "storage"))
        #expect(ItemLabels.isPlaceholderName("Unknown", category: "decor"))
        // a real name, even a generic one RoomPlan gave, isn't a placeholder
        #expect(!ItemLabels.isPlaceholderName("Storage", category: "storage"))
        #expect(!ItemLabels.isPlaceholderName("Chair", category: "chair"))
        #expect(!ItemLabels.isPlaceholderName("Grandma's lamp", category: "other"))
    }

    @Test func needsANameListsPlaceholdersOldestFirstWithAHint() {
        let items = [
            item(5, "Other", status: .failed),
            item(2, "IKEA Kallax shelf", "storage"),
            item(3, "other", status: .running, photos: ["https://x/a.jpg"]),
            item(4, "Unidentified item"),
        ]
        #expect(ItemLabels.needingNames(items).map(\.id) == [3, 4, 5])
        #expect(ItemLabels.hint(for: items[2]).contains("naming it from its photo"))
        #expect(ItemLabels.hint(for: items[0]).contains("couldn't tell"))
        #expect(ItemLabels.hint(for: items[3]).hasPrefix("Name it or pick"))
        // the demo bedroom has nothing to name
        #expect(ItemLabels.needingNames(DemoFixtures.inventory(owner: "me").items).isEmpty)
    }

    // MARK: Carry-over into the import

    @Test func labelCarriesNameKindAndCategory() {
        let object = ScanObject(scanObjectId: "a", category: "other", widthM: 0.6, heightM: 0.9, depthM: 0.6,
                                attributes: ["StorageType.cabinet"])
        // name and kind: both, the kind's category, the kind as UserKind
        let both = ItemLabels.applying(ItemLabels.Label(name: "  Grandma's rocker ", kind: .chair), to: object)
        #expect(both.name == "Grandma's rocker")
        #expect(both.category == "chair")
        #expect(both.attributes == ["StorageType.cabinet", "UserKind.chair"])
        // a name alone: the kind the name implies, like a rename after import
        let named = ItemLabels.applying(ItemLabels.Label(name: "Coffee table"), to: object)
        #expect(named.name == "Coffee table" && named.category == "other")
        #expect(named.attributes == ["StorageType.cabinet", "UserKind.table"])
        // a kind alone: no name (vision names it), category and kind set
        let kind = ItemLabels.applying(ItemLabels.Label(kind: .tv), to: object)
        #expect(kind.name == nil && kind.category == "television")
        #expect(kind.attributes.allSatisfy(ScanObject.isValidAttribute))
        // nothing chosen, "Other" alone, or no label: unchanged
        #expect(ItemLabels.applying(ItemLabels.Label(name: "  ", kind: .other), to: object) == object)
        #expect(ItemLabels.applying(nil, to: object) == object)
        // capped at the module's MAX_NAME
        let long = ItemLabels.applying(ItemLabels.Label(name: String(repeating: "x", count: 300)), to: object)
        #expect(long.name?.count == FixtureBackend.maxNameLength)
        #expect(ItemLabels.Label(name: "", kind: .lamp).title == "Lamp")
    }

    @Test func everyKindMapsToACategoryExceptOther() {
        for k in ItemFix.QuickKind.allCases {
            #expect((ItemLabels.category(for: k) == nil) == (k == .other))
        }
    }

    @Test func fixtureImportKeepsTheUserName() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        let objects = [
            ScanObject(scanObjectId: "a", category: "other", widthM: 0.5, heightM: 0.5, depthM: 0.5),
            // a demo object: the offline stand-in vision names it, but the user's name wins
            ScanObject(scanObjectId: "demo-14", category: "lamp", widthM: 0.3, heightM: 1.7, depthM: 0.3),
            ScanObject(scanObjectId: "b", category: "other", widthM: 0.5, heightM: 0.5, depthM: 0.5),
        ]
        let labels = ["a": ItemLabels.Label(name: "Record crate", kind: .box), "demo-14": ItemLabels.Label(name: "Arc lamp")]
        try await backend.importScan(ScanImport(roomName: "Den", objects: objects.map { ItemLabels.applying(labels[$0.scanObjectId], to: $0) }))
        let items = await firstSnapshot(backend).items
        #expect(items.map(\.name) == ["Record crate", "Arc lamp", "Other"])
        #expect(items[0].category == "box" && items[0].attributes == ["UserKind.box"])
        #expect(ItemLabels.needingNames(items).map(\.scanObjectId) == ["b"])
        #expect(ItemLabels.keptNames(for: labels, in: items) == [items[0].id: "Record crate", items[1].id: "Arc lamp"])
    }

    // MARK: Keeping the name through vision

    @Test func keptNamesComeBackUntilVisionIsDone() {
        let kept: [UInt64: String] = [1: "Record crate", 2: "Arc lamp", 3: "Desk", 9: "Gone"]
        let items = [
            item(1, "Wooden crate", status: .done, photos: ["p"]),     // vision replaced it: put it back, done
            item(2, "Arc lamp", status: .running, photos: ["p"]),      // vision still to answer: keep watching
            item(3, "Other", status: .pending, photos: ["p"]),         // not back yet: rename, keep watching
        ]
        let work = ItemLabels.keptNameWork(kept, items: items)
        #expect(work.renames == [1: "Record crate", 3: "Desk"])
        #expect(work.settled == [1, 9])
        // fixture items (no status) settle at once
        #expect(ItemLabels.keptNameWork([4: "Box"], items: [item(4, "Box")]) == ([:], [4]))
    }

    @Test func keptNamesRoundTripThroughDefaults() {
        let kept: [UInt64: String] = [12: "Arc lamp", 18_446_744_073_709_551_615: "Max"]
        #expect(ItemLabels.decode(ItemLabels.encode(kept)) == kept)
        #expect(ItemLabels.decode(["x": "bad", "7": 3]).isEmpty)
        #expect(ItemLabels.decode(nil).isEmpty)
    }
}
