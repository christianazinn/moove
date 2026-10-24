import SwiftUI
import MooveKit

/// The closing screen of the demo: what happened to everything, the money,
/// what the agents did, and how much stayed out of landfill. Live: it
/// recomputes from the store on every snapshot.
struct SummaryView: View {
    @Environment(MooveStore.self) private var store
    @AppStorage("moove.tab") private var tab = "summary"

    /// Spend and agent steps come from the `payment` and `agent_event` tables. With no
    /// rows yet (nothing has run), show labeled demo lines so the closing slide isn't empty.
    private var usingDemoActivity: Bool { store.snapshot.payments.isEmpty && store.snapshot.agentEvents.isEmpty }

    private var sales: [MoveSummary.Sale] { MoveSummary.sales(from: store.snapshot) }

    private var summary: MoveSummary {
        let snap = store.snapshot
        guard usingDemoActivity else { return MoveSummary(snapshot: snap) }
        return MoveSummary(items: snap.items, sales: sales, spend: SummaryDemo.spend, events: SummaryDemo.events())
    }

    var body: some View {
        let s = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MooveWordmark(height: 36).padding(.top, 8).padding(.bottom, 32)
                PageHeader(
                    eyebrow: "07 — Summary",
                    title: "Your move, handled.",
                    lede: store.items.isEmpty ? nil : "\(s.itemCount) items, start to finish."
                )
                if store.items.isEmpty {
                    emptyState.padding(.top, 36)
                } else {
                    stats(s).padding(.top, 32)
                    dispositions(s)
                    itemLists(s)
                    money(s)
                    impact(s)
                    agents(s)
                    safety(SafetySummary(snapshot: store.snapshot))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing to sum up yet").blockTitle()
            Text("Scan a room to start.").monoMeta().fixedSize(horizontal: false, vertical: true)
            Button("Scan a room") { tab = "scan" }
                .buttonStyle(.pill(.outline, compact: true))
                .padding(.top, 12)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
    }

    // MARK: Sections

    /// Two headline figures side by side, split by a hairline, between rules.
    private func stats(_ s: MoveSummary) -> some View {
        HStack(spacing: 0) {
            StatFigure(label: "Net", value: s.netMicros.netUSD, tint: s.netMicros >= 0 ? Theme.accentStrong : Theme.danger)
                .padding(.vertical, 18)
                .padding(.trailing, 20)
            Rectangle().fill(Theme.line).frame(width: 1).accessibilityHidden(true)
            StatFigure(label: "Kept from landfill", value: "\(Int(s.divertedKg.rounded())) kg")
                .accessibilityLabel("Kept from landfill, \(Int(s.divertedKg.rounded())) kilograms")
                .padding(.vertical, 18)
                .padding(.leading, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .ruled(.top)
        .ruled()
    }

    private static let order: [Disposition] = [.keep, .sell, .donate, .trash, .undecided]

    private func dispositions(_ s: MoveSummary) -> some View {
        section("Where everything went", count: "\(s.itemCount)") {
            let total = max(s.itemCount, 1)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Self.order.filter { (s.counts[$0] ?? 0) > 0 }, id: \.self) { d in
                        Rectangle()
                            .fill(Self.color(d))
                            .frame(width: max(4, geo.size.width * CGFloat(s.counts[d] ?? 0) / CGFloat(total) - 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .padding(.vertical, 18)
            .accessibilityHidden(true)
            ForEach(Self.order, id: \.self) { d in
                HStack(spacing: 12) {
                    Circle().fill(Self.color(d)).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(Self.label(d)).monoText(13.5)
                    Spacer()
                    Text("\(s.counts[d] ?? 0)").monoText(13.5, weight: .bold)
                }
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .ruled()
                .accessibilityElement(children: .combine)
            }
            if s.needsYou > 0 {
                Text("\(s.needsYou) still need you · sentimental or undecided")
                    .monoText(13.5)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    /// The items themselves: what's coming along, what went where, what's still open.
    @ViewBuilder
    private func itemLists(_ s: MoveSummary) -> some View {
        let items = store.items.sorted { a, b in
            let ra = Self.order.firstIndex(of: a.disposition) ?? 0, rb = Self.order.firstIndex(of: b.disposition) ?? 0
            return ra != rb ? ra < rb : a.name < b.name
        }
        let sale = bestSales
        let kept = items.filter { $0.disposition == .keep }
        let goneTo: Set<Disposition> = [.sell, .donate, .trash]
        let gone = items.filter { goneTo.contains($0.disposition) }
        let open = items.filter { $0.disposition == .undecided }

        if !kept.isEmpty {
            section("Coming with you", count: "\(kept.count)") {
                ForEach(kept) { item in
                    itemRow(item, state: "Kept", value: item.estValueCents.map(\.usd), sale: nil)
                }
                Text("\(s.keptVolumeM3, format: .number.precision(.fractionLength(1))) m³ to move")
                    .monoMeta()
                    .accessibilityLabel("\(Spoken.volume(s.keptVolumeM3)) to move")
                    .padding(.top, 12)
            }
        }
        if !gone.isEmpty {
            section("Let go", count: "\(gone.count)") {
                ForEach(gone) { item in
                    let line = sale[item.id]
                    itemRow(item, state: Self.state(item.disposition, line), value: line.map { $0.priceCents.usd }, sale: line)
                }
            }
        }
        if !open.isEmpty {
            section("Still deciding", count: "\(open.count)") {
                ForEach(open) { item in
                    itemRow(item, state: item.maybeSentimental ? "Sentimental · yours to call" : "Undecided", value: nil, sale: nil)
                }
            }
        }
    }

    private func itemRow(_ item: Item, state: String, value: String?, sale: MoveSummary.Sale?) -> some View {
        LedgerRow(
            title: item.name,
            meta: "\(String(format: "%.1f × %.1f m", item.widthM, item.depthM)) · \(state)",
            value: value,
            valueTint: sale?.stage == .sold ? Theme.accentStrong : Theme.text
        ) {
            VoxelThumbnail(item)
        } trailing: {
            if sale?.simulated == true && sale?.stage != .estimated { MonoTag(text: "Sim", tone: Theme.ochreInk) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([
            item.name, Spoken.size(item.widthM, item.depthM), state, value,
            sale?.simulated == true && sale?.stage != .estimated ? "simulated" : nil,
        ] as [String?]).compactMap { $0 }.joined(separator: ", "))
    }

    /// One sale line per item, the furthest-along stage winning (the same rule `MoveSummary` totals with).
    private var bestSales: [UInt64: MoveSummary.Sale] {
        func rank(_ stage: MoveSummary.Sale.Stage) -> Int {
            switch stage {
            case .estimated: 0
            case .listed: 1
            case .sold: 2
            }
        }
        var best: [UInt64: MoveSummary.Sale] = [:]
        for line in sales where (best[line.itemId].map { rank($0.stage) < rank(line.stage) } ?? true) {
            best[line.itemId] = line
        }
        return best
    }

    private static func state(_ d: Disposition, _ sale: MoveSummary.Sale?) -> String {
        switch d {
        case .sell:
            switch sale?.stage {
            case .sold?: "Sold"
            case .listed?: "Listed"
            case .estimated?: "Selling · estimate"
            case nil: "Selling"
            }
        case .donate: "Donated"
        case .trash: "Trashed"
        case .keep: "Kept"
        case .undecided: "Undecided"
        }
    }

    private func money(_ s: MoveSummary) -> some View {
        section("Money", tag: s.hasSimulatedMoney || usingDemoActivity ? "Simulated" : nil) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                GridRow {
                    StatFigure(label: "Sold", value: s.soldCents.usd, tint: Theme.accentStrong).padding(.vertical, 18)
                    StatFigure(label: "Still selling", value: s.pendingSalesCents.usd).padding(.vertical, 18)
                }
                Rectangle().fill(Theme.line).frame(height: 1).gridCellUnsizedAxes(.horizontal).accessibilityHidden(true)
                GridRow {
                    StatFigure(label: "Spent", value: UsdMicros.format(s.spentMicros), tint: Theme.ochreInk).padding(.vertical, 18)
                    StatFigure(label: "Net", value: s.netMicros.netUSD, tint: s.netMicros >= 0 ? Theme.accentStrong : Theme.danger)
                        .padding(.vertical, 18)
                }
            }
            .ruled()
            ForEach(s.rails) { rail in
                HStack(spacing: 8) {
                    Text(rail.rail == "x402" ? "x402 data payments" : rail.rail == "visa" ? "Visa purchases" : rail.rail)
                        .monoText(13.5)
                    if rail.simulatedMicros > 0 {
                        MonoTag(text: rail.simulatedMicros == rail.micros ? "Simulated" : "\(UsdMicros.format(rail.simulatedMicros)) sim", tone: Theme.ochreInk)
                    }
                    Spacer()
                    Text(UsdMicros.format(rail.micros)).rowValue()
                }
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .ruled()
                .accessibilityElement(children: .combine)
            }
            Text("Unsold items at listing price or estimate.").monoMeta().padding(.top, 12)
        }
    }

    private func impact(_ s: MoveSummary) -> some View {
        section("Impact") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("~\(Int(s.divertedKg.rounded())) kg")
                        .monoText(30, weight: .bold, maxScale: 1.6)
                        .foregroundStyle(Theme.accentStrong)
                    Text("kept out of landfill").monoText(13.5).foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("About \(Int(s.divertedKg.rounded())) kilograms kept out of landfill")
                Text("\(s.divertedItems) items sold or donated, not trashed.")
                    .sansText(15.5)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Rough weights by type and size.").monoMeta()
            }
            .padding(.top, 18)
        }
    }

    private func agents(_ s: MoveSummary) -> some View {
        section("What the agents did", tag: usingDemoActivity ? "Demo" : nil) {
            if s.agents.isEmpty {
                Text("No agent activity yet.").monoMeta().padding(.top, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(s.agents) { a in
                            HStack(spacing: 6) {
                                Text(a.agent).monoText(13, maxScale: 1.5).foregroundStyle(Theme.muted)
                                Text("\(a.steps)").monoText(13, weight: .bold, maxScale: 1.5)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(Capsule().fill(Theme.surface))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(a.agent), \(a.steps) step\(a.steps == 1 ? "" : "s")")
                        }
                    }
                }
                .padding(.vertical, 16)
                ForEach(Array(s.timeline.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: Self.icon(e.kind))
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Theme.accentStrong)
                            .frame(width: 18)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.message).sansText(15).fixedSize(horizontal: false, vertical: true)
                            Text("\(e.agent) · \(e.createdAt, style: .relative) ago").monoMeta()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 14)
                    .ruled(.top)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// The guardrails that fired (#225): scams blocked, approvals asked, sentimental items left
    /// alone, spend against the caps. Simulated money says so in the line and gets a tag.
    private func safety(_ safety: SafetySummary) -> some View {
        let lines = safety.lines
        return section("Agents kept you safe", tag: lines.contains(where: \.simulated) ? "Simulated" : nil) {
            if lines.isEmpty {
                Text(SafetySummary.emptyText).monoMeta().padding(.top, 16)
            } else {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: Self.safetyIcon(line.kind))
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Theme.accentStrong)
                            .frame(width: 18)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text).monoText(13.5).fixedSize(horizontal: false, vertical: true)
                            if let detail = line.detail {
                                Text(detail).monoMeta().lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if line.simulated { MonoTag(text: "Sim", tone: Theme.ochreInk) }
                    }
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .ruled()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.spoken)
                }
            }
        }
    }

    static func safetyIcon(_ kind: SafetySummary.LineKind) -> String {
        switch kind {
        case .fraud: "exclamationmark.shield"
        case .approvals: "hand.raised"
        case .sentimental: "heart"
        case .x402: "dollarsign.circle"
        case .roomX402: "person.2"
        case .card: "creditcard"
        case .ai: "gauge"
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, count: String? = nil, tag: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: title, count: count) {
                if let tag { MonoTag(text: tag, tone: Theme.ochreInk) }
            }
            content()
        }
        .padding(.top, 48)
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
    /// USD micros as a headline figure: whole cents, real minus sign ("−$12.40").
    var netUSD: String {
        let cents = (magnitude + 5_000) / 10_000
        let text = Int64(cents).usd
        return self < 0 && cents > 0 ? "−" + text : text
    }
}

#Preview {
    NavigationStack { SummaryView() }.environment(MooveStore.preview())
}
