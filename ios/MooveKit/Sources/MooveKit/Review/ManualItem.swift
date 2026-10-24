import Foundation

/// Adding an item by hand (Inventory → Add item): the kinds to pick from, and a size to start
/// from so nobody has to measure. The size is each kind's voxel default (`VoxelModels`).
public enum ManualItem {
    public struct Kind: Hashable, Sendable, Identifiable {
        public var label: String
        /// The item's `category` (the vision agent's vocabulary, so the 3D look and pricing match).
        public var category: String
        public var id: String { category }
    }

    public static let kinds: [Kind] = [
        ("Chair", "chair"), ("Sofa", "sofa"), ("Bed", "bed"), ("Mattress", "mattress"), ("Table", "table"), ("Desk", "desk"),
        ("Dresser", "dresser"), ("Bookshelf", "bookshelf"), ("Storage", "storage"), ("Lamp", "lamp"), ("TV", "tv"),
        ("Electronics", "electronics"), ("Appliance", "appliance"), ("Bike", "bike"), ("Plant", "plant"), ("Rug", "rug"),
        ("Art", "art"), ("Mirror", "mirror"), ("Kitchenware", "kitchenware"), ("Clothes", "clothes"), ("Books", "books"),
        ("Box", "box"), ("Other", "other"),
    ].map { Kind(label: $0.0, category: $0.1) }

    /// The kind a typed name points to ("Road bike" → Bike), by the same words the 3D models
    /// use, or nil when the name doesn't say.
    public static func suggestedKind(for name: String) -> Kind? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        let named = VoxelModels.kind(VoxelItemSpec(category: "other", name: trimmed, widthM: 0, depthM: 0, heightM: 0))
        guard named != .box else { return nil }
        return kinds.first { VoxelModels.kind(VoxelItemSpec(category: $0.category, name: $0.category, widthM: 0, depthM: 0, heightM: 0)) == named }
    }

    /// Width, height, depth in meters for a new item of this kind called `name`.
    public static func defaultSize(category: String, name: String = "") -> (w: Double, h: Double, d: Double) {
        let s = VoxelModels.kind(VoxelItemSpec(category: category, name: name.isEmpty ? category : name, widthM: 0, depthM: 0, heightM: 0)).defaultSize
        return (s.0, s.2, s.1)  // defaultSize is (w, d, h)
    }
}
