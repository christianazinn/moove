import Foundation
import Testing
@testable import MooveKit

@Suite struct SafetySummaryTests {
    let demo = SafetySummary(snapshot: DemoFixtures.demo(owner: "me"))

    @Test func countsTheDemoScam() {
        // Deal 76, the planted Aeron scam, is the only one at or over 0.7. Deal 75 isn't scored.
        #expect(demo.fraud.blocked == 1)
        #expect(demo.fraud.checked == 14)
        #expect(demo.fraud.maxScore == 0.85)
        #expect(demo.fraud.exampleTitle == "Herman Miller Aeron, brand new, $95, Zelle only, ship only")
    }

    @Test func countsTheDemoApprovals() {
        // Purchases only (the one listing, the $30 mesh chair, is under the threshold): 299 (expired,
        // re-asked as 302), 302 (denied), 303 (approved), 85 (pending).
        #expect(demo.approvals == .init(requested: 4, approved: 1, denied: 1, pending: 1, expired: 1, thresholdCents: 10_000))
    }

    @Test func countsSentimentalItems() {
        #expect(demo.sentimentalLeftToYou == 1) // the Yamaha guitar, as on the seeded Bedroom
    }

    @Test func x402SpendAgainstThePerAgentCaps() {
        // Payments 500 (real) + 501, 502 (simulated); 503 failed. Pricing and shopping have $5 caps each.
        let b = try! #require(demo.x402)
        #expect(b.spentUsdMicros == 25_000)
        #expect(b.simulatedUsdMicros == 15_000)
        #expect(b.capUsdMicros == 10_000_000)
        #expect(b.agents == 2)
        #expect(b.refusals == 1) // event 604, over the per-call max
    }

    @Test func cardSpendAgainstTheDefaultCap() {
        // The settled mattress (payment 90); the declined rug (91) didn't cost anything.
        let b = try! #require(demo.card)
        #expect(b.spentUsdMicros == 179_990_000)
        #expect(b.allSimulated)
        #expect(b.capUsdMicros == 1_500_000_000)
        #expect(demo.aiToday == nil) // the fixture has no spend_today
    }

    @Test func demoLinesSaySimulated() {
        #expect(!demo.isEmpty)
        #expect(demo.lines.map(\.text) == [
            "1 scam deal blocked · fraud score 0.85",
            "4 approvals asked · 1 approved · 1 denied · 1 waiting · 1 expired",
            "1 sentimental item left for you",
            "Spent $0.025 of $10.00 data budget ($0.015 simulated)",
            "Spent $179.99 of $1,500.00 card budget (simulated)",
        ])
        let byKind = Dictionary(uniqueKeysWithValues: demo.lines.map { ($0.kind, $0) })
        #expect(byKind[.approvals]?.detail == "Anything over $100 needs your OK")
        #expect(byKind[.x402]?.detail == "2 agents · $5.00 cap each · 1 payment refused")
        #expect(byKind[.x402]?.simulated == true)
        #expect(byKind[.card]?.simulated == true)
        #expect(byKind[.fraud]?.simulated == false)
        // Every line with simulated money says so in its text and its spoken label.
        for line in demo.lines where line.simulated {
            #expect(line.text.contains("simulated"))
            #expect(line.spoken.contains("simulated"))
        }
        #expect(byKind[.x402]?.spoken.hasPrefix("Spent 2.5 cents of $10.00 data budget, 1.5 cents simulated") == true)
        #expect(byKind[.approvals]?.spoken.hasPrefix("4 approvals asked, 1 approved") == true)
    }

    @Test func emptyWithoutCommerceData() {
        // Inventory only (no deals, approvals, payments or x402 steps) is still "nothing to guard".
        var s = DemoFixtures.inventory(owner: "me")
        s.approvals = []
        s.payments = []
        s.agentEvents = DemoFixtures.listingEvents(owner: "me")
        let summary = SafetySummary(snapshot: s)
        #expect(summary.isEmpty)
        #expect(summary.lines.isEmpty)
        #expect(SafetySummary(snapshot: SyncSnapshot(me: "me")).isEmpty)
        #expect(SafetySummary.emptyText == "No purchases yet, so nothing to guard.")
    }

    @Test func ignoresOtherOwnersRows() {
        var s = DemoFixtures.demo(owner: "me")
        s.deals = s.deals.map { var d = $0; d.owner = "someone else"; return d }
        s.approvals = []
        let summary = SafetySummary(snapshot: s)
        #expect(summary.fraud.blocked == 0)
        #expect(summary.approvals.requested == 0)
        #expect(!summary.lines.contains { $0.kind == .fraud })
    }

    @Test func noScamsLine() {
        var s = DemoFixtures.demo(owner: "me")
        s.deals.removeAll { $0.id == 76 }
        let line = SafetySummary(snapshot: s).lines.first { $0.kind == .fraud }
        #expect(line?.text == "13 deals checked · no scams found")
    }

    @Test func realOnlySpendHasNoSimulatedLabel() {
        var s = SyncSnapshot(me: "me")
        s.payments = [DemoFixtures.payments(owner: "me")[0]]
        let line = try! #require(SafetySummary(snapshot: s).lines.first { $0.kind == .x402 })
        #expect(line.text == "Spent $0.01 of $5.00 data budget")
        #expect(!line.simulated)
        #expect(line.detail == nil)
    }

    @Test func aiSpendTodayFromServiceConfig() {
        let now = Date(timeIntervalSince1970: 1_793_000_000) // 2026-10-26 UTC
        let day = SpendToday.utcDay(now)
        var s = DemoFixtures.demo(owner: "me")
        s.serviceConfig = ServiceConfig(values: ["spend_today":
            #"{"day":"\#(day)","claude":{"usd":0.42,"calls":7,"capUsd":3},"apify":{"usd":0.12,"runs":3,"capUsd":2}}"#])
        let summary = SafetySummary(snapshot: s, now: now)
        #expect(summary.aiToday?.spentUsdMicros == 540_000)
        #expect(summary.aiToday?.capUsdMicros == 5_000_000)
        #expect(summary.lines.last?.text == "AI today: $0.54 of $5.00 daily cap (estimate)")
        #expect(summary.lines.last?.spoken == "AI today, 54 cents of $5.00 daily cap, estimate")

        // A stale day (worker down since yesterday) isn't shown as today.
        #expect(SafetySummary(snapshot: s, now: now.addingTimeInterval(86_400)).aiToday == nil)
    }

    @Test func spendTodayParsing() {
        let t = SpendToday.parse(#"{"day":"2026-10-24","claude":{"usd":1.5,"calls":2,"capUsd":0},"apify":{"usd":0,"runs":0,"capUsd":2}}"#)
        #expect(t?.claudeUsdMicros == 1_500_000)
        #expect(t?.capUsdMicros == nil) // Claude is uncapped
        #expect(SpendToday.parse("not json") == nil)
        #expect(ServiceConfig().spendToday == nil)
        #expect(SpendToday.utcDay(Date(timeIntervalSince1970: 0)) == "1970-01-01")
    }

    @Test func spokenAmounts() {
        #expect(SafetySummary.spokenUsd(10_000) == "1 cent")
        #expect(SafetySummary.spokenUsd(5_000) == "0.5 cents")
        #expect(SafetySummary.spokenUsd(540_000) == "54 cents")
        #expect(SafetySummary.spokenUsd(179_990_000) == "$179.99")
    }
}
