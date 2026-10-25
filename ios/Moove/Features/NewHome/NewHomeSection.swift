import SwiftUI
import MooveKit

/// Move's "Your new home" part: which home it is, and the furniture that flies into it.
/// `MoveView` owns the scroll; this file has the pieces it stacks (the picker when no home is
/// chosen, the header, the 3D stage, layout controls and room shots).
enum NewHomeChoice {
    /// The home shown: the unsaved local pick (saving it failed or is still syncing) or the saved row.
    struct Current: Equatable {
        var name: String
        var source: NewHomeSource
        var plan: FloorPlan
    }

    /// Review's Keep pile from the selected rooms ("Rooms in this move"; by default the newest scan of
    /// each room name, so re-scans don't bring a second bed) plus bought ones (#15); the demo's if
    /// there's nothing yet. The same set as the truck and boxes (`MooveStore.moveItems`).
    static func furniture(_ move: MoveItems) -> Furniture {
        // Stored colors (`set_item_colors`); demo bedroom items without any use the demo room's.
        func layoutItem(_ item: Item) -> LayoutItem {
            item.colors == nil && DemoFixtures.isDemoItem(item) ? LayoutItem(item, colors: DemoFixtures.scanColors()) : LayoutItem(item)
        }
        return Furniture(items: move.kept.map(layoutItem) + move.boughtLayout, isDemo: move.isDemo, sources: move.kept)
    }
}

// MARK: - Picker

/// Where the new home comes from, in its own scroll (the Change home sheet).
struct NewHomePicker: View {
    var onPick: (_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) -> Void

    var body: some View {
        ScrollView {
            NewHomePickerContent(onPick: onPick)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 40)
        }
        .mooveScreen()
    }
}

/// The picker's blocks: Paste a Zillow link or the demo house. Move shows them at
/// the top of the page until a home is chosen.
struct NewHomePickerContent: View {
    var onPick: (_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Where are you moving?")
                .padding(.top, 8)
                .padding(.bottom, 28)

            NavigationLink {
                ListingImportView { name, source, plan in onPick(name, source, plan) }
            } label: {
                Label("Paste a Zillow link", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .accessibilityHint("Zillow, Redfin or Realtor.com")
            .padding(.bottom, 40)

            demoHouse
        }
    }

    private var demoHouse: some View {
        Button { onPick(DemoHouse.name, .demo, DemoHouse.floorPlan) } label: {
            VStack(alignment: .leading, spacing: 18) {
                FloorPlanSketch(plan: DemoHouse.floorPlan)
                    .frame(height: 220)
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                HStack(alignment: .center, spacing: 16) {
                    Text(DemoHouse.name).blockTitle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Use this home")
                        .monoText(13, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .foregroundStyle(Theme.accentInk)
                        .background(Capsule().fill(Theme.accentFill))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(DemoHouse.name), \(Self.spokenSummary(DemoHouse.floorPlan))")
        .accessibilityHint("Uses the demo house as your new home")
    }

    static func summary(_ plan: FloorPlan) -> String {
        let bedrooms = plan.rooms.filter { $0.kind == .bedroom }.count
        return "\(bedrooms) bed · \(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m²"
    }

    /// `summary` for VoiceOver: "2 bedrooms, 5 rooms, 82 square meters".
    static func spokenSummary(_ plan: FloorPlan) -> String {
        let bedrooms = plan.rooms.filter { $0.kind == .bedroom }.count
        return "\(bedrooms) bedroom\(bedrooms == 1 ? "" : "s"), \(plan.rooms.count) rooms, \(Spoken.area(plan.totalAreaM2))"
    }
}

struct Furniture: Equatable {
    var items: [LayoutItem]
    /// True when these are fixture items, not the user's.
    var isDemo: Bool
    /// The inventory rows behind `items` (room and scan object ids), for the fly-in's old-room starts.
    var sources: [Item] = []
}

// MARK: - Header

/// The home's name and Change home (which also has Paste a Zillow link). Nothing else: no
/// tags, no size line (Lisa: less overstimulating).
struct NewHomeHeader: View {
    var current: NewHomeChoice.Current
    var onChange: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title
                Spacer(minLength: 8)
                change
            }
            VStack(alignment: .leading, spacing: 12) {
                title
                change
            }
        }
    }

    private var title: some View {
        Text(current.name)
            .pageTitle()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var change: some View {
        Button("Change home", action: onChange)
            .buttonStyle(.pill(.text, compact: true))
            .accessibilityLabel("Change new home")
            .accessibilityHint("Pick another home or paste a Zillow link")
    }
}

// MARK: - Stage

/// The dollhouse: the 3D home large on the page with the fly-in, the room chips, layout controls
/// and room shots. Solves the layouts off the main thread (cached in `LayoutCache`) and reports
/// the shown layout through `layout`, so Move's Pieces list (further down) shows the same one.
/// No room chips (Lisa: too many buttons): drag to orbit, pinch to zoom.
struct NewHomeStage: View {
    @Environment(MooveStore.self) private var store
    var name: String
    var plan: FloorPlan
    /// The saved `newHome` row; nil while the plan is only local.
    var home: NewHome?
    var furniture: Furniture
    /// The layout shown in 3D once the fly-in is ready, nil before.
    @Binding var layout: LayoutOption?
    /// One small "Demo" tag on the 3D when these aren't the user's things.
    var demoTag = false

    @State private var options: [LayoutOption] = []
    @State private var flyInToken = 0
    /// Each piece's scanned spot in its old room, where the fly-in starts it (nil: the pile).
    @State private var starts: FlyInStarts?
    /// False until the layouts are solved and the starts looked up, so the first fly-in starts
    /// from the right place.
    @State private var ready = false
    /// True while the layouts are being solved off the main thread.
    @State private var arranging = false

    /// One style (Lisa): "By function". `LayoutSolver` still solves the others for its tests.
    private static let style: LayoutSolver.Style = .byFunction
    private var option: LayoutOption? { options.first { $0.style == Self.style } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
            if !furniture.items.isEmpty {
                controls
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 20)
            }
        }
        .onChange(of: shownOption, initial: true) { _, new in layout = new }
        // Re-runs (and cancels the previous run) whenever the plan or the items change.
        .task(id: SolveKey(plan: plan, items: furniture.items)) { await solve() }
    }

    private func solve() async {
        let key = SolveKey(plan: plan, items: furniture.items)
        ready = false
        // Solve off the main thread (cached per plan + items) while the old-room starts load.
        let cached = LayoutCache.options(for: key)
        arranging = cached == nil
        let solving = cached == nil ? Task { await LayoutSolver.arrange(plan: key.plan, items: key.items) } : nil
        let loaded = await OldRoomStarts.load(furniture.sources, snapshot: store.snapshot, beside: plan.bounds)
        let solved: [LayoutOption]
        if let cached {
            solved = cached
        } else if let solving {
            solved = await withTaskCancellationHandler { await solving.value } onCancel: { solving.cancel() }
            guard !Task.isCancelled else { return }
            LayoutCache.store(solved, for: key)
        } else { return }
        guard !Task.isCancelled else { return }
        options = solved
        starts = loaded
        arranging = false
        ready = true
        flyInToken += 1
        await autoSave()
    }

    /// The layout shown, once the fly-in's starts are known.
    private var shownOption: LayoutOption? { ready ? option : nil }

    /// Placements shown in 3D: none until the fly-in's starts are known.
    private var shownPlacements: [Placement] { shownOption?.placements ?? [] }

    /// Saves the arranged layout to the home as soon as it's ready (and again whenever the plan or
    /// the items change it), so Review and the boxes always see the layout on screen. Skipped when
    /// the newest saved layout already matches, or while the home is only local.
    private func autoSave() async {
        guard let home, let option else { return }
        let last = store.snapshot.layouts(for: home.id).max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        if let last, last.placements == option.placements { return }
        _ = await store.saveLayout(option.placements, name: option.name, for: home)
    }

    // MARK: Stage

    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            FloorPlan3DView(plan: plan, focusRoom: nil, items: furniture.items, placements: shownPlacements, flyInToken: flyInToken,
                            flyInStarts: starts)
                .frame(height: 420)
                .overlay { if arranging { arrangingNotice } }
                .overlay(alignment: .topLeading) {
                    if demoTag { MonoTag(text: "Demo").padding(12).accessibilityHidden(true) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(arranging ? "Arranging your home" : stageLabel)
                .accessibilityHint("Drag to orbit, pinch to zoom, double-tap to reset.")
        }
        .padding(.horizontal, Theme.gutter)
    }

    /// Over the stage while the layouts solve.
    private var arrangingNotice: some View {
        ProgressView()
            .padding(16)
            .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    /// "3D view of Maple House: 6 rooms, 14 pieces placed".
    private var stageLabel: String {
        let n = shownPlacements.count
        return "3D view of \(name): \(plan.rooms.count) rooms, \(n) piece\(n == 1 ? "" : "s") placed\(demoTag ? ", demo items" : "")"
    }

    // MARK: Layout

    /// One button: Rearrange replays the arrangement flying in.
    private var controls: some View {
        Button { flyInToken += 1 } label: {
            Label("Rearrange", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.pill(.outline, compact: true))
        .accessibilityHint("Plays the pieces flying into place again")
        .accessibilityIdentifier("newHome.rearrange")
    }

}

/// VoiceOver wording for sizes the screens print in short form ("3.2 × 4.1 m", "82 m²").
enum Spoken {
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "3.2 by 4.1 meters"
    static func size(_ widthM: Double, _ depthM: Double) -> String {
        "\(number(widthM)) by \(number(depthM)) meters"
    }

    /// "82 square meters"
    static func area(_ m2: Double) -> String { "\(Int(m2.rounded())) square meters" }

    /// "4.5 cubic meters"
    static func volume(_ m3: Double) -> String { "\(number(m3)) cubic meters" }
}

#Preview("Picker") {
    NavigationStack { NewHomePicker { _, _, _ in } }.environment(MooveStore.preview())
}

#Preview("Stage") {
    ScrollView {
        NewHomeStage(
            name: DemoHouse.name, plan: DemoHouse.floorPlan, home: nil,
            furniture: Furniture(items: DemoFixtures.inventory(owner: "demo").items.map(LayoutItem.init), isDemo: true,
                                 sources: DemoFixtures.inventory(owner: "demo").items),
            layout: .constant(nil)
        )
    }
    .mooveScreen()
    .environment(MooveStore.preview())
}
