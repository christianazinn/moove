import Foundation
import Testing
@testable import MooveKit

@Suite struct InventoryBinderTests {
    private func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double),
                      value: Int64? = nil) -> Item {
        Item(id: id, owner: "me", roomId: 1, scanObjectId: "uuid", name: name, category: category,
             widthM: dims.0, heightM: dims.1, depthM: dims.2, estValueCents: value)
    }

    // MARK: Sizes

    @Test func sizesFollowTheMeasuredBox() {
        #expect(ShelfSize.of(item(1, "Kettle", "kitchenware", (0.2, 0.25, 0.2))) == .small)
        #expect(ShelfSize.of(item(2, "Nightstand", "table", (0.45, 0.55, 0.4))) == .medium)
        #expect(ShelfSize.of(item(3, "Desk", "table", (1.2, 0.75, 0.6))) == .large)
        #expect(ShelfSize.of(item(4, "Bed", "bed", (1.4, 0.5, 2.0))) == .floor)
        #expect(ShelfSize.of(item(5, "Bookcase", "storage", (0.8, 1.8, 0.3))) == .floor)
        // Unmeasured items (added by photo) get a middling spot.
        #expect(ShelfSize.of(item(6, "Lamp", "lamp", (0, 0, 0))) == .medium)
    }

    // MARK: Packing

    @Test func smallThingsGoUpTopAndFurnitureOnTheFloor() {
        let items = [
            item(1, "Bed", "bed", (1.4, 0.5, 2.0), value: 30000),
            item(2, "Kettle", "kitchenware", (0.2, 0.25, 0.2), value: 2000),
            item(3, "Desk", "table", (1.2, 0.75, 0.6), value: 9000),
            item(4, "Nightstand", "table", (0.45, 0.55, 0.4), value: 4000),
        ]
        let shelves = InventoryBinder.shelves(items, capacity: 6, maxPerShelf: 3)
        // Kettle (1) + nightstand (2) + desk (3) share a plank, smallest first; the bed is on the floor.
        #expect(shelves.map(\.tier) == [.lower, .floor])
        #expect(shelves[0].items.map(\.name) == ["Kettle", "Nightstand", "Desk"])
        #expect(shelves[0].units == 6)
        #expect(shelves[1].items.map(\.name) == ["Bed"])
        // On their own, small things stand on an upper plank.
        #expect(InventoryBinder.shelves([items[1]], capacity: 6, maxPerShelf: 3).map(\.tier) == [.upper])
    }

    @Test func workDeskPacksTwoPerPlank() {
        // The demo's Work & study page: a monitor and three large pieces fill two planks, not three.
        let items = [
            item(1, "Office chair", "chair", (0.65, 1.1, 0.65), value: 42000),
            item(2, "Dell 27 inch monitor", "monitor", (0.6, 0.45, 0.2), value: 10000),
            item(3, "IKEA Micke desk", "table", (1.05, 0.75, 0.5), value: 6000),
            item(4, "Mesh office chair", "chair", (0.6, 1.0, 0.6), value: 3000),
        ]
        let shelves = InventoryBinder.shelves(items, capacity: 6, maxPerShelf: 3)
        #expect(shelves.map { $0.items.map(\.id) } == [[2, 1], [3, 4]])
        #expect(shelves.allSatisfy { $0.items.count >= 2 })
    }

    @Test func planksWrapByWidthAndCount() {
        // Seven small things on a phone: at most 3 per plank.
        let smalls = (1...7).map { item(UInt64($0), "Mug \($0)", "kitchenware", (0.1, 0.1, 0.1)) }
        let phone = InventoryBinder.shelves(smalls, capacity: 6, maxPerShelf: 3)
        #expect(phone.map(\.items.count) == [3, 3, 1])
        // Keeps the incoming order within a band.
        #expect(phone.flatMap(\.items).map(\.id) == Array(1...7))
        // On an iPad they fit two planks.
        let pad = InventoryBinder.shelves(smalls, capacity: 12, maxPerShelf: 6)
        #expect(pad.map(\.items.count) == [6, 1])

        // Large pieces are 3 units: two per phone plank.
        let larges = (1...3).map { item(UInt64($0), "Desk \($0)", "table", (1.0, 0.75, 0.6)) }
        #expect(InventoryBinder.shelves(larges, capacity: 6, maxPerShelf: 3).map(\.items.count) == [2, 1])
        // Floor pieces are 4 units: one per phone row, three on an iPad.
        let beds = (1...3).map { item(UInt64($0), "Bed \($0)", "bed", (1.4, 0.5, 2.0)) }
        #expect(InventoryBinder.shelves(beds, capacity: 6, maxPerShelf: 3).map(\.items.count) == [1, 1, 1])
        #expect(InventoryBinder.shelves(beds, capacity: 12, maxPerShelf: 6).map(\.items.count) == [3])
    }

    @Test func firstFitFillsEarlierPlanks() {
        // Smallest first, each on the first plank with room.
        let items = [
            item(1, "Chair", "chair", (0.5, 0.6, 0.5)),
            item(2, "Lamp", "lamp", (0.3, 0.3, 0.3)),
            item(3, "Stool", "chair", (0.4, 0.5, 0.4)),
            item(4, "Mug", "kitchenware", (0.1, 0.1, 0.1)),
        ]
        let shelves = InventoryBinder.shelves(items, capacity: 4, maxPerShelf: 3)
        // Sorted small first: Lamp(1) Mug(1) Chair(2) → 4 units; Stool on the next plank.
        #expect(shelves.map { $0.items.map(\.name) } == [["Lamp", "Mug", "Chair"], ["Stool"]])
    }

    @Test func emptyHallHasNoShelves() {
        #expect(InventoryBinder.shelves([], capacity: 6, maxPerShelf: 3).isEmpty)
    }

    @Test func demoBedroomPacksEveryItemOnce() {
        let items = DemoFixtures.inventory(owner: "me").items
        for entry in FunctionHall.halls(items) {
            let shelves = InventoryBinder.shelves(entry.items, capacity: 6, maxPerShelf: 3)
            let placed = shelves.flatMap(\.items).map(\.id)
            #expect(placed.sorted() == entry.items.map(\.id).sorted())
            #expect(shelves.allSatisfy { $0.units <= 6 && $0.items.count <= 3 })
            // The floor row is always at the bottom.
            #expect(shelves.map { $0.tier == .floor } == shelves.map { $0.tier == .floor }.sorted { !$0 && $1 })
        }
    }

    // MARK: Tabs

    @Test func tabsFollowHallOrderWithPageLabels() {
        let items = DemoFixtures.inventory(owner: "me").items
        let halls = FunctionHall.halls(items)
        let tabs = InventoryBinder.tabs(halls)
        #expect(tabs.map(\.hall) == halls.map(\.hall))
        #expect(tabs.map(\.page) == Array(0..<halls.count))
        let first = tabs[0]
        #expect(first.accessibilityLabel == "\(first.hall.name), \(first.count) pieces, page 1 of \(halls.count)")
        let one = BinderTab(hall: .music, count: 1, page: 2, pageCount: 3)
        #expect(one.accessibilityLabel == "Music, 1 piece, page 3 of 3")
    }

    @Test func pickedPageFallsBackToTheFirst() {
        let tabs = [BinderTab(hall: .sleep, count: 2, page: 0, pageCount: 2),
                    BinderTab(hall: .media, count: 1, page: 1, pageCount: 2)]
        #expect(InventoryBinder.page(.media, in: tabs) == .media)
        #expect(InventoryBinder.page(.music, in: tabs) == .sleep)
        #expect(InventoryBinder.page(nil, in: tabs) == .sleep)
        #expect(InventoryBinder.page(.sleep, in: []) == nil)
    }

    @Test func turningStopsAtTheCovers() {
        let tabs = [FunctionHall.sleep, .media, .music].enumerated().map {
            BinderTab(hall: $0.element, count: 1, page: $0.offset, pageCount: 3)
        }
        #expect(InventoryBinder.turn(from: .sleep, by: 1, in: tabs) == .media)
        #expect(InventoryBinder.turn(from: .media, by: -1, in: tabs) == .sleep)
        #expect(InventoryBinder.turn(from: .music, by: 1, in: tabs) == .music)
        #expect(InventoryBinder.turn(from: .sleep, by: -1, in: tabs) == .sleep)
        #expect(InventoryBinder.turn(from: nil, by: 1, in: tabs) == .media)
        #expect(InventoryBinder.turn(from: .sleep, by: 1, in: []) == nil)
    }

    @Test func neighboringHallsHaveDifferentTabColors() {
        let halls = FunctionHall.allCases
        for (a, b) in zip(halls, halls.dropFirst()) {
            #expect(InventoryBinder.tint(a) != InventoryBinder.tint(b), "\(a) and \(b)")
        }
    }
}
