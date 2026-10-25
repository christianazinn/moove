import SwiftUI
import MooveKit

/// The closing screen of the demo, "Your move, handled." (#335): the new home turning slowly
/// with the kept pieces in place, the story in one line, Made / Spent / Net, where everything
/// went, the landfill impact, the guardrails as a receipt, the agents' key steps and
/// "Share my move". Live: it recomputes from the store on every snapshot.
struct SummaryView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("moove.tab") private var tab = "summary"

    @State private var heroImage: UIImage?
    @State private var heroShots = 0
    @State private var shareImage: Image?
    @State private var openPile: OpenPile?

    private struct OpenPile: Identifiable {
        let destination: Disposition
        var id: String { destination.rawValue }
    }

    /// Spend and agent steps come from the `payment` and `agent_event` tables. With no
    /// rows yet (nothing has run), show labeled demo lines so the closing slide isn't empty.
    private var usingDemoActivity: Bool { store.snapshot.payments.isEmpty && store.snapshot.agentEvents.isEmpty }

    private var sales: [MoveSummary.Sale] { MoveSummary.sales(from: store.snapshot) }

    private static let timelineLimit = 12

    private var summary: MoveSummary {
        let snap = store.visibleSnapshot
        guard usingDemoActivity else { return MoveSummary(snapshot: snap, timelineLimit: Self.timelineLimit) }
        return MoveSummary(items: snap.items, sales: sales, spend: SummaryDemo.spend, events: SummaryDemo.events(),
                           timelineLimit: Self.timelineLimit)
    }

    private var simulatedTag: Bool { summary.hasSimulatedMoney || usingDemoActivity }

    var body: some View {
        let s = summary
        let home = SummaryHome.current(store)
        let story = SummaryPayoff.story(s)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MooveWordmark(height: 32).padding(.top, 8).padding(.bottom, 24)
                if store.visibleItems.isEmpty {
                    PageHeader(title: SummaryHero.title)
                    emptyState.padding(.top, 36)
                } else {
                    SummaryHero(home: home, story: story) { image in
                        heroImage = image
                        heroShots += 1
                    }
                    figures(s).padding(.top, 24)
                    share(s, home: home, story: story).padding(.top, 16)
                    whereItWent
                    impact(s)
                    safety(SafetySummary(snapshot: store.snapshot))
                    agents(s)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .sheet(item: $openPile) { pile in
            NavigationStack {
                ReviewPileScreen(destination: pile.destination)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { openPile = nil }.monoText(13, weight: .bold, maxScale: 1.4)
                        }
                    }
            }
            .environment(store)
        }
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

    // MARK: Made / Spent / Net

    /// Net big on top, Made and Spent side by side under it (one column at accessibility sizes),
    /// then one line per payment rail. Same figures as before the redesign (`DemoNumbersTests`).
    private func figures(_ s: MoveSummary) -> some View {
        let simulated = s.rails.map(\.simulatedMicros).reduce(0, +)
        let real = s.spentMicros - simulated
        let net = SummaryFigure(
            label: "Net", value: s.netMicros.netUSD, tint: s.netMicros >= 0 ? Theme.accentStrong : Theme.danger, size: 38,
            meter: SummaryPayoff.inShare(s), meterTint: Theme.accent, meterRest: Theme.ochre.opacity(0.55),
            caption: "In \((s.soldCents + s.pendingSalesCents).usd) · out \(UsdMicros.format(s.spentMicros)). Unsold items at listing price or estimate.",
            tag: simulatedTag ? "Simulated" : nil)
        let made = SummaryFigure(
            label: "Made", value: s.soldCents.usd, tint: Theme.accentStrong,
            meter: SummaryPayoff.soldShare(s), meterTint: Theme.accent,
            caption: s.pendingSalesCents > 0 ? "+\(s.pendingSalesCents.usd) still selling" : "Nothing left to sell",
            spoken: "Made, \(s.soldCents.usd) sold, \(s.pendingSalesCents.usd) still selling")
        let spent = SummaryFigure(
            label: "Spent", value: UsdMicros.format(s.spentMicros), tint: Theme.ochreInk,
            meter: s.spentMicros > 0 ? SummaryPayoff.simulatedShare(s) : nil, meterTint: Theme.ochre, meterRest: Theme.accent,
            caption: simulated > 0 ? "\(UsdMicros.format(simulated)) simulated · \(UsdMicros.format(real)) real" : nil,
            tag: simulatedTag ? "Sim" : nil)
        return VStack(alignment: .leading, spacing: 12) {
            net
            if dynamicTypeSize.isAccessibilitySize {
                made
                spent
            } else {
                HStack(alignment: .top, spacing: 12) {
                    made
                    spent
                }
                .fixedSize(horizontal: false, vertical: true)
            }
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
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .ruled()
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("summary.figures")
    }

    // MARK: Share

    private struct ShareKey: Hashable {
        var story: String?
        var made: String
        var spent: String
        var net: String
        var shots: Int
        var simulated: Bool
    }

    private func share(_ s: MoveSummary, home: SummaryHome?, story: String?) -> some View {
        let key = ShareKey(story: story, made: s.soldCents.usd, spent: UsdMicros.format(s.spentMicros), net: s.netMicros.netUSD,
                           shots: heroShots, simulated: simulatedTag)
        return Group {
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview(SummaryHero.title, image: shareImage)) {
                    Label("Share my move", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
            } else {
                Button {} label: {
                    Label("Share my move", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .disabled(true)
            }
        }
        .buttonStyle(.pill(.primary))
        .accessibilityIdentifier("summary.share")
        .task(id: key) {
            let card = SummaryShareCard(heroImage: heroImage, plan: home?.plan, story: key.story, made: key.made, spent: key.spent,
                                        net: key.net, netTint: s.netMicros >= 0 ? Theme.accentStrong : Theme.danger,
                                        simulated: key.simulated)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            shareImage = renderer.uiImage.map(Image.init(uiImage:))
        }
    }

    // MARK: Where everything went

    private var whereItWent: some View {
        let segments = SummaryPayoff.segments(store.visibleItems)
        return section("Where everything went", count: "\(store.visibleItems.count)") {
            SummaryDispositionBar(segments: segments) { seg in
                if let d = seg.destination { openPile = OpenPile(destination: d) } else { tab = "review" }
            }
            .padding(.top, 18)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(SummaryPayoff.spokenSegments(segments))
        }
    }

    // MARK: Impact

    private func impact(_ s: MoveSummary) -> some View {
        let items = store.visibleItems
        let diverted = items.filter { $0.disposition == .sell || $0.disposition == .donate }
        return section("Impact") {
            SummaryImpact(kg: s.divertedKg, divertedItems: diverted, divertedShare: SummaryPayoff.divertedShare(items))
                .padding(.top, 18)
        }
    }

    // MARK: Agents kept you safe

    /// The guardrails that fired (#225) as a receipt: scams blocked, approvals asked, sentimental
    /// items left alone, spend against the caps. Simulated money says so in the line and gets SIM.
    private func safety(_ safety: SafetySummary) -> some View {
        section("Agents kept you safe", tag: safety.lines.contains(where: \.simulated) ? "Simulated" : nil) {
            SafetyReceipt(safety: safety).padding(.top, 18)
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

    // MARK: What the agents did

    private func agents(_ s: MoveSummary) -> some View {
        let steps = SummaryPayoff.keySteps(s.timeline)
        let total = s.agents.map(\.steps).reduce(0, +)
        return section("What the agents did", count: total > 0 ? "\(s.agents.count) agents · \(total) steps" : nil,
                       tag: usingDemoActivity ? "Demo" : nil) {
            if s.timeline.isEmpty {
                Text("No agent activity yet.").monoMeta().padding(.top, 16)
            } else {
                SummaryAgentTimeline(key: steps.key, rest: steps.rest).padding(.top, 18)
            }
        }
    }

    static func icon(_ kind: String) -> String {
        switch kind {
        case "payment": "dollarsign.circle"
        case "approval": "hand.raised"
        case "tool_call": "magnifyingglass"
        case "plan": "list.bullet"
        case "error": "exclamationmark.triangle"
        default: "checkmark"
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
        .padding(.top, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
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
