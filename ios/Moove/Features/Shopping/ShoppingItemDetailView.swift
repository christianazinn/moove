import SwiftUI
import MooveKit

/// One shopping item: why it's on the list, where checkout stands, and every deal the buy agent
/// found (chosen one marked), each with its Visa payment rows.
struct ShoppingItemDetailView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let itemId: UInt64

    var body: some View {
        if let item = store.snapshot.shoppingItems.first(where: { $0.id == itemId }) {
            content(item)
        } else {
            ContentUnavailableView("Removed from the list", systemImage: "cart",
                                   description: Text("This item is no longer on your shopping list."))
                .mooveScreen()
        }
    }

    private func content(_ item: ShoppingItem) -> some View {
        let deals = store.snapshot.deals(for: item.id)
        let checkout = store.snapshot.checkout(for: item)
        let snapshot = store.snapshot
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("07 — Shopping").eyebrow().padding(.bottom, 12)
                StorefrontImage(spec: ShoppingThumbnails.spec(for: item), tint: StorefrontTint.color(for: item.id),
                                height: dynamicTypeSize.isAccessibilitySize ? 200 : 240, bought: item.status == .bought)
                    .overlay(alignment: .bottomLeading) {
                        if let price = (snapshot.chosenDeal(for: item) ?? snapshot.topPick(for: item))?.formattedPrice {
                            PriceChip(text: price, large: true).padding(12)
                        }
                    }
                    .padding(.bottom, 18)
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
                ShoppingCheckoutView(checkout: checkout, searchProblem: snapshot.dealSearchProblem(for: item),
                                     checkoutProblem: item.chosenDealId.flatMap(snapshot.checkoutProblem(dealId:)))
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ruled()

                if !deals.isEmpty {
                    ListHeader(title: "Deals", count: "\(deals.count)").padding(.top, 40)
                    let ribbons = snapshot.dealRibbons(for: item)
                    VStack(spacing: 12) {
                        ForEach(deals) { deal in
                            DealRow(item: item, deal: deal, isChosen: deal.id == item.chosenDealId, ribbon: ribbons[deal.id])
                        }
                    }
                    .padding(.top, 14)
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
    /// The buy agent's note when the deal search failed or found nothing.
    var searchProblem: String? = nil
    /// The buy agent's note on the chosen deal (refused, declined, gave up).
    var checkoutProblem: String? = nil

    var body: some View {
        switch checkout {
        case .findingDeals:
            if let searchProblem {
                VStack(alignment: .leading, spacing: 6) {
                    step("No deals yet.", systemImage: "magnifyingglass", tint: Theme.ochreInk)
                    Text(searchProblem).monoMeta().fixedSize(horizontal: false, vertical: true)
                    Text("The buy agent searches again when the list changes. You can also remove this item and add it with a different name.")
                        .monoMeta().fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.muted)
                    step("The buy agent is looking for deals.", systemImage: "magnifyingglass")
                }
            }
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.muted)
                    step("Cleared to buy. Waiting for the agent to place the Visa hold.", systemImage: "creditcard")
                }
                // e.g. a card-cap refusal or a temporary checkout error the agent will retry.
                if let checkoutProblem { CommerceProblem(text: checkoutProblem, tint: Theme.ochreInk) }
            }
        case .payment(let payment):
            VStack(alignment: .leading, spacing: 8) {
                VisaPaymentRow(payment: payment)
                switch payment.status {
                case .failed:
                    CommerceProblem(text: checkoutProblem ?? "The Visa checkout failed.")
                    Text("Nothing was charged. Pick another deal below to try again.")
                        .monoMeta().fixedSize(horizontal: false, vertical: true)
                case .pending:
                    Text("A hold is placed on the card. The agent captures it after a last approval check.")
                        .monoMeta().fixedSize(horizontal: false, vertical: true)
                case .settled:
                    Text(payment.simulated ? "Paid through the simulated Visa rail. No real card was charged."
                         : "Paid in the Visa sandbox with a test card.")
                        .monoMeta().fixedSize(horizontal: false, vertical: true)
                }
            }
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
    var ribbon: StorefrontRibbon? = nil
    @State private var working = false
    @State private var failed = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let payments = store.snapshot.visaPayments(for: deal.id)
        let large = dynamicTypeSize.isAccessibilitySize
        let locked = store.snapshot.isCheckoutLocked(item)
        VStack(alignment: .leading, spacing: 8) {
            summary(large: large)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenSummary)
                .accessibilityIdentifier("deal.\(deal.id)")
            ForEach(payments) { VisaPaymentRow(payment: $0) }
            if failed {
                CommerceProblem(text: "Couldn't send your choice. Check the connection and try again.")
            }
            actions(large: large, locked: locked)
        }
        .padding(12)
        .background(cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
            .strokeBorder(cardBorder, lineWidth: isChosen || !deal.isChoosable ? 1.5 : 1))
    }

    private var cardFill: Color { deal.isChoosable ? Theme.surface.opacity(0.55) : Theme.dangerSoft.opacity(0.5) }

    private var cardBorder: Color {
        if isChosen { return Theme.accentStrong }
        return deal.isChoosable ? Theme.line : Theme.danger
    }

    private var spokenSummary: String {
        var text = isChosen ? "Chosen deal. " : ""
        if let ribbon { text += "\(ribbon.label). " }
        text += deal.accessibilitySummary
        if !deal.fraudReasons.isEmpty, deal.fraudLevel != .low {
            text += ". " + deal.fraudReasons.joined(separator: ". ")
        }
        return text
    }

    /// The product-card top: a big picture beside (or, at accessibility sizes, over) the details.
    private func summary(large: Bool) -> some View {
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                           : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout {
            dealImage(large: large)
            info(large: large)
        }
    }

    private func dealImage(large: Bool) -> some View {
        let tint: Color = deal.isChoosable ? StorefrontTint.color(for: deal.id) : Theme.dangerSoft
        return StorefrontImage(spec: ShoppingThumbnails.spec(for: deal, item: item), tint: tint, height: large ? 160 : 108)
            .frame(width: large ? nil : 108)
            .overlay(alignment: .topLeading) {
                if let ribbon { RibbonTag(ribbon: ribbon).scaleEffect(0.85, anchor: .topLeading).padding(4) }
            }
    }

    private func info(large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accentStrong)
                }
                Text(deal.title).blockTitle().lineLimit(large ? 8 : 3).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if deal.isSample { ReplayBadge(sample: true) } else if deal.isReplay { ReplayBadge() }
            }
            AdaptiveLine {
                priceText()
                Text(deal.source).monoMeta()
                Spacer(minLength: 8)
                Label(deal.supportsCardCheckout ? "Visa checkout" : "Message seller",
                      systemImage: deal.supportsCardCheckout ? "creditcard" : "envelope")
                    .monoMeta()
                    .lineLimit(large ? 2 : 1)
            }
            if !deal.sellerDetails.isEmpty {
                Text(deal.sellerDetails).sansText(14).foregroundStyle(Theme.muted).lineLimit(large ? 8 : 3)
            }
            if let level = deal.fraudLevel, let score = deal.fraudScore {
                FraudChip(level: level, score: score)
                if level != .low {
                    ForEach(deal.fraudReasons, id: \.self) { reason in
                        Text("· \(reason)").monoMeta().fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Not fraud-screened yet").monoMeta()
            }
        }
    }

    private func actions(large: Bool, locked: Bool) -> some View {
        // At accessibility sizes "View" and the Choose button / Blocked tag stack instead of
        // squeezing "View" to "Vi…".
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if let url = deal.link {
                Link(destination: url) {
                    Label("View", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.pill(.text, compact: true))
                .accessibilityLabel("View the listing at \(deal.source)")
            }
            Spacer()
            if isChosen {
                MonoTag(text: "Chosen", tone: Theme.accentStrong).fixedSize()
            } else if item.status != .bought {
                if !deal.isChoosable {
                    // The worker refuses fraud-blocked deals, so the app doesn't offer them.
                    MonoTag(text: "Blocked: likely fraud", tone: Theme.danger)
                        .fixedSize()
                        .accessibilityLabel("Blocked, likely fraud. The agent won't buy this deal.")
                        .accessibilityIdentifier("deal.blocked.\(deal.id)")
                } else {
                    // Disabled while a hold or a purchase approval is pending: that one finishes (or is denied) first.
                    Button { choose() } label: {
                        if working { ProgressView() } else { Text("Choose") }
                    }
                    .buttonStyle(.pill(.primary, compact: true))
                    .disabled(working || locked)
                    .accessibilityLabel("Choose this deal, \(deal.formattedPrice) from \(deal.source)")
                    .accessibilityHint(locked ? "Locked while a hold or an approval is pending for this item" : "")
                    .accessibilityIdentifier("deal.choose.\(deal.id)")
                }
            }
        }
    }

    private func priceText() -> some View {
        Text(deal.formattedPrice)
            .monoText(20, weight: .bold, maxScale: 1.6)
            .foregroundStyle(deal.isChoosable ? Theme.text : Theme.muted)
            .strikethrough(!deal.isChoosable)
            .amountText()
    }

    private func choose() {
        working = true
        failed = false
        Task {
            failed = !(await store.choose(deal, for: item))
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
    @State private var failed = false

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
                    if failed {
                        CommerceProblem(text: "Couldn't add it. Check the connection and try again.")
                            .padding(.top, 16)
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
        .presentationDetents([.medium, .large])
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
            failed = !ok
            if ok { dismiss() }
        }
    }
}

#Preview {
    NavigationStack { ShoppingItemDetailView(itemId: 51) }.environment(MooveStore.preview())
}
