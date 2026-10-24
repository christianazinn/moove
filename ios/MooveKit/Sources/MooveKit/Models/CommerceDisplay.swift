import Foundation

// Pure display logic shared by the commerce screens (Spending, Listings, Shopping, Approvals):
// what a screen shows when it has no rows, why something failed, and the spoken (VoiceOver)
// summaries for amounts and badges. Kept here so it is unit-tested (#15 polish).

/// What a commerce screen body shows, from the connection status and whether it has rows.
public enum CommerceScreenState: Sendable, Equatable {
    /// Connecting and nothing has arrived yet.
    case loading
    /// Not connected and nothing to show. The string is a short reason.
    case offline(String)
    /// Connected, and the table really is empty.
    case empty
    /// Rows to show. Stale rows still show while reconnecting (the banner says so).
    case content

    public init(status: SyncStatus, hasRows: Bool) {
        if hasRows { self = .content; return }
        switch status {
        case .connected: self = .empty
        case .connecting: self = .loading
        case .reconnecting(let attempt): self = .offline("Reconnecting to the backend (attempt \(attempt)).")
        case .failed(let why): self = .offline(why.isEmpty ? "Couldn't reach the backend." : why)
        case .disconnected: self = .offline("Not connected to the backend.")
        }
    }

    /// Heading for the offline/loading placeholder.
    public var title: String? {
        switch self {
        case .loading: "Connecting…"
        case .offline: "Can't reach the backend"
        case .empty, .content: nil
        }
    }

    /// The next step for the offline placeholder.
    public static let offlineNextStep =
        "Check the server address in Settings > Backend, or switch Data source to \"Offline demo (fixtures)\" to see sample data."
}

extension PaymentStatus {
    /// Lowercase word for spoken summaries ("settled").
    public var spoken: String {
        switch self {
        case .pending: "pending"
        case .settled: "settled"
        case .failed: "failed"
        }
    }
}

extension Payment {
    /// How the payment must be labeled: SIMULATED, or which real rail it used.
    public var railTag: String {
        if simulated { return "SIMULATED" }
        switch rail {
        case .x402: return "BASE SEPOLIA"
        case .visa: return "VISA SANDBOX"
        }
    }

    /// VoiceOver summary, amount first: "$0.01, simulated, settled. Premium comps for ... Pricing agent, x402."
    public var accessibilitySummary: String {
        let kind = simulated ? "simulated" : (rail == .visa ? "Visa sandbox" : "on-chain testnet USDC")
        let railName = rail == .visa ? "Visa" : "x402"
        return "\(formattedAmount), \(kind), \(status.spoken). \(purpose). \(agent.agentDisplayName), \(railName)."
    }
}

extension String {
    /// "pricing" -> "Pricing agent".
    public var agentDisplayName: String {
        guard let first = first else { return "Agent" }
        return first.uppercased() + dropFirst() + " agent"
    }
}

extension ListingStatus {
    /// Status label. A simulated listing is never called "Live on eBay".
    public func displayLabel(simulated: Bool) -> String {
        switch self {
        case .draft: "Drafting"
        case .awaitingApproval: "Needs approval"
        case .rejected: "Not posted"
        case .posted: simulated ? "Posted (simulated)" : "Live on eBay"
        case .sold: simulated ? "Sold (simulated)" : "Sold"
        case .failed: "Failed to post"
        }
    }
}

extension Listing {
    /// The eBay item number, only for real posts (a simulated listing's number is made up).
    public var displayExternalId: String? { simulated ? nil : externalId }

    /// Formatted price, "$410" or "$7.50".
    public var formattedPrice: String { CentsFormat.usd(priceCents) }

    /// VoiceOver summary: "Herman Miller..., $410, needs approval, simulated listing, not on eBay".
    public var accessibilitySummary: String {
        var parts = [title, formattedPrice, status.displayLabel(simulated: simulated).lowercased()]
        if simulated { parts.append("simulated listing, not on eBay") }
        return parts.joined(separator: ", ")
    }
}

extension Approval {
    public var formattedAmount: String { CentsFormat.usd(amountCents) }

    /// What happened after the decision, in words.
    public var outcomeText: String? {
        switch (status, kind) {
        case (.pending, _): nil
        case (.approved, .listing): "You approved it. The listing agent posts it."
        case (.approved, .purchase): "You approved it. The buy agent checks out with Visa."
        case (.denied, .listing): "You denied it. The listing wasn't posted."
        case (.denied, .purchase): "You denied it. Nothing was bought."
        case (.expired, .listing): "The request expired. The listing wasn't posted."
        case (.expired, .purchase): "The request expired. Nothing was bought."
        }
    }

    /// VoiceOver summary: "Sell, $410, waiting on you. Sell "..." for $410".
    public var accessibilitySummary: String {
        let verb = kind == .listing ? "Sell" : "Buy"
        let state: String
        switch status {
        case .pending: state = "waiting on you"
        case .approved: state = "approved"
        case .denied: state = "denied"
        case .expired: state = "expired"
        }
        return "\(verb), \(formattedAmount), \(state). \(summary)"
    }
}

extension Deal {
    /// The user can pick it. The worker refuses fraud-blocked deals, so the app doesn't offer them.
    public var isChoosable: Bool { !isFraudBlocked }

    public var formattedPrice: String { CentsFormat.usd(priceCents) }

    /// VoiceOver summary: "$95, Herman Miller Aeron size B, from craigslist, message seller, likely fraud 0.81, sample data".
    public var accessibilitySummary: String {
        var parts = [formattedPrice, title, "from \(source)", supportsCardCheckout ? "Visa checkout" : "message seller"]
        if let level = fraudLevel, let score = fraudScore {
            let word = switch level { case .low: "low fraud risk"; case .medium: "some fraud risk"; case .high: "likely fraud" }
            parts.append("\(word) \(String(format: "%.2f", score))")
        } else {
            parts.append("not fraud-screened yet")
        }
        if isSample { parts.append("sample data, not a live listing") } else if isReplay { parts.append("cached replay, not a live listing") }
        return parts.joined(separator: ", ")
    }
}

extension VisaPaymentBadge {
    /// VoiceOver summary: "$179.99, simulated, paid".
    public func accessibilitySummary(amount: String) -> String {
        "\(amount), \(simulated ? "simulated, no money moved" : "Visa sandbox, test card"), \(stateLabel.lowercased())"
    }
}

/// Integer cents to "$410" / "$429.99" / "$1,500", locale-independent so it is testable.
public enum CentsFormat {
    public static func usd(_ cents: Int64) -> String {
        let micros = cents * 10_000
        let s = UsdMicros.format(micros)
        return cents % 100 == 0 && s.hasSuffix(".00") ? String(s.dropLast(3)) : s
    }
}

extension SyncSnapshot {
    /// The newest agent step that explains why something stopped: an error, or a "Not posting" /
    /// "Not buying" / "Did not buy" / "No deals found" note. nil when nothing went wrong.
    public func latestProblem(refTable: String, refId: UInt64) -> AgentEvent? {
        agentEvents(refTable: refTable, refId: refId).first { e in
            if e.kind == .error { return true }
            let m = e.message
            return m.hasPrefix("Not posting") || m.hasPrefix("Not buying") || m.hasPrefix("Did not buy")
                || m.hasPrefix("No deals found")
        }
    }

    /// Why a listing failed or wasn't posted, if the listing agent said.
    public func problem(for listing: Listing) -> String? {
        guard listing.status == .failed || listing.status == .rejected else { return nil }
        return latestProblem(refTable: "listing", refId: listing.id)?.message
    }

    /// Why a Visa checkout of a deal failed or was refused, if the buy agent said.
    public func checkoutProblem(dealId: UInt64) -> String? {
        latestProblem(refTable: "deal", refId: dealId)?.message
    }

    /// Why the buy agent found no deals for an item (search failed, or nothing matched).
    public func dealSearchProblem(for item: ShoppingItem) -> String? {
        latestProblem(refTable: "shopping_item", refId: item.id)?.message
    }

    /// The deal a purchase approval is for, if synced.
    public func deal(for approval: Approval) -> Deal? {
        guard approval.kind == .purchase else { return nil }
        return deals.first { $0.id == approval.refId }
    }
}
