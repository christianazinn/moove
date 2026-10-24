import Foundation

/// The numbers for the end-of-move summary screen (#16), computed from plain
/// inputs so it doesn't depend on how other lanes model listings, payments or
/// agent events. The app maps whatever tables exist into these.
public struct MoveSummary: Sendable, Equatable {
    /// Money coming in from one item: a listing, or just its estimated value if not listed yet.
    public struct Sale: Sendable, Hashable {
        public enum Stage: String, Sendable { case estimated, listed, sold }
        public var itemId: UInt64
        public var priceCents: Int64
        public var stage: Stage
        public var simulated: Bool

        public init(itemId: UInt64, priceCents: Int64, stage: Stage, simulated: Bool) {
            self.itemId = itemId
            self.priceCents = priceCents
            self.stage = stage
            self.simulated = simulated
        }
    }

    /// Money going out: an x402 data payment or a Visa purchase. In USD micros
    /// (millionths of a dollar), like the `payment` table: x402 calls cost fractions of a cent.
    public struct Spend: Sendable, Hashable {
        public var agent: String
        public var rail: String
        public var amountMicros: Int64
        public var simulated: Bool

        public init(agent: String, rail: String, amountMicros: Int64, simulated: Bool) {
            self.agent = agent
            self.rail = rail
            self.amountMicros = amountMicros
            self.simulated = simulated
        }
    }

    public struct Event: Sendable, Hashable {
        public var agent: String
        public var kind: String
        public var message: String
        public var createdAt: Date

        public init(agent: String, kind: String, message: String, createdAt: Date) {
            self.agent = agent
            self.kind = kind
            self.message = message
            self.createdAt = createdAt
        }
    }

    public struct RailTotal: Sendable, Hashable, Identifiable {
        public var rail: String
        public var micros: Int64
        public var simulatedMicros: Int64
        public var id: String { rail }
    }

    public struct AgentCount: Sendable, Hashable, Identifiable {
        public var agent: String
        public var steps: Int
        public var id: String { agent }
    }

    public var itemCount: Int
    public var counts: [Disposition: Int]
    /// Sentimental or undecided items still waiting on the user.
    public var needsYou: Int
    public var soldCents: Int64
    /// Listed but not sold yet, plus sell items not listed yet (at their estimate).
    public var pendingSalesCents: Int64
    public var spentMicros: Int64
    public var rails: [RailTotal]
    /// Portion of all money figures that is simulated, for the "simulated" label.
    public var hasSimulatedMoney: Bool
    public var agents: [AgentCount]
    /// Newest first.
    public var timeline: [Event]
    /// Sold, listed or donated: not going to landfill.
    public var divertedItems: Int
    public var divertedKg: Double
    public var keptVolumeM3: Double

    /// Earned plus still-expected sales, minus everything spent, in USD micros.
    public var netMicros: Int64 { (soldCents + pendingSalesCents) * 10_000 - spentMicros }

    public init(items: [Item], sales: [Sale], spend: [Spend], events: [Event], timelineLimit: Int = 8) {
        itemCount = items.count
        var counts: [Disposition: Int] = [:]
        for item in items { counts[item.disposition, default: 0] += 1 }
        self.counts = counts
        needsYou = items.filter(\.needsUser).count

        // One sale per item: the furthest-along stage wins (sold > listed > estimated).
        let rank: [Sale.Stage: Int] = [.estimated: 0, .listed: 1, .sold: 2]
        var best: [UInt64: Sale] = [:]
        for s in sales where (best[s.itemId].map { rank[$0.stage]! < rank[s.stage]! } ?? true) { best[s.itemId] = s }
        soldCents = best.values.filter { $0.stage == .sold }.reduce(0) { $0 + $1.priceCents }
        pendingSalesCents = best.values.filter { $0.stage != .sold }.reduce(0) { $0 + $1.priceCents }

        spentMicros = spend.reduce(0) { $0 + $1.amountMicros }
        rails = Dictionary(grouping: spend, by: \.rail)
            .map { rail, lines in
                RailTotal(rail: rail, micros: lines.reduce(0) { $0 + $1.amountMicros },
                          simulatedMicros: lines.filter(\.simulated).reduce(0) { $0 + $1.amountMicros })
            }
            .sorted { ($0.micros, $1.rail) > ($1.micros, $0.rail) }
        hasSimulatedMoney = spend.contains(where: \.simulated) || best.values.contains { $0.simulated && $0.stage != .estimated }

        agents = Dictionary(grouping: events, by: \.agent)
            .map { AgentCount(agent: $0.key, steps: $0.value.count) }
            .sorted { ($0.steps, $1.agent) > ($1.steps, $0.agent) }
        timeline = Array(events.sorted { $0.createdAt > $1.createdAt }.prefix(timelineLimit))

        let diverted = items.filter { $0.disposition == .sell || $0.disposition == .donate }
        divertedItems = diverted.count
        divertedKg = diverted.reduce(0) { $0 + Self.estimatedKg($1) }
        keptVolumeM3 = items.filter { $0.disposition == .keep }.reduce(0) { $0 + $1.volumeM3 }
    }

    /// Sale lines straight from the inventory: sell items at their estimated value.
    /// Listings (#11) replace these once they exist, since a later stage wins.
    public static func estimatedSales(from items: [Item]) -> [Sale] {
        items.compactMap { item in
            guard item.disposition == .sell, let value = item.estValueCents, value > 0 else { return nil }
            return Sale(itemId: item.id, priceCents: value, stage: .estimated, simulated: false)
        }
    }

    /// Sale lines from the listing agent's listings (#11). Drafts don't count as listed.
    public static func sales(from listings: [Listing]) -> [Sale] {
        listings.compactMap { l in
            switch l.status {
            case .sold: Sale(itemId: l.itemId, priceCents: l.priceCents, stage: .sold, simulated: l.simulated)
            case .posted, .awaitingApproval: Sale(itemId: l.itemId, priceCents: l.priceCents, stage: .listed, simulated: l.simulated)
            case .draft, .rejected, .failed: nil
            }
        }
    }

    /// Spend lines from the `payment` table (#7, #15). Failed payments didn't cost anything.
    public static func spend(from payments: [Payment]) -> [Spend] {
        payments.filter(\.countsTowardBudget).map {
            Spend(agent: $0.agent, rail: $0.rail.rawValue, amountMicros: $0.amountUsdMicros, simulated: $0.simulated)
        }
    }

    /// Timeline entries from the `agent_event` table.
    public static func events(from agentEvents: [AgentEvent]) -> [Event] {
        agentEvents.map { Event(agent: $0.agent, kind: $0.kind.rawValue, message: $0.message, createdAt: $0.createdAt) }
    }

    /// Rough weight from category, nudged by size. Good enough for "about N kg kept out of landfill".
    public static func estimatedKg(_ item: Item) -> Double {
        let typical: (kg: Double, m3: Double)
        switch item.category.lowercased() {
        case "bed": typical = (40, 1.3)
        case "sofa", "couch": typical = (35, 1.2)
        case "table", "desk": typical = (22, 0.7)
        case "chair": typical = (12, 0.5)
        case "storage", "dresser", "bookshelf", "nightstand": typical = (25, 0.4)
        case "lamp": typical = (4, 0.15)
        case "appliance", "refrigerator": typical = (20, 0.2)
        case "decor", "plant": typical = (4, 0.1)
        default: typical = (8, 0.2)
        }
        let scale = min(max(item.volumeM3 / typical.m3, 0.4), 2.5)
        return (typical.kg * scale * 10).rounded() / 10
    }
}

/// Labeled stand-ins for the parts of the summary whose lanes haven't landed yet
/// (used only when the app has no `payment` / `agent_event` rows yet). The UI says "demo" whenever these are used.
public enum SummaryDemo {
    public static let spend: [MoveSummary.Spend] = [
        .init(agent: "pricing", rail: "x402", amountMicros: 10_000, simulated: true),
        .init(agent: "pricing", rail: "x402", amountMicros: 10_000, simulated: true),
        .init(agent: "pricing", rail: "x402", amountMicros: 20_000, simulated: true),
        .init(agent: "pricing", rail: "x402", amountMicros: 10_000, simulated: true),
        .init(agent: "buy", rail: "x402", amountMicros: 30_000, simulated: true),
        .init(agent: "buy", rail: "visa", amountMicros: 89_990_000, simulated: true),
    ]

    public static func events(endingAt end: Date = .now) -> [MoveSummary.Event] {
        let script: [(String, String, String)] = [
            ("vision", "result", "Identified 12 items in the bedroom"),
            ("pricing", "payment", "Paid $0.01 (x402) for Aeron chair comps"),
            ("pricing", "result", "Aeron chair: $380–$460 from 3 comps"),
            ("sort", "result", "Sorted 10 items; left 2 sentimental items for you"),
            ("listing", "plan", "Drafting eBay listing for the Aeron chair"),
            ("listing", "approval", "Asked you to approve a $410 listing"),
            ("buy", "tool_call", "Searched deals for a dining table"),
            ("buy", "payment", "Bought a dining table for $89.99 (Visa)"),
        ]
        return script.enumerated().map { i, e in
            MoveSummary.Event(agent: e.0, kind: e.1, message: e.2, createdAt: end.addingTimeInterval(Double(i - script.count) * 90))
        }
    }
}
