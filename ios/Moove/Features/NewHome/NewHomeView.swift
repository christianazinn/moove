import SwiftUI
import MooveKit

/// The "New Home" tab: pick the new place (demo house or typed-in rooms),
/// then explore it in 3D with the kept items flown in and arranged (#14).
struct NewHomeView: View {
    @Environment(MooveStore.self) private var store
    @State private var showPicker = false
    @State private var showImport = false
    /// Shown when the save to `newHome` failed (e.g. live backend not ready), so the demo still works.
    @State private var unsaved: Unsaved?
    /// Which old rooms move (MooveKit `MovingRooms`): the user's picks, saved on this device.
    @State private var roomPicks: [UInt64: Bool] = MovingRooms.decode(UserDefaults.standard.stringArray(forKey: MovingRooms.defaultsKey))
    @State private var showRooms = false

    struct Unsaved: Equatable {
        var name: String
        var source: NewHomeSource
        var plan: FloorPlan
    }

    private var current: Unsaved? {
        if let unsaved { return unsaved }
        guard let home = store.newHome, let plan = home.floorPlan else { return nil }
        return Unsaved(name: home.name, source: home.source, plan: plan)
    }

    var body: some View {
        Group {
            if let current {
                NewHomeDetail(
                    name: current.name, source: current.source, plan: current.plan,
                    home: unsaved == nil ? store.newHome : nil, furniture: furniture,
                    movingFrom: movingChoices.isEmpty ? nil : MovingFrom(choices: movingChoices, itemCount: furniture.sources.count),
                    onImport: { showImport = true }, onChooseRooms: { showRooms = true }
                )
            } else {
                NewHomePicker(onPick: choose)
            }
        }
        .navigationTitle("New home")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .onChange(of: store.newHome?.id) { unsaved = nil }
        .toolbar {
            if current != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Change home") { showPicker = true }
                        .monoText(13, weight: .bold, maxScale: 1.4)
                        .accessibilityLabel("Change new home")
                }
            }
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                ListingImportView { name, source, plan in
                    showImport = false
                    choose(name, source, plan)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showImport = false }.monoText(13, maxScale: 1.4)
                    }
                }
            }
        }
        .sheet(isPresented: $showRooms) {
            NavigationStack {
                MovingRoomsPicker(choices: movingChoices, snapshot: store.visibleSnapshot,
                                  onToggle: { setPicks(MovingRooms.toggle($0, in: movingChoices, overrides: roomPicks)) },
                                  onAll: { setPicks(MovingRooms.setAll($0, in: movingChoices)) })
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showRooms = false }.monoText(13, weight: .bold, maxScale: 1.4)
                        }
                    }
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                NewHomePicker { name, source, plan in
                    showPicker = false
                    choose(name, source, plan)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showPicker = false }.monoText(13, maxScale: 1.4)
                    }
                }
            }
        }
    }

    private var keptItems: [Item] { store.visibleItems.filter { $0.disposition == .keep } }

    /// Every visible scanned room, newest first, with whether its kept items move.
    private var movingChoices: [MovingRooms.Choice] {
        MovingRooms.choices(store.visibleSnapshot, keptItems: keptItems, overrides: roomPicks)
    }

    private func setPicks(_ picks: [UInt64: Bool]) {
        roomPicks = MovingRooms.pruned(picks, rooms: store.snapshot.rooms)
        UserDefaults.standard.set(MovingRooms.encode(roomPicks), forKey: MovingRooms.defaultsKey)
    }

    /// Kept items from the rooms picked in "Moving from" (by default the newest scan of each
    /// room name, so re-scans don't bring a second bed) plus bought ones (#15); the demo's if
    /// nothing is kept or bought yet.
    private var furniture: Furniture {
        // Stored colors (`set_item_colors`); demo bedroom items without any use the demo room's.
        func layoutItem(_ item: Item) -> LayoutItem {
            item.colors == nil && DemoFixtures.isDemoItem(item) ? LayoutItem(item, colors: DemoFixtures.scanColors()) : LayoutItem(item)
        }
        let kept = keptItems
        let bought = store.snapshot.boughtLayoutItems
        if !kept.isEmpty || !bought.isEmpty {
            let moving = MovingRooms.items(kept, choices: movingChoices)
            return Furniture(items: moving.map(layoutItem) + bought, isDemo: false, sources: moving)
        }
        let demo = DemoFixtures.demo(owner: "demo")
        let demoKept = demo.items.filter { $0.disposition == .keep }
        return Furniture(items: demoKept.map(layoutItem) + demo.boughtLayoutItems, isDemo: true, sources: demoKept)
    }

    private func choose(_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) {
        // Show it right away; cleared when the saved row syncs back (onChange above).
        unsaved = Unsaved(name: name, source: source, plan: plan)
        Task { await store.createNewHome(name: name, source: source, plan: plan) }
    }
}

// MARK: - Picker

/// Where the new home comes from.
struct NewHomePicker: View {
    var onPick: (_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MooveWordmark(height: 36).padding(.top, 8).padding(.bottom, 32)
                PageHeader(eyebrow: "06 — New home", title: "Where are you moving?")
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
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .mooveScreen()
    }

    private var demoHouse: some View {
        Button { onPick(DemoHouse.name, .demo, DemoHouse.floorPlan) } label: {
            VStack(alignment: .leading, spacing: 18) {
                FloorPlanSketch(plan: DemoHouse.floorPlan)
                    .frame(height: 220)
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
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

/// The "Moving from" summary: the room picks and how many kept items they bring.
struct MovingFrom: Equatable {
    var choices: [MovingRooms.Choice]
    var itemCount: Int

    var noneSelected: Bool { !choices.contains { $0.included } }
}

/// Multi-select list of the scanned rooms whose kept items move to the new home.
struct MovingRoomsPicker: View {
    var choices: [MovingRooms.Choice]
    var snapshot: SyncSnapshot
    var onToggle: (UInt64) -> Void
    var onAll: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(eyebrow: "Moving from", title: "Which rooms are moving?")
                    .padding(.bottom, 12)
                Text("Only kept items from the rooms you pick go into the new home. Older scans of a room are left out by default.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                HStack(spacing: 10) {
                    Button("Select all") { onAll(true) }
                        .buttonStyle(.pill(.outline, compact: true))
                        .disabled(choices.allSatisfy { $0.included })
                    Button("None") { onAll(false) }
                        .buttonStyle(.pill(.outline, compact: true))
                        .disabled(!choices.contains { $0.included })
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)
                ForEach(choices) { c in
                    Button { onToggle(c.id) } label: {
                        LedgerRow(title: c.room.name, meta: meta(c), tag: snapshot.isDemoRoom(c.id) ? "Demo" : nil) {
                            Image(systemName: c.included ? "checkmark.square.fill" : "square")
                                .font(.system(size: 24))
                                .foregroundStyle(c.included ? Theme.accent : Theme.faint)
                                .frame(width: 44, height: 44)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(c.room.name), \(meta(c))")
                    .accessibilityAddTraits(c.included ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(c.included ? "Leaves this room's items behind" : "Moves this room's kept items")
                    .accessibilityIdentifier("movingRoom.\(c.id)")
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .mooveScreen()
        .navigationTitle("Moving from")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func meta(_ c: MovingRooms.Choice) -> String {
        let items = "\(c.itemCount) kept item\(c.itemCount == 1 ? "" : "s")"
        return [c.meta(), items].compactMap { $0 }.joined(separator: " · ")
    }
}

struct Furniture: Equatable {
    var items: [LayoutItem]
    /// True when these are fixture items, not the user's.
    var isDemo: Bool
    /// The inventory rows behind `items` (room and scan object ids), for the fly-in's old-room starts.
    var sources: [Item] = []
}

// MARK: - Detail

/// The dollhouse: a page header, the 3D home large on the page, layout controls,
/// and a ledger of the placed pieces. Tapping a room chip or a piece flies the camera to that room.
struct NewHomeDetail: View {
    @Environment(MooveStore.self) private var store
    var name: String
    var source: NewHomeSource
    var plan: FloorPlan
    /// The saved `newHome` row; nil while the plan is only local.
    var home: NewHome?
    var furniture: Furniture
    /// The rooms the furniture comes from (nil for the demo items).
    var movingFrom: MovingFrom? = nil
    /// Opens the listing import (paste a Zillow link) to replace this home.
    var onImport: () -> Void = {}
    /// Opens the "Moving from" room picker.
    var onChooseRooms: () -> Void = {}

    @State private var focusRoom: String?
    @State private var options: [LayoutOption] = []
    @State private var style: LayoutSolver.Style = .byFunction
    @State private var flyInToken = 0
    @State private var savedStyle: LayoutSolver.Style?
    /// Each piece's scanned spot in its old room, where the fly-in starts it (nil: the pile).
    @State private var starts: FlyInStarts?
    /// False until the starts are looked up, so the first fly-in starts from the right place.
    @State private var ready = false

    private static let stageID = "stage"

    private var saved: Bool { home != nil }
    private var option: LayoutOption? { options.first { $0.style == style } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    if let movingFrom {
                        movingFromRow(movingFrom)
                            .padding(.horizontal, Theme.gutter)
                            .padding(.bottom, 16)
                    }
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
                    pieces(proxy)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 44)
                }
                .padding(.bottom, 40)
            }
        }
        .background(Theme.bg)
        .onChange(of: plan) { focusRoom = nil }
        .task(id: SolveKey(plan: plan, items: furniture.items)) {
            ready = false
            solve()
            starts = await OldRoomStarts.load(furniture.sources, snapshot: store.snapshot, beside: plan.bounds)
            guard !Task.isCancelled else { return }
            ready = true
            flyInToken += 1
        }
    }

    private struct SolveKey: Equatable {
        var plan: FloorPlan
        var items: [LayoutItem]
    }

    /// Placements shown in 3D: none until the fly-in's starts are known.
    private var shownPlacements: [Placement] { ready ? option?.placements ?? [] : [] }

    private func solve() {
        // Lived-in pass: small things onto furniture tops, art and mirrors onto the walls
        // (PropPlacer's default wall top matches NewHomeScene's 1.1 m cut, the height every wall
        // has when it is nearest the camera; back walls rise higher but art stays below the cut).
        let placer = PropPlacer(plan: plan)
        options = LayoutSolver(plan: plan).solveAll(furniture.items).map { option in
            var option = option
            option.placements = placer.place(option.placements, items: furniture.items)
            return option
        }
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

    // MARK: Moving from

    /// "Moving from 2 rooms · 14 items ›", or the empty state when no room is picked.
    @ViewBuilder
    private func movingFromRow(_ m: MovingFrom) -> some View {
        if m.noneSelected {
            VStack(alignment: .leading, spacing: 10) {
                Text("No rooms selected").blockTitle()
                Text("Pick the scanned rooms whose kept items are moving.").monoMeta()
                Button("Choose rooms", action: onChooseRooms)
                    .buttonStyle(.pill(.primary, compact: true))
                    .accessibilityIdentifier("newHome.chooseRooms")
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ruled()
        } else {
            Button(action: onChooseRooms) {
                LedgerRow(title: MovingRooms.summary(m.choices, items: m.itemCount),
                          meta: m.choices.filter(\.included).map(\.room.name).joined(separator: " · "), chevron: true) {
                    IconTile(systemName: "shippingbox")
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose which scanned rooms move to the new home")
            .accessibilityIdentifier("newHome.movingFrom")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            MooveWordmark(height: 32).padding(.bottom, 28)
            PageHeader(eyebrow: "06 — New home", title: name)
            Text("\(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m²")
                .monoMeta()
                .padding(.top, 10)
                .accessibilityLabel("\(plan.rooms.count) rooms, \(Spoken.area(plan.totalAreaM2))")
            HStack(spacing: 6) {
                MonoTag(text: sourceLabel)
                if !saved { MonoTag(text: "Not saved", tone: Theme.ochreInk) }
            }
            .padding(.top, 14)
            Button(action: onImport) {
                Label(source == .zillow ? "Import another listing" : "Paste a Zillow link", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.outline))
            .padding(.top, 18)
            .accessibilityHint("Builds your new home from a Zillow, Redfin or Realtor.com listing")
        }
    }

    private var sourceLabel: String {
        switch source {
        case .demo: "Demo house"
        case .manual: "Entered by you"
        case .zillow: "From Zillow"
        }
    }

    // MARK: Stage

    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            FloorPlan3DView(plan: plan, focusRoom: focusRoom, items: furniture.items, placements: shownPlacements, flyInToken: flyInToken,
                            flyInStarts: starts)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(stageLabel)
                .accessibilityHint("Drag to orbit, pinch to zoom, double-tap to reset. Pick a room below to zoom in.")
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
        .padding(.horizontal, Theme.gutter)
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
            if let option, !option.unplaced.isEmpty {
                let stored = option.stored.count, misfit = option.unplaced.count - stored
                Text([misfit > 0 ? "\(misfit) didn't fit" : nil, stored > 0 ? "\(stored) extra bed\(stored == 1 ? "" : "s") to storage" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .monoText(13.5)
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Pieces

    private struct PieceRow: Identifiable {
        var item: LayoutItem
        var room: String?
        /// An extra bed kept out of the layout (more beds than bedrooms).
        var stored = false
        var id: UInt64 { item.id }
    }

    /// Placed pieces in plan room order, then the ones that didn't fit.
    private var pieceRows: [PieceRow] {
        let byId = Dictionary(furniture.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let order = Dictionary(plan.rooms.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let placed = (option?.placements ?? [])
            .compactMap { p in byId[p.itemId].map { PieceRow(item: $0, room: p.room) } }
            .sorted { a, b in
                let ra = order[a.room ?? ""] ?? .max, rb = order[b.room ?? ""] ?? .max
                return ra != rb ? ra < rb : a.item.name < b.item.name
            }
        let stored = Set(option?.stored ?? [])
        let unplaced = (option?.unplaced ?? []).compactMap { byId[$0] }.map { PieceRow(item: $0, room: nil, stored: stored.contains($0.id)) }
        return placed + unplaced
    }

    private func pieces(_ proxy: ScrollViewProxy) -> some View {
        let rows = pieceRows
        return VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Pieces", count: "\(rows.count)") {
                if furniture.isDemo { MonoTag(text: "Demo items") }
            }
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(furniture.items.isEmpty ? "Nothing to place yet" : "Arranging…").blockTitle()
                    Text("Kept items land here.").monoMeta()
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled()
            }
            ForEach(rows) { row in
                if let room = row.room {
                    Button {
                        focusRoom = room
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(Self.stageID, anchor: .top) }
                    } label: {
                        LedgerRow(title: row.item.name, meta: "\(Self.size(row.item)) · \(room)", chevron: true) {
                            VoxelThumbnail(row.item)
                        } trailing: {
                            if focusRoom == room { MonoTag(text: "In view", tone: Theme.accentStrong) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.item.name), \(Spoken.size(row.item.widthM, row.item.depthM)), \(room)\(focusRoom == room ? ", in view" : "")")
                    .accessibilityHint("Shows \(room) in 3D")
                } else {
                    LedgerRow(title: row.item.name, meta: Self.size(row.item), value: row.stored ? "Storage" : "Didn't fit",
                              valueTint: row.stored ? Theme.muted : Theme.danger) {
                        VoxelThumbnail(row.item)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.item.name), \(Spoken.size(row.item.widthM, row.item.depthM)), \(row.stored ? "extra bed, to storage" : "didn't fit")")
                }
            }
            if furniture.isDemo {
                Text("Nothing kept yet, so showing demo items.")
                    .monoMeta()
                    .padding(.top, 14)
            }
        }
    }

    static func size(_ item: LayoutItem) -> String {
        String(format: "%.1f × %.1f m", item.widthM, item.depthM)
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
    NavigationStack { NewHomeView() }.environment(MooveStore.preview())
}

#Preview("Detail") {
    NavigationStack {
        NewHomeDetail(
            name: DemoHouse.name, source: .demo, plan: DemoHouse.floorPlan, home: nil,
            furniture: Furniture(items: DemoFixtures.inventory(owner: "demo").items.map(LayoutItem.init), isDemo: true,
                                 sources: DemoFixtures.inventory(owner: "demo").items)
        )
        .mooveScreen()
    }
    .environment(MooveStore.preview())
}
