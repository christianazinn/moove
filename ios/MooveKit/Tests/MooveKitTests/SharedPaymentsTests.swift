import Foundation
import Testing
@testable import MooveKit

/// Payments and agent steps for items in rooms shared with the user (#254).
@Suite struct SharedPaymentsTests {
    /// What `my_payment` / `my_agent_event` send a judge who joined the seeded room: the seed
    /// user's simulated x402 comps payments for its items, plus the judge's own rows.
    private func joinedSnapshot(withOwn: Bool = true) -> SyncSnapshot {
        var s = SyncSnapshot(me: "me")
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.payments = [
            Payment(id: 1, owner: "seed", agent: "pricing", purpose: "comps for 'Desk'", payee: "x402",
                    amountUsdMicros: 10_000, simulated: true, refTable: "item", refId: 2, createdAt: t0),
            Payment(id: 2, owner: "seed", agent: "pricing", purpose: "comps for 'Chair'", payee: "x402",
                    amountUsdMicros: 10_000, simulated: true, refTable: "item", refId: 10, createdAt: t0.addingTimeInterval(10)),
        ]
        s.agentEvents = [
            AgentEvent(id: 1, owner: "seed", agent: "pricing", kind: .payment, message: "Paid $0.01 for comps",
                       refTable: "item", refId: 2, dataJson: #"{"rail":"x402","outcome":"settled","remainingUsdMicros":"4980000","capUsdMicros":"5000000"}"#,
                       createdAt: t0),
        ]
        if withOwn {
            s.payments.append(Payment(id: 9, owner: "me", agent: "pricing", purpose: "comps for 'Lamp'", payee: "x402",
                                      amountUsdMicros: 20_000, txHash: "0xabc", simulated: false, refTable: "item", refId: 40,
                                      createdAt: t0.addingTimeInterval(20)))
            s.agentEvents.append(AgentEvent(id: 9, owner: "me", agent: "pricing", kind: .payment, message: "Paid $0.02",
                                            dataJson: #"{"rail":"x402","outcome":"settled","remainingUsdMicros":"4900000"}"#,
                                            createdAt: t0.addingTimeInterval(20)))
        }
        return s
    }

    @Test func splitsYoursFromTheRoom() {
        let s = joinedSnapshot()
        #expect(s.myPayments.map(\.id) == [9])
        #expect(s.roomPayments.map(\.id) == [1, 2])
        #expect(s.isSharedRoom(s.payments[0]))
        #expect(!s.isSharedRoom(s.payments[2]))
        #expect(s.myAgentEvents.map(\.id) == [9])
        #expect(s.roomAgentEvents.map(\.id) == [1])
    }

    @Test func yourTotalsLeaveTheRoomOut() {
        let split = joinedSnapshot().spendingSplit()
        #expect(split.yours.realSpentUsdMicros == 20_000)
        #expect(split.yours.simulatedSpentUsdMicros == 0)
        #expect(split.room.simulatedSpentUsdMicros == 20_000)
        #expect(split.room.realSpentUsdMicros == 0)
        #expect(split.room.entries.map(\.id) == ["payment-2", "payment-1"])
        // Your budget comes from your own newest x402 step, not the seed user's.
        #expect(split.yours.budgets.first?.reportedRemainingUsdMicros == 4_900_000)
        #expect(joinedSnapshot().spendingLog() == split.yours)
    }

    @Test func aJoinedPhoneWithNoPaymentsOfItsOwnStillHasRows() {
        let split = joinedSnapshot(withOwn: false).spendingSplit()
        #expect(split.yours.isEmpty)
        #expect(!split.room.isEmpty)
        #expect(!split.isEmpty)
    }

    @Test func withoutAnIdentityEverythingIsYours() {
        var s = joinedSnapshot()
        s.me = nil
        #expect(s.roomPayments.isEmpty)
        #expect(s.myPayments.count == 3)
        #expect(s.spendingSplit().room.isEmpty)
    }

    @Test func summarySpendIsYoursOnly() {
        let summary = MoveSummary(snapshot: joinedSnapshot())
        #expect(summary.spentMicros == 20_000)
        #expect(summary.timeline.count == 2) // the room's agent steps still show
    }

    @Test func safetyCardShowsTheRoomsX402Separately() {
        let safety = SafetySummary(snapshot: joinedSnapshot(withOwn: false))
        #expect(!safety.isEmpty)
        #expect(safety.x402 == nil)
        let room = try! #require(safety.roomX402)
        #expect(room.spentUsdMicros == 20_000)
        #expect(room.allSimulated)
        #expect(room.capUsdMicros == nil)
        let line = try! #require(safety.lines.first { $0.kind == .roomX402 })
        #expect(line.text == "Shared room: agents paid $0.02 over x402 (simulated)")
        #expect(line.detail == SafetySummary.roomDetail)
        #expect(line.simulated)
        #expect(line.spoken.hasPrefix("Shared room, agents paid 2 cents over x402, simulated"))
    }

    @Test func safetyCardKeepsYourOwnX402Line() {
        let safety = SafetySummary(snapshot: joinedSnapshot())
        #expect(safety.x402?.spentUsdMicros == 20_000)
        #expect(safety.roomX402?.spentUsdMicros == 20_000)
        #expect(safety.lines.map(\.kind) == [.x402, .roomX402])
    }
}
