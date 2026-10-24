import Foundation

// Mirrors of the `payment` and `agent_event` tables (docs/data-model.md), written by the
// agent worker's x402 rail (#7). Enum raw values are the wire strings.

public enum PaymentRail: String, Codable, Sendable, CaseIterable {
    case x402, visa

    /// Tolerant mapping from the wire string (unknown values fall back to x402).
    public init(wire: String) { self = PaymentRail(rawValue: wire) ?? .x402 }
}

public enum PaymentStatus: String, Codable, Sendable, CaseIterable {
    case pending, settled, failed

    /// Tolerant mapping from the wire string (unknown values read as pending).
    public init(wire: String) { self = PaymentStatus(rawValue: wire) ?? .pending }
}

public enum AgentEventKind: String, Codable, Sendable, CaseIterable {
    case plan
    case toolCall = "tool_call"
    case result, payment, approval, error

    /// Tolerant mapping from the wire string (unknown values read as result).
    public init(wire: String) { self = AgentEventKind(rawValue: wire) ?? .result }
}

/// Base Sepolia block explorer, where x402 testnet payments settle.
public enum BaseSepolia {
    public static let explorerTxPrefix = "https://sepolia.basescan.org/tx/"

    /// Explorer page for a tx hash, or nil when there is no hash (simulated / not settled).
    public static func explorerURL(txHash: String?) -> URL? {
        guard let hash = txHash?.trimmingCharacters(in: .whitespaces), !hash.isEmpty else { return nil }
        return URL(string: explorerTxPrefix + hash)
    }
}

/// USD amounts in micros (USD x 1e6). x402 USDC atomic units are the same thing.
public enum UsdMicros {
    public static let perDollar: Int64 = 1_000_000

    /// Default per-agent cap, matching the worker's `AGENT_SPEND_CAP_USDC` default of 5.
    public static let defaultAgentCap: Int64 = 5 * perDollar

    /// "$0.01", "$5.00", "$1,234.50", and sub-cent amounts with just enough digits ("$0.001").
    /// Locale-independent integer math so it is deterministic in tests.
    public static func format(_ micros: Int64) -> String {
        let sign = micros < 0 ? "-" : ""
        let magnitude = micros.magnitude
        let dollars = magnitude / UInt64(perDollar)
        let fraction = magnitude % UInt64(perDollar)
        var frac = String(fraction)
        frac = String(repeating: "0", count: 6 - frac.count) + frac
        // Keep at least cents; keep more digits only if they're non-zero.
        while frac.count > 2, frac.hasSuffix("0") { frac.removeLast() }
        return "\(sign)$\(groupThousands(dollars)).\(frac)"
    }

    private static func groupThousands(_ n: UInt64) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return out
    }
}

/// Mirror of the `payment` table. `simulated` payments never touched a chain or card network
/// and must be labeled SIMULATED in the UI (Coinbase track rule).
public struct Payment: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var agent: String
    public var rail: PaymentRail
    public var purpose: String
    public var payee: String
    public var amountUsdMicros: Int64
    /// nil when the wire value is "" (simulated, or not settled yet).
    public var txHash: String?
    public var status: PaymentStatus
    public var simulated: Bool
    /// What the payment was for, e.g. ("item", 11). nil / 0 when unset.
    public var refTable: String?
    public var refId: UInt64
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UInt64, owner: IdentityHex, agent: String, rail: PaymentRail = .x402, purpose: String, payee: String,
        amountUsdMicros: Int64, txHash: String? = nil, status: PaymentStatus = .settled, simulated: Bool,
        refTable: String? = nil, refId: UInt64 = 0, createdAt: Date = .now, updatedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.agent = agent
        self.rail = rail
        self.purpose = purpose
        self.payee = payee
        self.amountUsdMicros = amountUsdMicros
        self.txHash = (txHash?.isEmpty ?? true) ? nil : txHash
        self.status = status
        self.simulated = simulated
        self.refTable = (refTable?.isEmpty ?? true) ? nil : refTable
        self.refId = refId
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Basescan link for x402 payments with a tx hash. Never for simulated payments.
    public var explorerURL: URL? {
        guard rail == .x402, !simulated else { return nil }
        return BaseSepolia.explorerURL(txHash: txHash)
    }

    public var formattedAmount: String { UsdMicros.format(amountUsdMicros) }

    /// Counts against the agent's budget: anything not failed (the worker reserves pending spend).
    public var countsTowardBudget: Bool { status != .failed }
}

/// The fields the x402 rail puts in `agent_event.data_json`. All optional; unknown keys ignored.
public struct AgentEventData: Sendable, Hashable, Decodable {
    public var txHash: String?
    public var explorer: String?
    public var url: String?
    public var payee: String?
    public var simulated: Bool?
    public var refused: Bool?
    public var amountUsdMicros: Int64?
    public var remainingUsdMicros: Int64?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case txHash, explorer, url, payee, simulated, refused, amountUsdMicros, remainingUsdMicros
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        txHash = try? c.decodeIfPresent(String.self, forKey: .txHash)
        explorer = try? c.decodeIfPresent(String.self, forKey: .explorer)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        payee = try? c.decodeIfPresent(String.self, forKey: .payee)
        simulated = try? c.decodeIfPresent(Bool.self, forKey: .simulated)
        refused = try? c.decodeIfPresent(Bool.self, forKey: .refused)
        amountUsdMicros = Self.int64(c, .amountUsdMicros)
        remainingUsdMicros = Self.int64(c, .remainingUsdMicros)
    }

    /// The worker serializes bigint micros as strings; accept numbers too.
    private static func int64(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let n = try? c.decodeIfPresent(Int64.self, forKey: key) { return n }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Int64(s) }
        return nil
    }

    /// Parses `data_json`; malformed or empty JSON gives an empty value.
    public static func parse(_ json: String) -> AgentEventData {
        guard let data = json.data(using: .utf8), !json.isEmpty else { return AgentEventData() }
        return (try? JSONDecoder().decode(AgentEventData.self, from: data)) ?? AgentEventData()
    }
}

/// Mirror of the `agent_event` table: one row per agent step.
public struct AgentEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var agent: String
    public var kind: AgentEventKind
    public var message: String
    public var refTable: String?
    public var refId: UInt64
    /// Raw JSON string from the wire; see `data`.
    public var dataJson: String
    public var createdAt: Date

    public init(
        id: UInt64, owner: IdentityHex, agent: String, kind: AgentEventKind, message: String,
        refTable: String? = nil, refId: UInt64 = 0, dataJson: String = "{}", createdAt: Date = .now
    ) {
        self.id = id
        self.owner = owner
        self.agent = agent
        self.kind = kind
        self.message = message
        self.refTable = (refTable?.isEmpty ?? true) ? nil : refTable
        self.refId = refId
        self.dataJson = dataJson
        self.createdAt = createdAt
    }

    public var data: AgentEventData { AgentEventData.parse(dataJson) }

    /// A spend-cap refusal from the x402 rail: an `error` event with `refused: true`.
    public var isRefusal: Bool { kind == .error && data.refused == true }

    /// An x402 attempt that errored without writing a `payment` row: the worker's
    /// "x402 payment for … failed: <reason>" (thrown before settlement) and
    /// "No USDC payment option …" events. The "failed (HTTP …)" variant is skipped
    /// because it comes with a failed `payment` row, which the log already shows.
    public var isFailedX402Attempt: Bool {
        guard kind == .error, !isRefusal else { return false }
        if message.hasPrefix("No USDC payment option") { return true }
        return message.hasPrefix("x402 payment") && message.contains(" failed: ")
    }
}

/// Per-agent spend against its cap.
///
/// The worker's real ledger is per process, keyed by agent across all owners, resets on
/// restart, and takes its cap from `AGENT_SPEND_CAP_USDC`. The app only sees this owner's
/// payment rows, so its own figure is an estimate. When the worker has reported a remaining
/// balance (on a refusal newer than any of the agent's payments), that number wins.
public struct AgentBudget: Sendable, Hashable, Identifiable {
    public var agent: String
    /// Assumed cap (the worker's default); the real one is worker config.
    public var capUsdMicros: Int64
    /// This owner's non-failed payments, real and simulated (the worker's ledger counts both).
    public var spentUsdMicros: Int64
    /// The part of `spentUsdMicros` that was simulated.
    public var simulatedUsdMicros: Int64
    public var refusals: Int
    /// `remainingUsdMicros` from the agent's newest refusal, if still current.
    public var reportedRemainingUsdMicros: Int64? = nil

    public var id: String { agent }
    /// True when "remaining" is the app's own estimate rather than a worker-reported figure.
    public var isEstimate: Bool { reportedRemainingUsdMicros == nil }
    public var estimatedRemainingUsdMicros: Int64 { max(0, capUsdMicros - spentUsdMicros) }
    public var remainingUsdMicros: Int64 { reportedRemainingUsdMicros.map { max(0, $0) } ?? estimatedRemainingUsdMicros }
    /// 0...1, for a progress bar.
    public var fractionUsed: Double {
        guard capUsdMicros > 0 else { return 1 }
        let used = reportedRemainingUsdMicros.map { capUsdMicros - max(0, $0) } ?? spentUsdMicros
        return min(1, max(0, Double(used) / Double(capUsdMicros)))
    }
    public var isExhausted: Bool { remainingUsdMicros == 0 }
}

/// One row of the spending log: a payment, a refused payment, or a failed x402 attempt.
public enum SpendingEntry: Sendable, Hashable, Identifiable {
    case payment(Payment)
    case refusal(AgentEvent)
    case failedAttempt(AgentEvent)

    public var id: String {
        switch self {
        case .payment(let p): "payment-\(p.id)"
        case .refusal(let e): "refusal-\(e.id)"
        case .failedAttempt(let e): "attempt-\(e.id)"
        }
    }

    public var createdAt: Date {
        switch self {
        case .payment(let p): p.createdAt
        case .refusal(let e), .failedAttempt(let e): e.createdAt
        }
    }

    public var agent: String {
        switch self {
        case .payment(let p): p.agent
        case .refusal(let e), .failedAttempt(let e): e.agent
        }
    }

    /// Tiebreak so equal timestamps still sort deterministically (higher id is newer).
    fileprivate var orderKey: (Date, UInt64, Int) {
        switch self {
        case .payment(let p): (p.createdAt, p.id, 1)
        case .refusal(let e), .failedAttempt(let e): (e.createdAt, e.id, 0)
        }
    }
}

/// Pure view model for the spending log screen.
public struct SpendingLog: Sendable, Equatable {
    public var entries: [SpendingEntry]
    public var budgets: [AgentBudget]
    /// Non-failed spend per rail.
    public var totalsByRail: [PaymentRail: Int64]
    /// Non-failed, non-simulated spend (real money / testnet USDC actually moved).
    public var realSpentUsdMicros: Int64
    /// Non-failed simulated spend.
    public var simulatedSpentUsdMicros: Int64

    public init(payments: [Payment], events: [AgentEvent], capPerAgentUsdMicros: Int64 = UsdMicros.defaultAgentCap) {
        let refusals = events.filter(\.isRefusal)
        // Only agents that actually use the x402 rail get failed-attempt rows.
        let x402Agents = Set(payments.filter { $0.rail == .x402 }.map(\.agent))
            .union(refusals.map(\.agent))
            .union(events.filter { $0.kind == .payment }.map(\.agent))
        let failedAttempts = events.filter { $0.isFailedX402Attempt && x402Agents.contains($0.agent) }
        entries = (payments.map(SpendingEntry.payment) + refusals.map(SpendingEntry.refusal)
                   + failedAttempts.map(SpendingEntry.failedAttempt))
            .sorted { a, b in
                let (ad, aid, ar) = a.orderKey, (bd, bid, br) = b.orderKey
                if ad != bd { return ad > bd }
                if aid != bid { return aid > bid }
                return ar > br
            }

        let counted = payments.filter(\.countsTowardBudget)
        var byRail: [PaymentRail: Int64] = [:]
        for p in counted { byRail[p.rail, default: 0] += p.amountUsdMicros }
        totalsByRail = byRail
        realSpentUsdMicros = counted.filter { !$0.simulated }.map(\.amountUsdMicros).reduce(0, +)
        simulatedSpentUsdMicros = counted.filter(\.simulated).map(\.amountUsdMicros).reduce(0, +)

        let agents = Set(payments.map(\.agent)).union(refusals.map(\.agent))
        budgets = agents.sorted().map { agent in
            let mine = counted.filter { $0.agent == agent }
            let myRefusals = refusals.filter { $0.agent == agent }
            // Trust the worker's figure only if no payment by this agent came after it.
            let newestRefusal = myRefusals.max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            let newestPaymentAt = payments.filter { $0.agent == agent }.map(\.createdAt).max()
            var reported: Int64?
            if let r = newestRefusal, newestPaymentAt.map({ r.createdAt >= $0 }) ?? true {
                reported = r.data.remainingUsdMicros
            }
            return AgentBudget(
                agent: agent,
                capUsdMicros: capPerAgentUsdMicros,
                spentUsdMicros: mine.map(\.amountUsdMicros).reduce(0, +),
                simulatedUsdMicros: mine.filter(\.simulated).map(\.amountUsdMicros).reduce(0, +),
                refusals: myRefusals.count,
                reportedRemainingUsdMicros: reported
            )
        }
    }

    public var totalSpentUsdMicros: Int64 { realSpentUsdMicros + simulatedSpentUsdMicros }
    public var isEmpty: Bool { entries.isEmpty }
}
