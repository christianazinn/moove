import Foundation

// Bought furniture for the new-home layout (#15 -> #14). A shopping item has no measured
// dimensions (neither it nor its deals carry any), so it gets a typical footprint for what it is.

/// Turns purchased shopping items into `LayoutItem`s for `LayoutSolver`.
public enum BoughtFurniture {
    /// Layout ids for bought items are `idBase + shoppingItemId`, so they never collide with
    /// inventory item ids (both tables count up from 1). Stays well under 2^53, so ids survive a
    /// JSON round trip through the worker (saved layouts store placements as JSON).
    public static let idBase: UInt64 = 1_000_000_000_000

    public static func layoutId(forShoppingItem id: UInt64) -> UInt64 { idBase + id }

    /// The shopping item behind a layout id, or nil when the id is an inventory item's.
    public static func shoppingItemId(fromLayoutId id: UInt64) -> UInt64? { id > idBase ? id - idBase : nil }

    /// A typical size for a kind of furniture, plus the category `LayoutSolver` and the voxel
    /// models understand for it.
    public struct Footprint: Sendable, Hashable {
        public var category: String
        public var widthM: Double
        public var depthM: Double
        public var heightM: Double

        public init(category: String, widthM: Double, depthM: Double, heightM: Double) {
            self.category = category
            self.widthM = widthM
            self.depthM = depthM
            self.heightM = heightM
        }
    }

    /// Keyword -> footprint, most specific first ("tv stand" before "tv", "desk chair" before "desk").
    /// Categories are ones both `LayoutSolver.preferredKinds` and the voxel router know.
    static let rules: [(keywords: [String], footprint: Footprint)] = [
        (["sofa bed", "futon"], .init(category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85)),
        (["sectional"], .init(category: "sofa", widthM: 2.6, depthM: 1.6, heightM: 0.85)),
        (["loveseat", "love seat"], .init(category: "sofa", widthM: 1.5, depthM: 0.9, heightM: 0.85)),
        (["sofa", "couch"], .init(category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85)),
        (["mattress"], .init(category: "bed", widthM: 1.4, depthM: 1.9, heightM: 0.25)),
        (["bunk bed"], .init(category: "bed", widthM: 1.0, depthM: 2.0, heightM: 1.6)),
        (["bed", "bed frame"], .init(category: "bed", widthM: 1.6, depthM: 2.1, heightM: 0.5)),
        (["nightstand", "night stand", "bedside table", "bedside"], .init(category: "dresser", widthM: 0.45, depthM: 0.4, heightM: 0.55)),
        (["wardrobe", "armoire"], .init(category: "dresser", widthM: 1.0, depthM: 0.6, heightM: 1.9)),
        (["dresser", "chest of drawers"], .init(category: "dresser", widthM: 1.2, depthM: 0.5, heightM: 0.8)),
        (["tv stand", "media console", "tv console", "entertainment center"], .init(category: "tv", widthM: 1.5, depthM: 0.45, heightM: 0.55)),
        (["tv", "television"], .init(category: "tv", widthM: 1.2, depthM: 0.25, heightM: 0.7)),
        (["desk chair", "office chair", "task chair", "gaming chair"], .init(category: "chair", widthM: 0.65, depthM: 0.65, heightM: 1.1)),
        (["armchair", "accent chair", "recliner"], .init(category: "chair", widthM: 0.85, depthM: 0.85, heightM: 0.9)),
        (["chair", "stool"], .init(category: "chair", widthM: 0.5, depthM: 0.55, heightM: 0.9)),
        (["desk"], .init(category: "desk", widthM: 1.2, depthM: 0.6, heightM: 0.75)),
        (["dining table", "kitchen table"], .init(category: "table", widthM: 1.5, depthM: 0.9, heightM: 0.75)),
        (["coffee table"], .init(category: "table", widthM: 1.1, depthM: 0.6, heightM: 0.45)),
        (["side table", "end table"], .init(category: "table", widthM: 0.5, depthM: 0.5, heightM: 0.55)),
        (["table"], .init(category: "table", widthM: 1.2, depthM: 0.8, heightM: 0.75)),
        (["bookshelf", "bookcase", "shelf", "shelving", "shelves"], .init(category: "storage", widthM: 0.8, depthM: 0.3, heightM: 1.8)),
        (["rug", "carpet"], .init(category: "rug", widthM: 1.8, depthM: 1.2, heightM: 0.01)),
        (["desk lamp", "table lamp"], .init(category: "lamp", widthM: 0.25, depthM: 0.25, heightM: 0.5)),
        (["lamp", "floor lamp", "light"], .init(category: "lamp", widthM: 0.35, depthM: 0.35, heightM: 1.6)),
        (["plant"], .init(category: "plant", widthM: 0.4, depthM: 0.4, heightM: 1.0)),
    ]

    /// Footprint for a bought item: its name decides first ("Desk chair" in category "furniture"),
    /// then its category, then a generic box-sized default that keeps the category as given.
    public static func footprint(category: String, name: String) -> Footprint {
        for text in [name, category] {
            let words = " " + tokens(text).joined(separator: " ") + " "
            for rule in rules where rule.keywords.contains(where: { words.contains(" \($0) ") || words.contains(" \($0)s ") }) {
                return rule.footprint
            }
        }
        let cat = category.trimmingCharacters(in: .whitespaces).lowercased()
        return Footprint(category: cat.isEmpty ? "decor" : cat, widthM: 0.6, depthM: 0.6, heightM: 0.8)
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter }.map(String.init)
    }
}

extension LayoutItem {
    /// A bought shopping item, with a typical footprint for its kind and a collision-free id.
    public init(bought item: ShoppingItem) {
        let f = BoughtFurniture.footprint(category: item.category, name: item.name)
        self.init(id: BoughtFurniture.layoutId(forShoppingItem: item.id), name: item.name, category: f.category,
                  widthM: f.widthM, depthM: f.depthM, heightM: f.heightM)
    }

    /// True when this is a bought item rather than one from the inventory.
    public var isBought: Bool { BoughtFurniture.shoppingItemId(fromLayoutId: id) != nil }
}

extension SyncSnapshot {
    /// Bought for the new home: the buy agent marked it `bought` (it does so once the card payment
    /// is captured), or the chosen deal already has a settled Visa payment and the status hasn't
    /// caught up yet.
    public func isPurchased(_ item: ShoppingItem) -> Bool {
        if item.status == .bought { return true }
        guard let deal = chosenDeal(for: item) else { return false }
        return visaPayment(for: deal.id)?.status == .settled
    }

    /// The signed-in user's purchased shopping items, in list order.
    public var purchasedShoppingItems: [ShoppingItem] { myShoppingItems.filter(isPurchased) }

    /// Purchased shopping items, ready for `LayoutSolver`.
    public var boughtLayoutItems: [LayoutItem] { purchasedShoppingItems.map(LayoutItem.init(bought:)) }

    /// Everything the new-home layout places: kept inventory items, then bought ones.
    public var newHomeLayoutItems: [LayoutItem] {
        items.filter { $0.disposition == .keep }.map(LayoutItem.init) + boughtLayoutItems
    }
}
