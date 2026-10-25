import Foundation
import Testing
@testable import MooveKit

/// Lisa's real move (iPad, #412 follow-up): three scans named Bedroom of one apartment came out as
/// 47 boxes. Typical contents count once per room kind, so extra rooms of a kind add only a little.
@Suite struct PackingSameKindRoomsTests {
    func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double), room: UInt64,
              fragile: Bool = false) -> Item {
        Item(id: id, owner: "me", roomId: room, name: name, category: category, widthM: dims.0, heightM: dims.1,
             depthM: dims.2, disposition: .keep, fragile: fragile)
    }

    /// Three scanned rooms of the bedroom kind, a handful of things each.
    func threeBedrooms(mapped: Bool) -> (items: [Item], rooms: [UInt64: String]) {
        var items: [Item] = []
        var rooms: [UInt64: String] = [:]
        var id: UInt64 = 1
        for (scan, name) in ["Bedroom", "Bedroom 2", "Bedroom 3"].enumerated() {
            func add(_ n: String, _ c: String, _ d: (Double, Double, Double), fragile: Bool = false) {
                items.append(item(id, n, c, d, room: UInt64(scan + 1), fragile: fragile))
                if mapped { rooms[id] = name }
                id += 1
            }
            // RoomPlan's furniture plus what the detector finds in a lived-in bedroom (its own
            // categories: box, suitcase, backpack, trash can, fan, ...), at their bounding boxes.
            add("Bed", "bed", (1.6, 0.5, 2.1))
            add("Nightstand", "storage", (0.45, 0.55, 0.4))
            add("Dresser", "dresser", (1.2, 0.8, 0.5))
            add("Chair", "chair", (0.5, 0.9, 0.5))
            add("Table lamp", "lamp", (0.3, 0.5, 0.3), fragile: true)
            add("Framed print", "art", (0.4, 0.5, 0.03), fragile: true)
            add("Plant", "plant", (0.25, 0.4, 0.25))
            add("Cardboard box", "box", (0.46, 0.41, 0.46))
            add("Cardboard box", "box", (0.41, 0.32, 0.32))
            add("Suitcase", "suitcase", (0.45, 0.7, 0.28))
            add("Backpack", "backpack", (0.3, 0.45, 0.2))
            add("Trash can", "trash can", (0.3, 0.45, 0.3))
            add("Fan", "fan", (0.35, 0.6, 0.3))
            add("Laptop", "laptop", (0.35, 0.03, 0.25), fragile: true)
            add("Monitor", "monitor", (0.6, 0.45, 0.2), fragile: true)
        }
        return (items, rooms)
    }

    private func checkRules(_ p: PackingPlan) {
        for b in p.boxes {
            #expect(b.weightKg <= b.size.maxKg + 0.05, "box \(b.id) over its weight")
            if b.fragile { #expect(b.weightKg <= PackingPlanner.fragileMaxKg + 0.05, "fragile box \(b.id) over 8 kg") }
            if b.fragile { #expect(!b.kinds.contains("books"), "books with fragile in box \(b.id)") }
        }
    }

    /// Before: 24 boxes with the saved layout's three bedrooms (20 without a layout): every box,
    /// suitcase, fan and bin the detector found got a moving box of its own, and each bedroom got a
    /// full set of typical clothes, bedding and desk things. Now: 9 (8).
    @Test func threeBedroomScansStayAroundADozenBoxes() {
        for mapped in [true, false] {
            let move = threeBedrooms(mapped: mapped)
            let p = PackingPlanner.plan(items: move.items, destinationRoom: move.rooms)
            #expect(p.boxes.count <= 14, "mapped: \(mapped): \(p.boxes.count) boxes")
            checkRules(p)
            // Boxes, suitcases, bags, bins and fans ride as they are, as notes, not in boxes.
            for name in ["Cardboard box", "Suitcase", "Backpack", "Trash can", "Fan"] {
                #expect(p.furniture.contains { $0.name == name }, "\(name) rides as is")
                #expect(!p.boxes.contains { $0.contents.contains { $0.name == name } }, "\(name) not boxed")
            }
            // One household's typical clothes, not three: extra bedrooms get about a third.
            let shirts = p.boxes.flatMap(\.contents).filter { $0.name == "Folded shirts and sweaters" }.reduce(0) { $0 + $1.quantity }
            #expect(shirts > 0 && shirts <= 12 + 2 * 4)
            let paperbacks = p.boxes.flatMap(\.contents).filter { $0.name == "Paperbacks" }.reduce(0) { $0 + $1.quantity }
            #expect(paperbacks <= 8)
        }
        let demo = PackingPlanner.plan(items: DemoFixtures.inventory(owner: "me").items)
        #expect(demo.boxes.count <= 6)
    }

    @Test func extraRoomsOfAKindGetAThirdOfTheTypicalLines() {
        let units = PackingPlanner.typicalUnits(["Bedroom", "Bedroom 2", "Living room"], units: [], bookRooms: [])
        func qty(_ room: String, _ name: String) -> Int { units.filter { $0.room == room && $0.name == name }.reduce(0) { $0 + $1.quantity } }
        #expect(qty("Bedroom", "Folded shirts and sweaters") == 12)
        #expect(qty("Bedroom 2", "Folded shirts and sweaters") == 4)
        #expect(qty("Bedroom 2", "Spare sheet set") == 0) // a third of one rounds to nothing
        #expect(qty("Living room", "Throws and cushions") == 2) // another kind: full
    }
}
