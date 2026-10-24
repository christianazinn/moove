import Foundation
import Testing
@testable import MooveKit

/// Settings' budget line (#221). Parsing itself is covered in SafetySummaryTests.
@Suite struct SpendTodayTextTests {
    let now = Date(timeIntervalSince1970: 1_793_000_000)

    func text(_ json: String?) -> String? {
        ServiceConfig(values: json.map { ["spend_today": $0] } ?? [:]).spendToday?.settingsText(now: now)
    }

    @Test func showsEachServiceAgainstItsCap() {
        #expect(text(FixtureBackend.sampleSpendToday(now: now)) == "AI today: $0.42 of $3.00 · Price lookups: $0.12 of $2.00")
    }

    @Test func capZeroSaysNoCap() {
        let day = SpendToday.utcDay(now)
        #expect(text(#"{"day":"\#(day)","claude":{"usd":1.5,"calls":2,"capUsd":0},"apify":{"usd":0,"runs":0,"capUsd":2}}"#)
                == "AI today: $1.50 (no cap) · Price lookups: $0.00 of $2.00")
    }

    @Test func hiddenWhenMissingBadOrStale() {
        #expect(text(nil) == nil)
        #expect(text("{not json") == nil)
        #expect(text(FixtureBackend.sampleSpendToday(now: now.addingTimeInterval(-86_400))) == nil)
    }

    @Test func fixtureBackendAnnouncesASample() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        var it = backend.snapshots().makeAsyncIterator()
        let snap = await it.next()!
        #expect(snap.serviceConfig.spendToday?.settingsText() != nil)
    }
}
