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
        let state = store.commerceState(hasRows: !items.isEmpty)
        // A plain List (not a ScrollView) so rows keep swipe-to-delete; the theme comes from clear
        // row backgrounds, gutter insets and rule-colored separators.
        List {
            Section {
                PageHeader(
                    eyebrow: "07 — Shopping",
                    title: "What the new place needs.",
                    lede: "The shopping agent writes the list, you edit it, and the buy agent finds deals and checks out with Visa."
                )
                .padding(.top, 16)
                .padding(.bottom, 8)
                .shoppingChromeRow()
                if state != .content {
                    CommercePlaceholder(
                        state: state,
                        emptyTitle: "Nothing to buy yet",
                        emptyDetail: "Set up your new home in New Home and the shopping agent lists what it still needs. You can add things yourself too."
                    ) {
                        Button("Add item", systemImage: "plus") { showAdd = true }
                            .buttonStyle(.pill(.primary, compact: true))
                    }
                    .padding(.top, 24)
                    .shoppingChromeRow()
                }
            }
            .listSectionSeparator(.hidden)
            if !approvals.isEmpty {
                Section {
                    ListHeader(title: "Needs you", count: "\(approvals.count)")
                        .padding(.top, 32)
                        .shoppingChromeRow()
                    ForEach(approvals) { approval in
                        PurchaseApprovalCard(approval: approval)
                            .shoppingLedgerRow()
                    }
                }
                .listSectionSeparator(.hidden)
            }
            if !items.isEmpty {
                Section {
                    ListHeader(title: "Still to buy", count: "\(items.filter { $0.status != .bought }.count)")
                        .padding(.top, 32)
                        .shoppingChromeRow()
                    ForEach(items) { item in
                        NavigationLink(value: ShoppingRoute(itemId: item.id)) { ShoppingItemRow(item: item) }
                            .shoppingLedgerRow()
                    }
                    .onDelete { offsets in remove(offsets.map { items[$0] }) }
                    Text("Swipe to remove anything you don't need. Agents only buy what's on this list.")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                        .shoppingChromeRow()
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle("Shopping")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ShoppingRoute.self) { ShoppingItemDetailView(itemId: $0.itemId) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Add item", systemImage: "plus") { showAdd = true }
                    .accessibilityLabel("Add an item to the shopping list")
            }
        }
        .sheet(isPresented: $showAdd) { AddShoppingItemSheet() }
        .mooveScreen()
        .animation(.default, value: items)
        .animation(.default, value: approvals)
    }

    private func remove(_ doomed: [ShoppingItem]) {
        Task {
            for item in doomed { await store.removeShoppingItem(item) }
        }
    }
}

private extension View {
    /// A non-interactive row (heading, note): no separator, page background, gutter insets.
    func shoppingChromeRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.bg)
    }

    /// An item row: page background and a full-width rule-colored separator.
    func shoppingLedgerRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowBackground(Theme.bg)
            .listRowSeparatorTint(Theme.line)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

struct ShoppingRoute: Hashable {
    let itemId: UInt64
}

/// A voxel drawing of a shopping item or deal (#15 piece 2), with a check when it's bought.
struct ShoppingThumbnail: View {
    let spec: VoxelItemSpec
    var bought = false
    var size: CGFloat = 56

    var body: some View {
        VoxelThumbnail(spec: spec, size: size)
            .overlay(alignment: .bottomTrailing) {
                if bought {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accentStrong)
                        .background(Circle().fill(Theme.bg))
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct ShoppingItemRow: View {
    @Environment(MooveStore.self) private var store
    let item: ShoppingItem

    var body: some View {
        let deals = store.snapshot.deals(for: item.id)
        let chosen = store.snapshot.chosenDeal(for: item)
        let payment = chosen.flatMap { store.snapshot.visaPayment(for: $0.id) }
        HStack(alignment: .top, spacing: 16) {
            ShoppingThumbnail(spec: ShoppingThumbnails.spec(for: item), bought: item.status == .bought)
            VStack(alignment: .leading, spacing: 5) {
                AdaptiveLine {
                    Text(item.name).blockTitle().lineLimit(2)
                    Spacer(minLength: 8)
                    if let chosen { Text(chosen.formattedPrice).rowValue().amountText() }
                }
                ShoppingStatusChip(status: item.status)
                if !item.reason.isEmpty {
                    Text(item.reason).sansText(14).foregroundStyle(Theme.muted).lineLimit(3)
                }
                HStack(spacing: 8) {
                    if let chosen {
                        Text(chosen.source).monoMeta()
                    } else if !deals.isEmpty {
                        Text("\(deals.count) deals · pick one").monoMeta()
                    }
                    Spacer(minLength: 0)
                    if let payment { VisaRailBadge(badge: VisaPaymentBadge(payment)) }
                }
                if payment?.status == .failed {
                    CommerceProblem(text: "Checkout failed. Nothing was charged. Pick another deal.")
                }
            }
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(chosen: chosen, payment: payment, dealCount: deals.count))
    }

    private func spoken(chosen: Deal?, payment: Payment?, dealCount: Int) -> String {
        var parts = [item.name, item.status.label]
        if let chosen { parts.append("\(chosen.formattedPrice) from \(chosen.source)") } else if dealCount > 0 { parts.append("\(dealCount) deals, pick one") }
        if let payment { parts.append(VisaPaymentBadge(payment).accessibilitySummary(amount: payment.formattedAmount)) }
        if payment?.status == .failed { parts.append("checkout failed, nothing was charged") }
        return parts.joined(separator: ", ")
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
        case .open: Theme.muted
        case .searching: Theme.text
        case .found: Theme.ochreInk
        case .bought: Theme.accentStrong
        }
    }
}

/// Status as a colored dot and mono label; the dot pulses while the agent searches.
struct ShoppingStatusChip: View {
    let status: ShoppingStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, isActive: status == .searching)
                .accessibilityHidden(true)
            Text(status.label).monoText(12.5)
        }
        .foregroundStyle(status.tint)
        .lineLimit(1)
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
    @State private var failed = false

    var body: some View {
        let deal = store.snapshot.deal(for: approval)
        let item = deal.flatMap { d in store.snapshot.shoppingItems.first { $0.id == d.shoppingItemId } }
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label {
                        Text("Buy").monoText(11.5, weight: .bold, maxScale: 1.6).tracking(0.5)
                    } icon: {
                        Image(systemName: "cart").font(.system(size: 10))
                    }
                    .labelStyle(.titleAndIcon)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                    if let item { Text(item.name).monoMeta().lineLimit(1) }
                    Spacer(minLength: 8)
                    if deal?.isSample == true { ReplayBadge(sample: true) } else if deal?.isReplay == true { ReplayBadge() }
                }
                HStack(alignment: .top, spacing: 14) {
                    if let deal { ShoppingThumbnail(spec: ShoppingThumbnails.spec(for: deal, item: item), size: 48) }
                    Text(deal?.title ?? approval.summary).blockTitle().fixedSize(horizontal: false, vertical: true)
                }
                AdaptiveLine {
                    Text(approval.formattedAmount)
                        .monoText(22, weight: .bold, maxScale: 1.6)
                        .foregroundStyle(Theme.text)
                        .amountText()
                    if let deal { Text("from \(deal.source)").monoMeta() }
                    Spacer(minLength: 8)
                    Text(approval.requestedAt, format: .relative(presentation: .named)).monoMeta()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(approval.accessibilitySummary + (deal.map { ". \($0.accessibilitySummary)" } ?? ""))
            if let deal, deal.priceCents != approval.amountCents {
                CommerceProblem(text: "Price changed to \(deal.formattedPrice) since this was requested. Approving won't buy it.",
                                tint: Theme.ochreInk)
            }
            if let level = deal?.fraudLevel, let score = deal?.fraudScore {
                FraudChip(level: level, score: score)
            }
            Text("Over your approval limit. The agent pays with Visa only after you approve.")
                .sansText(14)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if failed {
                CommerceProblem(text: "Couldn't send your decision. Check the connection and try again.")
            }
            HStack(spacing: 10) {
                Button(role: .destructive) { confirmDeny = true } label: {
                    Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.danger))
                .accessibilityLabel("Deny \(approval.formattedAmount)")
                Button { decide(approve: true) } label: {
                    if working {
                        ProgressView().tint(Theme.accentInk).frame(maxWidth: .infinity)
                    } else {
                        Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.pill(.primary))
                .accessibilityLabel("Approve \(approval.formattedAmount)")
            }
            .padding(.top, 4)
            .disabled(working)
        }
        .padding(.vertical, 18)
        .confirmationDialog("Deny this purchase?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny \(approval.formattedAmount)", role: .destructive) { decide(approve: false) }
        } message: {
            Text("The agent won't buy this.")
        }
        .sensoryFeedback(.success, trigger: approvedCount)
    }

    private func decide(approve: Bool) {
        working = true
        failed = false
        Task {
            let ok = await store.decide(approval, approve: approve)
            if ok, approve { approvedCount += 1 }
            failed = !ok
            working = false
        }
    }
}

/// REPLAY: deals from a cached real search ("cached replay"). SAMPLE: hand-made demo deals ("sample data").
struct ReplayBadge: View {
    var sample = false

    var body: some View {
        MonoTag(text: sample ? "Sample" : "Replay", tone: Theme.muted)
            .fixedSize()
            .accessibilityElement(children: .ignore)
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
        case .low: Theme.accentStrong
        case .medium: Theme.ochreInk
        case .high: Theme.danger
        }
    }
}

struct FraudChip: View {
    let level: FraudLevel
    let score: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: level == .low ? "checkmark.shield" : "exclamationmark.shield")
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text("\(level.label) · \(score.formatted(.number.precision(.fractionLength(2))))")
                .monoText(12.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(level.tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.label), score \(score.formatted(.number.precision(.fractionLength(2)))) out of 1")
    }
}

/// SIMULATED for simulated payments (never presented as real), otherwise the Visa sandbox label.
/// Simulated is the shared filled pill so it can't be mistaken for the outlined sandbox tag.
struct VisaRailBadge: View {
    let badge: VisaPaymentBadge

    var body: some View {
        if badge.simulated {
            SimulatedBadge(spoken: "Simulated payment, no money moved")
        } else {
            MonoTag(text: badge.railLabel, tone: Theme.muted)
                .fixedSize()
                .accessibilityElement(children: .ignore)
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
        case .hold: Theme.ochreInk
        case .paid: Theme.accentStrong
        case .failed: Theme.danger
        }
    }
}

/// One Visa `payment` row for a deal: hold (pending), paid (settled) or failed.
struct VisaPaymentRow: View {
    let payment: Payment

    var body: some View {
        let badge = VisaPaymentBadge(payment)
        AdaptiveLine(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .symbolEffect(.pulse, isActive: badge.state == .hold)
                    .accessibilityHidden(true)
                Text(badge.stateLabel).monoText(12.5).lineLimit(1)
            }
            .foregroundStyle(badge.state.tint)
            Text(payment.formattedAmount)
                .rowValue()
                .strikethrough(badge.state == .failed)
                .amountText()
            Spacer(minLength: 8)
            VisaRailBadge(badge: badge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilitySummary(amount: payment.formattedAmount))
    }
}

#Preview {
    NavigationStack { ShoppingView() }.environment(MooveStore.preview())
}
