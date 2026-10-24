import Foundation

/// Which old rooms New Home moves furniture from. Scanning the same room again makes a new
/// room row with the same name, and laying out every scan's kept items brought several beds
/// (decision 0300). So by default only the newest scan of each room name moves; older
/// same-named rooms are treated as re-scans. The user picks rooms in or out in New Home's
/// "Moving from" picker; picks are stored on this device only (UserDefaults
/// `moove.newHome.rooms`, like Inventory's hidden rooms, #271).
public enum MovingRooms {
    public static let defaultsKey = "moove.newHome.rooms"

    /// Stored as "+<room id>" (moved) / "-<room id>" (left behind), since UserDefaults has no UInt64.
    public static func decode(_ stored: [String]?) -> [UInt64: Bool] {
        var out: [UInt64: Bool] = [:]
        for s in stored ?? [] {
            guard let sign = s.first, sign == "+" || sign == "-", let id = UInt64(s.dropFirst()) else { continue }
            out[id] = sign == "+"
        }
        return out
    }

    public static func encode(_ choices: [UInt64: Bool]) -> [String] {
        choices.keys.sorted().map { "\(choices[$0]! ? "+" : "-")\($0)" }
    }

    public struct Choice: Sendable, Hashable, Identifiable {
        public var room: Room
        /// The room's newest scan, if one is visible.
        public var scanDate: Date?
        /// Kept items in the room.
        public var itemCount: Int
        /// Whether its kept items move to the new home.
        public var included: Bool
        /// What `included` is without a user choice: the newest room of its name.
        public var includedByDefault: Bool

        public var id: UInt64 { room.id }

        /// "Bedroom", then "Today 12:49" (when it was scanned) for the chip's meta line.
        public func meta(now: Date = .now) -> String? { scanDate.map { ScanDateLabel.text($0, now: now) } }
    }

    static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Every room in `snapshot`, newest scan first. The newest room of each name that has kept
    /// items is in by default (older same-named ones are re-scans), and so is a room with
    /// nothing kept; `overrides` (the user's picks) win, and ids that no longer exist are ignored.
    public static func choices(_ snapshot: SyncSnapshot, keptItems: [Item], overrides: [UInt64: Bool]) -> [Choice] {
        let counts = Dictionary(keptItems.map { ($0.roomId, 1) }, uniquingKeysWith: +)
        let rooms = snapshot.roomsNewestFirst()
        var seen = Set<String>()
        return rooms.map { room in
            let n = counts[room.id] ?? 0
            let first = n == 0 || seen.insert(key(room.name)).inserted
            return Choice(room: room, scanDate: snapshot.scanDate(ofRoom: room.id), itemCount: n,
                          included: overrides[room.id] ?? first, includedByDefault: first)
        }
    }

    /// The user's picks after tapping `roomId`: flipped, and dropped when it matches the default.
    public static func toggle(_ roomId: UInt64, in choices: [Choice], overrides: [UInt64: Bool]) -> [UInt64: Bool] {
        guard let c = choices.first(where: { $0.id == roomId }) else { return overrides }
        var out = overrides
        let next = !c.included
        out[roomId] = next == c.includedByDefault ? nil : next
        return out
    }

    /// Select all (`true`) or none (`false`).
    public static func setAll(_ included: Bool, in choices: [Choice]) -> [UInt64: Bool] {
        var out: [UInt64: Bool] = [:]
        for c in choices where c.includedByDefault != included { out[c.id] = included }
        return out
    }

    /// Picks for rooms that still exist.
    public static func pruned(_ overrides: [UInt64: Bool], rooms: [Room]) -> [UInt64: Bool] {
        let live = Set(rooms.map(\.id))
        return overrides.filter { live.contains($0.key) }
    }

    /// "Moving from 2 rooms · 14 items" for the summary row; `items` is what will be laid out.
    public static func summary(_ choices: [Choice], items: Int) -> String {
        let n = choices.filter(\.included).count
        guard n > 0 else { return "No rooms selected" }
        return "Moving from \(n) room\(n == 1 ? "" : "s") · \(items) item\(items == 1 ? "" : "s")"
    }

    /// Kept items from the included rooms (items in rooms without a choice row, which have no
    /// room, stay), with near-duplicates from same-named rooms dropped.
    public static func items(_ keptItems: [Item], choices: [Choice]) -> [Item] {
        let out = Set(choices.filter { !$0.included }.map(\.id))
        let order = Dictionary(choices.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(choices.map { ($0.id, key($0.room.name)) }, uniquingKeysWith: { a, _ in a })
        let kept = keptItems.filter { !out.contains($0.roomId) }
            .sorted { (order[$0.roomId] ?? .max, $0.id) < (order[$1.roomId] ?? .max, $1.id) }
        return dedupe(kept, roomName: { names[$0] })
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
