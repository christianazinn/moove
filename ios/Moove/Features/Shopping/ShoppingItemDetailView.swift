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
        }
    }

    private func content(_ item: ShoppingItem) -> some View {
        let deals = store.snapshot.deals(for: item.id)
        let checkout = store.snapshot.checkout(for: item)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.name).font(.title3.weight(.semibold))
                        Spacer()
                        ShoppingStatusChip(status: item.status)
                    }
                    if !item.reason.isEmpty {
                        Text(item.reason).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Section("Checkout") {
                ShoppingCheckoutView(checkout: checkout)
            }
            if !deals.isEmpty {
                Section {
                    ForEach(deals) { deal in
                        DealRow(item: item, deal: deal, isChosen: deal.id == item.chosenDealId)
                    }
                } header: {
                    Text("Deals · \(deals.count)")
                } footer: {
                    if deals.contains(where: \.isReplay) {
                        Text("REPLAY deals come from a cached search, not live listings.")
                    }
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
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
            Label("The buy agent is looking for deals.", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .chooseDeal:
            Label("Pick a deal below and the agent takes it from there.", systemImage: "hand.tap")
                .foregroundStyle(.secondary)
        case .messageSeller(let deal):
            Label("\(deal.source) sellers can't be paid through an API. The agent drafted a message to the seller.",
                  systemImage: "envelope")
                .foregroundStyle(.secondary)
        case .fraudBlocked(let deal):
            VStack(alignment: .leading, spacing: 4) {
                Label("Not buying: the fraud screen flagged this deal.", systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                ForEach(deal.fraudReasons, id: \.self) { reason in
                    Text("• \(reason)").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .needsApproval(let approval):
            PurchaseApprovalCard(approval: approval)
        case .notApproved(let approval):
            Label(approval.status == .expired ? "The approval expired. Nothing was bought."
                                              : "You denied this purchase. Nothing was bought.",
                  systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .checkingOut:
            Label("Cleared to buy. Waiting for the agent to place the Visa hold.", systemImage: "creditcard")
                .foregroundStyle(.secondary)
        case .payment(let payment):
            VisaPaymentRow(payment: payment)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if isChosen {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel("Chosen deal")
                }
                Text(deal.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                if deal.isReplay { ReplayBadge() }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(deal.priceCents.usd).font(.headline.monospacedDigit())
                Text(deal.source).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Label(deal.supportsCardCheckout ? "Visa checkout" : "Message seller",
                      systemImage: deal.supportsCardCheckout ? "creditcard" : "envelope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !deal.sellerDetails.isEmpty {
                Text(deal.sellerDetails).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let level = deal.fraudLevel, let score = deal.fraudScore {
                FraudChip(level: level, score: score)
                if level != .low {
                    ForEach(deal.fraudReasons, id: \.self) { reason in
                        Text("• \(reason)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(payments) { VisaPaymentRow(payment: $0) }
            HStack {
                if let url = deal.link {
                    Link(destination: url) {
                        Label("View", systemImage: "arrow.up.right.square").font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                if isChosen {
                    Text("Chosen").font(.caption.weight(.semibold)).foregroundStyle(.green)
                } else if item.status != .bought {
                    Button("Choose") { choose() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .disabled(working)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isChosen ? Color.green.opacity(0.06) : nil)
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
            Form {
                Section {
                    TextField("What do you need? (e.g. Desk lamp)", text: $name)
                    TextField("Category (optional, e.g. lamp)", text: $category)
                        .textInputAutocapitalization(.never)
                }
                Section("Why") {
                    TextField("Reason (optional)", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
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
