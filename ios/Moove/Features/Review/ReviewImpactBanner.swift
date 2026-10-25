import SwiftUI
import MooveKit

/// The strip on top of Items > Review: roughly how many kg your Sell and Donate decisions keep
/// out of landfill (`MoveSummary.divertedKg` over the visible items), live as you decide. It
/// moved here when the Summary tab was removed (decision 0129 addendum). A small sign: the kg in
/// serif, big and counting up as you decide (no count-up under Reduce Motion), the items under it.
/// Tap it for how it's estimated.
struct ReviewImpactBanner: View {
    let items: [Item]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showInfo = false

    var body: some View {
        let summary = MoveSummary(items: items, sales: [], spend: [], events: [])
        let kg = Int(summary.divertedKg.rounded())
        let count = summary.divertedItems
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        Button { showInfo = true } label: {
            // A calm sign (Lisa): one big number, a small label, the item count under it; the (i)
            // opens how it's estimated. Two lines of text at most.
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.accentStrong)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.accentSoft))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(kg) kg")
                            .serifType(30, weight: .semibold)
                            .foregroundStyle(Theme.text)
                            .contentTransition(reduceMotion ? ContentTransition.identity : .numericText(value: Double(kg)))
                            .lineLimit(1)
                        Text("kept out of landfill")
                            .monoText(12.5, maxScale: 1.6)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text("\(count) item\(count == 1 ? "" : "s") sold or donated")
                        .monoText(11.5, maxScale: 1.6)
                        .foregroundStyle(Theme.faint)
                        .contentTransition(reduceMotion ? ContentTransition.identity : .numericText(value: Double(count)))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
            .mooveShadow(.paper)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: kg)
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: count)
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
