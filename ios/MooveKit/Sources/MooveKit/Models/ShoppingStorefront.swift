import Foundation

// The Shopping screen as a storefront (Lisa's ask: bigger images, deals and headlines, slightly
// asymmetric boxes instead of a plain list). Everything here is pure and deterministic, so the
// same snapshot always gets the same hero, the same card sizes and the same shelves:
//
// - `hero`: how many things the new place still needs, plus the best saving on a low-risk deal.
// - `sections`: one per function hall that has shopping items (MooveKit `FunctionHall`, the same
//   categories as Inventory's museum), the ones that need the user first. Each is a "bento" grid
//   (the section's most urgent item gets the big feature card, then a repeating pattern of a tall
//   card beside two small ones, a wide card, and a pair; bought items after, smaller) and a
//   sideways row of that category's best deals.
// - `blocked`: the deals the fraud screen blocked, its own section at the end (kept visible so
//   the refusal is shown, never offered).

/// How big a bento card is drawn.
public enum StorefrontCardSize: String, Sendable, Hashable {
    /// Full width, tallest: the most urgent item.
    case feature
    /// Half width, two small cards tall.
    case tall
    /// Full width, short.
    case wide
    /// Half width, short.
    case small
}

/// A ribbon on an item card, from its deal data.
public enum StorefrontRibbon: String, Sendable, Hashable {
    case bestDeal, lowestPrice, localPickup

    public var label: String {
        switch self {
        case .bestDeal: "Best deal"
        case .lowestPrice: "Lowest price"
        case .localPickup: "Local pickup"
        }
    }
}

/// The status line on an item card, in words, with a tone for its color.
public struct StorefrontBadge: Sendable, Hashable {
    public enum Tone: Sendable, Hashable { case neutral, working, attention, good, danger }
    public var label: String
    public var tone: Tone

    public init(_ label: String, _ tone: Tone) {
        self.label = label
        self.tone = tone
    }
}

/// One deal on a shelf or a card, with what it saves against the priciest deal found for the item.
public struct StorefrontDeal: Sendable, Hashable, Identifiable {
    public var deal: Deal
    public var itemId: UInt64
    public var itemName: String
    /// The highest price among the item's deals the agent may buy (not fraud-blocked).
    public var referenceCents: Int64
    public var id: UInt64 { deal.id }

    public var savingsCents: Int64 { max(0, referenceCents - deal.priceCents) }

    /// Whole percent under the reference, rounded down (honest: never rounds a saving up).
    public var savingsPercent: Int {
        guard referenceCents > 0, savingsCents > 0 else { return 0 }
        return Int(savingsCents * 100 / referenceCents)
    }

    /// "Save $150 vs $229.99", or nil when it is the priciest (or only) deal.
    public var savingsText: String? {
        guard savingsCents > 0 else { return nil }
        return "Save \(CentsFormat.usd(savingsCents)) vs \(CentsFormat.usd(referenceCents))"
    }

    /// "4 mi" from the seller info, for marketplace deals that list a distance.
    public var distanceText: String? { deal.pickupDistance }

    /// A marketplace seller (no card checkout) with a distance: meet up and pick it up.
    public var isLocalPickup: Bool { deal.isLocalPickup }
}

/// One shopping-list item as a bento card.
public struct StorefrontTile: Sendable, Hashable, Identifiable {
    public var item: ShoppingItem
    public var size: StorefrontCardSize
    /// The deal whose price the card shows: the chosen one, else the top pick.
    public var featured: StorefrontDeal?
    public var dealCount: Int
    public var badge: StorefrontBadge
    public var ribbon: StorefrontRibbon?
    public var id: UInt64 { item.id }
}

/// A row of the bento grid.
public enum StorefrontRow: Sendable, Hashable {
    /// A feature or wide card alone on its row.
    case single(StorefrontTile)
    /// Two small cards side by side.
    case pair(StorefrontTile, StorefrontTile)
    /// A tall card beside a stack of two small ones; `tallLeading` alternates per tall row.
    case tall(StorefrontTile, stack: [StorefrontTile], tallLeading: Bool)

    public var tiles: [StorefrontTile] {
        switch self {
        case .single(let t): [t]
        case .pair(let a, let b): [a, b]
        case .tall(let t, let stack, _): [t] + stack
        }
    }
}

/// A horizontal row of deals with a headline.
public struct StorefrontShelf: Sendable, Hashable, Identifiable {
    /// `best`: a category's deals, best saving first. `blocked`: what the fraud screen refused.
    public enum Kind: String, Sendable, Hashable { case best, blocked }
    public var kind: Kind
    public var title: String
    public var deals: [StorefrontDeal]
    /// The category a `best` shelf belongs to.
    public var hall: FunctionHall?
    public var id: String { hall.map { "\(kind.rawValue).\($0.rawValue)" } ?? kind.rawValue }

    public init(kind: Kind, title: String, deals: [StorefrontDeal], hall: FunctionHall? = nil) {
        self.kind = kind
        self.title = title
        self.deals = deals
        self.hall = hall
    }
}

/// One category of the storefront: its items as bento cards, then its best deals.
public struct StorefrontSection: Sendable, Hashable, Identifiable {
    public var hall: FunctionHall
    public var rows: [StorefrontRow]
    /// The category's buyable deals for items not bought yet, best saving first (nil when none).
    public var deals: StorefrontShelf?
    /// Items not bought yet.
    public var toBuy: Int
    /// Items waiting on the user (approve, choose a deal, retry, message a seller).
    public var needsYou: Int
    public var bought: Int
    /// The cheapest buyable deal for an item still to buy.
    public var fromCents: Int64?
    public var id: String { hall.rawValue }

    public var tiles: [StorefrontTile] { rows.flatMap(\.tiles) }

    /// "Sleep", "Sit & lounge"; the leftovers are "Everything else".
    public var title: String { hall.name }

    /// "2 to buy · from $179.99 · 1 bought".
    public var subtitle: String {
        var parts: [String] = []
        if toBuy > 0 { parts.append("\(toBuy) to buy") }
        if toBuy > 0, let fromCents { parts.append("from \(CentsFormat.usd(fromCents))") }
        if bought > 0 { parts.append("\(bought) bought") }
        return parts.joined(separator: " · ")
    }
}

public struct StorefrontHero: Sendable, Hashable {
    /// Items not bought yet.
    public var stillNeeded: Int
    /// "Your new place still needs 4 things".
    public var headline: String
    /// The biggest percent saving on a low-fraud-risk deal for an item not bought yet.
    public var pick: StorefrontDeal?
}

public struct ShoppingStorefront: Sendable, Hashable {
    public var hero: StorefrontHero
    public var sections: [StorefrontSection]
    /// "Blocked for your safety": every fraud-blocked deal, nil when there are none.
    public var blocked: StorefrontShelf?

    /// Every card in page order (the one-column order at accessibility text sizes).
    public var tiles: [StorefrontTile] { sections.flatMap(\.tiles) }
}

extension Deal {
    /// "4 mi" when the seller info lists a distance ("... · 4 mi · ...").
    public var pickupDistance: String? {
        sellerInfo.components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { part in
                guard part.hasSuffix(" mi") else { return false }
                return Double(part.dropLast(3)) != nil
            }
    }

    /// A marketplace deal (no card checkout) whose seller lists a distance.
    public var isLocalPickup: Bool { !supportsCardCheckout && pickupDistance != nil }
}

extension SyncSnapshot {
    /// The storefront for the signed-in user's shopping list.
    public func storefront() -> ShoppingStorefront {
        let items = myShoppingItems
        let open = items.filter { $0.status != .bought }

        func storeDeal(_ deal: Deal, _ item: ShoppingItem) -> StorefrontDeal {
            let reference = deals(for: item.id).filter(\.isChoosable).map(\.priceCents).max() ?? deal.priceCents
            return StorefrontDeal(deal: deal, itemId: item.id, itemName: item.name, referenceCents: max(reference, deal.priceCents))
        }

        let hasFailed: (Deal) -> Bool = { d in visaPayments(for: d.id).contains { $0.status == .failed } }
        func topPick(_ item: ShoppingItem) -> Deal? { self.topPick(for: item) }

        let best = open.compactMap { item in topPick(item).map { storeDeal($0, item) } }
            .sorted { ($0.savingsPercent, $0.savingsCents, -Int64($0.itemId)) > ($1.savingsPercent, $1.savingsCents, -Int64($1.itemId)) }
        let heroPick = best.first { $0.savingsPercent > 0 && $0.deal.fraudLevel == .low }

        // MARK: Hero
        let headline: String
        if items.isEmpty {
            headline = "Your new place's list is empty"
        } else if open.isEmpty {
            headline = "Everything on the list is bought"
        } else {
            headline = "Your new place still needs \(open.count) \(open.count == 1 ? "thing" : "things")"
        }
        let hero = StorefrontHero(stillNeeded: open.count, headline: headline, pick: heroPick)

        // MARK: Tiles
        struct Ranked { var tile: StorefrontTile; var priority: Int; var savings: Int }
        let ranked: [Ranked] = items.map { item in
            let itemDeals = deals(for: item.id)
            let state = checkout(for: item)
            let featuredDeal = chosenDeal(for: item) ?? topPick(item)
            let featured = featuredDeal.map { storeDeal($0, item) }
            let (badge, priority) = Self.badge(item: item, checkout: state, dealCount: itemDeals.count)
            var ribbon: StorefrontRibbon?
            if item.status != .bought, let featured {
                let choosable = itemDeals.filter(\.isChoosable)
                if heroPick?.itemId == item.id && heroPick?.id == featured.id {
                    ribbon = .bestDeal
                } else if featured.isLocalPickup {
                    ribbon = .localPickup
                } else if choosable.count >= 2, featured.deal.priceCents == choosable.map(\.priceCents).min() {
                    ribbon = .lowestPrice
                }
            }
            let tile = StorefrontTile(item: item, size: .small, featured: featured, dealCount: itemDeals.count,
                                      badge: badge, ribbon: ribbon)
            return Ranked(tile: tile, priority: priority, savings: featured?.savingsPercent ?? 0)
        }
        let ordered = ranked.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            if a.savings != b.savings { return a.savings > b.savings }
            return a.tile.item.id < b.tile.item.id
        }.map(\.tile)

        // MARK: Sections
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        let priority = Dictionary(uniqueKeysWithValues: ranked.map { ($0.tile.id, $0.priority) })
        let byHall = Dictionary(grouping: ordered) { FunctionHall.of($0.item) }
        let sections: [StorefrontSection] = byHall.map { hall, tiles in
            let openTiles = tiles.filter { $0.item.status != .bought }
            let doneTiles = tiles.filter { $0.item.status == .bought }
            let offers: [StorefrontDeal] = openTiles.flatMap { tile in
                deals(for: tile.item.id).filter { $0.isChoosable && !hasFailed($0) }.map { storeDeal($0, tile.item) }
            }
            .sorted { a, b in
                if a.savingsPercent != b.savingsPercent { return a.savingsPercent > b.savingsPercent }
                if a.deal.priceCents != b.deal.priceCents { return a.deal.priceCents < b.deal.priceCents }
                return a.id < b.id
            }
            return StorefrontSection(
                hall: hall,
                rows: Self.bentoRows(openTiles) + Self.boughtRows(doneTiles),
                deals: offers.isEmpty ? nil : StorefrontShelf(kind: .best, title: "\(hall.name) deals", deals: offers, hall: hall),
                toBuy: openTiles.count,
                needsYou: openTiles.filter { (priority[$0.id] ?? 9) <= 2 }.count,
                bought: doneTiles.count,
                fromCents: offers.map(\.deal.priceCents).min()
            )
        }
        .sorted { a, b in
            // Categories with something to buy first, curiosities last among them; then the ones
            // that need the user most, then the most still to buy, then the most urgent card.
            if (a.toBuy > 0) != (b.toBuy > 0) { return a.toBuy > 0 }
            if (a.hall == .everythingElse) != (b.hall == .everythingElse) { return b.hall == .everythingElse }
            if a.needsYou != b.needsYou { return a.needsYou > b.needsYou }
            if a.toBuy != b.toBuy { return a.toBuy > b.toBuy }
            return (a.tiles.first.flatMap { rank[$0.id] } ?? 0) < (b.tiles.first.flatMap { rank[$0.id] } ?? 0)
        }

        // MARK: Blocked
        let blockedDeals: [StorefrontDeal] = items.flatMap { item in
            deals(for: item.id).filter(\.isFraudBlocked).map { storeDeal($0, item) }
        }
        let blocked = blockedDeals.isEmpty ? nil
            : StorefrontShelf(kind: .blocked, title: "Blocked for your safety", deals: blockedDeals)

        return ShoppingStorefront(hero: hero, sections: sections, blocked: blocked)
    }

    /// The deal a card leads with when none is chosen: one the agent may buy and that hasn't failed
    /// checkout, lowest fraud risk first (unscored after low), then lowest price, then rank order.
    public func topPick(for item: ShoppingItem) -> Deal? {
        deals(for: item.id)
            .filter { d in d.isChoosable && !visaPayments(for: d.id).contains { $0.status == .failed } }
            .min { a, b in
                let ra = Self.riskRank(a), rb = Self.riskRank(b)
                if ra != rb { return ra < rb }
                if a.priceCents != b.priceCents { return a.priceCents < b.priceCents }
                return a.id < b.id
            }
    }

    /// Ribbons for an item's deal cards (Item detail): the top pick is the best deal, the cheapest
    /// buyable deal (when it isn't the top pick) the lowest price, and marketplace deals with a
    /// distance local pickup. Fraud-blocked deals and bought items get none.
    public func dealRibbons(for item: ShoppingItem) -> [UInt64: StorefrontRibbon] {
        guard item.status != .bought else { return [:] }
        let all = deals(for: item.id).filter(\.isChoosable)
        var out: [UInt64: StorefrontRibbon] = [:]
        let pick = topPick(for: item)
        if all.count >= 2, let pick { out[pick.id] = .bestDeal }
        if all.count >= 2, let cheapest = all.min(by: { ($0.priceCents, $0.id) < ($1.priceCents, $1.id) }), out[cheapest.id] == nil {
            out[cheapest.id] = .lowestPrice
        }
        for d in all where out[d.id] == nil && d.isLocalPickup { out[d.id] = .localPickup }
        return out
    }

    /// Low risk first, then not scored yet, then some risk.
    static func riskRank(_ deal: Deal) -> Int {
        switch deal.fraudLevel {
        case .low: 0
        case nil: 1
        case .medium: 2
        case .high: 3
        }
    }

    /// The card's status words and its sort priority (lower comes first: things that need the user).
    static func badge(item: ShoppingItem, checkout: ShoppingCheckout, dealCount: Int) -> (StorefrontBadge, Int) {
        let deals = dealCount == 1 ? "1 deal" : "\(dealCount) deals"
        switch checkout {
        case .needsApproval:
            return (StorefrontBadge("Needs approval", .attention), 0)
        case .chooseDeal:
            return (StorefrontBadge(deals, .attention), 1)
        case .notApproved:
            return (StorefrontBadge("Not bought · \(deals)", .attention), 1)
        case .payment(let p):
            switch p.status {
            case .failed: return (StorefrontBadge("Checkout failed", .danger), 1)
            case .pending: return (StorefrontBadge(p.simulated ? "Hold placed (simulated)" : "Hold placed", .working), 3)
            case .settled: return (StorefrontBadge(p.simulated ? "Bought (simulated)" : "Bought (sandbox)", .good), 5)
            }
        case .messageSeller:
            return (StorefrontBadge("Message seller", .neutral), 2)
        case .fraudBlocked:
            return (StorefrontBadge("Blocked: likely fraud", .danger), 2)
        case .checkingOut:
            return (StorefrontBadge("Checking out…", .working), 3)
        case .findingDeals:
            if item.status == .bought { return (StorefrontBadge("Bought", .good), 5) }
            return (StorefrontBadge("Finding deals…", .working), 4)
        }
    }

    /// Bought cards after a category's open ones: small pairs, a leftover wide card.
    static func boughtRows(_ tiles: [StorefrontTile]) -> [StorefrontRow] {
        func sized(_ t: StorefrontTile, _ s: StorefrontCardSize) -> StorefrontTile {
            var t = t
            t.size = s
            return t
        }
        var rows: [StorefrontRow] = []
        var rest = tiles[...]
        while rest.count >= 2 {
            rows.append(.pair(sized(rest.removeFirst(), .small), sized(rest.removeFirst(), .small)))
        }
        if let last = rest.first { rows.append(.single(sized(last, .wide))) }
        return rows
    }

    /// Deterministic bento rows: the first card is the feature, then a repeating
    /// tall-with-two-small (alternating sides), wide, pair pattern. Leftovers fill in as a pair or
    /// a wide card, so no row is ever half empty.
    static func bentoRows(_ tiles: [StorefrontTile]) -> [StorefrontRow] {
        guard let first = tiles.first else { return [] }
        func sized(_ t: StorefrontTile, _ s: StorefrontCardSize) -> StorefrontTile {
            var t = t
            t.size = s
            return t
        }
        var rows: [StorefrontRow] = [.single(sized(first, .feature))]
        var rest = Array(tiles.dropFirst())
        var step = 0
        var tallLeading = true
        while !rest.isEmpty {
            let pattern = step % 3
            step += 1
            if rest.count == 1 {
                rows.append(.single(sized(rest.removeFirst(), .wide)))
            } else if pattern == 0, rest.count >= 3 {
                let tall = sized(rest.removeFirst(), .tall)
                let stack = [sized(rest.removeFirst(), .small), sized(rest.removeFirst(), .small)]
                rows.append(.tall(tall, stack: stack, tallLeading: tallLeading))
                tallLeading.toggle()
            } else if pattern == 1 {
                rows.append(.single(sized(rest.removeFirst(), .wide)))
            } else {
                let a = sized(rest.removeFirst(), .small)
                let b = sized(rest.removeFirst(), .small)
                rows.append(.pair(a, b))
            }
        }
        return rows
    }
}
