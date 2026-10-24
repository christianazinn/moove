import Foundation

/// Voxel thumbnail specs for the Shopping screens (#15 piece 2): one per shopping-list item and
/// one per deal. Neither table carries dimensions, so each gets a typical size for what it is.
/// The voxel router reads shape and color words from `name`, so a deal's spec uses its title
/// ("Gray 3-seat couch") while the size and category come from the shopping item.
///
/// Sizes and categories come from `BoughtFurniture.footprint`, the same table the new-home layout
/// uses for bought items, so a thumbnail and the placed piece always match.
public enum ShoppingThumbnails {
    /// A voxel category key the router knows plus a typical size.
    public typealias Size = BoughtFurniture.Footprint

    /// Size for a shopping item: its name decides first, then its category, then a box-sized default.
    public static func size(name: String, category: String) -> Size {
        BoughtFurniture.footprint(category: category, name: name)
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
}
