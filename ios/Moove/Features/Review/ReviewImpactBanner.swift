import SwiftUI
import MooveKit

/// The strip on top of Items > Review: roughly how many kg your Sell and Donate decisions keep
/// out of landfill (`MoveSummary.divertedKg` over the visible items), live as you decide. It
/// moved here when the Summary tab was removed (decision 0129 addendum). Tap it for how it's estimated.
struct ReviewImpactBanner: View {
    let items: [Item]
    @State private var showInfo = false

    var body: some View {
        let summary = MoveSummary(items: items, sales: [], spend: [], events: [])
        let kg = Int(summary.divertedKg.rounded())
        let count = summary.divertedItems
        Button { showInfo = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "leaf")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.accentStrong)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.bg.opacity(0.6)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("~\(kg) kg")
                            .monoText(16, weight: .bold, maxScale: 1.6)
                            .foregroundStyle(Theme.accentStrong)
                            .contentTransition(.numericText())
                        Text("kept out of landfill").monoText(13).foregroundStyle(Theme.text)
                    }
                    Text(count == 0 ? "Sell or donate to keep things out of landfill"
                                    : "\(count) item\(count == 1 ? "" : "s") sold or donated")
                        .monoText(12, maxScale: 1.8)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.default, value: kg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("About \(kg) kilograms kept out of landfill, \(count) item\(count == 1 ? "" : "s") sold or donated")
        .accessibilityHint("Shows how it's estimated")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("review.impact")
        .sheet(isPresented: $showInfo) { ReviewImpactInfo(items: items) }
    }
}

/// How the kg figure is estimated, with the Sell / Donate breakdown.
private struct ReviewImpactInfo: View {
    let items: [Item]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Kept out of landfill").blockTitle()
                Spacer()
                Button("Done") { dismiss() }
                    .monoText(13.5, weight: .bold)
                    .foregroundStyle(Theme.accentStrong)
                    .frame(minHeight: 44)
            }
            Text("Rough estimate: a typical weight for each item you sell or donate, scaled by its size.")
                .sansText(15)
                .lineSpacing(3)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 20)
            row("Sell", .sell)
            row("Donate", .donate)
            Spacer(minLength: 0)
        }
        .padding(Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .presentationDetents([.medium])
        .accessibilityIdentifier("review.impact.info")
    }

    private func row(_ title: String, _ d: Disposition) -> some View {
        let picked = items.filter { $0.disposition == d }
        let kg = Int(picked.reduce(0) { $0 + MoveSummary.estimatedKg($1) }.rounded())
        return HStack(spacing: 12) {
            Text(title).monoText(13.5)
            Spacer()
            Text("\(picked.count) item\(picked.count == 1 ? "" : "s")").monoText(13.5).foregroundStyle(Theme.muted)
            Text("~\(kg) kg").monoText(13.5, weight: .bold).frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(picked.count) item\(picked.count == 1 ? "" : "s"), about \(kg) kilograms")
    }
}
