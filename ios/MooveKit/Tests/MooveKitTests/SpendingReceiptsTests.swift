import Foundation
import Testing
@testable import MooveKit

/// The Spending screen's paper receipts: grouping, wording, totals and VoiceOver.
@Suite struct SpendingReceiptsTests {
    private let me: IdentityHex = "me"

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Sat 24 Oct 2026, 15:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_854_000)

    /// The offline demo's x402 rows plus its two Visa rows, at a fixed time.
    private func demoLog() -> (SyncSnapshot, SpendingLog) {
        var s = SyncSnapshot(me: me)
        s.payments = DemoFixtures.payments(owner: me, now: now) + [
            Payment(id: 90, owner: me, agent: "buy", rail: .visa, purpose: "Mattress: 8\" memory foam mattress, Full",
                    payee: "simulated merchant", amountUsdMicros: 179_990_000, status: .settled, simulated: true,
                    refTable: "deal", refId: 62, createdAt: now.addingTimeInterval(-20 * 60)),
            Payment(id: 91, owner: me, agent: "buy", rail: .visa, purpose: "Area rug: 5x7 flatweave area rug, cream/gray",
                    payee: "simulated merchant", amountUsdMicros: 89_990_000, status: .failed, simulated: true,
                    refTable: "deal", refId: 80, createdAt: now.addingTimeInterval(-15 * 60)),
        ]
        s.agentEvents = DemoFixtures.paymentEvents(owner: me, now: now)
        return (s, s.spendingLog())
    }

    @Test func demoGroupsIntoOneReceiptPerAgentRun() {
        let (s, log) = demoLog()
        let r = s.spendingReceipts(log, calendar: utc)
        // Newest receipt first: shopping (refusal 3 min ago), pricing (failed attempt 9 min ago), buy (rug 15 min ago).
        #expect(r.receipts.map(\.agent) == ["shopping", "pricing", "buy"])
        #expect(r.receipts.map(\.title) == ["Shopping agent", "Pricing agent", "Buy agent"])
        #expect(r.receipts.map(\.subtitle) == ["1 lookup", "3 lookups", "2 Visa checkouts"])
        // Every log entry is on exactly one receipt.
        #expect(r.receipts.flatMap(\.lines).map(\.id).sorted() == log.entries.map(\.id).sorted())
        // Lines print oldest first.
        let pricing = r.receipts[1]
        #expect(pricing.lines.map(\.rowId) == [500, 501, 502, 605])
        #expect(pricing.number == "RECEIPT #000500")
        #expect(r.unattachedBudgets.isEmpty)
    }

    @Test func receiptTotalsAddUpToTheScreenTotals() {
        let (s, log) = demoLog()
        let r = s.spendingReceipts(log, calendar: utc)
        #expect(r.receipts.map(\.subtotalUsdMicros).reduce(0, +) == log.totalSpentUsdMicros)
        #expect(r.receipts.map(\.simulatedUsdMicros).reduce(0, +) == log.simulatedSpentUsdMicros)
        #expect(r.receipts.map(\.refusals).reduce(0, +) == log.budgets.map(\.refusals).reduce(0, +))
        let pricing = r.receipts[1]
        #expect(UsdMicros.format(pricing.subtotalUsdMicros) == "$0.025")
        #expect(UsdMicros.format(pricing.simulatedUsdMicros) == "$0.015")
        #expect(pricing.budgetUsedLine == "$0.025 of $5.00 budget used")
        #expect(pricing.budgetRemaining == "$4.975")
        // The failed rug isn't counted; the mattress is.
        #expect(UsdMicros.format(r.receipts[2].subtotalUsdMicros) == "$179.99")
        #expect(r.receipts[2].budget == nil)  // Visa has no x402 budget
    }

    @Test func realPaymentPrintsBaseSepoliaAndSimulatedOnesAreStamped() {
        let (s, log) = demoLog()
        let r = s.spendingReceipts(log, calendar: utc)
        let pricing = r.receipts[1]
        let real = pricing.lines[0]
        #expect(real.note == "PAID ON BASE SEPOLIA")
        #expect(real.txHash == DemoFixtures.realX402TxHash)
        #expect(real.explorerURL?.absoluteString == BaseSepolia.explorerTxPrefix + DemoFixtures.realX402TxHash)
        #expect(!real.simulated && real.railTag == "x402" && real.amount == "$0.01")
        #expect(real.paymentId == 500)
        for line in r.receipts.flatMap(\.lines) where line.simulated { #expect(line.explorerURL == nil, "\(line.id)") }
        #expect(pricing.simulatedStamp == "SIM LINES: SIMULATED — NO MONEY MOVED")
        #expect(r.receipts[2].simulatedStamp == "SIMULATED — NO MONEY MOVED")
        #expect(r.receipts[2].lines.allSatisfy { $0.railTag == "VISA" })
    }

    @Test func refusalsAndFailuresAreStruckThrough() {
        let (s, log) = demoLog()
        let r = s.spendingReceipts(log, calendar: utc)
        let refusal = r.receipts[0].lines.first { $0.kind == .refused }
        #expect(refusal?.struck == true)
        #expect(refusal?.amount == "$0.25")
        #expect(refusal?.note == "REFUSED · OVER SPEND CAP")
        #expect(refusal?.description == "A premium deal scan")
        #expect(refusal?.detail == "$0.25 is over the per-call max of $0.10")
        #expect(refusal?.spoken.hasPrefix("$0.25, refused by the spend cap, no money moved.") == true)

        let rug = r.receipts[2].lines.first { $0.rowId == 91 }
        #expect(rug?.struck == true && rug?.note == "FAILED · NO MONEY MOVED")
        #expect(rug?.kind == .payment(.failed))

        let attempt = r.receipts[1].lines.first { $0.kind == .failedAttempt }
        #expect(attempt?.amount == nil && attempt?.struck == true)
    }

    @Test func paymentLinesSpeakLikeTheOldRows() {
        let (s, log) = demoLog()
        let r = s.spendingReceipts(log, calendar: utc)
        for line in r.receipts.flatMap(\.lines) {
            guard case .payment = line.kind, let id = line.paymentId,
                  let p = s.payments.first(where: { $0.id == id }) else { continue }
            #expect(line.spoken.hasPrefix(p.accessibilitySummary))
            // CommerceUITests finds simulated rows by this.
            if p.simulated { #expect(line.spoken.contains(", simulated,")) }
        }
    }

    @Test func longGapOrNewDayStartsANewReceipt() {
        func pay(_ id: UInt64, minutesAgo: Double) -> Payment {
            Payment(id: id, owner: me, agent: "pricing", purpose: "comps \(id)", payee: "x",
                    amountUsdMicros: 10_000, simulated: true, createdAt: now.addingTimeInterval(-minutesAgo * 60))
        }
        let log = SpendingLog(payments: [pay(1, minutesAgo: 200), pay(2, minutesAgo: 170), pay(3, minutesAgo: 30),
                                         pay(4, minutesAgo: 16 * 60)], events: [])
        let r = SpendingReceipts(log: log, calendar: utc)
        // 15:00 now: 14:30 | 11:40, 12:10 | 23:00 the day before.
        #expect(r.receipts.map { $0.lines.map(\.rowId) } == [[3], [1, 2], [4]])
        #expect(r.receipts[0].budget != nil && r.receipts[1].budget == nil)
    }

    @Test func liveRowJoinsTheNewestReceiptAndKeepsItsId() {
        let (s, log) = demoLog()
        let before = s.spendingReceipts(log, calendar: utc)
        var s2 = s
        s2.payments.append(Payment(id: 700, owner: me, agent: "buy", rail: .visa, purpose: "Desk chair: Mesh task chair with arms, black",
                                   payee: "simulated merchant", amountUsdMicros: 79_990_000, simulated: true, createdAt: now))
        let after = s2.spendingReceipts(s2.spendingLog(), calendar: utc)
        #expect(after.receipts[0].agent == "buy")
        #expect(after.receipts[0].id == before.receipts[2].id)
        #expect(after.receipts[0].lines.last?.rowId == 700)
        #expect(after.receipts[0].subtitle == "3 Visa checkouts")
    }

    @Test func formatting() {
        #expect(ReceiptFormat.day(now, calendar: utc) == "SAT 24 OCT 2026")
        #expect(ReceiptFormat.time(now, calendar: utc) == "3:00 PM")
        #expect(ReceiptFormat.shortHash(DemoFixtures.realX402TxHash) == "0xc794…136c")
        #expect(SpendingReceipts.pad(500) == "000500" && SpendingReceipts.pad(1_234_567) == "1234567")
        let bars = SpendingReceipts.barcode(seed: 500)
        #expect(bars == SpendingReceipts.barcode(seed: 500))
        #expect(bars != SpendingReceipts.barcode(seed: 501))
        #expect(bars.count == 36 && bars.allSatisfy { (1...3).contains($0) })
        #expect(SpendingReceipts.splitRefusal("Something else").1 == nil)
        #expect(SpendingReceipts.subtitle(payments: [], lineCount: 1) == "1 attempt")
    }

    @Test func emptyLogHasNoReceipts() {
        let r = SpendingReceipts(log: SpendingLog(payments: [], events: []))
        #expect(r.isEmpty && r.unattachedBudgets.isEmpty)
    }
}
