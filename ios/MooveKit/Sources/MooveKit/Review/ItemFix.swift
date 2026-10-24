import Foundation

/// Fix-it edits for a misread scan item (rename, "What is it?", turn around), stored in the
/// item's existing `attributes` (`set_item_attributes`, no contract change). Attributes must look
/// like `Type.value` (the module's `ATTRIBUTE_RE`), so the user's choices are:
/// - `UserKind.<voxel kind>` (`UserKind.table`): the voxel model to draw. Routing honors it
///   before anything else (`VoxelModels.route`).
/// - `UserRotate.<90|180|270>`: degrees added to the scanned facing in the dollhouse
///   (`Placement` rotation, every view that places scanned items).
/// Everything else (RoomPlan's `StorageType.shelf`, `Mount.wall`, ...) is kept as is.
public enum ItemFix {
    public static let kindType = "UserKind"
    public static let rotateType = "UserRotate"

    /// The "What is it?" chips.
    public enum QuickKind: String, CaseIterable, Sendable, Identifiable {
        case table, chair, sofa, bed, desk, dresser, shelf, lamp, plant, tv, box, other

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .tv: "TV"
            default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
            }
        }

        /// The voxel builder it asks for; nil for `.other` (clears the choice, back to automatic).
        var voxelKind: VoxelModels.Kind? {
            switch self {
            case .table: .table
            case .chair: .chair
            case .sofa: .sofa
            case .bed: .bed
            case .desk: .desk
            case .dresser: .dresser
            case .shelf: .bookshelf
            case .lamp: .lamp
            case .plant: .plant
            case .tv: .tv
            case .box: .box
            case .other: nil
            }
        }

        /// The `UserKind.*` attribute for this chip (nil for `.other`).
        public var attribute: String? { voxelKind.map { "\(ItemFix.kindType).\($0.rawValue)" } }
    }

    // MARK: Reading

    /// The user's `UserKind.*` value as written (e.g. "table", "bookshelf"), if any.
    public static func userKind(in attributes: [String]) -> String? {
        value(of: kindType, in: attributes)
    }

    /// The chip matching the user's kind choice, if one does.
    public static func quickKind(in attributes: [String]) -> QuickKind? {
        guard let v = userKind(in: attributes)?.lowercased() else { return nil }
        return QuickKind.allCases.first { $0.voxelKind?.rawValue.lowercased() == v }
    }

    /// The user's extra turn: 0, 90, 180 or 270.
    public static func turnDeg(in attributes: [String]) -> Int {
        guard let v = value(of: rotateType, in: attributes), let d = Int(v) else { return 0 }
        return [90, 180, 270].contains(d) ? d : 0
    }

    /// Voxel routing (lowercased attributes): the kind the user picked, if it names a builder.
    static func voxelKind(lowercasedAttributes attrs: Set<String>) -> VoxelModels.Kind? {
        let prefix = kindType.lowercased() + "."
        guard let raw = attrs.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count) else { return nil }
        return VoxelModels.Kind.allCases.first { $0.rawValue.lowercased() == raw }
    }

    // MARK: Writing (each returns the full new attribute list)

    /// Sets (or, with `.other`, clears) the user's kind; other attributes stay in order.
    public static func setting(_ kind: QuickKind, in attributes: [String]) -> [String] {
        replacing(kindType, with: kind.attribute, in: attributes)
    }

    /// "Turn around": adds 180° to the user's turn (0 ↔ 180, 90 ↔ 270).
    public static func turningAround(_ attributes: [String]) -> [String] {
        settingTurn((turnDeg(in: attributes) + 180) % 360, in: attributes)
    }

    /// "Rotate 90°": 0 → 90 → 180 → 270 → 0.
    public static func rotating90(_ attributes: [String]) -> [String] {
        settingTurn((turnDeg(in: attributes) + 90) % 360, in: attributes)
    }

    public static func settingTurn(_ deg: Int, in attributes: [String]) -> [String] {
        let d = ((deg % 360) + 360) % 360
        return replacing(rotateType, with: [90, 180, 270].contains(d) ? "\(rotateType).\(d)" : nil, in: attributes)
    }

    // MARK: Names

    /// Names that say nothing about the item ("Storage", "Object", or just its category), which a
    /// "What is it?" chip may replace with its own word.
    public static func isGenericName(_ name: String, category: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.isEmpty || n == category.trimmingCharacters(in: .whitespaces).lowercased() { return true }
        if QuickKind.allCases.contains(where: { $0.label.lowercased() == n }) { return true }
        return genericNames.contains(n)
    }

    static let genericNames: Set<String> = [
        "item", "object", "thing", "unknown", "other", "storage", "furniture", "cabinet", "shelf", "shelving",
        "table", "chair", "sofa", "bed", "television", "tv", "lamp", "decor", "box", "fixture", "appliance",
        "unidentified item", "unknown item", "unknown object",
    ]

    /// What a chip does to an item: the new name (nil: keep the current one) and attributes.
    public static func apply(_ kind: QuickKind, name: String, category: String, attributes: [String])
        -> (name: String?, attributes: [String]) {
        let rename = kind != .other && isGenericName(name, category: category) && name != kind.label
        return (rename ? kind.label : nil, setting(kind, in: attributes))
    }

    /// After a rename: the attributes that make the voxel model follow the new name. A name that
    /// names a builder ("Coffee table") becomes the user's kind, so it beats RoomPlan's own
    /// attributes (a `StorageType.cabinet` would otherwise keep drawing a cabinet). A name that
    /// names nothing ("Grandma's") leaves the attributes alone.
    public static func renamed(to name: String, attributes: [String]) -> [String] {
        let n = VName(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let kind = VoxelModels.routeByName(category: "", name: n)
        if kind == .box && !n.word("box", "boxes", "crate", "bin") { return attributes }
        return replacing(kindType, with: "\(kindType).\(kind.rawValue)", in: attributes)
    }

    // MARK: Placement

    /// `rotationDeg` plus the user's turn, in [0, 360).
    public static func rotationDeg(_ deg: Double, turnedBy attributes: [String]) -> Double {
        let turn = turnDeg(in: attributes)
        guard turn != 0 else { return deg }
        let r = (deg + Double(turn)).truncatingRemainder(dividingBy: 360)
        let n = r < 0 ? r + 360 : r
        return n >= 360 - 1e-9 ? 0 : n
    }

    /// `placements` with each item's user turn applied (items matched by id).
    public static func applyingTurns(_ placements: [Placement], items: [Item]) -> [Placement] {
        let turns = Dictionary(items.map { ($0.id, $0.attributes) }, uniquingKeysWith: { a, _ in a })
        return placements.map { p in
            guard let attrs = turns[p.itemId] else { return p }
            var q = p
            q.rotationDeg = rotationDeg(p.rotationDeg, turnedBy: attrs)
            return q
        }
    }

    // MARK: Helpers

    private static func value(of type: String, in attributes: [String]) -> String? {
        let prefix = type.lowercased() + "."
        return attributes.last { $0.lowercased().hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// Drops every `type.*` attribute and appends `new` (if any), keeping the rest in order.
    private static func replacing(_ type: String, with new: String?, in attributes: [String]) -> [String] {
        let prefix = type.lowercased() + "."
        var out = attributes.filter { !$0.lowercased().hasPrefix(prefix) }
        if let new { out.append(new) }
        return out
    }
}

public extension Item {
    /// The user's `UserKind.*` choice only, for views that don't carry RoomPlan's attributes
    /// (`LayoutItem`: the dollhouse and new-home 3D views).
    var userKindAttributes: [String] {
        attributes.filter { $0.lowercased().hasPrefix(ItemFix.kindType.lowercased() + ".") }
    }

    /// `attributes` without the user's turn, which only moves the placement (so turning an item
    /// doesn't re-seed or rebuild its voxel model).
    var modelAttributes: [String] {
        attributes.filter { !$0.lowercased().hasPrefix(ItemFix.rotateType.lowercased() + ".") }
    }

    /// The user's extra turn (`UserRotate.*`): 0, 90, 180 or 270.
    var userTurnDeg: Int { ItemFix.turnDeg(in: attributes) }
}
