import Foundation
import Testing
@testable import MooveKit

@Suite struct InventoryDisplayTests {
    func item(_ id: UInt64, room: UInt64, _ scanObjectId: String?, category: String = "chair", size: Double = 0.5) -> Item {
        Item(id: id, owner: "me", roomId: room, scanObjectId: scanObjectId, name: "x", category: category,
             widthM: size, heightM: size, depthM: size)
    }

    var snapshot: SyncSnapshot {
        var s = SyncSnapshot(me: "me")
        s.rooms = [Room(id: 1, owner: "me", name: "Bedroom"), Room(id: 2, owner: "me", name: "Bedroom"),
                   Room(id: 3, owner: "me", name: "Office")]
        s.scans = [Scan(id: 10, owner: "me", roomId: 1, createdAt: Date(timeIntervalSince1970: 1_000)),
                   Scan(id: 11, owner: "me", roomId: 2, createdAt: Date(timeIntervalSince1970: 3_000)),
                   Scan(id: 12, owner: "me", roomId: 1, createdAt: Date(timeIntervalSince1970: 2_000))]
        s.items = [item(1, room: 1, "demo-10"), item(2, room: 1, "photo:10"),
                   item(3, room: 2, "59B5C0DE-0000-0000-0000-000000000000"), item(4, room: 3, nil, size: 0)]
        return s
    }

    @Test func hiddenRoomsRoundTripAndFilter() {
        #expect(HiddenRooms.decode(HiddenRooms.encode([3, 1])) == [1, 3])
        #expect(HiddenRooms.decode(nil).isEmpty)
        #expect(HiddenRooms.decode(["7", "junk"]) == [7])
        let s = snapshot
        let visible = s.hidingRooms([1])
        #expect(visible.rooms.map(\.id) == [2, 3])
        #expect(visible.items.map(\.id) == [3, 4])
        #expect(s.hidingRooms([]) == s)
    }

    @Test func roomsSortNewestScanFirst() {
        // Room 2 scanned at 3000, room 1's newest scan at 2000, room 3 has no scan.
        #expect(snapshot.roomsNewestFirst().map(\.id) == [2, 1, 3])
        #expect(snapshot.scanDate(ofRoom: 1) == Date(timeIntervalSince1970: 2_000))
        #expect(snapshot.scanDate(ofRoom: 3) == nil)
    }

    @Test func demoRoomsAreTheOnesWithDemoItems() {
        #expect(snapshot.isDemoRoom(1))  // demo item + a sweep item
        #expect(!snapshot.isDemoRoom(2))
        #expect(!snapshot.isDemoRoom(3))
    }

    @Test func originTags() {
        let s = snapshot
        #expect(s.items[0].originTag(inSharedRoom: false) == .scanned)
        #expect(s.items[1].originTag(inSharedRoom: false) == .fromPhotos)
        #expect(s.items[3].originTag(inSharedRoom: false) == .addedByPhoto)
        #expect(s.items[2].originTag(inSharedRoom: true) == .shared)
        #expect(Item.OriginTag.allCases.allSatisfy { $0.label.count <= 14 })
        #expect(Item.OriginTag.fromPhotos.accessibilityLabel.localizedCaseInsensitiveContains("from room photos"))
    }

    @Test func renamedMarker() {
        let lamp = item(1, room: 1, "A", category: "lamp")
        #expect(lamp.renamedFrom(scannedCategory: "storage") == "storage")
        #expect(lamp.renamedFrom(scannedCategory: "Lamp") == nil)
        #expect(lamp.renamedFrom(scannedCategory: "other") == nil)
        #expect(lamp.renamedFrom(scannedCategory: nil) == nil)
        #expect(lamp.renamedFrom(scannedCategory: "washerDryer") == "washer dryer")
        // Sweep and photo items have no scanned box to compare with.
        #expect(item(2, room: 1, "photo:1", category: "lamp").renamedFrom(scannedCategory: "storage") == nil)
    }

    @Test func demoBedroomIsNotRenamed() {
        let scanned = Dictionary(DemoFixtures.roomGeometry().objects.map { ($0.id, $0.category) }, uniquingKeysWith: { a, _ in a })
        for item in DemoFixtures.inventory(owner: "me").items where DemoFixtures.isDemoItem(item) {
            #expect(item.renamedFrom(scannedCategory: item.scanObjectId.flatMap { scanned[$0] }) == nil, "\(item.name)")
        }
    }

    @Test func scanDateLabels() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_792_000_000)  // mid-October 2026
        let today = cal.date(bySettingHour: 10, minute: 42, second: 0, of: now)!
        #expect(ScanDateLabel.text(today, now: now, calendar: cal, locale: locale).hasPrefix("Today 10:42"))
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        #expect(ScanDateLabel.text(yesterday, now: now, calendar: cal, locale: locale).hasPrefix("Yesterday 10:42"))
        let earlier = cal.date(byAdding: .day, value: -5, to: today)!
        let older = ScanDateLabel.text(earlier, now: now, calendar: cal, locale: locale)
        #expect(older.hasPrefix("Oct ") && older.contains("10:42"), "\(older)")
        let lastYear = cal.date(byAdding: .year, value: -1, to: today)!
        #expect(ScanDateLabel.text(lastYear, now: now, calendar: cal, locale: locale).contains("2025"))
    }
}
