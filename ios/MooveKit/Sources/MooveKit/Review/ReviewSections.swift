import Foundation

/// Groups items for the review screen. "Needs you" comes first, with
/// possibly sentimental items at the top, because those are never auto-decided.
public enum ReviewSection: String, CaseIterable, Sendable, Identifiable {
    case needsYou, keep, sell, donate, trash

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .keep: "Keep"
        case .sell: "Sell"
        case .donate: "Donate"
        case .trash: "Trash"
        }
    }

    public static func of(_ item: Item) -> ReviewSection {
        if item.needsUser && item.dispositionSource != .user { return .needsYou }
        switch item.disposition {
        case .keep: return .keep
        case .sell: return .sell
        case .donate: return .donate
        case .trash: return .trash
        case .undecided: return .needsYou
        }
    }
}

public struct ReviewTotals: Equatable, Sendable {
    public var expectedSaleCents: Int64
    public var itemsToMove: Int
    public var volumeToMoveM3: Double
    public var needsYou: Int
    public var divertedFromLandfill: Int
}

public enum Review {
    /// Non-empty sections in display order, each sorted for scanning.
    public static func sections(_ items: [Item]) -> [(section: ReviewSection, items: [Item])] {
        let grouped = Dictionary(grouping: items, by: ReviewSection.of)
        return ReviewSection.allCases.compactMap { section in
            guard var rows = grouped[section], !rows.isEmpty else { return nil }
            rows.sort { a, b in
                if section == .needsYou, a.maybeSentimental != b.maybeSentimental { return a.maybeSentimental }
                if (a.estValueCents ?? 0) != (b.estValueCents ?? 0) { return (a.estValueCents ?? 0) > (b.estValueCents ?? 0) }
                return a.id < b.id
            }
            return (section, rows)
        }
    }

    public static func totals(_ items: [Item]) -> ReviewTotals {
        let keep = items.filter { $0.disposition == .keep }
        return ReviewTotals(
            expectedSaleCents: items.filter { $0.disposition == .sell }.compactMap(\.saleValueCents).reduce(0, +),
            itemsToMove: keep.count,
            volumeToMoveM3: keep.map(\.volumeM3).reduce(0, +),
            needsYou: items.filter { ReviewSection.of($0) == .needsYou }.count,
            divertedFromLandfill: items.filter { $0.disposition == .sell || $0.disposition == .donate }.count
        )
    }
}
