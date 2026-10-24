import Foundation
import Testing
@testable import MooveKit

@Suite struct ApprovalTests {
    /// The Offline demo has no listing approvals (its one listing, the $30 mesh chair, is under
    /// the $100 threshold), so these tests add one: a listing for the chair awaiting approval.
    private func withListingApproval(_ base: SyncSnapshot) -> SyncSnapshot {
        var s = base
        let owner = s.items.first { $0.id == 17 }!.owner
        s.listings.append(Listing(id: 200, owner: owner, itemId: 17, title: "Mesh office chair", description: "Test listing.",
                                  priceCents: 12_000, status: .awaitingApproval))
        s.approvals.append(Approval(id: 300, owner: owner, kind: .listing, refId: 200, amountCents: 12_000,
                                    summary: "Sell \"Mesh office chair\" for $120"))
        return s
    }

    private func connectedDemo() async throws -> FixtureBackend {
        let backend = FixtureBackend(identity: "me", seed: withListingApproval(DemoFixtures.demo(owner: "me")))
        _ = try await backend.connect(token: nil)
        return backend
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }

    @Test func pendingAndDecidedSplitAndSort() {
        var s = SyncSnapshot(me: "me")
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.approvals = [
            Approval(id: 1, owner: "me", kind: .listing, refId: 7, amountCents: 100, summary: "b", requestedAt: t0.addingTimeInterval(60)),
            Approval(id: 2, owner: "me", kind: .purchase, refId: 8, amountCents: 100, summary: "a", requestedAt: t0),
            Approval(id: 3, owner: "me", kind: .purchase, refId: 9, amountCents: 100, summary: "old", status: .denied,
                     requestedAt: t0, updatedAt: t0.addingTimeInterval(10)),
            Approval(id: 4, owner: "me", kind: .purchase, refId: 9, amountCents: 100, summary: "new", status: .approved,
                     requestedAt: t0, updatedAt: t0.addingTimeInterval(20)),
            Approval(id: 5, owner: "someone-else", kind: .listing, refId: 7, amountCents: 100, summary: "x"),
        ]
        #expect(s.pendingApprovals.map(\.id) == [2, 1])
        #expect(s.decidedApprovals.map(\.id) == [4, 3])
    }

    @Test func statusRawValuesMatchContract() {
        #expect(ApprovalStatus.allCases.map(\.rawValue) == ["pending", "approved", "denied", "expired"])
        #expect(ApprovalKind.allCases.map(\.rawValue) == ["listing", "purchase"])
    }

    @Test func demoHasNoListingApprovals() {
        // Its only listing is under the threshold; the purchase approvals carry the approval story.
        let s = DemoFixtures.demo(owner: "me")
        #expect(!s.approvals.contains { $0.kind == .listing })
        #expect(!s.listings.contains { $0.status == .awaitingApproval })
        #expect(s.pendingApprovals.contains { $0.kind == .purchase })
        #expect(!s.decidedApprovals.isEmpty)
    }

    @Test func approvingPostsTheListing() async throws {
        let backend = try await connectedDemo()
        try await backend.decideApproval(approvalId: 300, status: .approved)
        let s = await firstSnapshot(backend)
        #expect(s.approvals.first { $0.id == 300 }?.status == .approved)
        let l = s.listings.first { $0.id == 200 }
        #expect(l?.status == .posted)
        #expect(l?.externalId != nil)
        #expect(l?.simulated == true)
        #expect(!s.pendingApprovals.contains { $0.id == 300 })
    }

    @Test func denyingRejectsTheListing() async throws {
        let backend = try await connectedDemo()
        try await backend.decideApproval(approvalId: 300, status: .denied)
        let s = await firstSnapshot(backend)
        #expect(s.approvals.first { $0.id == 300 }?.status == .denied)
        #expect(s.listings.first { $0.id == 200 }?.status == .rejected)
    }

    @Test func approvalForAStalePriceRejects() async throws {
        var seed = withListingApproval(DemoFixtures.inventory(owner: "me"))
        seed.listings[seed.listings.firstIndex { $0.id == 200 }!].priceCents = 39_000 // price changed after the approval was requested
        let backend = FixtureBackend(identity: "me", seed: seed)
        _ = try await backend.connect(token: nil)
        try await backend.decideApproval(approvalId: 300, status: .approved)
        #expect(await firstSnapshot(backend).listings.first { $0.id == 200 }?.status == .rejected)
    }

    @Test func cannotDecideTwiceOrSomeoneElses() async throws {
        let backend = try await connectedDemo()
        try await backend.decideApproval(approvalId: 300, status: .approved)
        await #expect(throws: FixtureBackend.Failure.alreadyDecided) {
            try await backend.decideApproval(approvalId: 300, status: .denied)
        }
        await #expect(throws: FixtureBackend.Failure.invalidStatus) {
            try await backend.decideApproval(approvalId: 85, status: .expired)
        }
        await #expect(throws: FixtureBackend.Failure.noSuchApproval) {
            try await backend.decideApproval(approvalId: 9_999, status: .approved)
        }

        var seed = withListingApproval(DemoFixtures.inventory(owner: "alice"))
        seed.me = nil
        let other = FixtureBackend(identity: "bob", seed: seed)
        _ = try await other.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await other.decideApproval(approvalId: 300, status: .approved)
        }
    }
}
