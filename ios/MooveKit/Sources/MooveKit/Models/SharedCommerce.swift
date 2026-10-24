import Foundation

// Listings and approvals for items in rooms shared with the user (#195).
//
// SpacetimeDB subscriptions join at most two tables, so "listings for items in
// rooms I'm a member of" (listing -> item -> room_member) can't be one query.
// Until the module has per-user views for these (proposal #200), the app
// subscribes to every listing and every other user's *listing* approvals (both
// tables are public) and `scopedToVisibleItems()` drops whatever isn't about an
// item the user can already see (their own, or one in a room they joined).
// Purchase approvals stay owner-only: they're never subscribed for other users.

extension SyncSnapshot {
    /// Keeps the user's own listings and approvals, plus listings for visible
    /// items (`items` already holds owned and shared-room items) and the listing
    /// approvals that gate them. Call after `items`, `listings` and `approvals` are set.
    public func scopedToVisibleItems() -> SyncSnapshot {
        var s = self
        let visibleItems = Set(items.map(\.id))
        s.listings = listings.filter { $0.owner == me || visibleItems.contains($0.itemId) }
        let visibleListings = Set(s.listings.map(\.id))
        s.approvals = approvals.filter {
            $0.owner == me || ($0.kind == .listing && visibleListings.contains($0.refId))
        }
        return s
    }

    /// Pending listing approvals someone else owns, for an item in a room the
    /// user joined. Read-only: `decide_approval` is owner-only for now (#195),
    /// so the app shows who it's waiting on instead of Approve/Deny. Oldest first.
    public var sharedPendingApprovals: [Approval] {
        approvals.filter { $0.owner != me && $0.kind == .listing && $0.isPending }
            .sorted { ($0.requestedAt, $0.id) < ($1.requestedAt, $1.id) }
    }

    /// Who has to decide `approval`, for "Waiting for …".
    public func approverName(for approval: Approval) -> String { approverName(owner: approval.owner) }

    /// The owner's name when their user row is synced (`my_user` only returns
    /// the signed-in user today), otherwise "the owner".
    public func approverName(owner: IdentityHex) -> String {
        if let name = users.first(where: { $0.identity == owner })?.name, !name.isEmpty { return name }
        return "the owner"
    }

    /// True when the listing belongs to someone else (a shared-room item).
    public func isShared(_ listing: Listing) -> Bool { listing.owner != me }
}
