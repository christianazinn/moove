import Foundation

// The Shopping screen's cart (Lisa's ask): what the user already bought for the new home, one
// line per purchased shopping item (`SyncSnapshot.purchasedShoppingItems`, the same rule as
// `boughtPieces`), with its price, how it was paid and the room it goes to in the saved layout.

/// How one bought item was paid, for its status chip. Simulated payments always say so.
public enum CartLineStatus: Sendable, Hashable {
    /// Marked bought with no Visa payment row (a marketplace seller, paid in person).
    case bought
    /// A settled Visa payment on the simulated rail.
    case paidSimulated
    /// A settled Visa payment in the Visa (Authorize.net / CyberSource) sandbox: test card, no real money.
    case visaSandbox

    public var label: String {
        switch self {
        case .bought: "Bought"
        case .paidSimulated: "Paid (simulated)"
        case .visaSandbox: "Visa sandbox"
        }
    }
}

/// One bought item in the cart.
public struct CartLine: Sendable, Hashable, Identifiable {
    /// The shopping item's id.
    public var id: UInt64 { item.id }
    public var item: ShoppingItem
    public var deal: Deal?
    /// The settled Visa payment for the chosen deal, if any.
    public var payment: Payment?
    /// The chosen deal's title, or the item's name without one.
    public var title: String
    /// "TARGET" or "Craigslist · Dana" (`PackingPlanner.seller`), "" without a deal.
    public var seller: String
    /// What was paid: the settled payment's amount, else the chosen deal's price. nil without either.
    public var amountUsdMicros: Int64?
    public var status: CartLineStatus
    /// The room the saved new-home layout puts it in, if one does.
    public var room: String?

    /// "Delivering to Bedroom" once a saved layout places it, else the payment status.
    public var statusLabel: String { room.map { "Delivering to \($0)" } ?? status.label }

    public var formattedAmount: String? { amountUsdMicros.map(UsdMicros.format) }

    public var accessibilitySummary: String {
        var parts = [title]
        if !seller.isEmpty { parts.append("from \(seller)") }
        if let formattedAmount { parts.append(formattedAmount) }
        parts.append(status.label)
        if let room { parts.append("goes to the \(room)") }
        return parts.joined(separator: ", ")
    }
}

/// Everything bought so far, newest purchase last (shopping-list order).
public struct ShoppingCart: Sendable, Hashable {
    public var lines: [CartLine]

    public init(lines: [CartLine]) { self.lines = lines }

    public var count: Int { lines.count }
    public var isEmpty: Bool { lines.isEmpty }

    public var totalUsdMicros: Int64 { lines.compactMap(\.amountUsdMicros).reduce(0, +) }

    /// How the money moved, for the total: "simulated", "Visa sandbox", both, or nil when no line
    /// went through a Visa payment (nothing paid in the app).
    public var railNote: String? {
        let simulated = lines.contains { $0.status == .paidSimulated }
        let sandbox = lines.contains { $0.status == .visaSandbox }
        switch (simulated, sandbox) {
        case (true, true): return "simulated + Visa sandbox"
        case (true, false): return "simulated"
        case (false, true): return "Visa sandbox"
        case (false, false): return nil
        }
    }

    /// "2 things · $609.98, simulated", "1 thing · $79.99", or "Nothing bought yet".
    public var summary: String {
        guard !isEmpty else { return "Nothing bought yet" }
        let things = count == 1 ? "1 thing" : "\(count) things"
        let total = UsdMicros.format(totalUsdMicros)
        return "\(things) · \(total)" + (railNote.map { ", \($0)" } ?? "")
    }

    /// "Cart, 2 bought" for the floating button.
    public var accessibilityLabel: String { "Cart, \(count) bought" }
}

extension SyncSnapshot {
    /// The cart: purchased shopping items with their chosen deal, settled payment and the saved
    /// layout's room for them (bought pieces are placed under `BoughtFurniture.layoutId`).
    public func shoppingCart() -> ShoppingCart {
        var roomOf: [UInt64: String] = [:]
        for p in Review.savedLayout(in: self)?.placements ?? [] where roomOf[p.itemId] == nil {
            roomOf[p.itemId] = p.room
        }
        let lines = purchasedShoppingItems.map { item -> CartLine in
            let deal = chosenDeal(for: item)
            let payment = deal.flatMap { visaPayments(for: $0.id).first { $0.status == .settled } }
            let title = deal?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let status: CartLineStatus = payment.map { $0.simulated ? .paidSimulated : .visaSandbox } ?? .bought
            let room = roomOf[BoughtFurniture.layoutId(forShoppingItem: item.id)].flatMap { $0.isEmpty ? nil : $0 }
            return CartLine(
                item: item, deal: deal, payment: payment, title: title.isEmpty ? item.name : title,
                seller: deal.map(PackingPlanner.seller) ?? "",
                amountUsdMicros: payment?.amountUsdMicros ?? deal.map { $0.priceCents * 10_000 },
                status: status, room: room
            )
        }
        return ShoppingCart(lines: lines)
    }
}
