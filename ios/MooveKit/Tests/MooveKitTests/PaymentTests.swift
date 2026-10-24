import Foundation
import Testing
@testable import MooveKit

@Suite struct PaymentTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func payment(_ id: UInt64, agent: String = "pricing", rail: PaymentRail = .x402, micros: Int64 = 10_000,
                         tx: String? = nil, status: PaymentStatus = .settled, simulated: Bool = false, at minutes: Double = 0) -> Payment {
        Payment(id: id, owner: "me", agent: agent, rail: rail, purpose: "p\(id)", payee: "0xabc", amountUsdMicros: micros,
                txHash: tx, status: status, simulated: simulated, createdAt: t0.addingTimeInterval(minutes * 60))
    }

    private func refusal(_ id: UInt64, agent: String = "pricing", at minutes: Double = 0) -> AgentEvent {
        AgentEvent(id: id, owner: "me", agent: agent, kind: .error, message: "Refused",
                   dataJson: #"{"refused":true,"amountUsdMicros":"250000","remainingUsdMicros":"4990000"}"#,
                   createdAt: t0.addingTimeInterval(minutes * 60))
    }

    // MARK: Money

    @Test func formatsMicros() {
        #expect(UsdMicros.format(10_000) == "$0.01")
        #expect(UsdMicros.format(5_000_000) == "$5.00")
        #expect(UsdMicros.format(0) == "$0.00")
        #expect(UsdMicros.format(1_234_500_000) == "$1,234.50")
        #expect(UsdMicros.format(4_990_000) == "$4.99")
        #expect(UsdMicros.format(-250_000) == "-$0.25")
    }

    @Test func formatsSubCentWithoutRoundingToZero() {
        #expect(UsdMicros.format(1_000) == "$0.001")
        #expect(UsdMicros.format(5_000) == "$0.005")
        #expect(UsdMicros.format(1) == "$0.000001")
        #expect(UsdMicros.format(12_345) == "$0.012345")
    }

    // MARK: Wire mapping

    @Test func enumRawValuesMatchWireStrings() {
        #expect(PaymentRail.allCases.map(\.rawValue) == ["x402", "visa"])
        #expect(PaymentStatus.allCases.map(\.rawValue) == ["pending", "settled", "failed"])
        #expect(AgentEventKind.allCases.map(\.rawValue) == ["plan", "tool_call", "result", "payment", "approval", "error"])
        #expect(AgentEventKind(wire: "tool_call") == .toolCall)
        #expect(PaymentStatus(wire: "bogus") == .pending)
    }

    @Test func emptyStringSentinelsBecomeNil() {
        let p = Payment(id: 1, owner: "me", agent: "a", purpose: "x", payee: "y", amountUsdMicros: 1, txHash: "",
                        simulated: true, refTable: "")
        #expect(p.txHash == nil)
        #expect(p.refTable == nil)
    }

    // MARK: Explorer links

    @Test func basescanURLFromTxHash() {
        let hash = DemoFixtures.realX402TxHash
        #expect(BaseSepolia.explorerURL(txHash: hash)?.absoluteString == "https://sepolia.basescan.org/tx/\(hash)")
        #expect(BaseSepolia.explorerURL(txHash: "") == nil)
        #expect(BaseSepolia.explorerURL(txHash: nil) == nil)
        #expect(payment(1, tx: hash).explorerURL != nil)
    }

    @Test func simulatedPaymentsNeverLinkToExplorer() {
        #expect(payment(1, tx: "0xdead", simulated: true).explorerURL == nil)
        #expect(payment(2, rail: .visa, tx: "0xdead").explorerURL == nil)
    }

    // MARK: Event data

    @Test func parsesEventData() {
        let d = AgentEventData.parse(#"{"txHash":"0x1","explorer":"https://e","simulated":true,"amountUsdMicros":"250000","remainingUsdMicros":42,"extra":[1]}"#)
        #expect(d.txHash == "0x1")
        #expect(d.explorer == "https://e")
        #expect(d.simulated == true)
        #expect(d.amountUsdMicros == 250_000)
        #expect(d.remainingUsdMicros == 42)
        #expect(AgentEventData.parse("not json") == AgentEventData())
        #expect(AgentEventData.parse("") == AgentEventData())
    }

    @Test func onlyRefusedErrorsAreRefusals() {
        #expect(refusal(1).isRefusal)
        let failed = AgentEvent(id: 2, owner: "me", agent: "a", kind: .error, message: "x402 failed", dataJson: #"{"url":"u"}"#)
        let paid = AgentEvent(id: 3, owner: "me", agent: "a", kind: .payment, message: "Paid", dataJson: #"{"refused":true}"#)
        #expect(!failed.isRefusal)
        #expect(!paid.isRefusal)
    }

    // MARK: Spending log

    @Test func entriesAreNewestFirstAndIncludeRefusals() {
        let events = [refusal(50, at: 5), AgentEvent(id: 51, owner: "me", agent: "pricing", kind: .plan, message: "plan", createdAt: t0)]
        let log = SpendingLog(payments: [payment(1, at: 0), payment(2, at: 10), payment(3, at: 10)], events: events)
        #expect(log.entries.map(\.id) == ["payment-3", "payment-2", "refusal-50", "payment-1"])
    }

    @Test func totalsByAgentAndRailSkipFailedPayments() {
        let payments = [
            payment(1, agent: "pricing", micros: 10_000),
            payment(2, agent: "pricing", micros: 5_000, simulated: true),
            payment(3, agent: "pricing", micros: 999_000, status: .failed),
            payment(4, agent: "shopping", rail: .visa, micros: 2_000_000, status: .pending),
        ]
        // The refusal predates the shopping payment, so its reported balance is stale.
        let log = SpendingLog(payments: payments, events: [refusal(9, agent: "shopping", at: -1)])
        #expect(log.totalsByRail[.x402] == 15_000)
        #expect(log.totalsByRail[.visa] == 2_000_000)
        #expect(log.realSpentUsdMicros == 2_010_000)
        #expect(log.simulatedSpentUsdMicros == 5_000)
        #expect(log.totalSpentUsdMicros == 2_015_000)

        #expect(log.budgets.map(\.agent) == ["pricing", "shopping"])
        let pricing = log.budgets[0]
        #expect(pricing.capUsdMicros == 5_000_000)
        #expect(pricing.spentUsdMicros == 15_000)
        #expect(pricing.simulatedUsdMicros == 5_000)
        #expect(pricing.remainingUsdMicros == 4_985_000)
        #expect(pricing.refusals == 0)
        #expect(log.budgets[1].refusals == 1)
        // Card (Visa) spend has its own caps, so it doesn't use up the x402 budget (#15).
        #expect(log.budgets[1].remainingUsdMicros == 5_000_000)
        #expect(pricing.isEstimate)
        #expect(log.budgets[1].isEstimate)
    }

    /// An x402 rail event shaped like the worker's (#45).
    private func x402Event(_ id: UInt64, agent: String = "pricing", kind: AgentEventKind = .payment, outcome: String,
                           remaining: Int64, cap: Int64 = 5_000_000, amount: Int64? = nil, at minutes: Double = 0) -> AgentEvent {
        let amountField = amount.map { #","amountUsdMicros":"\#($0)""# } ?? ""
        return AgentEvent(id: id, owner: "me", agent: agent, kind: kind, message: "x402 \(outcome)",
                          dataJson: #"{"rail":"x402","outcome":"\#(outcome)","simulated":false,"remainingUsdMicros":"\#(remaining)","capUsdMicros":"\#(cap)"\#(amountField)}"#,
                          createdAt: t0.addingTimeInterval(minutes * 60))
    }

    @Test func parsesX402RailFields() {
        let d = x402Event(1, outcome: "settled", remaining: 4_990_000, cap: 2_000_000).data
        #expect(d.isX402)
        #expect(d.outcome == "settled")
        #expect(d.remainingUsdMicros == 4_990_000)
        #expect(d.capUsdMicros == 2_000_000)
        #expect(x402Event(2, kind: .error, outcome: "refused", remaining: 0).isRefusal)
        #expect(!x402Event(3, kind: .error, outcome: "failed", remaining: 0).isRefusal)
    }

    @Test func newestX402EventGivesRemainingAndCap() {
        // The worker's ledger spans owners and restarts: it says $1.50 of a $2.00 cap is left,
        // while this owner's rows only add up to $0.01.
        let events = [
            x402Event(10, outcome: "settled", remaining: 1_990_000, cap: 2_000_000, at: 0),
            x402Event(11, kind: .toolCall, outcome: "paying", remaining: 1_500_000, cap: 2_000_000, at: 5),
            AgentEvent(id: 12, owner: "me", agent: "pricing", kind: .result, message: "not x402", createdAt: t0.addingTimeInterval(600)),
        ]
        let b = SpendingLog(payments: [payment(1, micros: 10_000)], events: events).budgets[0]
        #expect(!b.isEstimate)
        #expect(b.reportedRemainingUsdMicros == 1_500_000)
        #expect(b.remainingUsdMicros == 1_500_000)
        #expect(b.capUsdMicros == 2_000_000)
        #expect(abs(b.fractionUsed - 0.25) < 1e-9)
        #expect(b.estimatedRemainingUsdMicros == 1_990_000)
    }

    @Test func noX402EventFallsBackToEstimateAgainstDefaultCap() {
        // Legacy refusal without rail fields, plus a payment: nothing worker-reported.
        let b = SpendingLog(payments: [payment(1, micros: 30_000)], events: [refusal(9)]).budgets[0]
        #expect(b.isEstimate)
        #expect(b.capUsdMicros == UsdMicros.defaultAgentCap)
        #expect(b.remainingUsdMicros == 4_970_000)
    }

    @Test func failedX402StepsShowAsAttemptsUnlessAPaymentRowCoversThem() {
        let events = [
            x402Event(20, kind: .error, outcome: "failed", remaining: 5_000_000, amount: 10_000, at: 0),  // thrown, no row
            x402Event(21, kind: .error, outcome: "failed", remaining: 5_000_000, at: 1),                  // no USDC option
            x402Event(22, kind: .error, outcome: "failed", remaining: 5_000_000, amount: 20_000, at: 30), // has failed row 2
            x402Event(23, kind: .error, outcome: "refused", remaining: 5_000_000, at: 2),                 // a refusal, not an attempt
            AgentEvent(id: 24, owner: "me", agent: "vision", kind: .error, message: "x402 payment for photos failed: boom",
                       createdAt: t0),                                                                     // no rail fields
        ]
        let payments = [payment(2, micros: 20_000, status: .failed, at: 30.2)]
        let log = SpendingLog(payments: payments, events: events)
        let attempts = log.entries.compactMap { if case .failedAttempt(let e) = $0 { e.id } else { nil } }
        #expect(attempts.sorted() == [20, 21])
        #expect(log.entries.contains { $0.id == "refusal-23" })
        #expect(log.entries.contains { $0.id == "payment-2" })
        #expect(!log.budgets.contains { $0.agent == "vision" })
    }

    @Test func amountlessFailureIsNotDedupedAgainstANearbyFailedPayment() {
        let events = [
            x402Event(30, kind: .error, outcome: "failed", remaining: 5_000_000, at: 0),                  // no USDC option
            x402Event(31, kind: .error, outcome: "failed", remaining: 5_000_000, amount: 20_000, at: 0.5), // has failed row 3
            x402Event(32, kind: .error, outcome: "failed", remaining: 5_000_000, amount: 99_000, at: 0.5), // different amount
        ]
        let payments = [payment(3, micros: 20_000, status: .failed, at: 0.2)]
        let log = SpendingLog(payments: payments, events: events)
        let attempts = log.entries.compactMap { if case .failedAttempt(let e) = $0 { e.id } else { nil } }
        #expect(attempts.sorted() == [30, 32])
        #expect(log.entries.contains { $0.id == "payment-3" })
    }

    @Test func simulatedFlagOnRefusalsAndFailedAttempts() {
        let simRefusal = AgentEvent(id: 40, owner: "me", agent: "shopping", kind: .error, message: "Refused",
                                    dataJson: #"{"rail":"x402","outcome":"refused","simulated":true}"#, createdAt: t0)
        let simFailed = AgentEvent(id: 41, owner: "me", agent: "shopping", kind: .error, message: "failed",
                                   dataJson: #"{"rail":"x402","outcome":"failed","simulated":true}"#, createdAt: t0)
        #expect(simRefusal.isRefusal && simRefusal.isSimulated)
        #expect(simFailed.isFailedX402Attempt && simFailed.isSimulated)
        // Real (simulated: false), legacy (no flag) and malformed data are not simulated.
        #expect(!x402Event(42, kind: .error, outcome: "refused", remaining: 0).isSimulated)
        #expect(!refusal(43).isSimulated)
        #expect(!AgentEvent(id: 44, owner: "me", agent: "a", kind: .error, message: "", dataJson: "nope").isSimulated)
    }

    @Test func demoRefusalBudgetMatchesBudgetRow() {
        let log = DemoFixtures.inventory(owner: "me").spendingLog()
        let shopping = try? #require(log.budgets.first { $0.agent == "shopping" })
        #expect(shopping?.remainingUsdMicros == 5_000_000)
        #expect(shopping?.estimatedRemainingUsdMicros == 5_000_000)
        #expect(log.entries.contains { if case .failedAttempt = $0 { true } else { false } })
    }

    @Test func demoBudgetsAreWorkerReportedAndFailuresShowOnce() {
        let log = DemoFixtures.inventory(owner: "me").spendingLog()
        let pricing = log.budgets.first { $0.agent == "pricing" }
        #expect(pricing?.isEstimate == false)
        // Worker-reported figure agrees with the demo's own rows ($0.025 spent).
        #expect(pricing?.remainingUsdMicros == 4_975_000)
        #expect(pricing?.estimatedRemainingUsdMicros == 4_975_000)
        let attempts = log.entries.compactMap { if case .failedAttempt(let e) = $0 { e.id } else { nil } }
        #expect(attempts == [605]) // 603 is covered by failed payment 503
    }

    @Test func budgetClampsWhenOverCap() {
        let log = SpendingLog(payments: [payment(1, micros: 7_000_000)], events: [], capPerAgentUsdMicros: 5_000_000)
        let b = log.budgets[0]
        #expect(b.remainingUsdMicros == 0)
        #expect(b.fractionUsed == 1)
        #expect(b.isExhausted)
    }

    @Test func agentWithOnlyRefusalsGetsABudgetRow() {
        let log = SpendingLog(payments: [], events: [refusal(1, agent: "shopping")])
        #expect(log.budgets.map(\.agent) == ["shopping"])
        #expect(log.budgets[0].spentUsdMicros == 0)
        #expect(!log.isEmpty)
    }

    @Test func snapshotFiltersAgentEventsByRef() {
        var s = SyncSnapshot(me: "me")
        s.agentEvents = [
            AgentEvent(id: 1, owner: "me", agent: "a", kind: .plan, message: "", refTable: "item", refId: 11, createdAt: t0),
            AgentEvent(id: 2, owner: "me", agent: "a", kind: .result, message: "", refTable: "item", refId: 11, createdAt: t0.addingTimeInterval(1)),
            AgentEvent(id: 3, owner: "me", agent: "a", kind: .result, message: "", refTable: "item", refId: 12, createdAt: t0),
        ]
        #expect(s.agentEvents(refTable: "item", refId: 11).map(\.id) == [2, 1])
        #expect(s.agentEvents().count == 3)
    }

    // MARK: Fixtures

    @Test func demoFixturesShowARealPaymentSimulatedOnesAndARefusal() {
        let s = DemoFixtures.inventory(owner: "me")
        let log = s.spendingLog()
        let real = s.payments.filter { !$0.simulated && $0.status == .settled }
        #expect(real.count == 1)
        #expect(real.first?.txHash == DemoFixtures.realX402TxHash)
        #expect(real.first?.amountUsdMicros == 10_000)
        #expect(real.first?.explorerURL != nil)
        #expect(s.payments.contains { $0.simulated })
        // Simulated payments carry no tx hash, so nothing simulated can look on-chain.
        for p in s.payments where p.simulated { #expect(p.txHash == nil && p.explorerURL == nil) }
        #expect(s.payments.contains { $0.status == .failed })
        #expect(s.agentEvents.contains { $0.isRefusal })
        #expect(log.entries.contains { if case .refusal = $0 { true } else { false } })
        #expect(log.entries.first?.createdAt == log.entries.map(\.createdAt).max())
    }

    @Test func fixtureBackendKeepsIdsUniqueAfterPaymentSeeds() async throws {
        let backend = FixtureBackend.demo(identity: "me")
        _ = try await backend.connect(token: nil)
        try await backend.createNewHome(name: "Home", source: .manual, floorPlanJson: "{}")
        var it = backend.snapshots().makeAsyncIterator()
        let s = try #require(await it.next())
        let maxSeeded = (s.payments.map(\.id) + s.agentEvents.map(\.id)).max() ?? 0
        #expect(try #require(s.newHomes.last).id > maxSeeded)
    }
}
