import SwiftUI
import MooveKit

/// Live spending log (#7), printed as paper receipts, under the approvals on Sell & Buy > Agents:
/// every payment the agents make (x402 USDC on Base Sepolia, or Visa), one receipt per agent run,
/// newest receipt first, with each agent's budget and any spend it was refused. Driven entirely by
/// `payment` and `agent_event` rows in the snapshot, so new lines print in as the worker writes
/// them. Grouping: MooveKit `SpendingReceipts`.
struct SpendingSection: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let split = store.snapshot.spendingSplit()
        let log = split.yours, room = split.room
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Receipts", count: nil)
            if !log.isEmpty {
                let receipts = store.snapshot.spendingReceipts(log)
                SpendingTape(log: log, extraBudgets: receipts.unattachedBudgets)
                    .padding(.top, 8)
                receiptStack(receipts)
            } else {
                Text("No payments yet. Agents pay to price an item (x402) or buy from your Shopping list (Visa).")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ruled()
            }
            if !room.isEmpty {
                // #254: other members' x402 comps for items in rooms you joined. Kept out of your totals.
                ListHeader(title: SpendingSplit.roomTag, count: "\(room.entries.count)").padding(.top, 44)
                Label(SpendingSplit.roomCaption, systemImage: "person.2")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                let receipts = store.snapshot.spendingReceipts(room)
                SpendingTape(log: room, extraBudgets: receipts.unattachedBudgets, sharedRoom: true)
                receiptStack(receipts, sharedRoom: true)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        // New lines "print" in; Reduce Motion just shows them.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: log.entries)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: room.entries)
    }

    @ViewBuilder
    private func receiptStack(_ receipts: SpendingReceipts, sharedRoom: Bool = false) -> some View {
        ForEach(receipts.receipts) { receipt in
            ReceiptCard(receipt: receipt, sharedRoom: sharedRoom)
                .padding(.top, 28)
                .transition(AnyTransition.printing(reduceMotion: reduceMotion))
        }
    }
}

/// The totals as a short tape above the receipts: Spent, Simulated, Refused (same figures as
/// before the receipts, checked by `DemoNumbersTests`), plus any budget without a receipt.
struct SpendingTape: View {
    let log: SpendingLog
    var extraBudgets: [AgentBudget] = []
    var sharedRoom = false

    var body: some View {
        let refused = log.budgets.map(\.refusals).reduce(0, +)
        VStack(alignment: .leading, spacing: 8) {
            Text(sharedRoom ? "SHARED ROOM · TOTALS" : "TOTALS · YOUR AGENTS")
                .courier(12.5, bold: true)
                .foregroundStyle(ReceiptPalette.muted)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(sharedRoom ? "spending.totals.room" : "spending.totals")
            LeaderRow(label: "SPENT", value: UsdMicros.format(log.realSpentUsdMicros), size: 16, bold: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Spent for real, \(UsdMicros.format(log.realSpentUsdMicros))")
            LeaderRow(label: "SIMULATED", value: UsdMicros.format(log.simulatedSpentUsdMicros), size: 16, bold: true,
                      tint: Theme.ochreInk)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Simulated, \(UsdMicros.format(log.simulatedSpentUsdMicros)), no money moved")
            LeaderRow(label: "REFUSED", value: "\(refused)", size: 16, bold: true, tint: Theme.danger)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(refused) \(refused == 1 ? "payment" : "payments") refused by spend caps")
            ForEach(extraBudgets) { b in
                LeaderRow(label: "\(b.agent.agentDisplayName.uppercased()) LEFT", value: UsdMicros.format(b.remainingUsdMicros))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(b.agent.agentDisplayName), \(UsdMicros.format(b.remainingUsdMicros)) left of \(UsdMicros.format(b.capUsdMicros))")
            }
        }
        .onReceiptPaper()
    }
}

/// One agent run on a strip of receipt paper.
struct ReceiptCard: View {
    let receipt: SpendingReceipt
    var sharedRoom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DashedRule()
            VStack(alignment: .leading, spacing: 16) {
                ForEach(receipt.lines) { line in
                    ReceiptLineView(line: line, sharedRoom: sharedRoom)
                        .transition(AnyTransition.printing(reduceMotion: reduceMotion))
                }
            }
            DashedRule()
            footer
            ReceiptBarcode(widths: receipt.barcode).padding(.top, 10)
            Text("THANK YOU FOR MOVING")
                .courier(13, bold: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .onReceiptPaper()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receipt.\(receipt.id)")
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text("MOOVE · AGENT SPENDING").courier(14, bold: true)
            Text("\(ReceiptFormat.day(receipt.startedAt))  \(ReceiptFormat.time(receipt.startedAt))")
                .courier(12.5).foregroundStyle(ReceiptPalette.muted)
            Text(receipt.number).courier(12.5).foregroundStyle(ReceiptPalette.muted)
            if sharedRoom {
                RailStamp(text: SpendingSplit.roomTag.uppercased()).padding(.top, 4)
            }
            DashedRule()
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.title.uppercased()).courier(15.5, bold: true)
                Text(receipt.subtitle).courier(13).foregroundStyle(ReceiptPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerSpoken)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerSpoken: String {
        let when = receipt.startedAt.formatted(date: .abbreviated, time: .shortened)
        return (sharedRoom ? "\(SpendingSplit.roomTag). " : "")
            + "Receipt, \(receipt.title), \(receipt.subtitle), \(when)"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            LeaderRow(label: "SUBTOTAL", value: UsdMicros.format(receipt.subtotalUsdMicros), size: 15, bold: true)
            if receipt.simulatedUsdMicros > 0 {
                LeaderRow(label: "  OF IT SIMULATED", value: UsdMicros.format(receipt.simulatedUsdMicros), size: 13.5,
                          tint: Theme.ochreInk)
            }
            if receipt.refusals > 0 {
                LeaderRow(label: "REFUSED", value: "\(receipt.refusals)", size: 13.5, tint: Theme.danger)
            }
            if let used = receipt.budgetUsedLine, let left = receipt.budgetRemaining {
                Text(used.uppercased())
                    .courier(13)
                    .foregroundStyle(ReceiptPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                LeaderRow(label: "REMAINING", value: left, size: 13.5)
            }
            if let stamp = receipt.simulatedStamp {
                NoMoneyMovedStamp(text: stamp).padding(.top, 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(receipt.footerSpoken + stampSpoken)
    }

    private var stampSpoken: String {
        guard receipt.hasSimulated else { return "" }
        return receipt.allSimulated ? " Stamped: simulated, no money moved." : " Stamped: lines marked simulated moved no money."
    }
}

/// One printed line: what the agent paid for, then time, rail, SIMULATED and the amount on dotted
/// leaders, then any status note. One VoiceOver element; the Basescan link is its own button.
struct ReceiptLineView: View {
    let line: ReceiptLine
    var sharedRoom = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.description)
                    .courier(15)
                    .strikethrough(line.struck)
                    .foregroundStyle(line.struck ? ReceiptPalette.muted : ReceiptPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                meta
                if let note = line.note {
                    Text(note)
                        .courier(12.5, bold: true)
                        .foregroundStyle(noteTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = line.detail {
                    Text(detail)
                        .courier(12.5)
                        .foregroundStyle(line.struck ? Theme.danger : ReceiptPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((sharedRoom ? "\(SpendingSplit.roomTag). " : "") + line.spoken)
            .accessibilityIdentifier(line.paymentId.map { "payment.\($0)" } ?? "receipt.line.\(line.id)")
            // Only real x402 payments with a tx hash link out (`explorerURL` is nil when simulated).
            if let url = line.explorerURL, let hash = line.txHash, let id = line.paymentId {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("TX \(ReceiptFormat.shortHash(hash))").underline()
                        Image(systemName: "arrow.up.right.square").font(.system(size: 12, weight: .semibold))
                    }
                    .courier(13, bold: true)
                    .foregroundStyle(Theme.accentStrong)
                    .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("View the transaction on Basescan")
                .accessibilityHint("Opens sepolia.basescan.org")
                .accessibilityIdentifier("payment.basescan.\(id)")
            }
        }
    }

    /// Time, rail, SIMULATED ........ amount. Leaders drop out when it doesn't fit on one line.
    @ViewBuilder
    private var meta: some View {
        let tags = HStack(spacing: 6) {
            Text(ReceiptFormat.time(line.createdAt)).courier(13).foregroundStyle(ReceiptPalette.muted).fixedSize()
            RailStamp(text: line.railTag)
            if line.simulated { SimStamp() }
        }
        let amount = Text(line.amount ?? "—")
            .courier(15, bold: true)
            .strikethrough(line.struck && line.amount != nil)
            .foregroundStyle(line.struck ? ReceiptPalette.muted : ReceiptPalette.ink)
            .lineLimit(1)
            .fixedSize()
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    tags
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ReceiptFormat.time(line.createdAt)).courier(13).foregroundStyle(ReceiptPalette.muted)
                        HStack(spacing: 6) {
                            RailStamp(text: line.railTag)
                            if line.simulated { SimStamp() }
                        }
                    }
                }
                amount
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 6) {
                    tags
                    DottedLeader()
                    amount
                }
                VStack(alignment: .leading, spacing: 4) {
                    tags
                    amount
                }
            }
        }
    }

    private var noteTint: Color {
        switch line.kind {
        case .refused, .payment(.failed): Theme.danger
        case .failedAttempt, .payment(.pending): Theme.ochreInk
        case .payment(.settled): Theme.accentStrong
        }
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

extension AnyTransition {
    /// A new receipt line feeds in from the top, like paper out of a till; none with Reduce Motion.
    static func printing(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? AnyTransition.identity : AnyTransition.move(edge: .top).combined(with: .opacity)
    }
}

#Preview {
    ScrollView { SpendingSection().padding(.horizontal, Theme.gutter) }.environment(MooveStore.preview())
}
