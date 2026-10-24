import Foundation
import Testing
@testable import MooveKit

/// Listings and approvals for items in rooms shared with the user (#195).
@Suite struct SharedCommerceTests {
    private func item(_ id: UInt64, owner: IdentityHex, room: UInt64) -> Item {
        Item(id: id, owner: owner, roomId: room, scanObjectId: "o\(id)", name: "Item \(id)", category: "chair",
             widthM: 0.6, heightM: 0.9, depthM: 0.6)
    }

    private func listing(_ id: UInt64, owner: IdentityHex, item: UInt64) -> Listing {
        Listing(id: id, owner: owner, itemId: item, title: "Listing \(id)", description: "", priceCents: 41_000,
                status: .awaitingApproval)
    }

    /// "me" joined the seed user's room 1 (items 10, 11). Item 20 is a stranger's, not visible.
    private func joinedSnapshot() -> SyncSnapshot {
        var s = SyncSnapshot(me: "me")
        s.items = [item(10, owner: "seed", room: 1), item(11, owner: "seed", room: 1), item(30, owner: "me", room: 3)]
        s.listings = [
            listing(1, owner: "seed", item: 10),
            listing(2, owner: "stranger", item: 20),
            listing(3, owner: "me", item: 30),
            listing(4, owner: "me", item: 99), // own listing for an item not synced yet: keep
        ]
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.approvals = [
            Approval(id: 1, owner: "seed", kind: .listing, refId: 1, amountCents: 41_000, summary: "Chair", requestedAt: t0),
            Approval(id: 2, owner: "stranger", kind: .listing, refId: 2, amountCents: 41_000, summary: "Not mine"),
            Approval(id: 3, owner: "me", kind: .listing, refId: 3, amountCents: 12_000, summary: "Mine",
                     requestedAt: t0.addingTimeInterval(60)),
            Approval(id: 4, owner: "seed", kind: .purchase, refId: 1, amountCents: 50_000, summary: "Seed's purchase"),
            Approval(id: 5, owner: "me", kind: .purchase, refId: 7, amountCents: 20_000, summary: "My purchase",
                     requestedAt: t0.addingTimeInterval(30)),
            Approval(id: 6, owner: "seed", kind: .listing, refId: 1, amountCents: 41_000, summary: "Done", status: .approved),
        ]
        return s
    }

    @Test func keepsOwnRowsAndSharedRoomListings() {
        let s = joinedSnapshot().scopedToVisibleItems()
        #expect(s.listings.map(\.id) == [1, 3, 4])
        // A purchase approval whose refId happens to match a visible listing id is still dropped.
        #expect(s.approvals.map(\.id) == [1, 3, 5, 6])
    }

    @Test func sharedApprovalsAreReadOnlyAndSeparateFromMine() {
        let s = joinedSnapshot().scopedToVisibleItems()
        #expect(s.pendingApprovals.map(\.id) == [5, 3])
        #expect(s.sharedPendingApprovals.map(\.id) == [1])
        #expect(s.listing(for: s.sharedPendingApprovals[0])?.itemId == 10)
    }

    @Test func approverNameFallsBackWhenOwnerRowIsntSynced() {
        var s = joinedSnapshot().scopedToVisibleItems()
        let a = s.sharedPendingApprovals[0]
        #expect(s.approverName(for: a) == "the owner")
        s.users = [User(identity: "seed", name: "Demo Mover")]
        #expect(s.approverName(for: a) == "Demo Mover")
        #expect(s.isShared(s.listings[0]))
        #expect(!s.isShared(s.listings[1]))
    }

    @Test func ownerOnlySnapshotIsUnchanged() {
        let s = DemoFixtures.inventory(owner: "me")
        let scoped = s.scopedToVisibleItems()
        #expect(scoped.listings == s.listings)
        #expect(scoped.approvals == s.approvals)
        #expect(scoped.sharedPendingApprovals.isEmpty)
    }
}
