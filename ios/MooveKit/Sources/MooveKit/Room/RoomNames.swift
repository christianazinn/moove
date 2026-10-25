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

    /// What room this probably is, from the objects found in it. Beds win (a studio with a
    /// kitchenette is still where you sleep), then kitchen appliances, bathroom fixtures,
    /// laundry, living-room seating, a dining set, a desk setup and garage gear; else "Room".
    public static func guess(_ objects: [Object]) -> String {
        var counts: [String: Int] = [:]
        for object in objects {
            for word in Set(words(of: object)) { counts[word, default: 0] += 1 }
        }
        func has(_ any: String...) -> Bool { any.contains { (counts[$0] ?? 0) > 0 } }
        func count(_ word: String) -> Int { counts[word] ?? 0 }

        if has("bed", "crib", "mattress", "nightstand", "dresser", "bunk") { return "Bedroom" }
        let kitchenAppliance = has("stove", "oven", "refrigerator", "fridge", "dishwasher", "range", "cooktop")
        if kitchenAppliance || (has("sink") && has("counter", "countertop")) { return "Kitchen" }
        if has("toilet", "bathtub", "tub", "shower") { return "Bathroom" }
        if has("washer", "dryer", "laundry") { return "Laundry" }
        if has("sink") { return "Bathroom" }
        if has("sofa", "couch", "television", "tv", "fireplace") || (has("coffee") && has("table")) { return "Living room" }
        let desk = has("desk") || (has("table") && has("swivel", "office"))
        let screen = has("monitor", "computer", "laptop", "printer")
        if (desk && (screen || has("swivel", "office"))) || (has("desk") && count("chair") > 0) { return "Office" }
        if has("dining") || (count("table") >= 1 && count("chair") >= 3) { return "Dining room" }
        if has("desk") || (screen && has("table", "chair")) { return "Office" }
        if has("bicycle", "bike", "toolbox", "workbench", "mower", "motorcycle", "tools") { return "Garage" }
        return fallback
    }

    /// Lowercased words from the object's name, category and attributes, camelCase split too
    /// ("washerDryer" → washerdryer, washer, dryer; "ChairType.swivel" → chairtype, chair, type, swivel).
    static func words(of object: Object) -> [String] {
        var out: [String] = []
        for text in [object.name ?? "", object.category] + object.attributes where !ObjectRecheck.isRecheckAttribute(text) {
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
