import Foundation
import Testing
@testable import MooveKit

@Suite struct PackingPlannerTests {
    let items = DemoFixtures.inventory(owner: "me").items
    var plan: PackingPlan { PackingPlanner.plan(items: items) }

    func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double),
              fragile: Bool = false, sentimental: Bool = false, _ disposition: Disposition = .keep) -> Item {
        Item(id: id, owner: "me", roomId: 1, name: name, category: category, widthM: dims.0, heightM: dims.1,
             depthM: dims.2, disposition: disposition, fragile: fragile, maybeSentimental: sentimental)
    }

    /// A bigger move across rooms: kitchen, books, a TV, a sofa.
    var bigMove: [Item] {
        [
            item(1, "Sofa", "sofa", (2.1, 0.85, 0.95)),
            item(2, "Dining table", "table", (1.6, 0.75, 0.9)),
            item(3, "Kitchenware set", "kitchenware", (0.4, 0.3, 0.3), fragile: true),
            item(4, "Box of paperbacks", "books", (0.4, 0.3, 0.3)),
            item(5, "Desk lamp", "lamp", (0.2, 0.4, 0.2), fragile: true),
            item(6, "Queen bed frame", "bed", (1.6, 0.4, 2.1)),
            item(7, "Wall art", "art", (0.8, 0.6, 0.04), fragile: true),
            item(8, "Dresser", "dresser", (1.2, 0.8, 0.5)),
            item(9, "Old letters", "decor", (0.3, 0.1, 0.2), sentimental: true, .undecided),
        ]
    }

    var bigMoveRooms: [UInt64: String] {
        [1: "Living room", 2: "Dining room", 3: "Kitchen", 4: "Office", 5: "Office", 6: "Primary bedroom", 7: "Living room", 8: "Primary bedroom"]
    }

    @Test func demoPlanIsSane() {
        let p = plan
        #expect(p.boxes.count >= 4)
        #expect(p.boxes.filter(\.openFirst).count == 1)
        #expect(p.boxes.contains { $0.keepWithYou })
        #expect(p.boxes.map(\.id) == Array(1...p.boxes.count))

        // Big furniture gets notes, not boxes.
        let bed = p.furniture.first { $0.id == 10 }
        #expect(bed != nil)
        #expect(bed?.steps.contains { $0.contains("bolts") } == true)
        #expect(p.furniture.contains { $0.id == 15 })
        let boxedIds = Set(p.boxes.flatMap(\.contents).compactMap(\.itemId))
        #expect(!boxedIds.contains(10))
        #expect(!boxedIds.contains(15))

        // Only things being moved show up.
        let moving = Set(items.filter { $0.disposition == .keep || ($0.disposition == .undecided && $0.maybeSentimental) }.map(\.id))
        #expect(boxedIds.union(p.furniture.map(\.id)).isSubset(of: moving))
        #expect(!boxedIds.contains(11)) // sold office chair
        #expect(!boxedIds.contains(17)) // trashed mirror

        // Typical contents are marked so the UI can label them.
        #expect(p.boxes.flatMap(\.contents).contains { $0.itemId == nil })
        #expect(p.boxes.first { $0.openFirst }?.contents.allSatisfy { $0.itemId == nil } == true)
    }

    // MARK: Filling boxes (fewer boxes)

    @Test func demoPlanUsesFewBoxes() {
        let p = plan
        // Before consolidation the demo came out as 16 boxes, most of them half empty.
        #expect(p.boxes.count <= 9)
        #expect(p.boxes.filter { !$0.openFirst && !$0.keepWithYou }.count <= 7)
        let living = p.boxes.filter { $0.room == "Living room" }
        #expect(living.count == 2)
        let padded = try! #require(living.first { $0.fragile })
        #expect(padded.reason == "Throws pad the vases, under 8 kg")
        #expect(padded.contents.contains { $0.name == "Throws and cushions" })
        #expect(padded.contents.contains { $0.name == "Vases and ceramics" })
        // Books are estimated once (one scanned room), in the living room, with the board games.
        let books = p.boxes.filter { $0.kinds.contains("books") }
        #expect(books.count == 1)
        #expect(books.first?.room == "Living room")
        #expect(books.first?.contents.contains { $0.name == "Board games and media" } == true)
        // Bedding and shoes ride under the hanging clothes.
        let wardrobe = try! #require(p.boxes.first { $0.size == .wardrobe })
        #expect(wardrobe.kinds.contains("hanging") && wardrobe.kinds.contains("bedding"))
        #expect(wardrobe.reason == "On hangers, soft things packed below")
    }

    @Test(arguments: [0, 1, 2]) func consolidatedBoxesKeepTheRules(input: Int) {
        let p = [plan, PackingPlanner.plan(items: bigMove, destinationRoom: bigMoveRooms), PackingPlanner.plan(items: bigMove)][input]
        let soft: Set<String> = ["clothes", "shoes", "bedding", "hanging"]
        for box in p.boxes {
            let kinds = Set(box.kinds)
            #expect(box.weightKg <= box.size.maxKg + 1e-9, "\(box.title)")
            if box.fragile { #expect(box.weightKg <= PackingPlanner.fragileMaxKg + 1e-9, "\(box.title)") }
            // Never heavy books with fragile things.
            if box.fragile { #expect(!kinds.contains("books"), "\(box.title)") }
            // Kitchen only with kitchen, or soft padding around fragile dishes.
            if kinds.contains("kitchen") {
                #expect(kinds.subtracting(["kitchen"]).isSubset(of: ["clothes", "bedding"]), "\(box.title)")
                if kinds.count > 1 { #expect(box.fragile, "\(box.title)") }
            }
            if kinds.contains("bathroom") { #expect(kinds == ["bathroom"], "\(box.title)") }
            if box.size == .wardrobe { #expect(kinds.isSubset(of: soft), "\(box.title)") }
            // The tote and the keep-with-you box stay on their own.
            if kinds.contains("openFirst") { #expect(kinds == ["openFirst"] && box.openFirst) }
            if kinds.contains("keepWithYou") { #expect(kinds == ["keepWithYou"] && box.keepWithYou) }
            #expect(box.contents.allSatisfy { $0.quantity > 0 })
        }
        #expect(p.boxes.filter(\.openFirst).count == 1)
        #expect(p.boxes.filter(\.keepWithYou).count == 1)
    }

    private func draft(_ kind: PackKind, _ size: BoxSize, room: String = "Office", fragile: Bool = false,
                       _ lines: [(String, Int, Double, Double)]) -> DraftBox {
        var d = DraftBox(size: size, room: room, kinds: [kind], fragile: fragile, lightOnly: false)
        for (name, qty, litres, kg) in lines {
            d.add(PackUnit(itemId: nil, name: name, quantity: qty, litres: litres, kg: kg, room: room, kind: kind, fragile: fragile), quantity: qty)
        }
        return d
    }

    @Test func mergesUpsizeSmallToMediumInsteadOfAddingABox() {
        let books = draft(.books, .small, [("Books", 20, 1, 0.5)])     // 20 L, 10 kg
        let desk = draft(.desk, .small, [("Papers", 1, 18, 4)])        // 18 L, 4 kg
        let out = PackingPlanner.consolidate([books, desk])
        #expect(out.count == 1)
        #expect(out.first?.size == .medium)
        #expect(out.first?.kinds == [.books, .desk])
        #expect(abs((out.first?.kg ?? 0) - 14) < 1e-9)
        // Too heavy together: they stay two boxes.
        let heavy = draft(.books, .small, [("Books", 30, 0.6, 0.5)])   // 18 L, 15 kg
        #expect(PackingPlanner.consolidate([heavy, desk, desk]).count == 2)
    }

    @Test func kindRulesDecideWhatShares() {
        let pots = draft(.kitchen, .medium, room: "Kitchen", [("Pots", 3, 6, 1.2)])
        let dishes = draft(.kitchen, .dishPack, room: "Kitchen", fragile: true, [("Plates", 6, 2.5, 0.5)])
        let clothes = draft(.clothes, .large, room: "Kitchen", [("Shirts", 5, 1.4, 0.3)])
        let towels = draft(.bedding, .large, room: "Kitchen", [("Tea towels", 4, 2, 0.2)])
        let vases = draft(.decor, .medium, room: "Kitchen", fragile: true, [("Vases", 2, 5, 0.8)])
        let books = draft(.books, .small, room: "Kitchen", [("Books", 10, 1, 0.5)])
        // Kitchen with kitchen, and soft things may pad fragile dishes; never clothes with pots.
        #expect(pots.combined(with: dishes, relaxed: false) != nil)
        #expect(dishes.combined(with: towels, relaxed: false)?.padding?.soft == "tea towels")
        #expect(pots.combined(with: clothes, relaxed: false) == nil)
        #expect(pots.combined(with: clothes, relaxed: true) == nil)
        // Never books with fragile things, even in the sparse pass.
        #expect(books.combined(with: vases, relaxed: true) == nil)
        #expect(vases.combined(with: books, relaxed: false) == nil)
        // Soft things pad decor; the merged box is fragile and says so.
        let padded = try! #require(towels.combined(with: vases, relaxed: false))
        #expect(padded.fragile)
        #expect(Reasons.box(padded) == "Tea towels pad the vases, under 8 kg")
        // Different rooms never share; the special boxes never take anything in.
        var other = vases
        other.room = "Bedroom"
        #expect(towels.combined(with: other, relaxed: true) == nil)
        let tote = DraftBox(size: .tote, room: "Open first", kinds: [.openFirst], fragile: false, lightOnly: false)
        #expect(tote.combined(with: towels, relaxed: true) == nil)
    }

    @Test func fragileMergesStayUnderEightKilos() {
        let dishes = draft(.kitchen, .dishPack, room: "Kitchen", fragile: true, [("Plates", 12, 2.5, 0.55)]) // 6.6 kg
        let pots = draft(.kitchen, .medium, room: "Kitchen", [("Pots", 3, 6, 1.2)])                          // 3.6 kg
        #expect(dishes.combined(with: pots, relaxed: false) == nil)
        #expect(PackingPlanner.consolidate([dishes, pots]).count == 2)
    }

    @Test func sparseBoxesJoinAnotherBoxOfTheirRoom() {
        // Desk papers don't usually go with clothes, but a nearly empty box of them does.
        let clothes = draft(.clothes, .large, room: "Bedroom", [("Shirts", 20, 1.4, 0.3)])
        let desk = draft(.desk, .small, room: "Bedroom", [("Papers", 1, 6, 3)])
        #expect(clothes.combined(with: desk, relaxed: false) == nil)
        let out = PackingPlanner.consolidate([clothes, desk])
        #expect(out.count == 1)
        #expect(out.first?.kinds == [.desk, .clothes])
    }

    @Test func typicalBooksAreCountedOncePerScannedRoom() {
        // Demo: one scanned bedroom, headed for a bedroom and a living room: one room's worth of books.
        let rooms = Set(plan.boxes.filter { $0.kinds.contains("books") }.map(\.room))
        #expect(rooms == ["Living room"])
        // Two scanned rooms: both get their books.
        var two = items
        for i in two.indices where two[i].id == 13 { two[i].roomId = 2 } // the Kallax came from a second room
        let p = PackingPlanner.plan(items: two)
        let bookRooms = Set(p.boxes.filter { $0.kinds.contains("books") }.map(\.room))
        #expect(bookRooms == ["Bedroom", "Living room"])
    }

    @Test func estimatedContentsAreMarked() {
        let p = plan
        let shade = try! #require(p.boxes.first { $0.contents.contains { $0.itemId == 14 } })
        #expect(!shade.estimatedOnly)
        #expect(shade.scannedLineCount == 1)
        #expect(shade.contents.first { $0.itemId == 14 }?.estimated == false)
        #expect(p.boxes.filter(\.estimatedOnly).count == p.boxes.count - 1)
        #expect(p.boxes.flatMap(\.contents).filter(\.estimated).allSatisfy { $0.itemId == nil && $0.reason == nil })
    }

    @Test func sentimentalItemsTravelWithYou() {
        // The demo's one sentimental item is the guitar; add small framed photos so a box gets used too.
        let items = items + [item(99, "Framed photos", "decor", (0.4, 0.5, 0.05), fragile: true, sentimental: true, .undecided)]
        let p = PackingPlanner.plan(items: items)
        let keepIds = Set(p.boxes.filter(\.keepWithYou).flatMap(\.contents).compactMap(\.itemId))
        let carIds = Set(p.furniture.filter { $0.room == "Keep with you" }.map(\.id))
        for sentimental in items.filter({ $0.maybeSentimental && $0.disposition == .undecided }) {
            #expect(keepIds.contains(sentimental.id) || carIds.contains(sentimental.id), "\(sentimental.name)")
        }
        #expect(keepIds.contains(99)) // framed photos fit a box
        #expect(carIds.contains(18)) // the guitar rides in the car
        for box in p.boxes where box.keepWithYou {
            #expect(box.room == "Keep with you")
            #expect(box.title.hasPrefix("Keep with you"))
        }
    }

    @Test func floorLampShadeIsBoxedAndBaseIsANote() {
        let p = plan
        #expect(p.furniture.contains { $0.id == 14 })
        #expect(p.boxes.contains { box in box.fragile && box.contents.contains { $0.itemId == 14 } })
    }

    @Test(arguments: [false, true]) func noBoxIsOverweightOrMixesFragileAndHeavy(big: Bool) {
        let p = big ? PackingPlanner.plan(items: bigMove, destinationRoom: bigMoveRooms) : plan
        #expect(!p.boxes.isEmpty)
        for box in p.boxes {
            #expect(box.weightKg <= box.size.maxKg, "\(box.title)")
            #expect(box.weightKg <= 20, "\(box.title)")
            #expect(box.weightKg > 0, "\(box.title)")
            if box.fragile {
                #expect(box.weightKg <= PackingPlanner.fragileMaxKg, "\(box.title)")
                #expect(box.thisSideUp)
            }
            #expect(!box.contents.isEmpty)
            #expect(box.contents.allSatisfy { $0.quantity > 0 })
        }
    }

    @Test(arguments: [false, true]) func boxesAreGroupedByRoom(big: Bool) {
        let p = big ? PackingPlanner.plan(items: bigMove, destinationRoom: bigMoveRooms) : plan
        let rooms = big ? bigMoveRooms : [:]
        for box in p.boxes where !box.openFirst && !box.keepWithYou {
            #expect(box.title.hasPrefix(box.room + " · "))
            for content in box.contents {
                if let id = content.itemId, let room = rooms[id] { #expect(room == box.room, "\(content.name)") }
            }
        }
        // Within a stage, each room's boxes are numbered together.
        for step in p.schedule {
            let roomsInOrder = step.boxIds.compactMap { id in p.boxes.first { $0.id == id }?.room }
            var seen: [String] = []
            for room in roomsInOrder where seen.last != room {
                #expect(!seen.contains(room), "\(room) split in \(step.title)")
                seen.append(room)
            }
        }
    }

    @Test func bigMoveUsesTheRightBoxes() {
        let p = PackingPlanner.plan(items: bigMove, destinationRoom: bigMoveRooms)
        #expect(Set(p.furniture.map(\.id)).isSuperset(of: [1, 2, 6, 8]))
        let rooms = Set(p.boxes.map(\.room))
        #expect(rooms.isSuperset(of: ["Kitchen", "Office", "Living room", "Primary bedroom", "Open first", "Keep with you"]))
        // Wall art goes in a picture box; the sentimental letters ride with you.
        #expect(p.boxes.first { $0.contents.contains { $0.itemId == 7 } }?.size == .picture)
        #expect(p.boxes.first { $0.contents.contains { $0.itemId == 9 } }?.keepWithYou == true)
        // A bigger move needs a bigger truck than the demo.
        #expect(p.truck.loadM3 > plan.truck.loadM3)
        #expect(p.supplies.contains { $0.name == "Moving blankets" && $0.quantity == p.furniture.count })
    }

    @Test func scheduleNumbersBoxesInPackingOrder() {
        let p = plan
        #expect(p.schedule.map(\.daysBeforeMove) == [14, 7, 2, 0])
        #expect(p.schedule.flatMap(\.boxIds) == p.boxes.map(\.id))
        let movingDay = Set(p.schedule.last?.boxIds ?? [])
        for box in p.boxes where box.openFirst || box.keepWithYou { #expect(movingDay.contains(box.id)) }
        #expect(p.boxes.last?.keepWithYou == true)
    }

    @Test func truckFitsTheDemo() {
        let t = plan.truck
        #expect([TruckSize.cargoVan, .ft10].contains(t.truck))
        #expect(t.trucks == 1)
        #expect(t.movers == 2)
        #expect(t.loadM3 > 1.3) // at least the bed
        #expect(t.loadM3 <= t.truck.capacityM3 * 0.85)
        #expect(t.moverHours >= 1.5)
        #expect(t.costLowCents > 0)
        #expect(t.costLowCents < t.costHighCents)
        #expect(VolumeEstimator.estimate(items: items, boxes: plan.boxes) == t)
    }

    @Test func truckScalesUp() {
        let sofas = (0..<40).map { item(UInt64(100 + $0), "Sofa \($0)", "sofa", (2.2, 0.9, 1.0)) }
        let t = VolumeEstimator.estimate(items: sofas, boxes: [])
        #expect(t.truck == .ft26)
        #expect(t.trucks >= 2)
        #expect(t.movers == 3)
        #expect(t.costLowCents < t.costHighCents)
    }

    @Test func suppliesMatchTheBoxes() {
        let p = plan
        let boxLines = p.supplies.filter { line in BoxSize.allCases.contains { $0.label == line.name } }
        #expect(boxLines.reduce(0) { $0 + $1.quantity } == p.boxes.count)
        let tape = p.supplies.first { $0.name == "Packing tape rolls" }?.quantity
        #expect(tape == (p.boxes.count + 7) / 8)
        #expect(p.supplies.contains { $0.name == "Mattress bag" })
        #expect(p.supplies.contains { $0.name == "Moving blankets" && $0.quantity == p.furniture.count })
        #expect(p.supplies.contains { $0.name == "Permanent markers" })
    }

    @Test func deterministic() {
        #expect(PackingPlanner.plan(items: items) == PackingPlanner.plan(items: items.reversed()))
        #expect(PackingPlanner.plan(items: bigMove, destinationRoom: bigMoveRooms)
            == PackingPlanner.plan(items: bigMove.reversed(), destinationRoom: bigMoveRooms))
    }

    @Test func nothingMovingMeansAnEmptyPlan() {
        for input in [[], items.filter({ $0.disposition == .sell || $0.disposition == .trash })] {
            let p = PackingPlanner.plan(items: input)
            #expect(p.boxes.isEmpty)
            #expect(p.furniture.isEmpty)
            #expect(p.supplies.isEmpty)
            #expect(p.schedule.isEmpty)
            #expect(p.truck == .zero)
            #expect(p.truck.costLowCents == 0 && p.truck.trucks == 0)
        }
        #expect(VolumeEstimator.estimate(items: [], boxes: []) == .zero)
    }

    @Test func boxSizesAreReal() {
        for size in BoxSize.allCases {
            #expect(size.maxKg <= 20)
            #expect(size.volumeM3 > 0)
            #expect(!size.label.isEmpty)
        }
        #expect(TruckSize.allCases.map(\.capacityM3) == TruckSize.allCases.map(\.capacityM3).sorted())
        #expect(TruckSize.ft10.label == "10 ft truck")
    }
}
