import SwiftUI
import MooveKit

/// The closing screen of the demo: what happened to everything, the money,
/// what the agents did, and how much stayed out of landfill. Live: it
/// recomputes from the store on every snapshot.
struct SummaryView: View {
    @Environment(MooveStore.self) private var store

    /// Spend and agent events come from the commerce lane (#7, #15) and the
    /// worker's event log; until the app syncs those tables, show labeled demo lines.
    private var usingDemoActivity: Bool { true }

    private var summary: MoveSummary {
        let items = store.items
        return MoveSummary(
            items: items,
            sales: MoveSummary.estimatedSales(from: items) + MoveSummary.sales(from: store.snapshot.listings),
            spend: usingDemoActivity ? SummaryDemo.spend : [],
            events: usingDemoActivity ? SummaryDemo.events() : []
        )
    }

    var body: some View {
        let s = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(s)
                dispositions(s)
                money(s)
                impact(s)
                agents(s)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .overlay {
            if store.items.isEmpty {
                VStack(spacing: 8) {
                    Text("Nothing to sum up yet").blockTitle()
                    Text("Scan a room and Moove will tally your move here.").monoMeta()
                }
                .multilineTextAlignment(.center)
                .padding()
            }
        }
    }

    // MARK: Sections

    private func hero(_ s: MoveSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary · \(s.itemCount) items").eyebrow()
            Text("Your move, handled.")
                .font(.system(size: 28, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                figure(s.netCents.signedUSD, "net", tint: s.netCents >= 0 ? Theme.accentStrong : Theme.danger)
                figure("\(Int(s.divertedKg.rounded())) kg", "kept from landfill", tint: Theme.text)
            }
            .padding(.top, 6)
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
    }

    private func dispositions(_ s: MoveSummary) -> some View {
        section("Where everything went") {
            let order: [Disposition] = [.keep, .sell, .donate, .trash, .undecided]
            let total = max(s.itemCount, 1)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(order.filter { (s.counts[$0] ?? 0) > 0 }, id: \.self) { d in
                        Rectangle()
                            .fill(Self.color(d))
                            .frame(width: max(4, geo.size.width * CGFloat(s.counts[d] ?? 0) / CGFloat(total) - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .padding(.bottom, 4)
            ForEach(order, id: \.self) { d in
                HStack(spacing: 10) {
                    Circle().fill(Self.color(d)).frame(width: 7, height: 7)
                    Text(Self.label(d)).font(.mono(13.5))
                    Spacer()
                    Text("\(s.counts[d] ?? 0)").font(.mono(13.5, weight: .bold))
                }
                .padding(.vertical, 9)
                .ruled()
            }
            if s.needsYou > 0 {
                Text("\(s.needsYou) still need you · sentimental or undecided")
                    .font(.mono(12))
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 4)
            }
        }
    }

    private func money(_ s: MoveSummary) -> some View {
        section("Money", tag: s.hasSimulatedMoney || usingDemoActivity ? "Simulated" : nil) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    figure(s.soldCents.usd, "sold", tint: Theme.accentStrong)
                    figure(s.pendingSalesCents.usd, "still selling", tint: Theme.text)
                }
                GridRow {
                    figure(s.spentCents.usd, "spent", tint: Theme.ochre)
                    figure(s.netCents.signedUSD, "net", tint: s.netCents >= 0 ? Theme.accentStrong : Theme.danger)
                }
            }
            .padding(.bottom, 6)
            ForEach(s.rails) { rail in
                HStack(spacing: 8) {
                    Text(rail.rail == "x402" ? "x402 data payments" : rail.rail == "visa" ? "Visa purchases" : rail.rail)
                        .font(.mono(13.5))
                    if rail.simulatedCents > 0 {
                        MonoTag(text: rail.simulatedCents == rail.cents ? "Simulated" : "\(rail.simulatedCents.usd) sim", tone: Theme.ochre)
                    }
                    Spacer()
                    Text(rail.cents.usd).font(.mono(13.5, weight: .bold))
                }
                .padding(.vertical, 9)
                .ruled(.top)
            }
            Text("Unsold items count at their listing price or estimate.").monoMeta().padding(.top, 4)
        }
    }

    private func impact(_ s: MoveSummary) -> some View {
        section("Impact") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("~\(Int(s.divertedKg.rounded())) kg").font(.mono(30, weight: .bold)).foregroundStyle(Theme.accentStrong)
                Text("kept out of landfill").font(.mono(13)).foregroundStyle(Theme.muted)
            }
            Text("\(s.divertedItems) items sold or donated instead of trashed. You're moving \(s.keptVolumeM3, format: .number.precision(.fractionLength(1))) m³ of things you kept.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
            Text("Weights are rough estimates by item type and size.").monoMeta()
        }
    }

    private func agents(_ s: MoveSummary) -> some View {
        section("What the agents did", tag: usingDemoActivity ? "Demo" : nil) {
            if s.agents.isEmpty {
                Text("No agent activity yet.").monoMeta()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(s.agents) { a in
                            HStack(spacing: 6) {
                                Text(a.agent).font(.mono(12.5))
                                Text("\(a.steps)").font(.mono(12.5, weight: .bold))
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(Capsule().fill(Theme.surface))
                        }
                    }
                }
                .padding(.bottom, 4)
                ForEach(Array(s.timeline.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: Self.icon(e.kind))
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Theme.accentStrong)
                            .frame(width: 18)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.message).font(.system(size: 15))
                            Text("\(e.agent) · \(e.createdAt, style: .relative) ago").monoMeta()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .ruled()
                }
            }
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, tag: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).eyebrow()
                Spacer()
                if let tag { MonoTag(text: tag, tone: Theme.ochre) }
            }
            content()
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
    }

    private func figure(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.mono(22, weight: .bold)).foregroundStyle(tint)
            Text(label).font(.mono(11.5)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func color(_ d: Disposition) -> Color {
        switch d {
        case .keep: Theme.accent
        case .sell: Theme.ochre
        case .donate: Theme.slate
        case .trash: Theme.stone
        case .undecided: Theme.danger
        }
    }

    static func label(_ d: Disposition) -> String {
        switch d {
        case .keep: "Kept"
        case .sell: "Selling"
        case .donate: "Donated"
        case .trash: "Trashed"
        case .undecided: "Undecided"
        }
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "payment": "dollarsign.circle"
        case "approval": "hand.raised"
        case "tool_call": "magnifyingglass"
        case "plan": "list.bullet"
        case "error": "exclamationmark.triangle"
        default: "checkmark.circle"
        }
    }
}

private extension Int64 {
    var signedUSD: String { self < 0 ? "−" + (-self).usd : usd }
}

#Preview {
    NavigationStack { SummaryView() }.environment(MooveStore.preview())
}
