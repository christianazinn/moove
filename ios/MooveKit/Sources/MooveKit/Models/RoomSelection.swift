import Foundation

/// **Rooms in this move**: the one per-device choice of which scanned rooms count. It replaced
/// three overlapping ones: Inventory's room focus (#336), Hide room (#271) and Move's "Moving
/// from" picks (#307/#320). A room that isn't selected is out of Inventory, Review, Scan home
/// and Move (layout, fly-in, truck, boxes); Listings, Shopping and Agents still show every
/// room's money. Nothing is deleted from the database.
///
/// Scanning a room again makes a new room row with the same name, so by default only the
/// newest scan of each room name is in; older same-named rooms are re-scans (decision 0300).
/// A room with no items is in and doesn't claim its name. Only the user's changes to that
/// default are stored (UserDefaults `moove.rooms`), so a new scan joins on its own and a
/// re-scan replaces its older namesake.
public enum RoomSelection {
    public static let defaultsKey = "moove.rooms"
    /// Keys of the three choices this replaced; `load(from:)` folds them in once.
    public static let legacyHiddenKey = "moove.hiddenRooms"
    public static let legacyFocusKey = "moove.inventory.focusRooms"
    public static let legacyMovingKey = "moove.newHome.rooms"

    public struct Choice: Sendable, Hashable, Identifiable {
        public var room: Room
        public var selected: Bool
        /// What `selected` is without a user choice: the newest room of its name.
        public var selectedByDefault: Bool

        public var id: UInt64 { room.id }
    }

    // MARK: Storage

    /// Stored as "+<room id>" (in) / "-<room id>" (out), since UserDefaults has no UInt64.
    public static func decode(_ stored: [String]?) -> [UInt64: Bool] {
        var out: [UInt64: Bool] = [:]
        for s in stored ?? [] {
            guard let sign = s.first, sign == "+" || sign == "-", let id = UInt64(s.dropFirst()) else { continue }
            out[id] = sign == "+"
        }
        return out
    }

    public static func encode(_ overrides: [UInt64: Bool]) -> [String] {
        overrides.keys.sorted().map { "\(overrides[$0]! ? "+" : "-")\($0)" }
    }

    /// One set of overrides from the old choices: the "Moving from" picks (same format), then
    /// focused rooms in, then hidden rooms out (hiding was the strongest "not this one").
    /// Focus only narrowed Inventory for a while, so rooms outside it aren't taken out.
    public static func migrate(hidden: [String]?, focus: String?, moving: [String]?) -> [UInt64: Bool] {
        var out = decode(moving)
        for id in (focus ?? "").split(separator: ",").compactMap({ UInt64($0) }) { out[id] = true }
        for id in (hidden ?? []).compactMap(UInt64.init) { out[id] = false }
        return out
    }

    /// The saved overrides. The first time, folds the old keys in (`migrate`), saves the result
    /// and removes them. `scope` maps a key to this backend's and database's copy (the app keeps
    /// one per database; Inventory's focus was never scoped, so it's read as is).
    public static func load(from defaults: UserDefaults, scope: (String) -> String = { $0 }) -> [UInt64: Bool] {
        if let stored = defaults.stringArray(forKey: scope(defaultsKey)) { return decode(stored) }
        let out = migrate(hidden: defaults.stringArray(forKey: scope(legacyHiddenKey)),
                          focus: defaults.string(forKey: legacyFocusKey),
                          moving: defaults.stringArray(forKey: scope(legacyMovingKey)))
        save(out, to: defaults, scope: scope)
        for key in [scope(legacyHiddenKey), legacyFocusKey, scope(legacyMovingKey)] { defaults.removeObject(forKey: key) }
        return out
    }

    public static func save(_ overrides: [UInt64: Bool], to defaults: UserDefaults, scope: (String) -> String = { $0 }) {
        defaults.set(encode(overrides), forKey: scope(defaultsKey))
    }

    // MARK: Choices

    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Every room in `snapshot`, newest scan first, with whether it's selected: `overrides`
    /// win, else the newest room of each name (built-in fixtures don't count as items).
    public static func choices(_ snapshot: SyncSnapshot, overrides: [UInt64: Bool]) -> [Choice] {
        let withItems = Set(snapshot.items.lazy.filter { !$0.isBuiltInFixture }.map(\.roomId))
        var seen = Set<String>()
        return snapshot.roomsNewestFirst().map { room in
            let first = !withItems.contains(room.id) || seen.insert(key(room.name)).inserted
            return Choice(room: room, selected: overrides[room.id] ?? first, selectedByDefault: first)
        }
    }

    /// Room ids that are left out.
    public static func unselected(_ choices: [Choice]) -> Set<UInt64> {
        Set(choices.lazy.filter { !$0.selected }.map(\.id))
    }

    /// The overrides after tapping `roomId`: flipped, and dropped when it matches the default.
    public static func toggle(_ roomId: UInt64, in choices: [Choice], overrides: [UInt64: Bool]) -> [UInt64: Bool] {
        guard let c = choices.first(where: { $0.id == roomId }) else { return overrides }
        var out = overrides
        let next = !c.selected
        out[roomId] = next == c.selectedByDefault ? nil : next
        return out
    }

    /// Select all (`true`) or none (`false`).
    public static func setAll(_ selected: Bool, in choices: [Choice]) -> [UInt64: Bool] {
        var out: [UInt64: Bool] = [:]
        for c in choices where c.selectedByDefault != selected { out[c.id] = selected }
        return out
    }

    /// Overrides for rooms that still exist.
    public static func pruned(_ overrides: [UInt64: Bool], rooms: [Room]) -> [UInt64: Bool] {
        let live = Set(rooms.map(\.id))
        return overrides.filter { live.contains($0.key) }
    }

    // MARK: Moving

    /// `items` newest room first, with near-duplicates from same-named selected rooms dropped
    /// (a re-scan the user kept in). Move lays out, packs and loads these.
    public static func moving(_ items: [Item], in snapshot: SyncSnapshot) -> [Item] {
        let rooms = snapshot.roomsNewestFirst()
        let order = Dictionary(rooms.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(rooms.map { ($0.id, key($0.name)) }, uniquingKeysWith: { a, _ in a })
        let sorted = items.sorted { (order[$0.roomId] ?? .max, $0.id) < (order[$1.roomId] ?? .max, $1.id) }
        return dedupe(sorted, roomName: { names[$0] })
    }

    /// Drops an item when an earlier one (newest room first) from a different room with the same
    /// name is the same kind of piece at about the same size (each earlier item matches once).
    /// Rooms with different names are never deduped: two kids' rooms can have the same bed.
    public static func dedupe(_ items: [Item], roomName: (UInt64) -> String?) -> [Item] {
        var kept: [(item: Item, role: DesignRole, matched: Bool)] = []
        var out: [Item] = []
        for item in items {
            let role = DesignRole.of(LayoutItem(item))
            let name = roomName(item.roomId)
            if let name, let i = kept.firstIndex(where: { k in
                !k.matched && k.item.roomId != item.roomId && roomName(k.item.roomId) == name && k.role == role && similar(k.item, item)
            }) {
                kept[i].matched = true
                continue
            }
            kept.append((item, role, false))
            out.append(item)
        }
        return out
    }

    /// Footprint and height within 15% (at least 12 cm), either way round.
    static func similar(_ a: Item, _ b: Item) -> Bool {
        func close(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= max(0.12, 0.15 * max(x, y)) }
        let h = close(a.heightM, b.heightM)
        return h && ((close(a.widthM, b.widthM) && close(a.depthM, b.depthM)) || (close(a.widthM, b.depthM) && close(a.depthM, b.widthM)))
    }
}

extension SyncSnapshot {
    /// The snapshot with only the selected rooms (and items in no room).
    public func selectingRooms(_ overrides: [UInt64: Bool]) -> SyncSnapshot {
        hidingRooms(RoomSelection.unselected(RoomSelection.choices(self, overrides: overrides)))
    }
}
