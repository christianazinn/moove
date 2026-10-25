import Foundation
import Testing
@testable import MooveKit

/// Reasons, bought deliveries, the shared room palette and printable labels for the Pack screen.
@Suite struct PackingReasonsTests {
    let items = DemoFixtures.inventory(owner: "me").items

    func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double),
              fragile: Bool = false, sentimental: Bool = false, _ disposition: Disposition = .keep) -> Item {
        Item(id: id, owner: "me", roomId: 1, name: name, category: category, widthM: dims.0, heightM: dims.1,
             depthM: dims.2, disposition: disposition, fragile: fragile, maybeSentimental: sentimental)
    }

    var move: [Item] {
        [
            item(1, "Sofa", "sofa", (2.1, 0.85, 0.95)),
            item(2, "Dining table", "table", (1.6, 0.75, 0.9)),
            item(3, "Kitchenware set", "kitchenware", (0.4, 0.3, 0.3), fragile: true),
            item(4, "Box of paperbacks", "books", (0.4, 0.3, 0.3)),
            item(6, "Queen bed frame", "bed", (1.6, 0.4, 2.1)),
            item(9, "Old letters", "decor", (0.3, 0.1, 0.2), sentimental: true, .undecided),
            item(10, "Grandma's armchair", "decor", (0.9, 1.0, 0.9), sentimental: true, .undecided),
        ]
    }

    let rooms: [UInt64: String] = [1: "Living room", 2: "Dining room", 3: "Kitchen", 4: "Bedroom 2", 6: "Bedroom 2"]

    // MARK: Reasons

    @Test func everyBoxAndScannedLineHasAShortReason() {
        for p in [PackingPlanner.plan(items: items), PackingPlanner.plan(items: move, destinationRoom: rooms)] {
            for box in p.boxes {
                #expect(!box.reason.isEmpty, "\(box.title)")
                #expect(!box.roomReason.isEmpty, "\(box.title)")
                #expect(box.reason.count <= 60, "\(box.reason)")
                #expect(!box.kinds.isEmpty)
                for line in box.contents {
                    if line.itemId == nil {
                        #expect(line.reason == nil, "typical line \(line.name)")
                    } else {
                        let reason = try! #require(line.reason)
                        #expect(reason.contains("Box \(box.id)"), "\(reason)")
                        #expect(reason.count <= 70, "\(reason)")
                    }
                }
            }
            for note in p.furniture {
                #expect(!note.reason.isEmpty && note.reason.count <= 60, "\(note.reason)")
                #expect(!note.roomReason.isEmpty)
            }
        }
    }

    @Test func fragileBoxesSayWhy() {
        let p = PackingPlanner.plan(items: move, destinationRoom: rooms)
        let kitchen = try! #require(p.boxes.first { $0.fragile && $0.contents.contains { $0.itemId == 3 } })
        #expect(kitchen.fragile)
        #expect(kitchen.reason == "Fragile: wrapped, nothing heavy, under 8 kg")
        #expect(kitchen.contents.first { $0.itemId == 3 }?.reason?.hasPrefix("Kitchen → Box \(kitchen.id)") == true)
        // The scanned paperbacks fill bigger boxes with the room's desk things and clothes.
        let books = p.boxes.filter { $0.kinds.contains("books") }
        #expect(!books.isEmpty)
        #expect(books.allSatisfy { !$0.fragile && $0.weightKg <= $0.size.maxKg && !$0.reason.isEmpty })
    }

    @Test func furnitureNotesSayWhyAndWhere() {
        let p = PackingPlanner.plan(items: move, destinationRoom: rooms)
        let sofa = try! #require(p.furniture.first { $0.id == 1 })
        #expect(sofa.reason == "Too big for a box: legs off, wrap in blankets")
        #expect(sofa.roomReason == "Goes to Living room (from your saved layout)")
        let bed = try! #require(p.furniture.first { $0.id == 6 })
        #expect(bed.roomReason == "Goes to Bedroom 2 (from your saved layout)")
        // The sentimental armchair can't be boxed: it rides in the car.
        let chair = try! #require(p.furniture.first { $0.id == 10 })
        #expect(chair.room == "Keep with you")
        #expect(chair.reason == "Sentimental: rides with you")
    }

    @Test func roomsWithoutALayoutAreGuesses() {
        let p = PackingPlanner.plan(items: move)
        for box in p.boxes where !box.openFirst && !box.keepWithYou {
            #expect(box.roomReason == "Room not set yet: best guess from what it is", "\(box.title)")
        }
        let mapped = PackingPlanner.plan(items: move, destinationRoom: rooms)
        let kitchen = try! #require(mapped.boxes.first { $0.room == "Kitchen" })
        #expect(kitchen.roomReason == "Goes to Kitchen (from your saved layout)")
        #expect(mapped.boxes.first { $0.openFirst }?.roomReason == "Load it last, open it first")
        #expect(mapped.boxes.first { $0.keepWithYou }?.roomReason == "Rides with you, not on the truck")
    }

    @Test func undecidedSentimentalStillGoesWithYou() {
        let p = PackingPlanner.plan(items: move, destinationRoom: rooms)
        let keep = try! #require(p.boxes.first { $0.keepWithYou })
        let letters = try! #require(keep.contents.first { $0.itemId == 9 })
        #expect(letters.reason == "Box \(keep.id) · sentimental, rides with you")
    }

    // MARK: Bought pieces

    private func shopping(_ id: UInt64, _ name: String, _ category: String, _ status: ShoppingStatus, deal: UInt64? = nil) -> ShoppingItem {
        ShoppingItem(id: id, owner: "me", name: name, category: category, status: status, chosenDealId: deal,
                     createdAt: Date(timeIntervalSince1970: Double(id)))
    }

    @Test func boughtPiecesAreDeliveredNotPacked() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [shopping(1, "Desk", "desk", .bought, deal: 10), shopping(2, "Rug", "rug", .found, deal: 20),
                           shopping(3, "Lamp", "lamp", .searching)]
        s.deals = [Deal(id: 10, owner: "me", shoppingItemId: 1, source: "ikea", title: "MICKE desk, white", priceCents: 9_900,
                        sellerInfo: "IKEA · new"),
                   Deal(id: 20, owner: "me", shoppingItemId: 2, source: "fb", title: "Wool rug", priceCents: 4_000)]
        // Only the bought desk comes; the rug and lamp are still being shopped for.
        #expect(s.boughtPieces.map(\.item.id) == [1])
        let layoutId = BoughtFurniture.layoutId(forShoppingItem: 1)
        let p = PackingPlanner.plan(items: move, destinationRoom: rooms.merging([layoutId: "Office"]) { a, _ in a },
                                    bought: s.boughtPieces)
        let desk = try! #require(p.delivered.first)
        #expect(p.delivered.count == 1)
        #expect(desk.title == "MICKE desk, white")
        #expect(desk.seller == "IKEA")
        #expect(desk.room == "Office")
        #expect(desk.reason == "Bought: ships straight to the new place, nothing to pack")
        #expect(desk.roomReason == "Goes to Office (from your saved layout)")
        #expect(desk.voxelSpec.category == "desk")
        // Not boxed, not a furniture note, not on the truck.
        #expect(!p.boxes.flatMap(\.contents).contains { $0.itemId == 1 && $0.name.contains("MICKE") })
        #expect(!p.furniture.contains { $0.name.contains("MICKE") || $0.name == "Desk" })
        #expect(p.truck == PackingPlanner.plan(items: move, destinationRoom: rooms).truck)
    }

    @Test func offlineDemoDeliversTheBoughtMattress() {
        let s = DemoFixtures.demo(owner: "me")
        let p = PackingPlanner.plan(items: s.items, bought: s.boughtPieces)
        #expect(p.delivered.map(\.name) == ["Mattress"])
        #expect(p.delivered.first?.room == "Bedroom")
    }

    @Test func boughtWithoutLayoutGuessesARoom() {
        let piece = BoughtPiece(item: shopping(5, "Bed frame", "bed", .bought))
        let p = PackingPlanner.plan(items: [], bought: [piece])
        #expect(p.boxes.isEmpty)
        #expect(p.delivered.map(\.room) == ["Bedroom"])
        #expect(p.delivered.first?.roomReason == "Room not set yet: best guess from what it is")
        #expect(p.delivered.first?.seller == "")
        #expect(p.delivered.first?.title == "Bed frame")
    }

    @Test func sellerReadsWell() {
        let d = Deal(id: 1, owner: "me", shoppingItemId: 1, source: "craigslist", title: "t", priceCents: 1,
                     sellerInfo: "Dana · like new · 2 mi")
        #expect(PackingPlanner.seller(d) == "Craigslist · Dana")
    }

    // MARK: Palette

    @Test func paletteIsDeterministicAndDistinct() {
        #expect(PackingPalette.color(forRoom: "Kitchen") == PackingPalette.color(forRoom: "kitchen"))
        #expect(PackingPalette.color(forRoom: "Bedroom") != PackingPalette.color(forRoom: "Bedroom 2"))
        #expect(PackingPalette.color(forRoom: "Open first") == PackingPalette.openFirst)
        #expect(PackingPalette.color(forRoom: "Keep with you") == PackingPalette.keepWithYou)
        let common = ["Living room", "Kitchen", "Bedroom", "Dining room", "Office", "Bathroom"]
        #expect(Set(common.map(PackingPalette.color(forRoom:))).count == common.count)
        for room in ["Den", "Nursery", "Sunroom", "Garage", "Primary bedroom"] {
            #expect(PackingPalette.roomColors.contains(PackingPalette.color(forRoom: room)))
        }
        #expect(PackingPalette.hex(0x9CC08A) == "#9CC08A")
        #expect(PackingPalette.hex(0x0000FF) == "#0000FF")
    }

    @Test func inkReadsOnEveryColor() {
        func lum(_ c: VoxelColor) -> Double {
            let (r, g, b) = PackingPalette.rgb(c)
            func ch(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
        }
        for c in PackingPalette.roomColors + [PackingPalette.openFirst, PackingPalette.keepWithYou] {
            #expect((lum(c) + 0.05) / (lum(PackingPalette.ink) + 0.05) >= 4.5, "\(PackingPalette.hex(c))")
        }
    }

    // MARK: Labels

    @Test func labelsCarryNumberRoomBadgesAndQR() {
        let p = PackingPlanner.plan(items: move, destinationRoom: rooms)
        let labels = BoxLabel.labels(for: p.boxes)
        #expect(labels.map(\.id) == p.boxes.map(\.id))
        for (label, box) in zip(labels, p.boxes) {
            #expect(label.qrPayload == "moove://box/\(box.id)")
            #expect(label.room == box.room.uppercased())
            #expect(label.roomColor == PackingPalette.color(forRoom: box.room))
            #expect(label.contents.count <= BoxLabel.maxContentLines)
            #expect(label.contents.count + label.moreCount == box.contents.count)
            #expect(label.badges.contains(.fragile) == box.fragile)
            #expect(label.badges.contains(.thisSideUp) == box.thisSideUp)
            #expect(label.sizeGlyph == box.size.glyph)
        }
        let first = try! #require(labels.first { $0.id == 1 })
        #expect(first.number == "01")
        let keep = try! #require(labels.first { $0.badges.contains(.keepWithYou) })
        #expect(!keep.badges.contains(.openFirst))
        #expect(labels.contains { $0.badges.first == .openFirst })
    }

    @Test func labelsListScannedThingsFirst() {
        let p = PackingPlanner.plan(items: move, destinationRoom: rooms)
        let box = try! #require(p.boxes.first { $0.contents.contains { $0.itemId == 9 } })
        #expect(BoxLabel(box: box).contents.first == "Old letters")
    }

    @Test func layoutsPlaceLabelsOnThePage() {
        #expect(BoxLabelLayout.fourBySix.pageCount(labels: 3) == 3)
        #expect(BoxLabelLayout.letterTwoUp.pageCount(labels: 3) == 2)
        #expect(BoxLabelLayout.letterTwoUp.pageCount(labels: 0) == 0)
        let top = BoxLabelLayout.letterTwoUp.slot(0), bottom = BoxLabelLayout.letterTwoUp.slot(1), next = BoxLabelLayout.letterTwoUp.slot(2)
        #expect(top.page == 0 && bottom.page == 0 && next.page == 1)
        #expect(top.rect.y + top.rect.height <= bottom.rect.y)
        #expect(bottom.rect.y + bottom.rect.height <= 792)
        #expect(next.rect == top.rect)
        let card = BoxLabelLayout.fourBySix.slot(4)
        #expect(card.page == 4)
        #expect(card.rect.width <= 288 && card.rect.height <= 432)
    }

    @Test func typicalLinesHaveAVoxelCategory() {
        let p = PackingPlanner.plan(items: items)
        let lines = p.boxes.flatMap(\.contents)
        #expect(lines.contains { $0.category == "books" })
        #expect(lines.allSatisfy { BoughtFurniture.voxelCategories.contains($0.category) })
    }
}
