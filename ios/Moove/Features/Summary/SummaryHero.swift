import SwiftUI
import MooveKit

/// What the Summary hero shows: the chosen new home with the moving pieces in it.
struct SummaryHome: Equatable, Sendable {
    var name: String
    var plan: FloorPlan
    var items: [LayoutItem]
    /// Fixture items stand in because nothing is kept or bought yet.
    var isDemoItems: Bool
    /// The saved home had no plan, so the demo house stands in.
    var isDemoHouse: Bool

    var key: SolveKey { SolveKey(plan: plan, items: items) }

    /// nil when no new home is chosen yet (the hero shows "Pick your new home").
    /// Same pieces as New Home: the picked rooms' kept items plus bought ones, or the demo's.
    @MainActor
    static func current(_ store: MooveStore) -> SummaryHome? {
        guard let home = store.newHome else { return nil }
        func layoutItem(_ item: Item) -> LayoutItem {
            item.colors == nil && DemoFixtures.isDemoItem(item) ? LayoutItem(item, colors: DemoFixtures.scanColors()) : LayoutItem(item)
        }
        let bought = store.snapshot.boughtLayoutItems
        let items: [LayoutItem]
        let isDemoItems: Bool
        if !store.keptItems.isEmpty || !bought.isEmpty {
            items = store.movingItems.map(layoutItem) + bought
            isDemoItems = false
        } else {
            let demo = DemoFixtures.demo(owner: "demo")
            items = demo.items.filter { $0.disposition == .keep }.map(layoutItem) + demo.boughtLayoutItems
            isDemoItems = true
        }
        let plan = home.floorPlan
        return SummaryHome(name: plan == nil ? DemoHouse.name : home.name, plan: plan ?? DemoHouse.floorPlan,
                           items: items, isDemoItems: isDemoItems, isDemoHouse: plan == nil)
    }
}

/// The top of Summary: the new home as a slowly turning voxel dollhouse with the kept pieces in
/// place (no orbit under Reduce Motion), "Your move, handled." and the one-line story over it.
/// Before a new home is chosen: the title, the story and "Pick your new home".
struct SummaryHero: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("moove.tab") private var tab = "summary"

    var home: SummaryHome?
    var story: String?
    /// The dollhouse as a still, for the share image.
    var onSnapshot: (UIImage) -> Void

    @State private var placements: [Placement] = []
    @State private var shownKey: SolveKey?

    static let title = "Your move, handled."

    var body: some View {
        if let home {
            stage(home)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock(onStage: false)
                pickHome.padding(.top, 24)
            }
        }
    }

    // MARK: Stage

    private func stage(_ home: SummaryHome) -> some View {
        let textOver = !dynamicTypeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                FloorPlan3DView(plan: home.plan, items: home.items, placements: placements,
                                autoOrbit: !reduceMotion, interactive: false, onSnapshot: onSnapshot)
                    .accessibilityElement()
                    .accessibilityLabel(stageLabel(home))
                if textOver {
                    LinearGradient(stops: [.init(color: Theme.bg.opacity(0), location: 0.35),
                                           .init(color: Theme.bg.opacity(0.92), location: 0.82)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    titleBlock(onStage: true).padding(18)
                }
            }
            .frame(height: sizeClass == .regular ? 480 : 380)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    MonoTag(text: home.name)
                    if home.isDemoItems || home.isDemoHouse { MonoTag(text: "Demo", tone: Theme.ochreInk) }
                }
                .padding(14)
            }
            if !textOver { titleBlock(onStage: false).padding(.top, 20) }
        }
        .task(id: home.key) { await arrange(home) }
    }

    private func titleBlock(onStage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.title)
                .pageTitle()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("summary.title")
            if let story {
                Text(story)
                    .sansText(16.5, weight: .medium)
                    .foregroundStyle(Theme.text)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("summary.story")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pickHome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick your new home").blockTitle()
            Text("See everything you kept, in place.").monoMeta().fixedSize(horizontal: false, vertical: true)
            Button("Pick your new home") { tab = "newhome" }
                .buttonStyle(.pill(.primary, compact: true))
                .accessibilityIdentifier("summary.pickHome")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
    }

    private func stageLabel(_ home: SummaryHome) -> String {
        let n = placements.count
        return "\(home.name) in 3D, \(n) piece\(n == 1 ? "" : "s") in place"
    }

    // MARK: Layout

    /// The layout the user saved last for this home if it still fits these pieces, else New Home's
    /// cached (or freshly solved) layout in the saved style, By function by default.
    private func arrange(_ home: SummaryHome) async {
        guard home.key != shownKey else { return }
        let ids = Set(home.items.map(\.id))
        let saved = Review.savedLayout(in: store.snapshot)
        if let saved, !home.isDemoHouse {
            let fits = saved.placements.filter { ids.contains($0.itemId) }
            if !fits.isEmpty, fits.count == saved.placements.count {
                placements = fits
                shownKey = home.key
                return
            }
        }
        let options: [LayoutOption]
        if let cached = LayoutCache.options(for: home.key) {
            options = cached
        } else {
            options = await LayoutSolver.arrange(plan: home.plan, items: home.items)
            guard !Task.isCancelled else { return }
            LayoutCache.store(options, for: home.key)
        }
        let style = LayoutSolver.Style.allCases.first { $0.label == saved?.name } ?? .byFunction
        placements = (options.first { $0.style == style } ?? options.first)?.placements ?? []
        shownKey = home.key
    }
}
