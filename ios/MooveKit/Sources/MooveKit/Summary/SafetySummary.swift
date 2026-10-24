import Foundation

/// "Agents kept you safe" (#225): the guardrails that fired during the move, from rows the app
/// already syncs. Scam deals the fraud screen blocked, approvals the agents asked for, sentimental
/// items left to the user, and spend against the caps. Simulated money is always called simulated.
public struct SafetySummary: Sendable, Equatable {
    public struct FraudBlocks: Sendable, Equatable {
        /// Deals the fraud screen scored (any score).
        public var checked: Int
        /// Deals at or above `Deal.fraudBlockScore`: the buy agent won't buy them.
        public var blocked: Int
        public var maxScore: Double?
        /// The highest-scored blocked deal's title.
        public var exampleTitle: String?
    }

    public struct Approvals: Sendable, Equatable {
        public var requested: Int
        public var approved: Int
        public var denied: Int
        public var pending: Int
        public var expired: Int
        /// The user's approval threshold, when their `user` row is synced.
        public var thresholdCents: Int64?
    }

    /// Spend on one rail (or the worker's daily AI spend) against its cap.
    public struct Budget: Sendable, Equatable {
        public var spentUsdMicros: Int64
        /// The part of `spentUsdMicros` that was simulated.
        public var simulatedUsdMicros: Int64
        /// nil when there is no cap to compare against.
        public var capUsdMicros: Int64?
        /// How many agents' caps `capUsdMicros` adds up (x402 caps are per agent).
        public var agents: Int
        /// Payments the caps or per-call limits refused.
        public var refusals: Int

        public var allSimulated: Bool { spentUsdMicros > 0 && simulatedUsdMicros == spentUsdMicros }
    }

    public enum LineKind: String, Sendable, Hashable { case fraud, approvals, sentimental, x402, roomX402, card, ai }

    /// One short line on the card.
    public struct Line: Sendable, Hashable, Identifiable {
        public var kind: LineKind
        public var text: String
        public var detail: String?
        /// The VoiceOver label: same facts, commas instead of dots, sub-dollar amounts in cents.
        public var spoken: String
        /// The line mentions simulated money (the UI adds a SIM tag).
        public var simulated: Bool
        public var id: String { kind.rawValue }
    }

    public var fraud: FraudBlocks
    public var approvals: Approvals
    /// `maybeSentimental` items: Moove never auto-decides these.
    public var sentimentalLeftToYou: Int
    /// x402 data payments against the per-agent caps; nil when no x402 activity.
    public var x402: Budget?
    /// x402 payments agents made for items in a room the user joined (#254): another member's
    /// spend, so it's never added into `x402`. nil when there are none. `capUsdMicros` is nil.
    public var roomX402: Budget?
    /// Visa purchases against the card cap; nil when no card payments.
    public var card: Budget?
    /// Today's Claude + Apify spend against the worker's daily caps (`spend_today`, #220).
    public var aiToday: Budget?

    /// No deals, approvals, payments or x402 steps: nothing for the guardrails to have done.
    public var isEmpty: Bool

    public static let emptyText = "No purchases yet, so nothing to guard."

    /// Detail under the shared-room x402 line (#254).
    public static let roomDetail = "For items in a room you joined. Not counted in your spend."

    /// The worker's card cap default (`VISA_SPEND_CAP_USD`, agents/src/integrations/caps.ts). Visa
    /// events don't report the live cap, so this is what the app compares against.
    public static let defaultCardCapUsdMicros: Int64 = 1_500 * UsdMicros.perDollar

    public init(snapshot s: SyncSnapshot, cardCapUsdMicros: Int64 = Self.defaultCardCapUsdMicros, now: Date = .now) {
        func mine(_ owner: IdentityHex) -> Bool { s.me == nil || owner == s.me }

        let deals = s.deals.filter { mine($0.owner) }
        let blocked = deals.filter(\.isFraudBlocked)
        let worst = blocked.max { ($0.fraudScore ?? 0, $1.id) < ($1.fraudScore ?? 0, $0.id) }
        fraud = FraudBlocks(checked: deals.filter { $0.fraudScore != nil }.count, blocked: blocked.count,
                            maxScore: worst?.fraudScore, exampleTitle: worst?.title)

        let asked = s.approvals.filter { mine($0.owner) }
        func count(_ status: ApprovalStatus) -> Int { asked.filter { $0.status == status }.count }
        approvals = Approvals(requested: asked.count, approved: count(.approved), denied: count(.denied),
                              pending: count(.pending), expired: count(.expired),
                              thresholdCents: s.users.first { $0.identity == s.me }?.approvalThresholdCents)

        sentimentalLeftToYou = s.items.filter { mine($0.owner) && $0.maybeSentimental }.count

        let payments = s.payments.filter { mine($0.owner) }
        let events = s.agentEvents.filter { mine($0.owner) }
        let log = SpendingLog(payments: payments, events: events)
        if log.budgets.isEmpty {
            x402 = nil
        } else {
            x402 = Budget(
                spentUsdMicros: log.budgets.map(\.spentUsdMicros).reduce(0, +),
                simulatedUsdMicros: log.budgets.map(\.simulatedUsdMicros).reduce(0, +),
                capUsdMicros: log.budgets.map(\.capUsdMicros).reduce(0, +),
                agents: log.budgets.count,
                refusals: log.budgets.map(\.refusals).reduce(0, +))
        }

        let roomCounted = s.roomPayments.filter { $0.rail == .x402 && $0.countsTowardBudget }
        roomX402 = roomCounted.isEmpty ? nil : Budget(
            spentUsdMicros: roomCounted.map(\.amountUsdMicros).reduce(0, +),
            simulatedUsdMicros: roomCounted.filter(\.simulated).map(\.amountUsdMicros).reduce(0, +),
            capUsdMicros: nil, agents: Set(roomCounted.map(\.agent)).count, refusals: 0)

        let cardPayments = payments.filter { $0.rail == .visa }
        if cardPayments.isEmpty {
            card = nil
        } else {
            let counted = cardPayments.filter(\.countsTowardBudget)
            card = Budget(
                spentUsdMicros: counted.map(\.amountUsdMicros).reduce(0, +),
                simulatedUsdMicros: counted.filter(\.simulated).map(\.amountUsdMicros).reduce(0, +),
                capUsdMicros: cardCapUsdMicros, agents: Set(cardPayments.map(\.agent)).count,
                refusals: events.filter { $0.isRefusal && $0.data.rail == "visa" }.count)
        }

        aiToday = s.serviceConfig.spendToday.flatMap { t in
            guard t.day == SpendToday.utcDay(now) else { return nil }
            return Budget(spentUsdMicros: t.spentUsdMicros, simulatedUsdMicros: 0, capUsdMicros: t.capUsdMicros,
                          agents: 0, refusals: 0)
        }

        isEmpty = deals.isEmpty && asked.isEmpty && payments.isEmpty && !events.contains(where: \.isX402) && roomX402 == nil
    }

    // MARK: Text

    /// The card's lines, in order. Empty when `isEmpty` (the UI shows `emptyText`).
    public var lines: [Line] {
        guard !isEmpty else { return [] }
        var out: [Line] = []

        if fraud.blocked > 0 {
            let score = fraud.maxScore.map(Self.score) ?? ""
            let text = "\(Self.plural(fraud.blocked, "scam deal")) blocked · \(fraud.blocked > 1 ? "top " : "")fraud score \(score)"
            out.append(Line(kind: .fraud, text: text, detail: fraud.exampleTitle.map { "“\($0)”" },
                            spoken: Self.spoken(text) + (fraud.exampleTitle.map { ", \($0)" } ?? ""), simulated: false))
        } else if fraud.checked > 0 {
            let text = "\(Self.plural(fraud.checked, "deal")) checked · no scams found"
            out.append(Line(kind: .fraud, text: text, detail: nil, spoken: Self.spoken(text), simulated: false))
        }

        if approvals.requested > 0 {
            let a = approvals
            let parts = ["\(Self.plural(a.requested, "approval")) asked"]
                + [(a.approved, "approved"), (a.denied, "denied"), (a.pending, "waiting"), (a.expired, "expired")]
                    .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            let text = parts.joined(separator: " · ")
            let detail = a.thresholdCents.map { "Anything over \(Self.dollars(cents: $0)) needs your OK" }
            out.append(Line(kind: .approvals, text: text, detail: detail,
                            spoken: Self.spoken(text) + (detail.map { ", \($0)" } ?? ""), simulated: false))
        }

        if sentimentalLeftToYou > 0 {
            let text = "\(Self.plural(sentimentalLeftToYou, "sentimental item")) left for you"
            out.append(Line(kind: .sentimental, text: text, detail: nil, spoken: text, simulated: false))
        }

        if let b = x402 {
            let text = Self.spendText(b, budget: "data budget")
            let detail = ([b.agents > 1 ? "\(b.agents) agents · \(UsdMicros.format((b.capUsdMicros ?? 0) / Int64(b.agents))) cap each" : nil,
                           b.refusals > 0 ? "\(Self.plural(b.refusals, "payment")) refused" : nil] as [String?])
                .compactMap { $0 }.joined(separator: " · ")
            out.append(Line(kind: .x402, text: text, detail: detail.isEmpty ? nil : detail,
                            spoken: Self.spokenSpend(b, budget: "data budget") + (detail.isEmpty ? "" : ", " + Self.spoken(detail)),
                            simulated: b.simulatedUsdMicros > 0))
        }

        if let b = roomX402 {
            let text = "Shared room: agents paid \(UsdMicros.format(b.spentUsdMicros)) over x402\(Self.simulatedSuffix(b, format: UsdMicros.format))"
            let spokenSim = Self.simulatedSuffix(b, format: Self.spokenUsd)
                .replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "")
            let detail = Self.roomDetail
            out.append(Line(kind: .roomX402, text: text, detail: detail,
                            spoken: "Shared room, agents paid \(Self.spokenUsd(b.spentUsdMicros)) over x402\(spokenSim), \(detail)",
                            simulated: b.simulatedUsdMicros > 0))
        }

        if let b = card {
            let text = Self.spendText(b, budget: "card budget")
            let detail = b.refusals > 0 ? "\(Self.plural(b.refusals, "purchase")) refused" : nil
            out.append(Line(kind: .card, text: text, detail: detail,
                            spoken: Self.spokenSpend(b, budget: "card budget") + (detail.map { ", \($0)" } ?? ""),
                            simulated: b.simulatedUsdMicros > 0))
        }

        if let b = aiToday {
            let cap = b.capUsdMicros.map { " of \(UsdMicros.format($0)) daily cap" } ?? ", no daily cap"
            let text = "AI today: \(UsdMicros.format(b.spentUsdMicros))\(cap) (estimate)"
            let spokenCap = b.capUsdMicros.map { " of \(Self.spokenUsd($0)) daily cap" } ?? ", no daily cap"
            out.append(Line(kind: .ai, text: text, detail: nil,
                            spoken: "AI today, \(Self.spokenUsd(b.spentUsdMicros))\(spokenCap), estimate", simulated: false))
        }
        return out
    }

    /// "Spent $0.025 of $10.00 data budget ($0.015 simulated)"; "(simulated)" when all of it was.
    static func spendText(_ b: Budget, budget: String) -> String {
        let cap = b.capUsdMicros.map { " of \(UsdMicros.format($0)) \(budget)" } ?? ""
        return "Spent \(UsdMicros.format(b.spentUsdMicros))\(cap)\(simulatedSuffix(b, format: UsdMicros.format))"
    }

    static func spokenSpend(_ b: Budget, budget: String) -> String {
        let cap = b.capUsdMicros.map { " of \(spokenUsd($0)) \(budget)" } ?? ""
        let sim = simulatedSuffix(b, format: spokenUsd)
            .replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "")
        return "Spent \(spokenUsd(b.spentUsdMicros))\(cap)\(sim)"
    }

    private static func simulatedSuffix(_ b: Budget, format: (Int64) -> String) -> String {
        if b.allSimulated { return " (simulated)" }
        if b.simulatedUsdMicros > 0 { return " (\(format(b.simulatedUsdMicros)) simulated)" }
        return ""
    }

    /// "0.85"
    static func score(_ s: Double) -> String { String(format: "%.2f", s) }

    static func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    /// "$100" for whole dollars, else "$100.50".
    static func dollars(cents: Int64) -> String {
        cents % 100 == 0 ? "$\(cents / 100)" : UsdMicros.format(cents * 10_000)
    }

    /// For VoiceOver: sub-dollar amounts as cents ("2.5 cents", "1 cent"), the rest as "$179.99".
    static func spokenUsd(_ micros: Int64) -> String {
        guard micros.magnitude < UInt64(UsdMicros.perDollar) else { return UsdMicros.format(micros) }
        let tenths = (micros + 500) / 1_000 // tenths of a cent, rounded
        let whole = tenths % 10 == 0
        let n = whole ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
        return "\(n) cent\(whole && tenths == 10 ? "" : "s")"
    }

    static func spoken(_ text: String) -> String { text.replacingOccurrences(of: " · ", with: ", ") }
}

/// The worker's `spend_today` announcement (#220): estimated Claude + Apify spend for the UTC day
/// against the daily caps (`capUsd` 0 = no cap).
public struct SpendToday: Sendable, Equatable {
    public var day: String
    public var claudeUsdMicros: Int64
    public var apifyUsdMicros: Int64
    /// 0 when uncapped.
    public var claudeCapUsdMicros: Int64
    public var apifyCapUsdMicros: Int64

    public var spentUsdMicros: Int64 { claudeUsdMicros + apifyUsdMicros }
    /// Both daily caps added up; nil when either service is uncapped.
    public var capUsdMicros: Int64? {
        claudeCapUsdMicros > 0 && apifyCapUsdMicros > 0 ? claudeCapUsdMicros + apifyCapUsdMicros : nil
    }

    private struct Wire: Decodable {
        struct Service: Decodable { var usd: Double?; var capUsd: Double? }
        var day: String
        var claude: Service?
        var apify: Service?
    }

    /// nil when the JSON is missing or malformed.
    public static func parse(_ json: String) -> SpendToday? {
        guard let data = json.data(using: .utf8), let w = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        func micros(_ usd: Double?) -> Int64 { Int64(((usd ?? 0) * Double(UsdMicros.perDollar)).rounded()) }
        return SpendToday(day: w.day, claudeUsdMicros: micros(w.claude?.usd), apifyUsdMicros: micros(w.apify?.usd),
                          claudeCapUsdMicros: micros(w.claude?.capUsd), apifyCapUsdMicros: micros(w.apify?.capUsd))
    }

    /// "2026-10-24", the worker's day key.
    public static func utcDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension ServiceConfig {
    /// Today's AI spend against the daily caps, if the worker announced it (#220).
    public var spendToday: SpendToday? { values["spend_today"].flatMap(SpendToday.parse) }
}
