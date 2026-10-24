import SwiftUI
import MooveKit

/// Live spending log (#7): every payment the agents make (x402 USDC on Base Sepolia, or Visa),
/// newest first, with per-agent budgets and spend-cap refusals. Driven entirely by
/// `payment` and `agent_event` rows in the snapshot, so it updates as the worker writes them.
struct SpendingView: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        let log = store.snapshot.spendingLog()
        let state = store.commerceState(hasRows: !log.isEmpty)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "06 — Spending",
                    title: "Where the money went.",
                    lede: "Every payment the agents make, live, with each agent's budget and any spend it was refused."
                )
                if state != .content {
                    CommercePlaceholder(
                        state: state,
                        emptyTitle: "No payments yet",
                        emptyDetail: "Agents pay when they price an item (comps over x402) or buy something on your Shopping list (Visa). Sort an item to Sell, or choose a deal in Shopping, and the payment shows up here live."
                    )
                    .padding(.top, 32)
                } else {
                    SpendingTotals(log: log).padding(.top, 28)
                    if !log.budgets.isEmpty {
                        ListHeader(title: "Budgets", count: "\(log.budgets.count)").padding(.top, 40)
                        ForEach(log.budgets) { AgentBudgetRow(budget: $0) }
                    }
                    ListHeader(title: "Activity", count: "\(log.entries.count)").padding(.top, 40)
                    ForEach(log.entries) { entry in
                        switch entry {
                        case .payment(let payment):
                            PaymentRow(payment: payment, failureReason: store.snapshot.failureReason(for: payment))
                        case .refusal(let event): RefusalRow(event: event)
                        case .failedAttempt(let event): FailedAttemptRow(event: event)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Spending")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .animation(.default, value: log.entries)
    }
}

private extension String {
    /// "pricing" -> "Pricing agent".
    var agentLabel: String { agentDisplayName }
}

private extension Date {
    var ago: String { formatted(.relative(presentation: .named)) }
}

/// Three headline figures between rules, split by hairlines.
struct SpendingTotals: View {
    let log: SpendingLog

    var body: some View {
        let refused = log.budgets.map(\.refusals).reduce(0, +)
        HStack(spacing: 0) {
            StatFigure(label: "Spent", value: UsdMicros.format(log.realSpentUsdMicros))
                .padding(.vertical, 18).padding(.trailing, 14)
                .accessibilityLabel("Spent for real, \(UsdMicros.format(log.realSpentUsdMicros))")
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Simulated", value: UsdMicros.format(log.simulatedSpentUsdMicros), tint: Theme.ochreInk)
                .padding(.vertical, 18).padding(.horizontal, 14)
                .accessibilityLabel("Simulated, \(UsdMicros.format(log.simulatedSpentUsdMicros)), no money moved")
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Refused", value: "\(refused)", tint: Theme.danger)
                .padding(.vertical, 18).padding(.leading, 14)
                .accessibilityLabel("\(refused) \(refused == 1 ? "payment" : "payments") refused by spend caps")
        }
        .fixedSize(horizontal: false, vertical: true)
        .ruled(.top)
        .ruled()
    }
}

struct AgentBudgetRow: View {
    let budget: AgentBudget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveLine(spacing: 12) {
                Text(budget.agent.agentLabel).blockTitle()
                Spacer(minLength: 8)
                if budget.isEstimate {
                    // The worker's ledger is per process and its cap is worker config, so the
                    // app's own sum is only an estimate; don't present it as an exact balance.
                    Text("\(UsdMicros.format(budget.spentUsdMicros)) spent of \(UsdMicros.format(budget.capUsdMicros)) cap (est.)")
                        .monoText(13.5)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(UsdMicros.format(budget.remainingUsdMicros)) left")
                        .monoText(13.5)
                        .foregroundStyle(budget.isExhausted ? Theme.danger : Theme.text)
                        .amountText()
                }
            }
            ProgressView(value: budget.fractionUsed)
                .tint(budget.isExhausted ? Theme.danger : budget.fractionUsed > 0.8 ? Theme.ochre : Theme.accent)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                if budget.isEstimate {
                    Text("Your payments only")
                } else {
                    Text("Reported by the agent worker")
                }
                if budget.simulatedUsdMicros > 0 {
                    Text("· \(UsdMicros.format(budget.simulatedUsdMicros)) simulated").foregroundStyle(Theme.ochreInk)
                }
                if budget.refusals > 0 {
                    Text("· \(budget.refusals) refused").foregroundStyle(Theme.danger)
                }
            }
            .monoMeta()
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var parts = [budget.agent.agentLabel]
        parts.append(budget.isEstimate
            ? "\(UsdMicros.format(budget.spentUsdMicros)) spent of a \(UsdMicros.format(budget.capUsdMicros)) cap, estimated"
            : "\(UsdMicros.format(budget.remainingUsdMicros)) left of \(UsdMicros.format(budget.capUsdMicros))")
        if budget.simulatedUsdMicros > 0 { parts.append("\(UsdMicros.format(budget.simulatedUsdMicros)) of it simulated") }
        if budget.refusals > 0 { parts.append("\(budget.refusals) refused") }
        return parts.joined(separator: ", ")
    }
}

struct PaymentRow: View {
    let payment: Payment
    var failureReason: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                AdaptiveLine {
                    Text(payment.formattedAmount)
                        .monoText(16, weight: .bold)
                        .strikethrough(payment.status == .failed)
                        .foregroundStyle(payment.status == .failed ? Theme.muted : Theme.text)
                        .amountText()
                    if payment.simulated {
                        SimulatedBadge()
                    } else if payment.rail == .visa {
                        MonoTag(text: payment.railTag, tone: Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(payment.createdAt.ago).monoMeta()
                }
                Text(payment.purpose)
                    .sansText(15)
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                AdaptiveLine(spacing: 6) {
                    Text("\(payment.agent.agentLabel) · \(payment.rail.label)")
                    Spacer(minLength: 8)
                    PaymentStatusChip(status: payment.status)
                }
                .monoMeta()
                if payment.status == .failed {
                    CommerceProblem(text: failureReason ?? "The payment didn't go through. No money moved.")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(payment.accessibilitySummary + (failureReason.map { " \($0)" } ?? ""))
            .accessibilityIdentifier("payment.\(payment.id)")
            // Only real x402 payments with a tx hash link out (`explorerURL` is nil when simulated).
            if let url = payment.explorerURL, let hash = payment.txHash {
                Link(destination: url) {
                    Label("Basescan \(hash.shortHash)", systemImage: "arrow.up.right.square")
                        .monoText(12.5, weight: .bold)
                        .foregroundStyle(Theme.accentStrong)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("View the transaction on Basescan")
                .accessibilityHint("Opens sepolia.basescan.org")
                .accessibilityIdentifier("payment.basescan.\(payment.id)")
            }
        }
        .padding(.top, 16)
        .padding(.bottom, payment.explorerURL != nil && payment.txHash != nil ? 4 : 16)
        .ruled()
    }
}

/// A payment the worker refused to make because it broke a spend cap.
struct RefusalRow: View {
    let event: AgentEvent

    var body: some View {
        let data = event.data
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hand.raised")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.danger)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                AdaptiveLine {
                    Text("Refused").monoText(14.5, weight: .bold).foregroundStyle(Theme.danger)
                    if let amount = data.amountUsdMicros {
                        Text(UsdMicros.format(amount))
                            .monoText(14.5)
                            .strikethrough()
                            .foregroundStyle(Theme.muted)
                            .amountText()
                    }
                    if event.isSimulated { SimulatedPaymentBadge() }
                    Spacer(minLength: 8)
                    Text(event.createdAt.ago).monoMeta()
                }
                Text(event.message)
                    .sansText(15)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(event.agent.agentLabel)
                    if let remaining = data.remainingUsdMicros {
                        Text("· \(UsdMicros.format(remaining)) budget left")
                    }
                }
                .monoMeta()
                Text("Nothing was signed or paid.").monoMeta()
            }
        }
        .padding(.vertical, 16)
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(data.amountUsdMicros.map { UsdMicros.format($0) + ", " } ?? "")\(event.isSimulated ? "simulated, " : "")refused by the spend cap, no money moved. \(event.message)")
    }
}

/// An x402 attempt that errored before any payment was recorded (no money moved).
struct FailedAttemptRow: View {
    let event: AgentEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.ochreInk)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                AdaptiveLine {
                    Text("Failed attempt").monoText(14.5, weight: .bold).foregroundStyle(Theme.ochreInk)
                    if event.isSimulated { SimulatedPaymentBadge() }
                    Spacer(minLength: 8)
                    Text(event.createdAt.ago).monoMeta()
                }
                Text(event.message)
                    .sansText(15)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(event.agent.agentLabel) · no payment made").monoMeta()
            }
        }
        .padding(.vertical, 16)
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Failed payment attempt, no payment made. \(event.message). \(event.agent.agentLabel).")
    }
}

/// The SIMULATED pill on payment rows (see `SimulatedBadge`).
struct SimulatedPaymentBadge: View {
    var body: some View { SimulatedBadge(spoken: "Simulated payment, no money moved") }
}

/// Status as a colored dot and mono label; the dot pulses while pending.
struct PaymentStatusChip: View {
    let status: PaymentStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, isActive: status == .pending)
                .accessibilityHidden(true)
            Text(status.label).monoText(12.5)
        }
        .foregroundStyle(status.tint)
        .lineLimit(1)
    }
}

extension PaymentStatus {
    var label: String {
        switch self {
        case .pending: "Pending"
        case .settled: "Settled"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "clock"
        case .settled: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: Theme.ochreInk
        case .settled: Theme.accentStrong
        case .failed: Theme.danger
        }
    }
}

extension PaymentRail {
    var label: String {
        switch self {
        case .x402: "x402 · USDC"
        case .visa: "Visa"
        }
    }
}

private extension String {
    /// "0xc794…136c"
    var shortHash: String { count > 12 ? "\(prefix(6))…\(suffix(4))" : self }
}

#Preview {
    NavigationStack { SpendingView() }.environment(MooveStore.preview())
}
