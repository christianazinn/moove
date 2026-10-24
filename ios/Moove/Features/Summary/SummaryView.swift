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
            VStack(spacing: 16) {
                hero(s)
                dispositions(s)
                money(s)
                impact(s)
                agents(s)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Summary")
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("Nothing to sum up yet", systemImage: "chart.bar.doc.horizontal",
                                       description: Text("Scan a room and Moove will tally your move here."))
            }
        }
    }

    // MARK: Sections

    private func hero(_ s: MoveSummary) -> some View {
        VStack(spacing: 6) {
            Text("Your move, handled").font(.title2.bold())
            Text("\(s.itemCount) items sorted · \(s.netCents.signedUSD) net · \(Int(s.divertedKg.rounded())) kg kept out of landfill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func dispositions(_ s: MoveSummary) -> some View {
        card("Where everything went") {
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 14)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(order, id: \.self) { d in
                    HStack(spacing: 6) {
                        Circle().fill(Self.color(d)).frame(width: 8, height: 8)
                        Text("\(s.counts[d] ?? 0)").font(.headline.monospacedDigit())
                        Text(Self.label(d)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if s.needsYou > 0 {
                Label("\(s.needsYou) still need you (sentimental or undecided)", systemImage: "heart")
                    .font(.footnote)
                    .foregroundStyle(.pink)
            }
        }
    }

    private func money(_ s: MoveSummary) -> some View {
        card("Money", badge: s.hasSimulatedMoney || usingDemoActivity ? "SIMULATED" : nil) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    stat("Sold", s.soldCents.usd, tint: .green)
                    stat("Still selling", s.pendingSalesCents.usd, tint: .teal)
                }
                GridRow {
                    stat("Spent", s.spentCents.usd, tint: .orange)
                    stat("Net", s.netCents.signedUSD, tint: s.netCents >= 0 ? .green : .red)
                }
            }
            if !s.rails.isEmpty {
                Divider()
                ForEach(s.rails) { rail in
                    HStack {
                        Text(rail.rail == "x402" ? "x402 data payments" : rail.rail == "visa" ? "Visa purchases" : rail.rail)
                        if rail.simulatedCents > 0 {
                            Text(rail.simulatedCents == rail.cents ? "simulated" : "\(rail.simulatedCents.usd) simulated")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(rail.cents.usd).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            Text("Sales not yet sold are counted at their listing price or estimate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func impact(_ s: MoveSummary) -> some View {
        card("Impact") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                Text("~\(Int(s.divertedKg.rounded())) kg").font(.title.bold())
                Text("kept out of landfill").foregroundStyle(.secondary)
            }
            Text("\(s.divertedItems) items sold or donated instead of trashed. You're moving \(s.keptVolumeM3, format: .number.precision(.fractionLength(1))) m³ of things you kept.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Weights are rough estimates by item type and size.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func agents(_ s: MoveSummary) -> some View {
        card("What the agents did", badge: usingDemoActivity ? "DEMO" : nil) {
            if s.agents.isEmpty {
                Text("No agent activity yet.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(s.agents) { a in
                            VStack(spacing: 2) {
                                Text("\(a.steps)").font(.headline.monospacedDigit())
                                Text(a.agent.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(s.timeline.enumerated()), id: \.offset) { _, e in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: Self.icon(e.kind)).foregroundStyle(.tint).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.message).font(.subheadline)
                                Text("\(e.agent) · \(e.createdAt, style: .relative) ago").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, badge: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let badge {
                    Text(badge).font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func color(_ d: Disposition) -> Color {
        switch d {
        case .keep: .blue
        case .sell: .green
        case .donate: .teal
        case .trash: .gray
        case .undecided: .pink
        }
    }

    static func label(_ d: Disposition) -> String {
        switch d {
        case .keep: "kept"
        case .sell: "selling"
        case .donate: "donated"
        case .trash: "trashed"
        case .undecided: "undecided"
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
