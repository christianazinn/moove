import Foundation

/// Naming items yourself, before the import (the scan checklist's "Name it…") and after it
/// (Review's "Needs a name", the room card's Rename / What is it?). No contract change:
/// - Before: a label rides along in `import_scan_v2` as the object's `name` / `category`, and
///   a picked kind as its `UserKind.*` attribute (`ItemFix`), so the voxel model follows it.
/// - Vision still runs on a named item (it has a photo) and its `set_item_details` replaces the
///   name, so the app keeps the user's name (`MooveStore.keptNames`) and puts it back with
///   `rename_item` once vision is done (`keptNameWork`).
public enum ItemLabels {
    /// What the user called one scanned object before import. Either part may be missing.
    public struct Label: Hashable, Sendable {
        public var name: String
        public var kind: ItemFix.QuickKind?

        public init(name: String = "", kind: ItemFix.QuickKind? = nil) {
            self.name = name
            self.kind = kind
        }

        /// The name as sent: trimmed and capped at the module's `MAX_NAME`; nil when empty.
        public var cleanName: String? {
            let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(FixtureBackend.maxNameLength))
            return n.isEmpty ? nil : n
        }

        /// The chip, unless it's "Other" (automatic).
        public var pickedKind: ItemFix.QuickKind? { kind == .other ? nil : kind }

        /// Nothing chosen: same as no label.
        public var isEmpty: Bool { cleanName == nil && pickedKind == nil }

        /// What the checklist row shows: the name, else the kind.
        public var title: String? { cleanName ?? pickedKind?.label }
    }

    // MARK: Placeholder names

    /// Names that only say Moove doesn't know what it is yet.
    static let placeholderNames: Set<String> = [
        "other", "others", "unidentified", "unidentified item", "unknown", "unknown item", "unknown object",
        "item", "object", "thing", "misc", "miscellaneous", "n/a",
    ]

    /// True for an empty name, "Other" / "Unidentified item" and the like, or the unknown
    /// category's own name (what the module stores for an `other` object with no name).
    public static func isPlaceholderName(_ name: String, category: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.isEmpty || placeholderNames.contains(n) { return true }
        return category.lowercased() == ObjectSanity.relabelCategory && n == category.lowercased()
    }

    /// Vision hasn't finished with it yet (the live backend says so; fixtures don't).
    public static func isIdentifying(_ item: Item) -> Bool {
        item.detailsStatus == .pending || item.detailsStatus == .running
    }

    /// Review's "Needs a name": items still called by a placeholder, oldest first.
    public static func needingNames(_ items: [Item]) -> [Item] {
        items.filter { isPlaceholderName($0.name, category: $0.category) }.sorted { $0.id < $1.id }
    }

    /// The one-line hint under a "Needs a name" row.
    public static func hint(for item: Item) -> String {
        if isIdentifying(item) && !item.photoUrls.isEmpty { return "Moove is naming it from its photo · or name it yourself" }
        if item.detailsStatus == .failed { return "Moove couldn't tell from the photo · name it or pick what it is" }
        return "Name it or pick what it is, so the 3D model looks right"
    }

    // MARK: Carry-over into the import

    /// The Moove category a "What is it?" chip stands for (RoomPlan's names where it has one,
    /// so size checks and the voxel router read it like a scanned one). nil for "Other".
    public static func category(for kind: ItemFix.QuickKind) -> String? {
        switch kind {
        case .table, .desk: "table"
        case .chair: "chair"
        case .sofa: "sofa"
        case .bed: "bed"
        case .dresser, .shelf: "storage"
        case .lamp: "lamp"
        case .plant: "plant"
        case .tv: "television"
        case .box: "box"
        case .other: nil
        }
    }

    /// `object` with the user's label applied: the name, the kind's category, and the kind as
    /// `UserKind.*` (or, for a name alone, the kind the name implies, as a rename does after
    /// import). No label, or an empty one, returns it unchanged.
    public static func applying(_ label: Label?, to object: ScanObject) -> ScanObject {
        guard let label, !label.isEmpty else { return object }
        var o = object
        if let name = label.cleanName { o.name = name }
        if let kind = label.pickedKind {
            o.category = category(for: kind) ?? o.category
            o.attributes = ItemFix.setting(kind, in: o.attributes)
        } else if let name = label.cleanName {
            o.attributes = ItemFix.renamed(to: name, attributes: o.attributes)
        }
        return o
    }

    // MARK: Keeping the user's name through vision

    /// What to do with the names the app is keeping (item id → name), given the current items:
    /// `renames` puts the user's name back wherever it differs, `settled` lists ids that need no
    /// more watching (vision is done with them, or the item is gone). While vision is still
    /// identifying, the name is put back but kept, since vision's answer is still to come.
    public static func keptNameWork(_ kept: [UInt64: String], items: [Item])
        -> (renames: [UInt64: String], settled: Set<UInt64>) {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var renames: [UInt64: String] = [:]
        var settled: Set<UInt64> = []
        for (id, name) in kept {
            guard let item = byId[id] else { settled.insert(id); continue }
            if item.name != name { renames[id] = name }
            if !isIdentifying(item) { settled.insert(id) }
        }
        return (renames, settled)
    }

    /// The imported items (matched by scan object id) that got a user name, item id → name.
    public static func keptNames(for labels: [String: Label], in items: [Item]) -> [UInt64: String] {
        var out: [UInt64: String] = [:]
        for item in items {
            guard let key = item.scanObjectId, let name = labels[key]?.cleanName else { continue }
            out[item.id] = name
        }
        return out
    }

    // MARK: Persisting (UserDefaults)

    public static let keptNamesDefaultsKey = "moove.keptNames"

    public static func encode(_ kept: [UInt64: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: kept.map { (String($0.key), $0.value) })
    }

    public static func decode(_ raw: [String: Any]?) -> [UInt64: String] {
        var out: [UInt64: String] = [:]
        for (k, v) in raw ?? [:] {
            if let id = UInt64(k), let name = v as? String { out[id] = name }
        }
        return out
    }
}
