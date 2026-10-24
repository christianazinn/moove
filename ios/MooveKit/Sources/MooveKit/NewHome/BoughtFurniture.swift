import Foundation

// Bought furniture for the new-home layout (#15 -> #14). A shopping item has no measured
// dimensions (neither it nor its deals carry any), so it gets a typical footprint for what it is.
// The voxel builder draws it like a kept item, from category + name (the chosen deal's title).

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

    /// The category keys `VoxelModels.route` switches on (#108). A bought item's category is always one of them.
    public static let voxelCategories: Set<String> = [
        "sofa", "bed", "mattress", "desk", "chair", "table", "dresser", "storage", "lamp", "tv", "books", "art",
        "photos", "trading_cards", "plant", "rug", "kitchenware", "clothes", "electronics", "appliance", "decor",
    ]

    /// Other spellings the voxel router accepts, folded onto their key.
    static let categoryAliases: [String: String] = [
        "couch": "sofa", "light": "lamp", "lighting": "lamp", "television": "tv", "book": "books", "plants": "plant",
        "kitchen": "kitchenware", "clothing": "clothes", "appliances": "appliance",
    ]

    /// Keyword -> footprint, most specific first ("tv stand" before "tv", "desk chair" before "desk").
    /// Every category is a voxel builder key (`voxelCategories`).
    static let rules: [(keywords: [String], footprint: Footprint)] = [
        (["sofa bed", "futon"], .init(category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85)),
        (["sectional"], .init(category: "sofa", widthM: 2.6, depthM: 1.6, heightM: 0.85)),
        (["loveseat", "love seat"], .init(category: "sofa", widthM: 1.5, depthM: 0.9, heightM: 0.85)),
        (["sofa", "couch"], .init(category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85)),
        // The voxel builder draws armchairs as a one-seat sofa, and they belong in the living room.
        (["armchair", "accent chair", "recliner"], .init(category: "sofa", widthM: 0.85, depthM: 0.85, heightM: 0.9)),
        (["mattress"], .init(category: "mattress", widthM: 1.4, depthM: 1.9, heightM: 0.25)),
        (["bunk bed"], .init(category: "bed", widthM: 1.0, depthM: 2.0, heightM: 1.6)),
        (["bed", "bed frame"], .init(category: "bed", widthM: 1.6, depthM: 2.1, heightM: 0.5)),
        (["nightstand", "night stand", "bedside table", "bedside"], .init(category: "dresser", widthM: 0.45, depthM: 0.4, heightM: 0.55)),
        (["wardrobe", "armoire"], .init(category: "dresser", widthM: 1.0, depthM: 0.6, heightM: 1.9)),
        (["dresser", "chest of drawers"], .init(category: "dresser", widthM: 1.2, depthM: 0.5, heightM: 0.8)),
        // A TV stand is a low cabinet (the `tv` builder would draw a screen at this height).
        (["tv stand", "television stand", "media console", "tv console", "entertainment center", "sideboard", "credenza"],
         .init(category: "dresser", widthM: 1.5, depthM: 0.45, heightM: 0.55)),
        (["tv", "television"], .init(category: "tv", widthM: 1.2, depthM: 0.25, heightM: 0.7)),
        (["desk chair", "office chair", "task chair", "gaming chair"], .init(category: "chair", widthM: 0.65, depthM: 0.65, heightM: 1.1)),
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
        (["fridge", "refrigerator", "freezer"], .init(category: "appliance", widthM: 0.75, depthM: 0.7, heightM: 1.75)),
        (["washer", "dryer", "dishwasher", "oven", "stove", "range"], .init(category: "appliance", widthM: 0.6, depthM: 0.65, heightM: 0.9)),
        (["microwave", "toaster", "blender", "kettle", "coffee maker"], .init(category: "appliance", widthM: 0.5, depthM: 0.4, heightM: 0.3)),
        (["cookware", "pots", "pans", "pot", "pan", "dishes", "dinnerware", "utensils", "kitchenware"],
         .init(category: "kitchenware", widthM: 0.6, depthM: 0.4, heightM: 0.4)),
        (["mirror"], .init(category: "decor", widthM: 0.6, depthM: 0.05, heightM: 0.9)),
        (["poster", "painting", "artwork", "art", "print"], .init(category: "art", widthM: 0.6, depthM: 0.04, heightM: 0.8)),
        (["shower curtain", "curtain", "curtains", "towel", "towels", "bath mat", "bedding", "linens"],
         .init(category: "decor", widthM: 0.35, depthM: 0.25, heightM: 0.3)),
    ]

    /// Footprint for a bought item: its name decides first ("Desk chair" in category "furniture"),
    /// then its category, then a generic default whose category is the given one when the voxel
    /// builder knows it, else "decor".
    public static func footprint(category: String, name: String) -> Footprint {
        for text in [name, category] {
            let words = " " + tokens(text).joined(separator: " ") + " "
            for rule in rules where rule.keywords.contains(where: { words.contains(" \($0) ") || words.contains(" \($0)s ") }) {
                return rule.footprint
            }
        }
        return Footprint(category: voxelCategory(category) ?? "decor", widthM: 0.6, depthM: 0.6, heightM: 0.8)
    }

    /// The voxel builder key for a category as typed ("Couch" -> "sofa"), or nil if it has none.
    public static func voxelCategory(_ category: String) -> String? {
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if voxelCategories.contains(cat) { return cat }
        return categoryAliases[cat]
    }

    /// The name the voxel model reads: the chosen deal's title, which carries the shape and color
    /// words ("Round dining table, 42\", natural wood"), unless that title would make the builder
    /// draw something else than the shopping item's own name does ("Arc floor lamp for sofa" would
    /// route to a sofa). Then, and without a deal, the shopping item's name. When the title lacks the
    /// item's own words, they're appended ("2-drawer bedside table, white · Nightstand").
    public static func modelName(itemName: String, dealTitle: String?, category: String) -> String {
        guard let title = dealTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return itemName }
        func kind(_ name: String) -> VoxelModels.Kind {
            VoxelModels.kind(VoxelItemSpec(category: category, name: name, widthM: 1, depthM: 1, heightM: 1))
        }
        // Keep the item's own word ("Nightstand") when the title lacks it, so routing that keys on it still sees it.
        let titleWords = Set(tokens(title))
        let hasItemWords = tokens(itemName).allSatisfy { titleWords.contains($0) || titleWords.contains($0 + "s") }
        let name = hasItemWords || itemName.isEmpty ? title : "\(title) · \(itemName)"
        return kind(name) == kind(itemName) ? name : itemName
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter }.map(String.init)
    }
}

extension LayoutItem {
    /// A bought shopping item, with a collision-free id, a voxel builder category, the chosen
    /// deal's title as its name (see `BoughtFurniture.modelName`), and a typical footprint for its
    /// kind (deals carry no dimensions).
    public init(bought item: ShoppingItem, deal: Deal? = nil) {
        let f = BoughtFurniture.footprint(category: item.category, name: item.name)
        let name = BoughtFurniture.modelName(itemName: item.name, dealTitle: deal?.title, category: f.category)
        self.init(id: BoughtFurniture.layoutId(forShoppingItem: item.id), name: name, category: f.category,
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
    public var boughtLayoutItems: [LayoutItem] {
        purchasedShoppingItems.map { LayoutItem(bought: $0, deal: chosenDeal(for: $0)) }
    }

    /// Everything the new-home layout places: kept inventory items, then bought ones.
    public var newHomeLayoutItems: [LayoutItem] {
        items.filter { $0.disposition == .keep }.map(LayoutItem.init) + boughtLayoutItems
    }
}
