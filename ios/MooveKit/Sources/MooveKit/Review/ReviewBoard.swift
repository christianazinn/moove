import Foundation

/// One destination on the Review board ("Where it goes"): Keep, Sell, Donate or Trash, with
/// its items (most valuable first) and the figures its tile shows.
public struct ReviewPile: Sendable, Equatable, Identifiable {
    public var destination: Disposition
    public var items: [Item]
    /// Sum of the items' estimated values (Sell's "expected sales").
    public var valueCents: Int64
    /// Rough weight (`MoveSummary.estimatedKg`), for Donate's "kg kept from landfill".
    public var kg: Double
    public var volumeM3: Double

    public var id: Disposition { destination }
    public var count: Int { items.count }
}

/// Keep items grouped by the room they land in on the saved New Home layout.
public struct ReviewKeepGroup: Sendable, Equatable {
    /// The new home's room, or nil for items the layout didn't place.
    public var room: String?
    public var items: [Item]
}

extension Review {
    /// The board's four destinations, always in this order.
    public static let destinations: [Disposition] = [.keep, .sell, .donate, .trash]

    /// Items that need a person (undecided, or possibly sentimental and not yet decided by the
    /// user), as a card deck: sentimental first, then by value (highest first), then by id.
    public static func deck(_ items: [Item]) -> [Item] {
        items.filter { ReviewSection.of($0) == .needsYou }.sorted { a, b in
            if a.maybeSentimental != b.maybeSentimental { return a.maybeSentimental }
            if (a.saleValueCents ?? 0) != (b.saleValueCents ?? 0) { return (a.saleValueCents ?? 0) > (b.saleValueCents ?? 0) }
            return a.id < b.id
        }
    }

    /// The four piles (empty ones included), without the deck's items.
    public static func piles(_ items: [Item]) -> [ReviewPile] {
        let decided = items.filter { ReviewSection.of($0) != .needsYou }
        return destinations.map { d in
            let rows = decided.filter { $0.disposition == d }.sorted { a, b in
                if (a.saleValueCents ?? 0) != (b.saleValueCents ?? 0) { return (a.saleValueCents ?? 0) > (b.saleValueCents ?? 0) }
                return a.id < b.id
            }
            return ReviewPile(
                destination: d,
                items: rows,
                valueCents: rows.compactMap(\.saleValueCents).reduce(0, +),
                kg: rows.map(MoveSummary.estimatedKg).reduce(0, +),
                volumeM3: rows.map(\.volumeM3).reduce(0, +)
            )
        }
    }

    /// The layout the user last saved for their current new home, if any.
    public static func savedLayout(in snapshot: SyncSnapshot) -> Layout? {
        guard let home = snapshot.myNewHome else { return nil }
        return snapshot.layouts(for: home.id).max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Keep items by destination room, rooms in the layout's order, unplaced items last.
    /// One group with `room == nil` when there is no layout (or it placed none of them).
    public static func keepByRoom(_ keep: [Item], layout: Layout?) -> [ReviewKeepGroup] {
        let placements = layout?.placements ?? []
        var roomOf: [UInt64: String] = [:]
        var order: [String] = []
        for p in placements where roomOf[p.itemId] == nil {
            roomOf[p.itemId] = p.room
            if !order.contains(p.room) { order.append(p.room) }
        }
        var groups = order.compactMap { room -> ReviewKeepGroup? in
            let rows = keep.filter { roomOf[$0.id] == room }
            return rows.isEmpty ? nil : ReviewKeepGroup(room: room, items: rows)
        }
        let unplaced = keep.filter { roomOf[$0.id] == nil }
        if !unplaced.isEmpty { groups.append(ReviewKeepGroup(room: nil, items: unplaced)) }
        return groups
    }

    /// Low and high comparable-listing prices, when there are at least two distinct ones.
    public static func valueRange(_ item: Item, comps: [Comp]) -> ClosedRange<Int64>? {
        let prices = comps.filter { $0.itemId == item.id }.map(\.priceCents)
        guard let low = prices.min(), let high = prices.max(), low < high else { return nil }
        return low...high
    }

    /// What the sort agent would do with a deck item, if it said (the user always decides).
    public static func suggestion(_ item: Item) -> Disposition? {
        item.dispositionSource == .auto && item.disposition != .undecided ? item.disposition : nil
    }
}

/// The deck's swipe directions: right = Keep, left = Sell, up = Donate, down = Trash.
/// Vertical drags count for less (`verticalBias`), since the deck sits in a scrolling page.
public enum ReviewSwipe {
    /// A vertical drag must go this much farther than a horizontal one to commit.
    public static let verticalBias = 1.35

    /// The direction a card points for a drag, by its dominant axis (screen coordinates,
    /// y grows downward). nil while it's still at rest.
    public static func pointing(dx: Double, dy: Double) -> Disposition? {
        guard dx != 0 || dy != 0 else { return nil }
        // Only sideways swipes decide (right keep, left sell): a mostly vertical drag is someone
        // scrolling, so it never donates or trashes. Donate and Trash are the buttons.
        if abs(dx) >= abs(dy) / verticalBias { return dx > 0 ? .keep : .sell }
        return nil
    }

    /// How far along the drag is toward committing, 0...1 (1 = at the threshold).
    public static func progress(dx: Double, dy: Double, threshold: Double) -> Double {
        guard threshold > 0 else { return 0 }
        guard pointing(dx: dx, dy: dy) != nil else { return 0 }
        return min(abs(dx) / threshold, 1)
    }

    /// The disposition a released drag commits to: past the threshold on its dominant axis,
    /// or a quick flick (predicted end past 2× the threshold). nil snaps the card back.
    public static func commit(dx: Double, dy: Double, predictedDx: Double? = nil, predictedDy: Double? = nil,
                              threshold: Double) -> Disposition? {
        if progress(dx: dx, dy: dy, threshold: threshold) >= 1 { return pointing(dx: dx, dy: dy) }
        if let px = predictedDx, let py = predictedDy, abs(px) >= threshold * 2,
           pointing(dx: px, dy: py) == pointing(dx: dx, dy: dy) {
            return pointing(dx: dx, dy: dy)
        }
        return nil
    }
}
