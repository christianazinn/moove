import Foundation

extension SpendToday {
    /// Settings' budget line (#221): "AI today: $0.42 of $3.00 · Price lookups: $0.12 of $2.00".
    /// Each service shows its own cap, or "no cap". nil when the announcement is for another
    /// UTC day (the worker hasn't written since midnight, so it isn't today's spend).
    public func settingsText(now: Date = .now) -> String? {
        settingsRows(now: now).map { $0.map { "\($0.label): \($0.value)" }.joined(separator: " · ") }
    }

    /// The same as label/value rows: ("AI today", "$0.42 of $3.00"), ("Price lookups", "$0.12 of $2.00").
    public func settingsRows(now: Date = .now) -> [(label: String, value: String)]? {
        guard day == Self.utcDay(now) else { return nil }
        func value(_ spent: Int64, _ cap: Int64) -> String {
            UsdMicros.format(spent) + (cap > 0 ? " of \(UsdMicros.format(cap))" : " (no cap)")
        }
        return [("AI today", value(claudeUsdMicros, claudeCapUsdMicros)),
                ("Price lookups", value(apifyUsdMicros, apifyCapUsdMicros))]
    }
}

extension FixtureBackend {
    /// A sample `spend_today` for the offline demo and previews (#221), dated today.
    public static func sampleSpendToday(now: Date = .now) -> String {
        #"{"day":"\#(SpendToday.utcDay(now))","claude":{"usd":0.42,"calls":7,"capUsd":3},"apify":{"usd":0.12,"runs":3,"capUsd":2}}"#
    }
}
