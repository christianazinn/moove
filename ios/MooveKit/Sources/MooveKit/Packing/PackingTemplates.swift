import Foundation

// What goes in boxes, by kind, and the typical contents Moove adds for each
// destination room. A scan only sees the big things, so without these a
// bedroom move would come out as two boxes. Typical lines carry itemId == nil.

/// What a box holds. The order is the packing order inside a stage.
enum PackKind: Int, CaseIterable, Comparable, Sendable {
    case books, decor, lamps, desk, electronics, clothes, shoes, bedding, misc, kitchen, bathroom, hanging
    case openFirst, keepWithYou

    static func < (a: PackKind, b: PackKind) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .books: return "books"
        case .decor: return "decor"
        case .lamps: return "lamps"
        case .desk: return "desk supplies"
        case .electronics: return "electronics"
        case .clothes: return "folded clothes"
        case .shoes: return "shoes"
        case .bedding: return "bedding"
        case .misc: return "odds and ends"
        case .kitchen: return "kitchen"
        case .bathroom: return "bathroom"
        case .hanging: return "hanging clothes"
        case .openFirst: return "first-night essentials"
        case .keepWithYou: return "photos and valuables"
        }
    }

    /// Box sizes to try, best first. Heavy things go in small boxes.
    var sizes: [BoxSize] {
        switch self {
        case .books, .desk: return [.small, .medium]
        case .decor: return [.medium, .large, .dishPack]
        case .lamps: return [.medium, .large]
        case .electronics: return [.medium, .large, .small]
        case .clothes, .shoes, .bedding: return [.large, .medium]
        case .misc: return [.medium, .large, .small, .tote]
        case .kitchen: return [.dishPack, .medium, .large]
        case .bathroom: return [.medium, .small, .large]
        case .hanging: return [.wardrobe, .large]
        case .openFirst: return [.tote, .large]
        case .keepWithYou: return [.small, .medium, .tote, .large]
        }
    }

    /// When to pack it: 14 (books, decor, rarely used), 7 (most things),
    /// 2 (kitchen, bathroom, hanging clothes) or 0 (moving day).
    var daysBeforeMove: Int {
        switch self {
        case .books, .decor, .misc: return 14
        case .lamps, .desk, .electronics, .clothes, .shoes, .bedding: return 7
        case .kitchen, .bathroom, .hanging: return 2
        case .openFirst, .keepWithYou: return 0
        }
    }

    /// kg per m³ of an item's bounding box, for scanned items.
    var density: Double {
        switch self {
        case .books: return 650
        case .clothes, .hanging: return 130
        case .shoes: return 200
        case .bedding: return 90
        case .kitchen: return 380
        case .electronics: return 260
        case .lamps: return 110
        case .bathroom: return 300
        case .desk: return 400
        case .decor, .misc, .openFirst, .keepWithYou: return 220
        }
    }

    /// The kind for a scanned item's category.
    init(category: String) {
        switch category.lowercased() {
        case "books", "book": self = .books
        case "clothes", "clothing": self = .clothes
        case "shoes": self = .shoes
        case "linens", "linen", "bedding": self = .bedding
        case "kitchenware", "kitchen", "dishes": self = .kitchen
        case "electronics", "electronic", "computer": self = .electronics
        case "decor", "art", "photos", "plant": self = .decor
        case "lamp", "lighting": self = .lamps
        case "toiletries", "bathroom": self = .bathroom
        case "office", "stationery": self = .desk
        default: self = .misc
        }
    }
}

/// A typical thing to pack: name, count, litres and kg per piece.
struct TypicalLine: Sendable {
    var kind: PackKind
    var name: String
    var quantity: Int
    var litres: Double
    var kg: Double
    var fragile: Bool = false
}

enum PackingTemplates {
    /// Always in the open-first tote: what you need on the first night.
    static let openFirst: [TypicalLine] = [
        TypicalLine(kind: .openFirst, name: "Sheets and pillowcases", quantity: 1, litres: 8, kg: 1.2),
        TypicalLine(kind: .openFirst, name: "Bath towel", quantity: 1, litres: 5, kg: 0.6),
        TypicalLine(kind: .openFirst, name: "Toiletries bag", quantity: 1, litres: 3, kg: 1.5),
        TypicalLine(kind: .openFirst, name: "Phone and laptop chargers", quantity: 1, litres: 0.5, kg: 0.3),
        TypicalLine(kind: .openFirst, name: "Medications", quantity: 1, litres: 0.5, kg: 0.2),
        TypicalLine(kind: .openFirst, name: "Tool kit (screwdrivers, Allen keys)", quantity: 1, litres: 3, kg: 1.5),
        TypicalLine(kind: .openFirst, name: "Box cutter and tape", quantity: 1, litres: 0.5, kg: 0.3),
        TypicalLine(kind: .openFirst, name: "Toilet paper", quantity: 2, litres: 2, kg: 0.2),
        TypicalLine(kind: .openFirst, name: "Snacks and water", quantity: 1, litres: 4, kg: 2.5),
        TypicalLine(kind: .openFirst, name: "Spare light bulbs", quantity: 2, litres: 0.5, kg: 0.1),
    ]

    /// Always in the keep-with-you box, next to the sentimental items.
    static let keepWithYou: [TypicalLine] = [
        TypicalLine(kind: .keepWithYou, name: "Important documents (IDs, lease, passport)", quantity: 1, litres: 1, kg: 0.5),
        TypicalLine(kind: .keepWithYou, name: "Jewelry and watches", quantity: 1, litres: 0.5, kg: 0.3),
        TypicalLine(kind: .keepWithYou, name: "Laptop and hard drives", quantity: 1, litres: 3, kg: 2.2, fragile: true),
        TypicalLine(kind: .keepWithYou, name: "Spare keys", quantity: 1, litres: 0.1, kg: 0.1),
    ]

    /// Typical everyday contents for a destination room.
    static func typical(for kind: RoomKind?) -> [TypicalLine] {
        switch kind ?? .other {
        case .bedroom: return bedroom
        case .living: return living
        case .kitchen: return kitchen
        case .bathroom: return bathroom
        case .office: return office
        case .dining: return dining
        case .hallway, .other: return other
        }
    }

    static let bedroom: [TypicalLine] = [
        TypicalLine(kind: .books, name: "Paperbacks", quantity: 20, litres: 0.5, kg: 0.3),
        TypicalLine(kind: .books, name: "Hardcover books", quantity: 8, litres: 1.6, kg: 0.8),
        TypicalLine(kind: .decor, name: "Small picture frames", quantity: 3, litres: 2, kg: 0.6, fragile: true),
        TypicalLine(kind: .decor, name: "Candles and keepsakes", quantity: 4, litres: 0.8, kg: 0.3, fragile: true),
        TypicalLine(kind: .desk, name: "Notebooks and papers", quantity: 1, litres: 6, kg: 3),
        TypicalLine(kind: .desk, name: "Pens, stapler and desk odds", quantity: 1, litres: 2, kg: 0.8),
        TypicalLine(kind: .desk, name: "Cables and chargers", quantity: 1, litres: 3, kg: 1),
        TypicalLine(kind: .electronics, name: "Bluetooth speaker", quantity: 1, litres: 3, kg: 1, fragile: true),
        TypicalLine(kind: .electronics, name: "Headphones", quantity: 1, litres: 2, kg: 0.3, fragile: true),
        TypicalLine(kind: .clothes, name: "Folded shirts and sweaters", quantity: 24, litres: 1.4, kg: 0.3),
        TypicalLine(kind: .clothes, name: "Jeans and trousers", quantity: 8, litres: 2, kg: 0.6),
        TypicalLine(kind: .shoes, name: "Shoes (pairs)", quantity: 5, litres: 6, kg: 0.8),
        TypicalLine(kind: .bedding, name: "Spare sheet sets", quantity: 2, litres: 6, kg: 1),
        TypicalLine(kind: .bedding, name: "Spare blanket", quantity: 1, litres: 15, kg: 1.5),
        TypicalLine(kind: .bedding, name: "Pillows", quantity: 2, litres: 12, kg: 0.7),
        TypicalLine(kind: .hanging, name: "Hanging clothes (on hangers)", quantity: 15, litres: 4, kg: 0.45),
    ]

    static let living: [TypicalLine] = [
        TypicalLine(kind: .books, name: "Books", quantity: 15, litres: 1, kg: 0.55),
        TypicalLine(kind: .decor, name: "Vases and ceramics", quantity: 2, litres: 5, kg: 0.8, fragile: true),
        TypicalLine(kind: .decor, name: "Picture frames", quantity: 3, litres: 2, kg: 0.6, fragile: true),
        TypicalLine(kind: .misc, name: "Board games and media", quantity: 4, litres: 4, kg: 0.8),
        TypicalLine(kind: .electronics, name: "Remotes, router and cables", quantity: 1, litres: 4, kg: 1.5, fragile: true),
        TypicalLine(kind: .bedding, name: "Throws and cushions", quantity: 4, litres: 10, kg: 0.6),
    ]

    static let kitchen: [TypicalLine] = [
        TypicalLine(kind: .kitchen, name: "Dinner plates", quantity: 6, litres: 2.5, kg: 0.55, fragile: true),
        TypicalLine(kind: .kitchen, name: "Bowls", quantity: 6, litres: 3, kg: 0.4, fragile: true),
        TypicalLine(kind: .kitchen, name: "Mugs", quantity: 4, litres: 2.4, kg: 0.35, fragile: true),
        TypicalLine(kind: .kitchen, name: "Drinking glasses", quantity: 6, litres: 2, kg: 0.25, fragile: true),
        TypicalLine(kind: .kitchen, name: "Pots and pans", quantity: 3, litres: 6, kg: 1.2),
        TypicalLine(kind: .kitchen, name: "Cutlery and utensils", quantity: 1, litres: 5, kg: 2),
    ]

    static let bathroom: [TypicalLine] = [
        TypicalLine(kind: .bathroom, name: "Towels", quantity: 4, litres: 4, kg: 0.5),
        TypicalLine(kind: .bathroom, name: "Toiletries and cleaning supplies", quantity: 1, litres: 8, kg: 3),
    ]

    static let office: [TypicalLine] = [
        TypicalLine(kind: .books, name: "Books and binders", quantity: 18, litres: 1.2, kg: 0.6),
        TypicalLine(kind: .desk, name: "Notebooks and papers", quantity: 1, litres: 6, kg: 3),
        TypicalLine(kind: .desk, name: "Pens, stapler and desk odds", quantity: 1, litres: 2, kg: 0.8),
        TypicalLine(kind: .electronics, name: "Keyboard, mouse and cables", quantity: 1, litres: 8, kg: 2, fragile: true),
    ]

    static let dining: [TypicalLine] = [
        TypicalLine(kind: .decor, name: "Serving dishes", quantity: 3, litres: 4, kg: 0.9, fragile: true),
        TypicalLine(kind: .bedding, name: "Table linens", quantity: 1, litres: 6, kg: 1),
    ]

    static let other: [TypicalLine] = [
        TypicalLine(kind: .misc, name: "Odds and ends", quantity: 6, litres: 3, kg: 0.6),
    ]
}

/// Room kind from a room's name ("Primary bedroom" -> .bedroom).
func roomKind(named name: String) -> RoomKind? {
    let n = name.lowercased()
    let table: [(RoomKind, [String])] = [
        (.bedroom, ["bedroom", "bed room", "nursery", "guest"]),
        (.living, ["living", "lounge", "family", "den"]),
        (.kitchen, ["kitchen"]),
        (.dining, ["dining"]),
        (.bathroom, ["bath", "toilet", "powder"]),
        (.office, ["office", "study"]),
        (.hallway, ["hall", "entry", "foyer"]),
    ]
    for (kind, words) in table where words.contains(where: { n.contains($0) }) {
        return kind
    }
    for kind in RoomKind.allCases where kind != .other && n == kind.label.lowercased() {
        return kind
    }
    return nil
}
