import Foundation

// Inventory display helpers (#267): where an item came from, which scan a room
// section is, and rooms the user hid on this device. UI only; no contract change.

/// Room ids hidden on this device (Inventory > room header > Hide room), stored in
/// UserDefaults as strings because UserDefaults has no UInt64.
public enum HiddenRooms {
    public static let defaultsKey = "moove.hiddenRooms"

    public static func decode(_ stored: [String]?) -> Set<UInt64> {
        Set((stored ?? []).compactMap(UInt64.init))
    }

    public static func encode(_ ids: Set<UInt64>) -> [String] {
        ids.sorted().map(String.init)
    }
}

extension SyncSnapshot {
    /// The snapshot without the hidden rooms and their items, so every screen that
    /// totals or lays out the inventory agrees on what's visible.
    public func hidingRooms(_ hidden: Set<UInt64>) -> SyncSnapshot {
        guard !hidden.isEmpty else { return self }
        var copy = self
        copy.rooms.removeAll { hidden.contains($0.id) }
        copy.items.removeAll { hidden.contains($0.roomId) }
        return copy
    }

    /// When the room was last scanned (its newest scan), nil when no scan row is visible.
    public func scanDate(ofRoom roomId: UInt64) -> Date? {
        latestScan(ofRoom: roomId)?.createdAt
    }

    /// Rooms with the most recently scanned first; rooms without a visible scan go
    /// last, newest room id first.
    public func roomsNewestFirst(_ rooms: [Room]? = nil) -> [Room] {
        (rooms ?? self.rooms).sorted { a, b in
            let da = scanDate(ofRoom: a.id) ?? .distantPast, db = scanDate(ofRoom: b.id) ?? .distantPast
            return da != db ? da > db : a.id > b.id
        }
    }

    /// A room made by "Load demo scan": it holds the demo bedroom's items ("demo-<n>").
    /// Sweep items added later don't make it less of a demo room.
    public func isDemoRoom(_ roomId: UInt64) -> Bool {
        items.contains { $0.roomId == roomId && DemoFixtures.isDemoItem($0) }
    }
}

extension Item {
    /// The short chip Inventory shows on each row.
    public enum OriginTag: String, Sendable, CaseIterable {
        /// A measured box from the LiDAR scan. RoomPlan and the extra detector can't be
        /// told apart from synced data (both use UUID scan object ids).
        case scanned
        /// Added by the room photo sweep (#92).
        case fromPhotos
        /// Added by its photo during scan review (no size).
        case addedByPhoto
        /// Added by hand in Inventory.
        case addedByYou
        /// In a room someone else shared with me (#10).
        case shared

        public var label: String {
            switch self {
            case .scanned: "Scanned"
            case .fromPhotos: "From photos"
            case .addedByPhoto: "Added by photo"
            case .addedByYou: "Added by you"
            case .shared: "Shared"
            }
        }

        public var accessibilityLabel: String {
            switch self {
            case .scanned: "Scanned with LiDAR"
            case .fromPhotos: "From room photos"
            case .addedByPhoto: "Added by photo"
            case .addedByYou: "Added by you"
            case .shared: "From a shared room"
            }
        }
    }

    public func originTag(inSharedRoom shared: Bool) -> OriginTag {
        if shared { return .shared }
        switch origin {
        case .scan: return .scanned
        case .roomPhotos: return .fromPhotos
        case .photo: return .addedByPhoto
        case .manual: return .addedByYou
        }
    }

    /// The scanner's own category when the item's category has since changed (a photo
    /// sweep match or the vision pass renamed it), else nil. `scannedCategory` is the
    /// category of this item's object in the scan geometry. "other" boxes are meant to
    /// be named later, so they don't count as renamed.
    public func renamedFrom(scannedCategory: String?) -> String? {
        guard origin == .scan, let scanned = scannedCategory?.trimmingCharacters(in: .whitespaces),
              !scanned.isEmpty, scanned.lowercased() != "other",
              scanned.lowercased() != category.lowercased() else { return nil }
        return Self.readableCategory(scanned)
    }

    /// RoomPlan's camel-case names read as words ("washerDryer" → "washer dryer").
    static func readableCategory(_ category: String) -> String {
        var out = ""
        for ch in category {
            if ch.isUppercase, !out.isEmpty { out.append(" ") }
            out.append(contentsOf: ch.lowercased())
        }
        return out
    }
}

/// "Today 10:42", "Yesterday 18:03", "Oct 22 10:42": when a room was scanned.
public enum ScanDateLabel {
    public static func text(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        let clock = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(clock)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(clock)"
        }
        let day = DateFormatter()
        day.locale = locale
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        day.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return "\(day.string(from: date)) \(clock)"
    }
}
