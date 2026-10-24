import Foundation
import Testing
@testable import MooveKit

/// Expired approvals and re-asks in Approvals (#186, follow-up to #214).
@Suite struct ApprovalExpiryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func approval(_ id: UInt64, _ status: ApprovalStatus, kind: ApprovalKind = .listing, refId: UInt64 = 7,
                          owner: IdentityHex = "me") -> Approval {
        Approval(id: id, owner: owner, kind: kind, refId: refId, amountCents: 41_000, summary: "s\(id)", status: status,
                 requestedAt: t0.addingTimeInterval(Double(id)))
    }

    @Test func firstAskIsNotAReask() {
        var s = SyncSnapshot(me: "me")
        s.approvals = [approval(1, .pending)]
        let asks = s.asks(for: s.approvals[0])
        #expect(asks == ApprovalAsks(askNumber: 1, expiredBefore: [], askedAgain: false))
        #expect(asks.pendingCaption == nil)
        #expect(asks.spokenPendingCaption == nil)
    }

    @Test func reaskCountsEarlierExpiredAsksForTheSameRef() {
        var s = SyncSnapshot(me: "me")
        s.approvals = [
            approval(1, .expired), approval(4, .expired), approval(9, .pending),
            approval(2, .expired, refId: 8),                    // another listing
            approval(3, .expired, kind: .purchase),             // a deal with the same id
            approval(5, .expired, owner: "someone-else"),       // someone else's
        ]
        let pending = s.approvals[2]
        let asks = s.asks(for: pending)
        #expect(asks.askNumber == 3)
        #expect(asks.expiredBefore.map(\.id) == [4, 1])
        #expect(!asks.askedAgain)
        #expect(asks.pendingCaption == "Asked again (3 of 3). The 2 earlier requests got no answer in 12 h.")
        #expect(asks.spokenPendingCaption == "Asked again, 3 of 3. The 2 earlier requests got no answer in 12 hours.")
        #expect(s.approvalGroup(for: pending).map(\.id) == [1, 4, 9])
    }

    @Test func oneEarlierExpiryReadsTwoOfThree() {
        var s = SyncSnapshot(me: "me")
        s.approvals = [approval(1, .expired), approval(2, .pending)]
        #expect(s.asks(for: s.approvals[1]).pendingCaption == "Asked again (2 of 3). The earlier request got no answer in 12 h.")
    }

    @Test func moreAsksThanTheDefaultCapDontClaimAnOutOf() {
        var s = SyncSnapshot(me: "me")
        s.approvals = (1...3).map { approval($0, .expired) } + [approval(4, .pending)]
        #expect(s.asks(for: s.approvals[3]).pendingCaption == "Asked again (ask 4). The 3 earlier requests got no answer in 12 h.")
    }

    @Test func deniedEarlierAsksDontCountAsReasks() {
        var s = SyncSnapshot(me: "me")
        s.approvals = [approval(1, .denied, kind: .purchase), approval(2, .pending, kind: .purchase)]
        #expect(s.asks(for: s.approvals[1]).askNumber == 1)
    }

    @Test func historyLineSaysWhetherTheAgentAskedAgain() {
        var s = SyncSnapshot(me: "me")
        s.approvals = [
            approval(1, .expired), approval(2, .pending),   // re-asked listing
            approval(3, .expired, refId: 8),                // listing it gave up on
            approval(4, .expired, kind: .purchase, refId: 9),
            approval(5, .denied, refId: 10),
        ]
        #expect(s.asks(for: s.approvals[0]).askedAgain)
        #expect(s.historyOutcome(for: s.approvals[0]) == "No answer in 12 h. The agent asked again.")
        #expect(s.historyOutcome(for: s.approvals[2]) == "No answer in 12 h.")
        #expect(s.historyOutcome(for: s.approvals[3]) == "No answer in 12 h. Nothing was bought.")
        #expect(s.historyOutcome(for: s.approvals[4]) == s.approvals[4].outcomeText)
        #expect(s.historyAccessibilitySummary(for: s.approvals[0])
            == "Sell, $410, expired. s1. No answer in 12 hours. The agent asked again.")
        #expect(s.historyAccessibilitySummary(for: s.approvals[4]).hasPrefix("Sell, $410, denied. s5. You denied it."))
    }

    @Test func demoHistoryHasOneExpiredAskThatWasAskedAgain() async throws {
        let backend = FixtureBackend.demo(identity: "me")
        _ = try await backend.connect(token: nil)
        var it = backend.snapshots().makeAsyncIterator()
        let s = try #require(await it.next())

        // Pending stays the Aeron listing and the Wayfair sofa (UI tests and the demo script rely on it).
        #expect(s.pendingApprovals.map(\.amountCents).sorted() == [41_000, 42_999])
        #expect(s.pendingApprovals.allSatisfy { !s.asks(for: $0).isReask })

        let expired = s.decidedApprovals.filter { $0.status == .expired }
        #expect(expired.map(\.id) == [299])
        let kivik = try #require(expired.first)
        #expect(s.historyOutcome(for: kivik) == "No answer in 12 h. The agent asked again.")
        // The re-ask (302) is still the deal's latest approval, so Shopping still shows it as denied.
        let latest = try #require(s.purchaseApproval(for: kivik.refId))
        #expect(latest.id == 302)
        #expect(s.asks(for: latest).askNumber == 2)
        // The buy agent logged the re-ask.
        #expect(s.agentEvents.contains { $0.refTable == "deal" && $0.refId == 70 && $0.message.contains("asking again (1 of 2)") })
    }
}
