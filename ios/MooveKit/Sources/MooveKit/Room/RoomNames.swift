import Foundation

/// Room names the user picks (Lisa: "can you not call every room a bedroom? let the user name
/// the room"). The scan's photo step prefills a guess from what was found (`guess`), offers
/// quick chips, and suggests "Bedroom 2" when a visible room already has the name (`numbered`).
/// Inventory can rename a room later; until the module's `rename_room` reducer is live, the new
/// name is a local display override (`applying(_:to:)`, UserDefaults `moove.roomNames`).
public enum RoomNames {
    /// One scanned object, as far as the guess cares: its category (RoomPlan's or the
    /// detector's, see `ObjectVocabulary`), RoomPlan attributes and any name the user gave it.
    public struct Object: Sendable, Hashable {
        public var category: String
        public var attributes: [String]
        public var name: String?

        public init(category: String, attributes: [String] = [], name: String? = nil) {
            self.category = category
            self.attributes = attributes
            self.name = name
        }
    }

    /// Quick picks on the scan's photo step ("Other…" clears the field to type a name).
    public static let chips = ["Bedroom", "Living room", "Kitchen", "Bathroom", "Office", "Dining room", "Garage"]
    /// The name when nothing in the room says what it is.
    public static let fallback = "Room"
    /// `MAX_NAME` in the module.
    public static let maxLength = 120

    // MARK: Guess from the scan

    /// What room this probably is, from the objects found in it. Every object votes for the room
    /// it belongs in, strong signs counting most (a bed, a stove, a toilet, a sofa), and the room
    /// with the most points wins, so one misread nightstand no longer makes every room a bedroom
    /// (Lisa). Ties go to the stronger kind: a studio with a kitchenette is still where you sleep.
    /// Under 2 points, it's just "Room".
    public static func guess(_ objects: [Object]) -> String {
        var counts: [String: Int] = [:]
        var score: [String: Int] = [:]
        // Per object: the strongest sign it gives each room (a "washerDryer" counts once).
        let signs: [(room: String, weight: Int, words: Set<String>)] = [
            ("Bedroom", 4, ["bed", "crib", "mattress", "bunk"]),
            ("Bedroom", 2, ["nightstand", "dresser"]),
            ("Kitchen", 3, ["stove", "oven", "refrigerator", "fridge", "dishwasher", "range", "cooktop"]),
            ("Bathroom", 4, ["toilet", "bathtub", "tub", "shower"]),
            ("Laundry", 3, ["washer", "dryer", "laundry"]),
            ("Living room", 3, ["sofa", "couch"]),
            ("Living room", 2, ["television", "tv", "fireplace"]),
            ("Office", 2, ["desk"]),
            ("Office", 1, ["monitor", "computer", "laptop", "printer", "swivel", "office"]),
            ("Dining room", 3, ["dining"]),
            ("Garage", 2, ["bicycle", "bike", "toolbox", "workbench", "mower", "motorcycle", "tools"]),
        ]
        for object in objects {
            let words = Set(words(of: object))
            for word in words { counts[word, default: 0] += 1 }
            var best: [String: Int] = [:]
            for sign in signs where !sign.words.isDisjoint(with: words) {
                best[sign.room] = max(best[sign.room] ?? 0, sign.weight)
            }
            for (room, weight) in best { score[room, default: 0] += weight }
        }
        func has(_ any: String...) -> Bool { any.contains { (counts[$0] ?? 0) > 0 } }
        func count(_ word: String) -> Int { counts[word] ?? 0 }

        // Signs that take two things together.
        if has("sink") { score[has("counter", "countertop") ? "Kitchen" : "Bathroom", default: 0] += has("counter", "countertop") ? 3 : 2 }
        if has("coffee") && has("table") { score["Living room", default: 0] += 2 }
        let screen = has("monitor", "computer", "laptop", "printer")
        if screen && has("table", "chair") { score["Office", default: 0] += 1 }
        if has("desk") && count("chair") > 0 { score["Office", default: 0] += 1 }
        if count("table") >= 1 && count("chair") >= 3 { score["Dining room", default: 0] += 3 }

        let order = ["Bedroom", "Kitchen", "Bathroom", "Laundry", "Living room", "Office", "Dining room", "Garage"]
        guard let top = order.max(by: { (score[$0] ?? 0, order.firstIndex(of: $1)!) < (score[$1] ?? 0, order.firstIndex(of: $0)!) }),
              (score[top] ?? 0) >= 2 else { return fallback }
        return top
    }

    /// Lowercased words from the object's name, category and attributes, camelCase split too
    /// ("washerDryer" → washerdryer, washer, dryer; "ChairType.swivel" → chairtype, chair, type, swivel).
    static func words(of object: Object) -> [String] {
        var out: [String] = []
        for text in [object.name ?? "", object.category] + object.attributes {
            for run in text.split(whereSeparator: { !$0.isLetter }) {
                out.append(run.lowercased())
                var part = ""
                for ch in run {
                    if ch.isUppercase, let last = part.last, last.isLowercase {
                        out.append(part.lowercased())
                        part = ""
                    }
                    part.append(ch)
                }
                if part.count < run.count { out.append(part.lowercased()) }
            }
        }
        return out
    }

    // MARK: Unique names

    /// `name` trimmed, or nil when empty. Long names are cut to `maxLength`.
    public static func clean(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }

    /// Whether a room in `existing` already has `name` (ignoring case and spaces at the ends).
    public static func isTaken(_ name: String, in existing: [String]) -> Bool {
        guard let key = clean(name)?.lowercased() else { return false }
        return existing.contains { clean($0)?.lowercased() == key }
    }

    /// `name` if no room has it, else the base name with the next free number:
    /// "Bedroom" → "Bedroom 2" (or "Bedroom 3" when 2 is taken too); "Bedroom 2" → "Bedroom 3".
    public static func numbered(_ name: String, existing: [String]) -> String {
        let name = clean(name) ?? fallback
        guard isTaken(name, in: existing) else { return name }
        let base = baseName(name)
        var n = 2
        while isTaken("\(base) \(n)", in: existing) { n += 1 }
        return "\(base) \(n)"
    }

    /// "Bedroom 2" → "Bedroom"; "Bedroom" → "Bedroom".
    public static func baseName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count > 1, let last = parts.last, Int(last) != nil else { return name }
        return parts.dropLast().joined(separator: " ")
    }

    // MARK: Local rename overrides (until `rename_room` is live)

    public static let defaultsKey = "moove.roomNames"

    /// UserDefaults key for one database's overrides: room ids are per database.
    public static func defaultsKey(database: String) -> String {
        database.isEmpty || database == "moove" ? defaultsKey : "\(defaultsKey).\(database)"
    }

    public static func decode(_ stored: [String: Any]?) -> [UInt64: String] {
        var out: [UInt64: String] = [:]
        for (key, value) in stored ?? [:] {
            if let id = UInt64(key), let name = value as? String, let name = clean(name) { out[id] = name }
        }
        return out
    }

    public static func encode(_ names: [UInt64: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
    }

    /// The overrides the synced rooms don't show yet. One whose room already has that name
    /// (`rename_room` landed) is dropped; one whose room isn't in `rooms` is kept, since a
    /// snapshot can be partway through subscribing.
    public static func pending(_ names: [UInt64: String], rooms: [Room]) -> [UInt64: String] {
        let byId = Dictionary(rooms.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return names.filter { id, name in byId[id] != name }
    }
}

extension SyncSnapshot {
    /// The snapshot with the user's local room names (`RoomNames` overrides) in place of the
    /// synced ones, so every screen that shows `room.name` shows the name the user chose.
    public func renamingRooms(_ names: [UInt64: String]) -> SyncSnapshot {
        guard !names.isEmpty else { return self }
        var copy = self
        for i in copy.rooms.indices {
            if let name = names[copy.rooms[i].id] { copy.rooms[i].name = name }
        }
        return copy
    }
}
