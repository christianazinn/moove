import SwiftUI
import MooveKit

/// One shopping item: why it's on the list, where checkout stands, and every deal the buy agent
/// found (chosen one marked), each with its Visa payment rows.
struct ShoppingItemDetailView: View {
    @Environment(MooveStore.self) private var store
    let itemId: UInt64

    var body: some View {
        if let item = store.snapshot.shoppingItems.first(where: { $0.id == itemId }) {
            content(item)
        } else {
            ContentUnavailableView("Removed from the list", systemImage: "cart")
                .mooveScreen()
        }
    }

    private func content(_ item: ShoppingItem) -> some View {
        let deals = store.snapshot.deals(for: item.id)
        let checkout = store.snapshot.checkout(for: item)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("07 — Shopping").eyebrow().padding(.bottom, 12)
                Text(item.name)
                    .pageTitle()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ShoppingStatusChip(status: item.status).padding(.top, 10)
                if !item.reason.isEmpty {
                    Text(item.reason)
                        .lede()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }

                ListHeader(title: "Checkout").padding(.top, 36)
                ShoppingCheckoutView(checkout: checkout)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ruled()

                if !deals.isEmpty {
                    ListHeader(title: "Deals", count: "\(deals.count)").padding(.top, 40)
                    ForEach(deals) { deal in
                        DealRow(item: item, deal: deal, isChosen: deal.id == item.chosenDealId)
                    }
                    Group {
                        if deals.contains(where: \.isSample) {
                            Text("SAMPLE deals are hand-made demo data, not live listings.")
                        } else if deals.contains(where: \.isReplay) {
                            Text("REPLAY deals come from a cached search, not live listings.")
                        }
                    }
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .animation(.default, value: deals)
        .animation(.default, value: item)
    }
}

/// The next step for an item, in words, plus the approval card when it's waiting on the user.
struct ShoppingCheckoutView: View {
    let checkout: ShoppingCheckout

    var body: some View {
        switch checkout {
        case .findingDeals:
            step("The buy agent is looking for deals.", systemImage: "magnifyingglass")
        case .chooseDeal:
            step("Pick a deal below and the agent takes it from there.", systemImage: "hand.tap")
        case .messageSeller(let deal):
            step("\(deal.source) sellers can't be paid through an API. The agent drafted a message to the seller.",
                 systemImage: "envelope")
        case .fraudBlocked(let deal):
            VStack(alignment: .leading, spacing: 6) {
                step("Not buying: the fraud screen flagged this deal.", systemImage: "exclamationmark.shield.fill",
                     tint: Theme.danger)
                ForEach(deal.fraudReasons, id: \.self) { reason in
                    Text("· \(reason)").monoMeta().fixedSize(horizontal: false, vertical: true)
                }
            }
        case .needsApproval(let approval):
            PurchaseApprovalCard(approval: approval)
        case .notApproved(let approval):
            step(approval.status == .expired ? "The approval expired. Nothing was bought."
                 : approval.status == .approved ? "The price changed after you approved. Nothing was bought."
                 : "You denied this purchase. Nothing was bought.",
                 systemImage: "xmark.circle")
        case .checkingOut:
            step("Cleared to buy. Waiting for the agent to place the Visa hold.", systemImage: "creditcard")
        case .payment(let payment):
            VisaPaymentRow(payment: payment)
        }
    }

    private func step(_ text: String, systemImage: String, tint: Color = Theme.muted) -> some View {
        Label {
            Text(text).sansText(15).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).font(.system(size: 14, weight: .light))
        }
        .foregroundStyle(tint)
    }
}

struct DealRow: View {
    @Environment(MooveStore.self) private var store
    let item: ShoppingItem
    let deal: Deal
    let isChosen: Bool
    @State private var working = false

    var body: some View {
        let payments = store.snapshot.visaPayments(for: deal.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accentStrong)
                        .accessibilityLabel("Chosen deal")
                }
                Text(deal.title).blockTitle().lineLimit(2)
                Spacer(minLength: 8)
                if deal.isSample { ReplayBadge(sample: true) } else if deal.isReplay { ReplayBadge() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(deal.priceCents.usd).monoText(16, weight: .bold).foregroundStyle(Theme.text)
                Text(deal.source).monoMeta()
                Spacer(minLength: 8)
                Label(deal.supportsCardCheckout ? "Visa checkout" : "Message seller",
                      systemImage: deal.supportsCardCheckout ? "creditcard" : "envelope")
                    .monoMeta()
                    .lineLimit(1)
            }
            if !deal.sellerDetails.isEmpty {
                Text(deal.sellerDetails).sansText(14).foregroundStyle(Theme.muted).lineLimit(2)
            }
            if let level = deal.fraudLevel, let score = deal.fraudScore {
                FraudChip(level: level, score: score)
                if level != .low {
                    ForEach(deal.fraudReasons, id: \.self) { reason in
                        Text("· \(reason)").monoMeta().fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(payments) { VisaPaymentRow(payment: $0) }
            HStack(spacing: 8) {
                if let url = deal.link {
                    Link(destination: url) {
                        Label("View", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.pill(.text, compact: true))
                }
                Spacer()
                if isChosen {
                    MonoTag(text: "Chosen", tone: Theme.accentStrong)
                } else if item.status != .bought {
                    // Disabled while a hold or a purchase approval is pending: that one finishes (or is denied) first.
                    Button("Choose") { choose() }
                        .buttonStyle(.pill(.outline, compact: true))
                        .disabled(working || store.snapshot.isCheckoutLocked(item))
                }
            }
        }
        .padding(.vertical, 16)
        .ruled()
    }

    private func choose() {
        working = true
        Task {
            await store.choose(deal, for: item)
            working = false
        }
    }
}

/// The user's edit step: add something the shopping agent missed.
struct AddShoppingItemSheet: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var reason = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field("Item") {
                        TextField("What do you need? (e.g. Desk lamp)", text: $name)
                    }
                    field("Category") {
                        TextField("Category (optional, e.g. lamp)", text: $category)
                            .textInputAutocapitalization(.never)
                    }
                    field("Why") {
                        TextField("Reason (optional)", text: $reason, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .mooveScreen()
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(trimmed(name).isEmpty || saving)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.bg)
    }

    /// Mono label over a sans text field, on a rule.
    private func field<Field: View>(_ label: String, @ViewBuilder _ input: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).eyebrow()
            input()
                .sansText(16)
                .foregroundStyle(Theme.text)
                .frame(minHeight: 44)
                .ruled()
        }
        .padding(.top, 20)
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        saving = true
        let n = trimmed(name)
        let c = trimmed(category).lowercased()
        let r = trimmed(reason)
        Task {
            let ok = await store.addShoppingItem(name: n, category: c, reason: r.isEmpty ? "Added by you" : r)
            saving = false
            if ok { dismiss() }
        }
    }
}

#Preview {
    NavigationStack { ShoppingItemDetailView(itemId: 51) }.environment(MooveStore.preview())
}
