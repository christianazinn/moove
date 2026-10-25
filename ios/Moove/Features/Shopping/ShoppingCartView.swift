import SwiftUI
import MooveKit

// The Shopping screen's cart (Lisa's ask): a round button at the bottom right with a count of
// what's bought, opening a half-height sheet that lists it. Lines, totals and labels come from
// MooveKit `SyncSnapshot.shoppingCart()` (`ShoppingCartTests`).

/// Floating cart button: `cart.fill` in a sage circle, a count badge once something is bought.
struct ShoppingCartButton: View {
    let cart: ShoppingCart
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 56
    @State private var taps = 0

    var body: some View {
        let size = min(scaledSize, 76)
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: "cart.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Theme.accentInk)
                .frame(width: size, height: size)
                .background(Theme.accentFill, in: Circle())
                .overlay(Circle().strokeBorder(Theme.bg.opacity(0.35), lineWidth: 1))
                .mooveShadow(.lifted)
                .overlay(alignment: .topTrailing) {
                    if cart.count > 0 {
                        Text("\(cart.count)")
                            .monoText(12, weight: .bold, maxScale: 1.4)
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Theme.ochreInk, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.bg, lineWidth: 2))
                            .offset(x: 4, y: -4)
                            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: cart.count)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(cart.accessibilityLabel)
        .accessibilityHint("Shows what you bought")
        .accessibilityIdentifier("shopping.cart")
    }
}

/// What's bought, in a sheet that opens at half height. A row pushes that item's detail.
struct ShoppingCartSheet: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cart = store.snapshot.shoppingCart()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if cart.isEmpty {
                        empty
                    } else {
                        Text(cart.summary)
                            .monoText(14, weight: .bold)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .ruled()
                            .accessibilityIdentifier("shopping.cart.summary")
                        ForEach(cart.lines) { line in
                            NavigationLink(value: ShoppingRoute(itemId: line.id)) {
                                ShoppingCartRow(line: line)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("shopping.cart.line.\(line.id)")
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("Bought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("shopping.cart.done")
                }
            }
            .navigationDestination(for: ShoppingRoute.self) { ShoppingItemDetailView(itemId: $0.itemId) }
            .mooveScreen()
        }
    }

    private var empty: some View {
        EmptyState(title: "Nothing bought yet", detail: "What you buy for the new place shows up here.")
            .accessibilityIdentifier("shopping.cart.empty")
    }
}

/// One bought item: voxel thumbnail, deal title, seller and price, status chip and payment rail.
struct ShoppingCartRow: View {
    let line: CartLine

    var body: some View {
        let spec = line.deal.map { ShoppingThumbnails.spec(for: $0, item: line.item) } ?? ShoppingThumbnails.spec(for: line.item)
        HStack(alignment: .top, spacing: 14) {
            ShoppingThumbnail(spec: spec, bought: true, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(line.title)
                    .monoText(15, weight: .bold, maxScale: 1.6)
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                AdaptiveLine {
                    if !line.seller.isEmpty { Text(line.seller).monoMeta().lineLimit(1) }
                    Spacer(minLength: 8)
                    if let amount = line.formattedAmount {
                        Text(amount).rowValue().fontWeight(.bold).amountText()
                    }
                }
                AdaptiveLine {
                    statusChip
                    if let payment = line.payment { VisaRailBadge(badge: VisaPaymentBadge(payment)) }
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilitySummary)
        .accessibilityHint("Opens the item")
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).accessibilityHidden(true)
            Text(line.statusLabel).monoText(12.5).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.accentStrong)
    }

    private var symbol: String {
        if line.room != nil { return "house" }
        switch line.status {
        case .bought: return "checkmark.circle.fill"
        case .paidSimulated, .visaSandbox: return "creditcard"
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShoppingCartSheet().presentationDetents([.medium, .large])
    }
    .environment(MooveStore.preview())
}
