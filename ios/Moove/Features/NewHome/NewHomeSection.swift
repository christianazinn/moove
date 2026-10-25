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

    /// Kept items from the rooms picked in "Moving from" (by default the newest scan of each
    /// room name, so re-scans don't bring a second bed) plus bought ones (#15); the demo's if
    /// nothing is kept or bought yet.
    @MainActor static func furniture(_ store: MooveStore) -> Furniture {
        // Stored colors (`set_item_colors`); demo bedroom items without any use the demo room's.
        func layoutItem(_ item: Item) -> LayoutItem {
            item.colors == nil && DemoFixtures.isDemoItem(item) ? LayoutItem(item, colors: DemoFixtures.scanColors()) : LayoutItem(item)
        }
        let bought = store.snapshot.boughtLayoutItems
        if !store.keptItems.isEmpty || !bought.isEmpty {
            let moving = store.movingItems
            return Furniture(items: moving.map(layoutItem) + bought, isDemo: false, sources: moving)
        }
        let demo = DemoFixtures.demo(owner: "demo")
        let demoKept = demo.items.filter { $0.disposition == .keep }
        return Furniture(items: demoKept.map(layoutItem) + demo.boughtLayoutItems, isDemo: true, sources: demoKept)
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

/// The picker's blocks: Paste a Zillow link, the demo house, or room sizes. Move shows them at
/// the top of the page until a home is chosen.
struct NewHomePickerContent: View {
    var onPick: (_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MooveWordmark(height: 36).padding(.top, 8).padding(.bottom, 32)
            PageHeader(title: "Where are you moving?")
            .padding(.bottom, 24)

            NavigationLink {
                ListingImportView { name, source, plan in onPick(name, source, plan) }
            } label: {
                Label("Paste a Zillow link", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .accessibilityHint("Zillow, Redfin or Realtor.com")
            .padding(.bottom, 36)

            demoHouse.padding(.bottom, 44)

            ListHeader(title: "Or start from")
            NavigationLink {
                ManualRoomsEditor { name, plan in onPick(name, .manual, plan) }
            } label: {
                LedgerRow(title: "Enter room sizes", meta: "Width × depth", chevron: true) {
                    IconTile(systemName: "ruler")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enter room sizes, width by depth")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DemoHouse.name).blockTitle()
                        Text(Self.summary(DemoHouse.floorPlan)).monoMeta()
                    }
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

/// The home's name, size and source, with Change home and Paste a Zillow link.
struct NewHomeHeader: View {
    var current: NewHomeChoice.Current
    /// False while the pick is only local (the `newHome` save hasn't synced).
    var saved: Bool
    var onChange: () -> Void
    var onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MooveWordmark(height: 32).padding(.bottom, 28)
            PageHeader(title: current.name)
            Text("\(current.plan.rooms.count) rooms · \(Int(current.plan.totalAreaM2.rounded())) m²")
                .monoMeta()
                .padding(.top, 10)
                .accessibilityLabel("\(current.plan.rooms.count) rooms, \(Spoken.area(current.plan.totalAreaM2))")
            HStack(spacing: 6) {
                MonoTag(text: sourceLabel)
                if !saved { MonoTag(text: "Not saved", tone: Theme.ochreInk) }
            }
            .padding(.top, 14)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
            .padding(.top, 18)
        }
    }

    @ViewBuilder private var buttons: some View {
        Button("Change home", action: onChange)
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityLabel("Change new home")
        Button(action: onImport) {
            Label(current.source == .zillow ? "Import another listing" : "Paste a Zillow link", systemImage: "link")
        }
        .buttonStyle(.pill(.outline, compact: true))
        .accessibilityHint("Builds your new home from a Zillow, Redfin or Realtor.com listing")
    }

    private var sourceLabel: String {
        switch current.source {
        case .demo: "Demo house"
        case .manual: "Entered by you"
        case .zillow: "From Zillow"
        }
    }
}

// MARK: - Stage

/// The dollhouse: the 3D home large on the page with the fly-in, the room chips, layout controls
/// and room shots. Solves the layouts off the main thread (cached in `LayoutCache`) and reports
/// the shown layout through `layout`, so Move's Pieces list (further down) shows the same one.
/// Tapping a room chip flies the camera to that room.
struct NewHomeStage: View {
    @Environment(MooveStore.self) private var store
    var name: String
    var plan: FloorPlan
    /// The saved `newHome` row; nil while the plan is only local.
    var home: NewHome?
    var furniture: Furniture
    @Binding var focusRoom: String?
    /// The layout shown in 3D once the fly-in is ready, nil before.
    @Binding var layout: LayoutOption?

    @State private var options: [LayoutOption] = []
    @State private var style: LayoutSolver.Style = .byFunction
    @State private var flyInToken = 0
    @State private var savedStyle: LayoutSolver.Style?
    /// Each piece's scanned spot in its old room, where the fly-in starts it (nil: the pile).
    @State private var starts: FlyInStarts?
    /// False until the layouts are solved and the starts looked up, so the first fly-in starts
    /// from the right place.
    @State private var ready = false
    /// True while the layouts are being solved off the main thread.
    @State private var arranging = false

    /// Scroll target for "show this room" (Move's Pieces rows).
    static let stageID = "newhome.stage"

    private var saved: Bool { home != nil }
    private var option: LayoutOption? { options.first { $0.style == style } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage.id(Self.stageID)
            roomStrip.padding(.top, 10)
            if !furniture.items.isEmpty {
                controls
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 36)
            }
            if !shownPlacements.isEmpty {
                RoomShotsSection(homeName: name, plan: plan, items: furniture.items, placements: shownPlacements, ready: ready)
                    .padding(.top, 44)
            }
        }
        .onChange(of: plan) { focusRoom = nil }
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
        apply(solved)
        starts = loaded
        arranging = false
        ready = true
        flyInToken += 1
    }

    /// The layout shown, once the fly-in's starts are known.
    private var shownOption: LayoutOption? { ready ? option : nil }

    /// Placements shown in 3D: none until the fly-in's starts are known.
    private var shownPlacements: [Placement] { shownOption?.placements ?? [] }

    /// Shows solved layouts (MooveKit `LayoutSolver.arrangeAll`: every style with the lived-in
    /// pass, small things on furniture tops and art on the walls under the 1.1 m cut).
    private func apply(_ solved: [LayoutOption]) {
        options = solved
        // Reopen on the layout the user saved last, if any.
        if let home, let last = store.snapshot.layouts(for: home.id).max(by: { $0.id < $1.id }),
           let match = LayoutSolver.Style.allCases.first(where: { $0.label == last.name }) {
            style = match
            savedStyle = match
        }
    }

    private func save() async {
        guard let home, let option else { return }
        if await store.saveLayout(option.placements, name: option.name, for: home) { savedStyle = option.style }
    }

    // MARK: Stage

    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            FloorPlan3DView(plan: plan, focusRoom: focusRoom, items: furniture.items, placements: shownPlacements, flyInToken: flyInToken,
                            flyInStarts: starts)
                .frame(height: 420)
                .overlay { if arranging { arrangingNotice } }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(arranging ? "Arranging your home" : stageLabel)
                .accessibilityHint("Drag to orbit, pinch to zoom, double-tap to reset. Pick a room below to zoom in.")
            stageCaption
        }
        .padding(.horizontal, Theme.gutter)
    }

    private var stageCaption: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(focusRoom.map { "Showing \($0)" } ?? (starts == nil ? "Drag to orbit · pinch to zoom" : "Flying in from your scanned room · drag to orbit"))
                .monoText(13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if focusRoom != nil {
                Button("Whole home") { focusRoom = nil }
                    .buttonStyle(.pill(.text, compact: true))
            }
        }
        .frame(minHeight: 44)
        .padding(.top, 6)
    }

    /// Over the stage while the layouts solve.
    private var arrangingNotice: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Arranging your home…").monoText(13, weight: .bold).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityHidden(true)
        .transition(.opacity)
    }

    /// "3D view of Maple House: 6 rooms, 14 pieces placed, showing Bedroom".
    private var stageLabel: String {
        let n = shownPlacements.count
        var text = "3D view of \(name): \(plan.rooms.count) rooms, \(n) piece\(n == 1 ? "" : "s") placed"
        if let focusRoom { text += ", showing \(focusRoom)" }
        return text
    }

    private var roomStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ChoiceChip(title: "Whole home", selected: focusRoom == nil) { focusRoom = nil }
                ForEach(plan.rooms.filter { $0.kind != .hallway }) { room in
                    ChoiceChip(
                        title: room.name,
                        meta: String(format: "%.1f×%.1f", room.widthM, room.depthM),
                        selected: focusRoom == room.name
                    ) { focusRoom = room.name }
                    .accessibilityLabel("\(room.name), \(Spoken.size(room.widthM, room.depthM))")
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: Layout

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The Pieces list is folded at the bottom of Move, so the placed count stays here.
            ListHeader(title: "Layout", count: option.map { "\($0.placements.count) placed" })
            ScrollView(.horizontal, showsIndicators: false) {
                PillPicker(options: LayoutSolver.Style.allCases, selection: $style) { $0.label }
            }
            .padding(.top, 16)
            HStack(spacing: 10) {
                Button { flyInToken += 1 } label: {
                    Label("Fly in", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityLabel("Play fly-in again")
                Button(savedStyle == style ? "Saved" : "Save layout") { Task { await save() } }
                    .buttonStyle(.pill(.primary, compact: true))
                    .disabled(!saved || savedStyle == style || option == nil)
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            if let option, !option.unplaced.isEmpty { unplacedNote(option) }
        }
    }

    private func unplacedNote(_ option: LayoutOption) -> some View {
        let stored = option.stored.count, misfit = option.unplaced.count - stored
        return Text([misfit > 0 ? "\(misfit) didn't fit" : nil, stored > 0 ? "\(stored) extra bed\(stored == 1 ? "" : "s") to storage" : nil]
            .compactMap { $0 }.joined(separator: " · "))
            .monoText(13.5)
            .foregroundStyle(Theme.danger)
            .padding(.top, 8)
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
            focusRoom: .constant(nil), layout: .constant(nil)
        )
    }
    .mooveScreen()
    .environment(MooveStore.preview())
}
