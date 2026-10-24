import Foundation

/// Inventory's **+ Add item** (take a photo of something the scan missed): the `add_item`
/// object it sends. Existing reducers only: `add_item` (with the uploaded photo's URL, so the
/// worker's vision agent picks the item up as `details_status = pending` with a photo) and,
/// when the upload has to wait, `add_item_photo` later.
public enum AddedItem {
    /// `scan_object_id` prefix that marks an item added this way (`Item.origin` = `.photo`).
    public static let scanObjectIdPrefix = "added:"

    /// Shown until vision names it. The worker's pricing agent treats it as generic,
    /// so it doesn't search comps for "New item" while the photo is still on its way.
    public static let placeholderName = "New item"

    /// The category sent when the user doesn't know: vision fills in the real one.
    public static let defaultCategory = "other"

    /// `MAX_NAME` in the module.
    public static let maxNameLength = 120

    /// A fresh id, unique so the app can find the new row (`add_item` can't return its id).
    public static func newScanObjectId(_ uuid: UUID = UUID()) -> String {
        scanObjectIdPrefix + uuid.uuidString.lowercased()
    }

    /// The typed name, trimmed and capped, or the placeholder.
    public static func name(typed: String) -> String {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? placeholderName : String(t.prefix(maxNameLength))
    }

    /// True while the item still has the placeholder name (vision hasn't named it).
    public static func isUnnamed(_ item: Item) -> Bool { item.name == placeholderName }

    /// Rough size chips. Optional: with none, the item has no size (`Item.origin` "Added by photo")
    /// and 3D views draw its kind at the default size.
    public enum Size: String, CaseIterable, Sendable, Identifiable {
        case small, medium, large
        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }

        /// Multiplier on a known kind's default size.
        var scale: Double {
            switch self {
            case .small: 0.6
            case .medium: 1.0
            case .large: 1.4
            }
        }

        /// (w, d, h) in meters when the name doesn't say what it is.
        var generic: (Double, Double, Double) {
            switch self {
            case .small: (0.3, 0.25, 0.3)  // fits in a moving box
            case .medium: (0.6, 0.45, 0.6)
            case .large: (1.2, 0.6, 0.9)
            }
        }
    }

    /// Width, height, depth (m) for a size chip: the default size of the kind the name and
    /// category route to (`VoxelModels`), scaled, or a generic box when they don't say. Nil size = 0 × 0 × 0.
    public static func dims(_ size: Size?, name: String, category: String) -> (widthM: Double, heightM: Double, depthM: Double) {
        guard let size else { return (0, 0, 0) }
        let n = name == placeholderName ? "" : name
        let kind = VoxelModels.routeByName(category: category.lowercased(), name: VName(n.lowercased()))
        let unknown = VoxelModels.routeByName(category: defaultCategory, name: VName(""))
        let def = kind.defaultSize
        let wdh = kind == unknown ? size.generic : (def.0 * size.scale, def.1 * size.scale, def.2 * size.scale)
        func r(_ v: Double) -> Double { min(30, (v * 100).rounded() / 100) }
        return (r(wdh.0), r(wdh.2), r(wdh.1))
    }

    /// The `add_item` object. `photoUrl` nil when the photo hasn't uploaded yet.
    public static func object(scanObjectId: String, name: String, category: String = defaultCategory,
                              size: Size?, photoUrl: String?) -> ScanObject {
        let d = dims(size, name: name, category: category)
        return ScanObject(scanObjectId: scanObjectId, category: category,
                          widthM: d.widthM, heightM: d.heightM, depthM: d.depthM, photoUrl: photoUrl)
    }

    /// The room the sheet picks first: the one whose "+" was tapped, else the newest old-home
    /// room listed (the inventory you're moving), else the newest of any.
    public static func defaultRoom(_ roomsNewestFirst: [Room], preferred: UInt64?) -> Room? {
        roomsNewestFirst.first { $0.id == preferred } ?? roomsNewestFirst.first { $0.home == .old } ?? roomsNewestFirst.first
    }

    /// `MAX_ROOM_NAME` in the module.
    public static let maxRoomNameLength = 80
}
