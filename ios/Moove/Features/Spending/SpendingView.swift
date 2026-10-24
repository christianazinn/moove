import SwiftUI
import MooveKit

/// Live spending log (#7): every payment the agents make (x402 USDC on Base Sepolia, or Visa),
/// newest first, with per-agent budgets and spend-cap refusals. Driven entirely by
/// `payment` and `agent_event` rows in the snapshot, so it updates as the worker writes them.
struct SpendingView: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        let log = store.snapshot.spendingLog()
        List {
            if !log.isEmpty {
                Section { SpendingTotals(log: log) }
                Section("Budgets") {
                    ForEach(log.budgets) { AgentBudgetRow(budget: $0) }
                }
                Section("Activity · \(log.entries.count)") {
                    ForEach(log.entries) { entry in
                        switch entry {
                        case .payment(let payment): PaymentRow(payment: payment)
                        case .refusal(let event): RefusalRow(event: event)
                        }
                    }
                }
            }
        }
        .navigationTitle("Spending")
        .overlay {
            if log.isEmpty {
                ContentUnavailableView("No payments yet", systemImage: "creditcard",
                                       description: Text("When agents pay for data or services, each payment shows up here live."))
            }
        }
        .animation(.default, value: log.entries)
    }
}

private extension String {
    /// "pricing" -> "Pricing agent".
    var agentLabel: String { prefix(1).uppercased() + String(dropFirst()) + " agent" }
}

private extension Date {
    var ago: String { formatted(.relative(presentation: .named)) }
}

struct SpendingTotals: View {
    let log: SpendingLog

    var body: some View {
        HStack {
            stat(UsdMicros.format(log.realSpentUsdMicros), "spent", tint: .primary)
            Divider()
            stat(UsdMicros.format(log.simulatedSpentUsdMicros), "simulated", tint: .orange)
            Divider()
            stat("\(log.budgets.map(\.refusals).reduce(0, +))", "refused", tint: .red)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AgentBudgetRow: View {
    let budget: AgentBudget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(budget.agent.agentLabel).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(UsdMicros.format(budget.remainingUsdMicros)) left")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(budget.isExhausted ? Color.red : Color.primary)
            }
            ProgressView(value: budget.fractionUsed)
                .tint(budget.isExhausted ? .red : budget.fractionUsed > 0.8 ? .orange : .green)
            HStack(spacing: 6) {
                Text("\(UsdMicros.format(budget.spentUsdMicros)) of \(UsdMicros.format(budget.capUsdMicros)) cap")
                if budget.simulatedUsdMicros > 0 {
                    Text("· \(UsdMicros.format(budget.simulatedUsdMicros)) simulated").foregroundStyle(.orange)
                }
                if budget.refusals > 0 {
                    Text("· \(budget.refusals) refused").foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct PaymentRow: View {
    let payment: Payment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(payment.formattedAmount)
                    .font(.headline.monospacedDigit())
                    .strikethrough(payment.status == .failed)
                    .foregroundStyle(payment.status == .failed ? .secondary : .primary)
                if payment.simulated { SimulatedPaymentBadge() }
                Spacer()
                Text(payment.createdAt.ago).font(.caption).foregroundStyle(.secondary)
            }
            Text(payment.purpose).font(.subheadline).lineLimit(2)
            HStack(spacing: 6) {
                Text(payment.agent.agentLabel)
                Text("·")
                Text(payment.rail.label)
                Spacer()
                PaymentStatusChip(status: payment.status)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let url = payment.explorerURL, let hash = payment.txHash {
                Link(destination: url) {
                    Label("Basescan \(hash.shortHash)", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium).monospaced())
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A payment the worker refused to make because it broke a spend cap.
struct RefusalRow: View {
    let event: AgentEvent

    var body: some View {
        let data = event.data
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Refused").font(.headline).foregroundStyle(.red)
                    if let amount = data.amountUsdMicros {
                        Text(UsdMicros.format(amount)).font(.headline.monospacedDigit()).strikethrough()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(event.createdAt.ago).font(.caption).foregroundStyle(.secondary)
                }
                Text(event.message).font(.subheadline).lineLimit(3)
                HStack(spacing: 6) {
                    Text(event.agent.agentLabel)
                    if let remaining = data.remainingUsdMicros {
                        Text("· \(UsdMicros.format(remaining)) budget left")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.red.opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Payment refused by spend cap. \(event.message)")
    }
}

/// CLAUDE.md hard rule (Coinbase track): simulated payments are never presented as real.
struct SimulatedPaymentBadge: View {
    var body: some View {
        Text("SIMULATED")
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(.orange, in: .capsule)
            .accessibilityLabel("Simulated payment, no money moved")
    }
}

struct PaymentStatusChip: View {
    let status: PaymentStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.12), in: .capsule)
            .symbolEffect(.pulse, isActive: status == .pending)
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
        case .pending: .orange
        case .settled: .green
        case .failed: .red
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
