import Foundation

/// One `set_item_colors` call: an item and the colors sampled for it.
public struct ItemColorUpdate: Sendable, Hashable {
    public var itemId: UInt64
    public var colors: ItemColors

    public init(itemId: UInt64, colors: ItemColors) {
        self.itemId = itemId
        self.colors = colors
    }
}

extension ItemColors {
    /// A sampled object color in the item's `colors_json` form.
    public init(_ c: ScanColors.ObjectColor) {
        self.init(primary: c.primary, secondary: c.secondary)
    }
}

extension ScanColors {
    /// The writes that persist these colors onto `items` (matched by `scanObjectId`): one per
    /// item with a sampled color that it doesn't already store. Ordered by item id.
    public func itemColorUpdates(for items: [Item]) -> [ItemColorUpdate] {
        items.compactMap { item -> ItemColorUpdate? in
            guard let c = colors(for: item) else { return nil }
            let wanted = ItemColors(c)
            guard wanted.isValid, item.colors != wanted else { return nil }
            return ItemColorUpdate(itemId: item.id, colors: wanted)
        }
        .sorted { $0.itemId < $1.itemId }
    }

    /// These colors with gaps filled from `fallback`: its wall / floor color when this has
    /// none, and its object colors for objects this didn't sample.
    public func filling(from fallback: ScanColors) -> ScanColors {
        ScanColors(
            wallColor: wallColor ?? fallback.wallColor,
            floorColor: floorColor ?? fallback.floorColor,
            objectColors: fallback.objectColors.merging(objectColors) { _, mine in mine }
        )
    }
}
