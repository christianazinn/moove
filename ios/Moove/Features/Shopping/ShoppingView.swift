import SwiftUI
import MooveKit

/// What the new home still needs (#15). The shopping agent writes the list, the user edits it
/// (add, swipe to remove), the buy agent finds deals, and the chosen deal checks out through Visa,
/// after the user approves anything over their threshold.
struct ShoppingView: View {
    @Environment(MooveStore.self) private var store
    @State private var showAdd = false

    var body: some View {
        let items = store.shoppingItems
        let approvals = store.snapshot.pendingPurchaseApprovals
        List {
            if !approvals.isEmpty {
                Section {
                    ForEach(approvals) { approval in
                        PurchaseApprovalCard(approval: approval)
                    }
                } header: {
                    Text("Needs you · \(approvals.count)")
                }
            }
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        NavigationLink(value: ShoppingRoute(itemId: item.id)) { ShoppingItemRow(item: item) }
                    }
                    .onDelete { offsets in remove(offsets.map { items[$0] }) }
                } header: {
                    Text("Still to buy · \(items.filter { $0.status != .bought }.count)")
                } footer: {
                    Text("Swipe to remove anything you don't need. Agents only buy what's on this list.")
                }
            }
        }
        .navigationTitle("Shopping")
        .navigationDestination(for: ShoppingRoute.self) { ShoppingItemDetailView(itemId: $0.itemId) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Add item", systemImage: "plus") { showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) { AddShoppingItemSheet() }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to buy yet", systemImage: "cart")
                } description: {
                    Text("Once your new home is set up, the shopping agent lists what it still needs. You can add things too.")
                } actions: {
                    Button("Add item") { showAdd = true }
                }
            }
        }
        .animation(.default, value: items)
        .animation(.default, value: approvals)
    }

    private func remove(_ doomed: [ShoppingItem]) {
        Task {
            for item in doomed { await store.removeShoppingItem(item) }
        }
    }
}

struct ShoppingRoute: Hashable {
    let itemId: UInt64
}

struct ShoppingItemRow: View {
    @Environment(MooveStore.self) private var store
    let item: ShoppingItem

    var body: some View {
        let deals = store.snapshot.deals(for: item.id)
        let chosen = store.snapshot.chosenDeal(for: item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(.headline)
                Spacer()
                ShoppingStatusChip(status: item.status)
            }
            if !item.reason.isEmpty {
                Text(item.reason).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                if let chosen {
                    Text(chosen.priceCents.usd).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text("· \(chosen.source)").font(.caption).foregroundStyle(.secondary)
                } else if !deals.isEmpty {
                    Text("\(deals.count) deals · pick one").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let chosen, let payment = store.snapshot.visaPayment(for: chosen.id) {
                    VisaRailBadge(badge: VisaPaymentBadge(payment))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension ShoppingStatus {
    var label: String {
        switch self {
        case .open: "Open"
        case .searching: "Searching"
        case .found: "Deals found"
        case .bought: "Bought"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "circle"
        case .searching: "magnifyingglass"
        case .found: "tag"
        case .bought: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .open: .secondary
        case .searching: .blue
        case .found: .orange
        case .bought: .green
        }
    }
}

struct ShoppingStatusChip: View {
    let status: ShoppingStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.12), in: .capsule)
            .symbolEffect(.pulse, isActive: status == .searching)
    }
}

/// A pending `purchase` approval for a chosen deal: Approve / Deny through `decide_approval`.
/// Shares `MooveStore.decide` with the approvals inbox (#12).
struct PurchaseApprovalCard: View {
    @Environment(MooveStore.self) private var store
    let approval: Approval
    @State private var confirmDeny = false
    @State private var working = false
    @State private var approvedCount = 0

    var body: some View {
        let deal = store.snapshot.deals.first { $0.id == approval.refId }
        let item = deal.flatMap { d in store.snapshot.shoppingItems.first { $0.id == d.shoppingItemId } }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Buy", systemImage: "cart")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if let item { Text(item.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                Spacer()
                if deal?.isSample == true { ReplayBadge(sample: true) } else if deal?.isReplay == true { ReplayBadge() }
            }
            Text(deal?.title ?? approval.summary).font(.subheadline.weight(.semibold)).lineLimit(3)
            HStack {
                Text(approval.amountCents.usd).font(.title3.weight(.bold).monospacedDigit())
                if let deal { Text("from \(deal.source)").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                Text(approval.requestedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let deal, deal.priceCents != approval.amountCents {
                Label("Price changed to \(deal.priceCents.usd) since this was requested. Approving won't buy it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let level = deal?.fraudLevel, let score = deal?.fraudScore {
                FraudChip(level: level, score: score)
            }
            Text("Over your approval limit. The agent pays with Visa only after you approve.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(role: .destructive) { confirmDeny = true } label: {
                    Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { decide(approve: true) } label: {
                    Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .disabled(working)
        }
        .padding(.vertical, 4)
        .confirmationDialog("Deny this purchase?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny \(approval.amountCents.usd)", role: .destructive) { decide(approve: false) }
        } message: {
            Text("The agent won't buy this.")
        }
        .sensoryFeedback(.success, trigger: approvedCount)
    }

    private func decide(approve: Bool) {
        working = true
        Task {
            if await store.decide(approval, approve: approve), approve { approvedCount += 1 }
            working = false
        }
    }
}

/// REPLAY: deals from a cached real search ("cached replay"). SAMPLE: hand-made demo deals ("sample data").
struct ReplayBadge: View {
    var sample = false

    var body: some View {
        Text(sample ? "SAMPLE" : "REPLAY")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.purple)
            .overlay(Capsule().strokeBorder(.purple.opacity(0.6)))
            .accessibilityLabel(sample ? "Sample data, not a live listing" : "Cached replay, not a live listing")
    }
}

extension FraudLevel {
    var label: String {
        switch self {
        case .low: "Low fraud risk"
        case .medium: "Some fraud risk"
        case .high: "Likely fraud"
        }
    }

    var tint: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

struct FraudChip: View {
    let level: FraudLevel
    let score: Double

    var body: some View {
        Label("\(level.label) · \(score.formatted(.number.precision(.fractionLength(2))))",
              systemImage: level == .low ? "checkmark.shield" : "exclamationmark.shield")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(level.tint)
            .background(level.tint.opacity(0.12), in: .capsule)
    }
}

/// SIMULATED for simulated payments (never presented as real), otherwise the Visa sandbox label.
struct VisaRailBadge: View {
    let badge: VisaPaymentBadge

    var body: some View {
        if badge.simulated {
            Text(badge.railLabel)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(.orange, in: .capsule)
                .accessibilityLabel("Simulated payment, no money moved")
        } else {
            Text(badge.railLabel)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(.blue, in: .capsule)
                .accessibilityLabel("Visa sandbox payment, test card, no real money")
        }
    }
}

extension VisaPaymentBadge.State {
    var systemImage: String {
        switch self {
        case .hold: "clock"
        case .paid: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .hold: .orange
        case .paid: .green
        case .failed: .red
        }
    }
}

/// One Visa `payment` row for a deal: hold (pending), paid (settled) or failed.
struct VisaPaymentRow: View {
    let payment: Payment

    var body: some View {
        let badge = VisaPaymentBadge(payment)
        HStack(spacing: 8) {
            Label(badge.stateLabel, systemImage: badge.state.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(badge.state.tint)
                .background(badge.state.tint.opacity(0.12), in: .capsule)
                .symbolEffect(.pulse, isActive: badge.state == .hold)
            Text(payment.formattedAmount)
                .font(.subheadline.monospacedDigit())
                .strikethrough(badge.state == .failed)
            Spacer()
            VisaRailBadge(badge: badge)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { ShoppingView() }.environment(MooveStore.preview())
}
