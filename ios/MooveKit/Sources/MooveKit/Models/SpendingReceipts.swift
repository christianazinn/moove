import Foundation

// The Spending screen as paper receipts: the spending log's entries grouped into one receipt per
// agent run (same agent, same day, no gap over an hour), newest receipt first, lines oldest first
// like a printed till roll. Pure grouping and wording, so the screen only draws it.

/// One printed line: a payment, a refused payment, or a failed x402 attempt.
public struct ReceiptLine: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A payment row (any status).
        case payment(PaymentStatus)
        /// The rail refused it before signing (spend cap / per-call max).
        case refused
        /// An x402 attempt that failed before any payment row was written.
        case failedAttempt
    }

    /// The `SpendingEntry` id ("payment-500"), stable across snapshots.
    public var id: String
    /// The row id behind the line (payment or agent event id).
    public var rowId: UInt64
    public var kind: Kind
    public var createdAt: Date
    /// What the agent paid for, e.g. "Premium comps for "IKEA Micke desk"".
    public var description: String
    /// "x402" or "VISA".
    public var railTag: String
    /// "$0.01", or nil when the step had no amount.
    public var amount: String?
    /// Drawn struck through: nothing was paid (failed or refused).
    public var struck: Bool
    public var simulated: Bool
    /// The short status under the line: "REFUSED · OVER SPEND CAP", "FAILED · NO MONEY MOVED", …
    public var note: String?
    /// Why, in the agent's words (refusal reason, failure reason).
    public var detail: String?
    /// The real payment's tx hash and Basescan link ("PAID ON BASE SEPOLIA").
    public var txHash: String?
    public var explorerURL: URL?
    /// The payment behind a payment line, for row identifiers (`payment.<id>`).
    public var paymentId: UInt64?
    /// One VoiceOver sentence, amount first.
    public var spoken: String

    /// Counts toward the receipt's subtotal.
    var countedMicros: Int64 = 0
    var simulatedMicros: Int64 = 0
}

/// One paper receipt: one agent's run of payments.
public struct SpendingReceipt: Sendable, Hashable, Identifiable {
    public var id: String
    public var agent: String
    /// "RECEIPT #000500" (the run's first row id).
    public var number: String
    /// "Pricing agent"
    public var title: String
    /// "3 lookups", "2 Visa checkouts"
    public var subtitle: String
    /// Oldest first, like a printed roll.
    public var lines: [ReceiptLine]
    public var startedAt: Date
    public var endedAt: Date
    /// Non-failed payments on this receipt (real + simulated).
    public var subtotalUsdMicros: Int64
    public var simulatedUsdMicros: Int64
    public var refusals: Int
    /// The agent's x402 budget, printed on its newest receipt only.
    public var budget: AgentBudget?
    /// Deterministic bar widths (1...3) for the decorative barcode.
    public var barcode: [Int]

    public var hasSimulated: Bool { lines.contains(where: \.simulated) }
    public var allSimulated: Bool { !lines.isEmpty && lines.allSatisfy(\.simulated) }

    /// The footer stamp, or nil when nothing on the receipt is simulated.
    public var simulatedStamp: String? {
        guard hasSimulated else { return nil }
        return allSimulated ? "SIMULATED — NO MONEY MOVED" : "SIM LINES: SIMULATED — NO MONEY MOVED"
    }

    /// "$0.025 of $5.00 budget used", with "(est.)" when the app summed it itself.
    public var budgetUsedLine: String? {
        guard let b = budget else { return nil }
        let used = b.isEstimate ? b.spentUsdMicros : b.capUsdMicros - b.remainingUsdMicros
        return "\(UsdMicros.format(used)) of \(UsdMicros.format(b.capUsdMicros)) budget used" + (b.isEstimate ? " (est.)" : "")
    }

    public var budgetRemaining: String? { budget.map { UsdMicros.format($0.remainingUsdMicros) } }

    /// VoiceOver for the footer block.
    public var footerSpoken: String {
        var parts = ["Subtotal \(UsdMicros.format(subtotalUsdMicros))"]
        if simulatedUsdMicros > 0 { parts.append("\(UsdMicros.format(simulatedUsdMicros)) of it simulated, no money moved") }
        if refusals > 0 { parts.append("\(refusals) refused") }
        if let used = budgetUsedLine, let left = budgetRemaining { parts.append("\(used), \(left) left") }
        return parts.joined(separator: ". ") + "."
    }
}

public struct SpendingReceipts: Sendable, Equatable {
    /// Newest receipt first.
    public var receipts: [SpendingReceipt]
    /// Budgets of agents that have no receipt (only "paying" steps so far).
    public var unattachedBudgets: [AgentBudget]

    /// A gap longer than this starts a new receipt for the same agent.
    public static let runGap: TimeInterval = 60 * 60

    public init(
        log: SpendingLog, calendar: Calendar = .current,
        failureReason: (Payment) -> String? = { _ in nil }
    ) {
        let oldestFirst = log.entries.reversed()
        var runs: [[SpendingEntry]] = []
        var openRun: [String: Int] = [:]  // agent -> index in runs
        for entry in oldestFirst {
            if let i = openRun[entry.agent], let last = runs[i].last,
               calendar.isDate(last.createdAt, inSameDayAs: entry.createdAt),
               entry.createdAt.timeIntervalSince(last.createdAt) <= Self.runGap {
                runs[i].append(entry)
            } else {
                runs.append([entry])
                openRun[entry.agent] = runs.count - 1
            }
        }

        var built = runs.map { Self.receipt($0, failureReason: failureReason) }
        built.sort { a, b in
            if a.endedAt != b.endedAt { return a.endedAt > b.endedAt }
            return a.id > b.id
        }
        // Each agent's budget goes on its newest receipt.
        var placed = Set<String>()
        for i in built.indices where !placed.contains(built[i].agent) {
            if let b = log.budgets.first(where: { $0.agent == built[i].agent }) {
                built[i].budget = b
                placed.insert(b.agent)
            }
        }
        receipts = built
        unattachedBudgets = log.budgets.filter { !placed.contains($0.agent) }
    }

    public var isEmpty: Bool { receipts.isEmpty }

    private static func receipt(_ entries: [SpendingEntry], failureReason: (Payment) -> String?) -> SpendingReceipt {
        let lines = entries.map { line($0, failureReason: failureReason) }
        let first = lines[0]
        let agent = entries[0].agent
        let payments: [Payment] = entries.compactMap { entry -> Payment? in
            if case .payment(let p) = entry { return p }
            return nil
        }
        return SpendingReceipt(
            id: "\(agent)-\(first.id)",
            agent: agent,
            number: "RECEIPT #" + pad(first.rowId),
            title: agent.agentDisplayName,
            subtitle: subtitle(payments: payments, lineCount: lines.count),
            lines: lines,
            startedAt: first.createdAt,
            endedAt: lines[lines.count - 1].createdAt,
            subtotalUsdMicros: lines.map(\.countedMicros).reduce(0, +),
            simulatedUsdMicros: lines.map(\.simulatedMicros).reduce(0, +),
            refusals: lines.filter { $0.kind == .refused }.count,
            budget: nil,
            barcode: barcode(seed: first.rowId)
        )
    }

    static func subtitle(payments: [Payment], lineCount: Int) -> String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if payments.isEmpty { return plural(lineCount, "attempt") }
        let rails = Set(payments.map(\.rail))
        if rails == [.visa] { return payments.count == 1 ? "Visa checkout" : plural(payments.count, "Visa checkout") }
        if rails == [.x402] { return plural(payments.count, "lookup") }
        return plural(payments.count, "payment")
    }

    static func line(_ entry: SpendingEntry, failureReason: (Payment) -> String?) -> ReceiptLine {
        switch entry {
        case .payment(let p):
            let real = p.explorerURL != nil && p.status == .settled
            let note: String? = switch p.status {
            case .failed: "FAILED · NO MONEY MOVED"
            case .pending: "PENDING"
            case .settled: real ? "PAID ON BASE SEPOLIA" : nil
            }
            let reason = failureReason(p)
            var line = ReceiptLine(
                id: entry.id, rowId: p.id, kind: .payment(p.status), createdAt: p.createdAt,
                description: p.purpose, railTag: p.rail == .visa ? "VISA" : "x402",
                amount: p.formattedAmount, struck: p.status == .failed, simulated: p.simulated,
                note: note, detail: reason, txHash: p.explorerURL != nil ? p.txHash : nil,
                explorerURL: p.explorerURL, paymentId: p.id,
                spoken: p.accessibilitySummary + (reason.map { " \($0)" } ?? ""))
            if p.countsTowardBudget {
                line.countedMicros = p.amountUsdMicros
                if p.simulated { line.simulatedMicros = p.amountUsdMicros }
            }
            return line
        case .refusal(let e):
            let (what, why) = splitRefusal(e.message)
            let amount = e.data.amountUsdMicros.map(UsdMicros.format)
            return ReceiptLine(
                id: entry.id, rowId: e.id, kind: .refused, createdAt: e.createdAt,
                description: what, railTag: e.data.rail == "visa" ? "VISA" : "x402",
                amount: amount, struck: true, simulated: e.isSimulated,
                note: "REFUSED · OVER SPEND CAP", detail: why ?? "Nothing was signed or paid.",
                txHash: nil, explorerURL: nil, paymentId: nil,
                spoken: "\(amount.map { $0 + ", " } ?? "")\(e.isSimulated ? "simulated, " : "")refused by the spend cap, no money moved. \(e.message)")
        case .failedAttempt(let e):
            return ReceiptLine(
                id: entry.id, rowId: e.id, kind: .failedAttempt, createdAt: e.createdAt,
                description: e.message, railTag: "x402",
                amount: e.data.amountUsdMicros.map(UsdMicros.format), struck: true, simulated: e.isSimulated,
                note: "FAILED ATTEMPT · NO PAYMENT MADE", detail: nil,
                txHash: nil, explorerURL: nil, paymentId: nil,
                spoken: "Failed payment attempt, no payment made. \(e.message). \(e.agent.agentDisplayName).")
        }
    }

    /// "Refused x402 payment for a premium deal scan: $0.25 is over the per-call max of $0.10"
    /// -> ("A premium deal scan", "$0.25 is over the per-call max of $0.10").
    static func splitRefusal(_ message: String) -> (String, String?) {
        let prefixes = ["Refused x402 payment for ", "Refused payment for ", "Refused "]
        guard let prefix = prefixes.first(where: message.hasPrefix) else { return (message, nil) }
        let rest = message.dropFirst(prefix.count)
        guard let colon = rest.range(of: ": ") else { return (message, nil) }
        let what = String(rest[..<colon.lowerBound])
        let why = String(rest[colon.upperBound...])
        guard !what.isEmpty, !why.isEmpty else { return (message, nil) }
        return (what.prefix(1).uppercased() + what.dropFirst(), why)
    }

    static func pad(_ id: UInt64) -> String {
        let s = String(id)
        return s.count >= 6 ? s : String(repeating: "0", count: 6 - s.count) + s
    }

    /// 36 bar widths from a small LCG, so the same receipt always gets the same barcode.
    static func barcode(seed: UInt64, count: Int = 36) -> [Int] {
        var x = seed &* 2_654_435_761 &+ 0x9E37_79B9
        return (0..<count).map { _ in
            x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((x >> 33) % 3) + 1
        }
    }
}

/// Receipt-style dates and times, in fixed English like a till printer.
public enum ReceiptFormat {
    /// "SAT 24 OCT 2026"
    public static func day(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("EEE dd MMM yyyy", calendar).string(from: date).uppercased()
    }

    /// "10:42 AM"
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("h:mm a", calendar).string(from: date)
    }

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    /// "0xc794…136c"
    public static func shortHash(_ hash: String) -> String {
        hash.count > 12 ? "\(hash.prefix(6))…\(hash.suffix(4))" : hash
    }
}

extension SyncSnapshot {
    /// The user's own spending log as receipts, with failure reasons from the agents' notes.
    public func spendingReceipts(_ log: SpendingLog, calendar: Calendar = .current) -> SpendingReceipts {
        SpendingReceipts(log: log, calendar: calendar, failureReason: { failureReason(for: $0) })
    }
}
