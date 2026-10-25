import Foundation

// Inventory as a small museum: items hang in halls by function (`FunctionHall`), each an exhibit with a placard
// (name, catalog line, when it was catalogued, a one-line story). Everything here is
// honest about what Moove knows: there are no purchase dates, so the date is when the
// item was catalogued (its room's scan, else its last update), and a year only appears
// when the user wrote one in their own story. UI only; no contract change.

public enum MuseumLabel {
    /// "12 pieces · est. $1,049"; no value part while nothing is priced.
    public static func piecesLine(pieces: Int, valueCents: Int64) -> String {
        let count = pieces == 1 ? "1 piece" : "\(pieces) pieces"
        return valueCents > 0 ? "\(count) · est. \(dollars(valueCents))" : count
    }

    /// The short line under the name: "IKEA · 140 × 195 cm", or just the size. Brand only
    /// when known (no material: Lisa wanted less text), then the size: footprint (W × D) for
    /// low pieces like beds and tables, face (W × H) for upright ones. "≈" when the size is an
    /// estimate (room photos, a hand-added item's typical size). Falls back to the category
    /// when there's no size.
    public static func catalogLine(_ item: Item) -> String {
        let brand = item.brand?.trimmingCharacters(in: .whitespaces).nonEmpty
        guard let size = sizeText(item) else { return brand ?? Item.readableCategory(item.category).capitalizedFirstLetter }
        return brand.map { "\($0) · \(size)" } ?? size
    }

    static func sizeText(_ item: Item) -> String? {
        guard item.origin != .photo else { return nil }
        let w = cm(item.widthM), d = cm(item.depthM), h = cm(item.heightM)
        let low = item.heightM < min(item.widthM, item.depthM)
        let (a, b) = low ? (w, d) : (w, h)
        guard a > 0, b > 0 else { return nil }
        let estimated = item.origin == .roomPhotos || item.origin == .manual
        return "\(estimated ? "≈" : "")\(a) × \(b) cm"
    }

    private static func cm(_ m: Double) -> Int { m > 0 ? Int((m * 100).rounded()) : 0 }

    /// "Catalogued Oct 24, 2026", or "Acquired 1974 · catalogued Oct 24, 2026" when the
    /// user's story names a year.
    public static func acquiredLine(cataloguedAt date: Date, story: String?, now: Date = .now,
                                    calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        let day = f.string(from: date)
        if let year = story.flatMap({ storyYear($0, now: now, calendar: calendar) }) {
            return "Acquired \(year) · catalogued \(day)"
        }
        return "Catalogued \(day)"
    }

    /// The first plausible year in the user's story ("Grandma's, 1974" → 1974): 1900
    /// through this year, as a whole number (not part of "12345" or "1974s" stays 1974).
    public static func storyYear(_ story: String, now: Date = .now, calendar: Calendar = .current) -> Int? {
        let thisYear = calendar.component(.year, from: now)
        let chars = Array(story)
        var i = 0
        while i < chars.count {
            guard chars[i].isASCII, chars[i].isNumber else { i += 1; continue }
            var j = i
            while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
            if j - i == 4, let y = Int(String(chars[i..<j])), (1900...thisYear).contains(y) { return y }
            i = j
        }
        return nil
    }

    /// One honest line about the piece, from what Moove knows. `isTopPiece`: the most
    /// valuable priced piece in its hall.
    public static func autoStory(_ item: Item, isTopPiece: Bool = false) -> String {
        if item.dispositionSource == .user {
            switch item.disposition {
            case .keep: return "Coming along: your call."
            case .sell: return "Headed for sale: your call."
            case .donate: return "Off to a new home: your call."
            case .trash: return "Leaving the collection: your call."
            case .undecided: break
            }
        }
        if item.maybeSentimental { return "Possibly sentimental. Moove leaves this one to you." }
        if item.isBuiltInFixture { return "Part of the building; it stays." }
        if item.priceState == .identifying { return "Still being identified from its photo." }
        if item.origin == .roomPhotos { return "Spotted in the room photos; size estimated." }
        if case .priced(let v) = item.priceState, v > 0 {
            if isTopPiece { return "Worth ~\(dollars(v)), the hall's most valuable piece." }
            if item.origin != .photo {
                let cost = moveCostCents(item)
                if v < sellMinCents { return "Worth ~\(dollars(v)), too little to list." }
                if Double(v) < Double(cost) * keepMargin { return "Worth ~\(dollars(v)), cheaper to sell than to move." }
            }
        }
        if item.fragile { return "Fragile; handle with care." }
        switch item.origin {
        case .scan: return "Measured by the LiDAR scan."
        case .manual: return "Added by hand."
        case .photo: return "Added from its photo."
        case .roomPhotos: return "Spotted in the room photos; size estimated."
        }
    }

    /// "from the Bedroom" under the placard; "my room" / "the attic" keep their own article.
    public static func fromRoom(_ roomName: String) -> String {
        let name = roomName.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()
        if name.isEmpty { return "from an unnamed room" }
        return lower.hasPrefix("the ") || lower.hasPrefix("my ") ? "from \(name)" : "from the \(name)"
    }

    // The worker's sort rules (agents/src/agents/sort.ts), so the story agrees with the
    // keep/sell call: $60 per m³ (at least $2), fragile ×1.5, keep only at 1.25× the move.
    static let moveCentsPerM3: Double = 6000
    static let minMoveCents: Double = 200
    static let sellMinCents: Int64 = 2500
    static let keepMargin = 1.25

    public static func moveCostCents(_ item: Item) -> Int64 {
        let vol = max(0, item.widthM) * max(0, item.heightM) * max(0, item.depthM)
        return Int64((max(minMoveCents, vol * moveCentsPerM3) * (item.fragile ? 1.5 : 1)).rounded())
    }

    /// Whole dollars with thousands separators: 104_900 → "$1,049".
    static func dollars(_ cents: Int64) -> String {
        let whole = Int64((Double(cents) / 100).rounded())
        let digits = String(abs(whole))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (whole < 0 ? "-$" : "$") + out
    }

    /// The most valuable priced piece among `items` (ties: lowest id), the hall's centerpiece.
    public static func topPiece(_ items: [Item]) -> UInt64? {
        items.filter { ($0.saleValueCents ?? 0) > 0 }
            .max { a, b in
                let va = a.saleValueCents ?? 0, vb = b.saleValueCents ?? 0
                return va != vb ? va < vb : a.id > b.id
            }?.id
    }
}

/// The user's own one-line placard stories ("Grandma's, 1974"), kept on this device in
/// UserDefaults as a JSON object of item id → story. (A synced `item.story` column would
/// share them across phones; that's a contract change for later.)
public enum ItemStories {
    public static let defaultsKey = "moove.itemStories"
    public static let maxLength = 60

    public static func decode(_ json: String) -> [UInt64: String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String] else { return [:] }
        var out: [UInt64: String] = [:]
        for (key, value) in object {
            if let id = UInt64(key), let story = clean(value) { out[id] = story }
        }
        return out
    }

    public static func encode(_ stories: [UInt64: String]) -> String {
        let object = Dictionary(uniqueKeysWithValues: stories.compactMap { id, s in clean(s).map { (String(id), $0) } })
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// One line, trimmed, at most `maxLength` characters; nil when empty.
    public static func clean(_ story: String) -> String? {
        let oneLine = story.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return nil }
        return String(oneLine.prefix(maxLength))
    }

    /// `json` with `story` set for `id` (or removed when it cleans to nothing).
    public static func setting(_ story: String, for id: UInt64, in json: String) -> String {
        var all = decode(json)
        all[id] = clean(story)
        return encode(all)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
