import Foundation

public enum ListingStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case awaitingApproval = "awaiting_approval"
    case rejected, posted, sold, failed
}

/// Mirror of the `listing` table. `simulated` listings were never sent to eBay
/// (the demo's eBay backend is simulated, #11) and must be labeled in the UI.
public struct Listing: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var itemId: UInt64
    public var platform: String
    public var title: String
    public var description: String
    public var priceCents: Int64
    public var status: ListingStatus
    /// eBay item number once posted.
    public var externalId: String?
    /// Listing page once posted (for simulated listings, a page served by the worker).
    public var url: String?
    public var simulated: Bool
    public var updatedAt: Date

    public init(
        id: UInt64, owner: IdentityHex, itemId: UInt64, platform: String = "ebay", title: String, description: String,
        priceCents: Int64, status: ListingStatus = .draft, externalId: String? = nil, url: String? = nil,
        simulated: Bool = true, updatedAt: Date = .now
    ) {
        self.id = id
        self.owner = owner
        self.itemId = itemId
        self.platform = platform
        self.title = title
        self.description = description
        self.priceCents = priceCents
        self.status = status
        self.externalId = externalId
        self.url = url
        self.simulated = simulated
        self.updatedAt = updatedAt
    }

    /// Plain text for manual cross-posting to FB Marketplace or Craigslist (no APIs for those).
    public var copyText: String {
        let price = priceCents % 100 == 0 ? "$\(priceCents / 100)" : "$\(priceCents / 100).\(String(format: "%02d", Int(priceCents % 100)))"
        return "\(title)\n\(price)\n\n\(description)"
    }
}
