import Foundation

// Inventory as a tabbed binder (Lisa: "simulate different shelves or even a notebook/file
// organizer ... where items are grouped by page"): each `FunctionHall` with items is a page
// behind a colored index tab, and each page is a wall of shelves the items stand on. This
// file is the pure layout: tab order, labels and colors, and packing items onto shelves.

/// How much shelf an item takes, from its measured size.
public enum ShelfSize: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Lamps, kettles, monitors: grouped on the upper shelves.
    case small
    /// Nightstands, chairs, guitars, and items with no measured size.
    case medium
    /// Desks, dressers, TVs: a lower, wider shelf.
    case large
    /// Beds, sofas, wardrobes, bookcases: they stand on the floor row.
    case floor

    public static func < (a: ShelfSize, b: ShelfSize) -> Bool { a.rawValue < b.rawValue }

    /// Shelf width units the item takes (a plank holds `InventoryBinder.capacity` units).
    public var units: Int {
        switch self {
        case .small: 1
        case .medium: 2
        case .large: 3
        case .floor: 4
        }
    }

    /// Which shelf band the size goes on: small and medium share the upper shelves.
    public var tier: ShelfTier {
        switch self {
        case .small, .medium: .upper
        case .large: .lower
        case .floor: .floor
        }
    }

    public static func of(_ item: Item) -> ShelfSize {
        let w = max(0, item.widthM), d = max(0, item.depthM), h = max(0, item.heightM)
        // Unmeasured (added by photo, or no size yet): a middling spot.
        guard w > 0 || d > 0 || h > 0 else { return .medium }
        let wide = max(w, d)
        if wide >= 1.3 || h >= 1.4 || w * d * h >= 0.6 { return .floor }
        if wide >= 0.7 || h >= 0.8 { return .large }
        if wide >= 0.35 || h >= 0.4 { return .medium }
        return .small
    }
}

/// A shelf band, top to bottom.
public enum ShelfTier: Int, Sendable, Hashable, Comparable {
    case upper, lower, floor
    public static func < (a: ShelfTier, b: ShelfTier) -> Bool { a.rawValue < b.rawValue }
}

/// One plank (or the floor row) and the items standing on it, left to right.
public struct Shelf: Sendable, Hashable {
    public var tier: ShelfTier
    public var items: [Item]
    /// Width units used.
    public var units: Int

    public init(tier: ShelfTier, items: [Item], units: Int) {
        self.tier = tier
        self.items = items
        self.units = units
    }
}

/// The binder's index tab colors; the app maps each to a light and a dark shade.
public enum BinderTint: String, Sendable, Hashable, CaseIterable {
    case sage, ochre, slate, clay, plum, stone, teal
}

/// One index tab: a page of the binder.
public struct BinderTab: Sendable, Hashable, Identifiable {
    public var hall: FunctionHall
    public var count: Int
    /// 0-based page number.
    public var page: Int
    public var pageCount: Int
    public var id: FunctionHall { hall }

    public var tint: BinderTint { InventoryBinder.tint(hall) }
    /// "Sleep, 4 pieces, page 1 of 6".
    public var accessibilityLabel: String {
        "\(hall.name), \(count == 1 ? "1 piece" : "\(count) pieces"), page \(page + 1) of \(pageCount)"
    }
}

public enum InventoryBinder {
    /// Shelf width units per plank: 2–3 items on a phone, about twice that on an iPad.
    public static func capacity(regularWidth: Bool) -> Int { regularWidth ? 12 : 6 }
    /// Most items on one plank, so their hanging tags stay readable.
    public static func maxPerShelf(regularWidth: Bool) -> Int { regularWidth ? 6 : 3 }

    /// One tab per hall with items, in `FunctionHall.halls` order (biggest first,
    /// everything else last).
    public static func tabs(_ halls: [(hall: FunctionHall, items: [Item])]) -> [BinderTab] {
        halls.enumerated().map { i, entry in
            BinderTab(hall: entry.hall, count: entry.items.count, page: i, pageCount: halls.count)
        }
    }

    /// The page to show: the picked hall while it still has items, else the first page.
    public static func page(_ picked: FunctionHall?, in tabs: [BinderTab]) -> FunctionHall? {
        if let picked, tabs.contains(where: { $0.hall == picked }) { return picked }
        return tabs.first?.hall
    }

    /// The hall `delta` pages away from `current` (a swipe or a VoiceOver scroll), stopping
    /// at the first and last page.
    public static func turn(from current: FunctionHall?, by delta: Int, in tabs: [BinderTab]) -> FunctionHall? {
        guard !tabs.isEmpty else { return nil }
        let i = tabs.firstIndex { $0.hall == current } ?? 0
        return tabs[min(max(i + delta, 0), tabs.count - 1)].hall
    }

    /// A fixed color per hall (not per page position), so Sleep is always the same tab;
    /// halls next to each other in `FunctionHall.allCases` differ.
    public static func tint(_ hall: FunctionHall) -> BinderTint {
        switch hall {
        case .sleep: .slate
        case .sitAndLounge: .clay
        case .workAndStudy: .sage
        case .kitchenAndDining: .ochre
        case .media: .plum
        case .storage: .stone
        case .lightAndDecor: .ochre
        case .music: .teal
        case .bathAndLaundry: .slate
        case .getAroundAndPlay: .clay
        case .everythingElse: .stone
        }
    }

    /// Items packed onto shelves: small things on the upper planks, larger ones on lower,
    /// wider planks, and big furniture on the floor row at the bottom. Within a band items
    /// keep their order (most valuable first) and go on the first plank with room
    /// (`capacity` width units, at most `maxPerShelf` items); anything wider than a plank
    /// gets one to itself.
    public static func shelves(_ items: [Item], capacity: Int, maxPerShelf: Int) -> [Shelf] {
        let cap = max(1, capacity), most = max(1, maxPerShelf)
        let sized = items.map { (item: $0, size: ShelfSize.of($0)) }
        var out: [Shelf] = []
        for tier in [ShelfTier.upper, .lower, .floor] {
            // Upper band: the smallest things on the top planks.
            let band = sized.enumerated()
                .filter { $0.element.size.tier == tier }
                .sorted { a, b in a.element.size != b.element.size ? a.element.size < b.element.size : a.offset < b.offset }
                .map(\.element)
            var planks: [Shelf] = []
            for entry in band {
                let units = min(entry.size.units, cap)
                if let i = planks.firstIndex(where: { $0.units + units <= cap && $0.items.count < most }) {
                    planks[i].items.append(entry.item)
                    planks[i].units += units
                } else {
                    planks.append(Shelf(tier: tier, items: [entry.item], units: units))
                }
            }
            out += planks
        }
        return out
    }
}
