import Foundation

/// The pure parts of the Summary screen's "payoff" layout (#335): the one-line story under the
/// hero, the "Where everything went" bar, the small meters under the money figures, the leaf
/// meter, the agents' key steps and the safety receipt's barcode. Every figure comes from
/// `MoveSummary` / `Review.piles`, so the screen's numbers stay the ones `DemoNumbersTests` checks.
public enum SummaryPayoff {
    // MARK: Story

    /// "7 things kept, 1 sold, 3 still selling — and ~49 kg kept out of landfill."
    /// Sold counts items with a sold listing; still selling is the rest of the sell pile.
    /// nil when there are no items.
    public static func story(_ s: MoveSummary) -> String? {
        guard s.itemCount > 0 else { return nil }
        let sold = min(s.soldItems, s.counts[.sell] ?? 0)
        let selling = (s.counts[.sell] ?? 0) - sold
        let parts: [(Int, String)] = [
            (s.counts[.keep] ?? 0, "kept"),
            (sold, "sold"),
            (selling, "still selling"),
            (s.counts[.donate] ?? 0, "donated"),
            (s.counts[.trash] ?? 0, "trashed"),
        ].filter { $0.0 > 0 }
        guard let first = parts.first else {
            return "\(plural(s.itemCount, "thing")) to decide."
        }
        var text = "\(plural(first.0, "thing")) \(first.1)"
        for p in parts.dropFirst() { text += ", \(p.0) \(p.1)" }
        let kg = Int(s.divertedKg.rounded())
        return kg > 0 ? text + " — and ~\(kg) kg kept out of landfill." : text + "."
    }

    // MARK: Where everything went

    /// One piece of the stacked bar. `destination` nil is "Needs you" (undecided or sentimental
    /// items the user hasn't decided): the same split Review's board and deck use, so a segment's
    /// count is exactly the rows its list shows.
    public struct Segment: Sendable, Hashable, Identifiable {
        public var destination: Disposition?
        public var count: Int
        /// Share of all items, 0...1.
        public var fraction: Double
        public var id: String { destination?.rawValue ?? "needsYou" }

        public var label: String {
            switch destination {
            case .keep?: "Keep"
            case .sell?: "Sell"
            case .donate?: "Donate"
            case .trash?: "Trash"
            case .undecided?, nil: "Needs you"
            }
        }
    }

    /// Keep, Sell, Donate, Trash (Review's piles), then Needs you; empty segments left out.
    public static func segments(_ items: [Item]) -> [Segment] {
        guard !items.isEmpty else { return [] }
        let total = Double(items.count)
        let piles = Review.piles(items)
        var out = piles.filter { $0.count > 0 }.map {
            Segment(destination: $0.destination, count: $0.count, fraction: Double($0.count) / total)
        }
        let needsYou = items.count - piles.map(\.count).reduce(0, +)
        if needsYou > 0 { out.append(Segment(destination: nil, count: needsYou, fraction: Double(needsYou) / total)) }
        return out
    }

    /// "Keep 7, Sell 4, Needs you 1", for VoiceOver.
    public static func spokenSegments(_ segments: [Segment]) -> String {
        segments.map { "\($0.label) \($0.count)" }.joined(separator: ", ")
    }

    // MARK: Meters

    /// `part / whole` clamped to 0...1; 0 when there's no whole.
    public static func share(_ part: Int64, of whole: Int64) -> Double {
        guard whole > 0 else { return 0 }
        return min(max(Double(part) / Double(whole), 0), 1)
    }

    /// Under "Made": how much of the expected sales has actually sold.
    public static func soldShare(_ s: MoveSummary) -> Double { share(s.soldCents, of: s.soldCents + s.pendingSalesCents) }

    /// Under "Spent": the simulated part of the spend (the rest is real money).
    public static func simulatedShare(_ s: MoveSummary) -> Double {
        share(s.rails.map(\.simulatedMicros).reduce(0, +), of: s.spentMicros)
    }

    /// Under "Net": money in (sold + still selling) against money in plus money out.
    public static func inShare(_ s: MoveSummary) -> Double {
        let inflow = (s.soldCents + s.pendingSalesCents) * 10_000
        return share(inflow, of: inflow + s.spentMicros)
    }

    // MARK: Impact

    /// Kilograms one leaf stands for on the leaf meter.
    public static let kgPerLeaf = 5.0
    public static let maxLeaves = 12

    /// Leaves on the meter: one per ~5 kg kept out of landfill, at least one when anything was,
    /// at most 12.
    public static func leaves(kg: Double) -> Int {
        guard kg > 0 else { return 0 }
        return min(max(Int((kg / kgPerLeaf).rounded()), 1), maxLeaves)
    }

    /// Of everything let go (sold, donated, trashed), the share by weight that skipped the landfill.
    /// nil when nothing was let go.
    public static func divertedShare(_ items: [Item]) -> Double? {
        let gone = items.filter { [.sell, .donate, .trash].contains($0.disposition) }
        let total = gone.map(MoveSummary.estimatedKg).reduce(0, +)
        guard total > 0 else { return nil }
        let diverted = gone.filter { $0.disposition != .trash }.map(MoveSummary.estimatedKg).reduce(0, +)
        return diverted / total
    }

    // MARK: What the agents did

    /// The steps worth telling, from the timeline (newest first): results, payments and approvals
    /// before plans and tool calls, at most `limit`, oldest first so they read as a story. `rest`
    /// is everything else, oldest first, for "Show all".
    public static func keySteps(_ timeline: [MoveSummary.Event], limit: Int = 4) -> (key: [MoveSummary.Event], rest: [MoveSummary.Event]) {
        let rank: [String: Int] = ["payment": 0, "approval": 0, "result": 1, "error": 2]
        let indexed = Array(timeline.enumerated())
        let picked = indexed
            .sorted { (rank[$0.element.kind] ?? 3, $0.offset) < (rank[$1.element.kind] ?? 3, $1.offset) }
            .prefix(limit)
            .map(\.offset)
        let keep = Set(picked)
        func oldestFirst(_ xs: [(offset: Int, element: MoveSummary.Event)]) -> [MoveSummary.Event] {
            xs.sorted { ($0.element.createdAt, -$0.offset) < ($1.element.createdAt, -$1.offset) }.map(\.element)
        }
        return (oldestFirst(indexed.filter { keep.contains($0.offset) }), oldestFirst(indexed.filter { !keep.contains($0.offset) }))
    }

    // MARK: Safety receipt

    /// The stamp under the safety receipt when any line mentions simulated money.
    public static func safetyStamp(_ lines: [SafetySummary.Line]) -> String? {
        guard lines.contains(where: \.simulated) else { return nil }
        return lines.allSatisfy(\.simulated) ? "SIMULATED — NO MONEY MOVED" : "SIM LINES: SIMULATED — NO MONEY MOVED"
    }

    /// The safety receipt's decorative barcode: the same bars for the same lines.
    public static func safetyBarcode(_ lines: [SafetySummary.Line]) -> [Int] {
        var seed: UInt64 = 1_469_598_103_934_665_603
        for byte in lines.map(\.text).joined(separator: "|").utf8 { seed = (seed ^ UInt64(byte)) &* 1_099_511_628_211 }
        return SpendingReceipts.barcode(seed: seed)
    }

    static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
