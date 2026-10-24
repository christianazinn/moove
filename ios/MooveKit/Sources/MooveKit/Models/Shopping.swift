import Foundation

// Mirrors of the `shopping_item` and `deal` tables (docs/data-model.md), plus the pure logic
// behind the Shopping screen (#15): deals grouped per item, the purchase approval and Visa
// payment for the chosen deal, and which badge each deal and payment gets.

public enum ShoppingStatus: String, Codable, Sendable, CaseIterable {
    case open, searching, found, bought

    /// Tolerant mapping from the wire string (unknown values read as open).
    public init(wire: String) { self = ShoppingStatus(rawValue: wire) ?? .open }
}

/// Mirror of the `shopping_item` table: something the new home still needs.
public struct ShoppingItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var name: String
    public var category: String
    /// Why the shopping agent (or the user) put it on the list.
    public var reason: String
    public var status: ShoppingStatus
    /// nil when the wire value is 0 (no deal chosen yet).
    public var chosenDealId: UInt64?
    public var createdAt: Date

    public init(
        id: UInt64, owner: IdentityHex, name: String, category: String = "", reason: String = "",
        status: ShoppingStatus = .open, chosenDealId: UInt64? = nil, createdAt: Date = .now
    ) {
        self.id = id
        self.owner = owner
        self.name = name
        self.category = category
        self.reason = reason
        self.status = status
        self.chosenDealId = chosenDealId == 0 ? nil : chosenDealId
        self.createdAt = createdAt
    }
}

/// Mirror of the `deal` table: one listing the buy agent found for a shopping item.
public struct Deal: Codable, Sendable, Hashable, Identifiable {
    /// Retail merchants the buy agent can pay by card (agents/src/integrations/deals.ts).
    /// Marketplace deals (fb, craigslist, ...) get a drafted message to the seller instead.
    public static let cardCheckoutSources: Set<String> = ["ikea", "target", "amazon", "wayfair"]
    /// The worker won't buy a deal the fraud screen (#18) scored at or above this (`BUY_FRAUD_BLOCK`).
    public static let fraudBlockScore = 0.7

    public var id: UInt64
    public var owner: IdentityHex
    public var shoppingItemId: UInt64
    public var source: String
    public var title: String
    public var priceCents: Int64
    /// nil when the wire value is "".
    public var url: String?
    /// "who · condition · distance · how to pay · score", plus "cached replay" for fixture deals.
    public var sellerInfo: String
    /// 0 (clean) ... 1 (likely fraud). nil when the wire value is -1 (not scored yet).
    public var fraudScore: Double?
    /// AI-generated-text likelihood of the listing copy. nil when not scored.
    public var aiTextScore: Double?
    public var fraudReasons: [String]
    public var createdAt: Date

    public init(
        id: UInt64, owner: IdentityHex, shoppingItemId: UInt64, source: String, title: String, priceCents: Int64,
        url: String? = nil, sellerInfo: String = "", fraudScore: Double? = nil, aiTextScore: Double? = nil,
        fraudReasons: [String] = [], createdAt: Date = .now
    ) {
        self.id = id
        self.owner = owner
        self.shoppingItemId = shoppingItemId
        self.source = source
        self.title = title
        self.priceCents = priceCents
        self.url = (url?.isEmpty ?? true) ? nil : url
        self.sellerInfo = sellerInfo
        self.fraudScore = fraudScore.flatMap { $0 < 0 ? nil : $0 }
        self.aiTextScore = aiTextScore.flatMap { $0 < 0 ? nil : $0 }
        self.fraudReasons = fraudReasons
        self.createdAt = createdAt
    }

    /// Replayed from cached fixtures rather than live listings; the UI shows a REPLAY badge.
    public var isReplay: Bool { sellerInfo.range(of: "cached replay", options: .caseInsensitive) != nil }

    /// `sellerInfo` without the replay marker (the badge says it instead).
    public var sellerDetails: String {
        sellerInfo
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: "cached replay", options: .caseInsensitive) == nil }
            .joined(separator: " · ")
    }

    /// The buy agent can pay this merchant through Visa checkout.
    public var supportsCardCheckout: Bool { Self.cardCheckoutSources.contains(source.lowercased()) }

    public var fraudLevel: FraudLevel? { fraudScore.map(FraudLevel.init(score:)) }

    /// The worker refuses to buy it.
    public var isFraudBlocked: Bool { (fraudScore ?? 0) >= Self.fraudBlockScore }

    public var link: URL? { url.flatMap(URL.init(string:)) }
}

public enum FraudLevel: String, Sendable, Hashable {
    case low, medium, high

    public init(score: Double) {
        if score >= Deal.fraudBlockScore { self = .high } else if score >= 0.3 { self = .medium } else { self = .low }
    }
}

/// What a Visa `payment` row means for the purchase, and how it must be labeled.
public struct VisaPaymentBadge: Sendable, Hashable {
    public enum State: Sendable, Hashable { case hold, paid, failed }

    public var state: State
    public var simulated: Bool

    public init(_ payment: Payment) {
        switch payment.status {
        case .pending: state = .hold
        case .settled: state = .paid
        case .failed: state = .failed
        }
        simulated = payment.simulated
    }

    public var stateLabel: String {
        switch state {
        case .hold: "Hold placed"
        case .paid: "Paid"
        case .failed: "Failed"
        }
    }

    /// Simulated payments are never presented as real (CLAUDE.md hard rule).
    public var railLabel: String { simulated ? "SIMULATED" : "Visa sandbox · test card" }
}

/// Where one shopping item is in the find -> choose -> approve -> pay flow.
public enum ShoppingCheckout: Sendable, Hashable {
    /// No deals yet (the buy agent is searching, or found nothing).
    case findingDeals
    /// Deals found, none chosen.
    case chooseDeal
    /// The chosen deal is a marketplace seller: no API to pay, the agent drafts a message.
    case messageSeller(Deal)
    /// The fraud screen flagged the chosen deal, so the agent won't buy it.
    case fraudBlocked(Deal)
    /// Over the approval threshold and waiting on the user.
    case needsApproval(Approval)
    /// The user denied (or let expire) the purchase approval for the chosen deal.
    case notApproved(Approval)
    /// Cleared to buy; waiting for the worker to place the Visa hold.
    case checkingOut(Deal)
    /// A Visa payment row exists for the chosen deal.
    case payment(Payment)
}

extension SyncSnapshot {
    /// The signed-in user's shopping list, in the order it was written.
    public var myShoppingItems: [ShoppingItem] {
        shoppingItems.filter { $0.owner == me }.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    /// Deals grouped by shopping item, each group in the buy agent's rank order (insert order).
    public var dealsByShoppingItem: [UInt64: [Deal]] {
        Dictionary(grouping: deals, by: \.shoppingItemId).mapValues { $0.sorted { $0.id < $1.id } }
    }

    public func deals(for shoppingItemId: UInt64) -> [Deal] {
        deals.filter { $0.shoppingItemId == shoppingItemId }.sorted { $0.id < $1.id }
    }

    /// The chosen deal, if it is synced and still belongs to the item.
    public func chosenDeal(for item: ShoppingItem) -> Deal? {
        guard let id = item.chosenDealId else { return nil }
        return deals.first { $0.id == id && $0.shoppingItemId == item.id }
    }

    /// The newest purchase approval for a deal (the worker reads the same one).
    public func purchaseApproval(for dealId: UInt64) -> Approval? {
        approvals.filter { $0.kind == .purchase && $0.refId == dealId }.max { $0.id < $1.id }
    }

    /// Visa payments for a deal, newest first.
    public func visaPayments(for dealId: UInt64) -> [Payment] {
        payments
            .filter { $0.rail == .visa && $0.refTable == "deal" && $0.refId == dealId }
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    /// The payment that decides the deal's state: a settled one, else a hold, else the latest failure.
    public func visaPayment(for dealId: UInt64) -> Payment? {
        let all = visaPayments(for: dealId)
        return all.first { $0.status == .settled } ?? all.first { $0.status == .pending } ?? all.first
    }

    public func checkout(for item: ShoppingItem) -> ShoppingCheckout {
        guard let deal = chosenDeal(for: item) else {
            return deals.contains { $0.shoppingItemId == item.id } ? .chooseDeal : .findingDeals
        }
        if let payment = visaPayment(for: deal.id) { return .payment(payment) }
        if deal.isFraudBlocked { return .fraudBlocked(deal) }
        if !deal.supportsCardCheckout { return .messageSeller(deal) }
        if let approval = purchaseApproval(for: deal.id) {
            switch approval.status {
            case .pending: return .needsApproval(approval)
            case .denied, .expired: return .notApproved(approval)
            case .approved: return .checkingOut(deal)
            }
        }
        return .checkingOut(deal)
    }

    /// Pending purchase approvals for deals on the user's shopping list, oldest first.
    public var pendingPurchaseApprovals: [Approval] {
        pendingApprovals.filter { $0.kind == .purchase }
    }
}
