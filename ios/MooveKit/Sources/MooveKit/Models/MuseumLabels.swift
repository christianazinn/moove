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

    /// "from the Bedroom" under the placard; "my room" / "the attic" keep their own article.
    public static func fromRoom(_ roomName: String) -> String {
        let name = roomName.trimmingCharacters(in: .whitespaces)
        let lower = name.lowercased()
        if name.isEmpty { return "from an unnamed room" }
        return lower.hasPrefix("the ") || lower.hasPrefix("my ") ? "from \(name)" : "from the \(name)"
    }

    // The worker's sort rules (agents/src/agents/sort.ts): $60 per m³ (at least $2), fragile ×1.5.
    static let moveCentsPerM3: Double = 6000
    static let minMoveCents: Double = 200

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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}
