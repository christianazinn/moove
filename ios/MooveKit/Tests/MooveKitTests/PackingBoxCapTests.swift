import Foundation
import Testing
@testable import MooveKit

/// Move shows at most about 12 boxes for a typical move (Lisa, #335): `PackingPlanner.boxCap`.
@Suite struct PackingBoxCapTests {
    func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double), room: UInt64 = 1,
              fragile: Bool = false, sentimental: Bool = false, _ disposition: Disposition = .keep) -> Item {
        Item(id: id, owner: "me", roomId: room, name: name, category: category, widthM: dims.0, heightM: dims.1,
             depthM: dims.2, disposition: disposition, fragile: fragile, maybeSentimental: sentimental)
    }

    /// A scan-like whole-home inventory: two bedrooms, living room, kitchen, office, bathroom.
    var wholeHome: (items: [Item], rooms: [UInt64: String]) {
        var items: [Item] = []
        var rooms: [UInt64: String] = [:]
        var id: UInt64 = 1
        func add(_ name: String, _ category: String, _ dims: (Double, Double, Double), _ room: String, fragile: Bool = false) {
            items.append(item(id, name, category, dims, fragile: fragile))
            rooms[id] = room
            id += 1
        }
        for bed in ["Primary bedroom", "Bedroom 2"] {
            add("Queen bed frame", "bed", (1.6, 0.4, 2.1), bed)
            add("Nightstand", "storage", (0.45, 0.55, 0.4), bed)
            add("Dresser", "dresser", (1.2, 0.8, 0.5), bed)
            add("Table lamp", "lamp", (0.3, 0.5, 0.3), bed, fragile: true)
            add("Framed photo", "art", (0.3, 0.4, 0.03), bed, fragile: true)
            add("Alarm clock", "electronics", (0.15, 0.1, 0.08), bed)
        }
        add("Sofa", "sofa", (2.1, 0.85, 0.95), "Living room")
        add("Coffee table", "table", (1.1, 0.45, 0.6), "Living room")
        add("TV", "television", (1.2, 0.7, 0.1), "Living room", fragile: true)
        add("Bookshelf", "storage", (0.8, 1.8, 0.3), "Living room")
        add("Box of paperbacks", "books", (0.4, 0.3, 0.3), "Living room")
        add("Vase", "decor", (0.2, 0.35, 0.2), "Living room", fragile: true)
        add("Floor lamp", "lamp", (0.3, 1.7, 0.3), "Living room")
        add("Speaker", "electronics", (0.2, 0.3, 0.2), "Living room")
        add("Dining table", "table", (1.6, 0.75, 0.9), "Kitchen")
        add("Kitchenware set", "kitchenware", (0.4, 0.3, 0.3), "Kitchen", fragile: true)
        add("Microwave", "microwave", (0.5, 0.3, 0.4), "Kitchen")
        add("Toaster", "appliance", (0.3, 0.2, 0.2), "Kitchen")
        add("Desk", "table", (1.2, 0.75, 0.6), "Office")
        add("Office chair", "chair", (0.65, 1.0, 0.65), "Office")
        add("Monitor", "electronics", (0.61, 0.45, 0.18), "Office", fragile: true)
        add("Printer", "electronics", (0.45, 0.25, 0.4), "Office")
        add("Desk lamp", "lamp", (0.2, 0.4, 0.2), "Office", fragile: true)
        add("Bath towels", "linens", (0.4, 0.2, 0.3), "Bathroom")
        return (items, rooms)
    }

    private func draft(_ kind: PackKind, room: String, fragile: Bool = false, id: UInt64? = nil, litres: Double, kg: Double) -> DraftBox {
        var d = DraftBox(size: .small, room: room, kinds: [kind], fragile: fragile, lightOnly: false)
        d.add(PackUnit(itemId: id, name: "\(kind.label) \(id ?? 0)", quantity: 1, litres: litres, kg: kg, room: room, kind: kind, fragile: fragile), quantity: 1)
        return d
    }

    private func checkRules(_ p: PackingPlan) {
        for b in p.boxes {
            #expect(b.weightKg <= b.size.maxKg + 0.05, "box \(b.id) over its weight")
            if b.fragile { #expect(b.weightKg <= PackingPlanner.fragileMaxKg + 0.05, "fragile box \(b.id) over 8 kg") }
            if b.fragile { #expect(!b.kinds.contains("books"), "books with fragile in box \(b.id)") }
        }
    }

    @Test func demoAndTypicalMovesStayUnderTheCap() {
        let demo = PackingPlanner.plan(items: DemoFixtures.inventory(owner: "me").items)
        #expect(demo.boxes.count <= PackingPlanner.boxCap)
        checkRules(demo)
        let tests = PackingPlannerTests()
        let big = PackingPlanner.plan(items: tests.bigMove, destinationRoom: tests.bigMoveRooms)
        #expect(big.boxes.count <= PackingPlanner.boxCap)
        checkRules(big)
    }

    /// A whole two-bedroom home is over the cap: its fragile things need a box per 8 kg and kitchen,
    /// books and breakables can't share, so it lands a few boxes over the weight floor. The cap passes
    /// still merge what they can, and every box keeps its limits.
    @Test func wholeHomeMergesWhatTheRulesAllow() {
        let home = wholeHome
        let p = PackingPlanner.plan(items: home.items, destinationRoom: home.rooms)
        checkRules(p)
        let kg = p.boxes.reduce(0) { $0 + $1.weightKg }
        let fragileKg = p.boxes.filter(\.fragile).reduce(0) { $0 + $1.weightKg }
        let floor = Int((fragileKg / PackingPlanner.fragileMaxKg).rounded(.up)) + Int(((kg - fragileKg) / 20).rounded(.up))
        #expect(p.boxes.count > PackingPlanner.boxCap)
        #expect(p.boxes.count <= floor + 4)
        // Towels share the bathroom box once over the cap.
        #expect(p.boxes.filter { $0.room == "Bathroom" }.count == 1)
    }

    @Test func overTheCapLeftoversShareAMiscBox() {
        // 14 light, half-empty boxes in 14 rooms: nothing shares a room, so only the Misc pass helps.
        let boxes = (0..<14).map { i in draft(.decor, room: "Room \(i)", id: UInt64(i + 1), litres: 4, kg: 1) }
        let out = PackingPlanner.consolidate(boxes)
        #expect(out.count == PackingPlanner.boxCap)
        let misc = out.filter { $0.room == PackingPlanner.miscRoom }
        #expect(!misc.isEmpty)
        // Each line still says which room it goes to.
        #expect(misc.allSatisfy { $0.lines.allSatisfy { $0.room?.hasPrefix("Room ") == true } })
        let numbered = PackingPlanner.finalize(out).map(\.box)
        let line = numbered.first { $0.room == PackingPlanner.miscRoom }?.contents.first
        #expect(line?.reason?.hasPrefix("Room ") == true)
        // Under the cap nothing crosses rooms.
        #expect(PackingPlanner.consolidate(Array(boxes.prefix(10))).allSatisfy { $0.room != PackingPlanner.miscRoom })
    }

    @Test func capNeverMixesFragileOverEightKilos() {
        let boxes = (0..<16).map { i in draft(.decor, room: "Room \(i % 3)", fragile: true, id: UInt64(i + 1), litres: 10, kg: 5) }
        let out = PackingPlanner.consolidate(boxes)
        #expect(out.allSatisfy { $0.kg <= PackingPlanner.fragileMaxKg + 1e-9 })
        #expect(out.count == 16) // 5 kg each: no two fit in one fragile box
    }
}
