import Foundation

/// Voxel thumbnail specs for the Shopping screens (#15 piece 2): one per shopping-list item and
/// one per deal. Neither table carries dimensions, so each gets a typical size for what it is.
/// The voxel router reads shape and color words from `name`, so a deal's spec uses its title
/// ("Gray 3-seat couch") while the size and category come from the shopping item.
///
/// The size table mirrors the one in #125's `BoughtFurniture` (not on main yet); keep them in step.
public enum ShoppingThumbnails {
    public struct Size: Sendable, Hashable {
        /// A voxel category key the router knows (`VoxelModels.route`).
        public var category: String
        public var widthM: Double
        public var depthM: Double
        public var heightM: Double
    }

    /// Keyword -> size, most specific first ("desk chair" before "desk", "dining table" before "table").
    static let rules: [(keywords: [String], size: Size)] = [
        (["sofa bed", "futon"], .init(category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85)),
        (["sectional"], .init(category: "sofa", widthM: 2.6, depthM: 1.6, heightM: 0.85)),
        (["loveseat", "love seat"], .init(category: "sofa", widthM: 1.5, depthM: 0.9, heightM: 0.85)),
        (["sofa", "couch"], .init(category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85)),
        (["mattress"], .init(category: "mattress", widthM: 1.4, depthM: 1.9, heightM: 0.25)),
        (["bed", "bed frame"], .init(category: "bed", widthM: 1.6, depthM: 2.1, heightM: 0.5)),
        (["nightstand", "night stand", "bedside table", "bedside"], .init(category: "dresser", widthM: 0.45, depthM: 0.4, heightM: 0.55)),
        (["wardrobe", "armoire"], .init(category: "dresser", widthM: 1.0, depthM: 0.6, heightM: 1.9)),
        (["dresser", "chest of drawers"], .init(category: "dresser", widthM: 1.2, depthM: 0.5, heightM: 0.8)),
        (["tv stand", "media console", "tv console"], .init(category: "tv", widthM: 1.5, depthM: 0.45, heightM: 0.55)),
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

    /// Size for a shopping item: its name decides first, then its category, then a box-sized default.
    public static func size(name: String, category: String) -> Size {
        for text in [name, category] {
            let words = " " + tokens(text).joined(separator: " ") + " "
            for rule in rules where rule.keywords.contains(where: { words.contains(" \($0) ") || words.contains(" \($0)s ") }) {
                return rule.size
            }
        }
        let cat = category.trimmingCharacters(in: .whitespaces).lowercased()
        return Size(category: cat.isEmpty ? "decor" : cat, widthM: 0.6, depthM: 0.6, heightM: 0.8)
    }

    /// The thumbnail for a shopping-list item.
    public static func spec(for item: ShoppingItem) -> VoxelItemSpec {
        let s = size(name: item.name, category: item.category)
        return VoxelItemSpec(category: s.category, name: item.name, widthM: s.widthM, depthM: s.depthM, heightM: s.heightM,
                             id: "shopping-\(item.id)")
    }

    /// The thumbnail for a deal: the item's kind and size, drawn from the deal's title.
    public static func spec(for deal: Deal, item: ShoppingItem?) -> VoxelItemSpec {
        let s = item.map { size(name: $0.name, category: $0.category) } ?? size(name: deal.title, category: "")
        return VoxelItemSpec(category: s.category, name: deal.title, widthM: s.widthM, depthM: s.depthM, heightM: s.heightM,
                             id: "deal-\(deal.id)")
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter }.map(String.init)
    }
}
