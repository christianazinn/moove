import SwiftUI
import MooveKit

/// The "New Home" tab: pick the new place (demo house or typed-in rooms),
/// then explore it in 3D with the kept items flown in and arranged (#14).
struct NewHomeView: View {
    @Environment(MooveStore.self) private var store
    @State private var showPicker = false
    /// Shown when the save to `newHome` failed (e.g. live backend not ready), so the demo still works.
    @State private var unsaved: Unsaved?

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
                    home: unsaved == nil ? store.newHome : nil, furniture: furniture
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
                    Button("Change") { showPicker = true }
                        .monoText(13, weight: .bold, maxScale: 1.4)
                        .accessibilityLabel("Change new home")
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

    /// Kept items from the inventory; the demo inventory's keeps if there are none yet.
    private var furniture: Furniture {
        let kept = store.items.filter { $0.disposition == .keep }
        if !kept.isEmpty { return Furniture(items: kept.map(LayoutItem.init), isDemo: false) }
        let demo = DemoFixtures.inventory(owner: "demo").items.filter { $0.disposition == .keep }
        return Furniture(items: demo.map(LayoutItem.init), isDemo: true)
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
                MooveWordmark(height: 24).padding(.bottom, 28)
                PageHeader(
                    eyebrow: "06 — New home",
                    title: "Where are you moving?",
                    lede: "Pick the new place so Moove can lay out everything you keep."
                )
                .padding(.bottom, 32)

                demoHouse.padding(.bottom, 44)

                ListHeader(title: "Or start from")
                NavigationLink {
                    ManualRoomsEditor { name, plan in onPick(name, .manual, plan) }
                } label: {
                    LedgerRow(title: "Enter room sizes", meta: "Type each room as width × depth", chevron: true) {
                        IconTile(systemName: "ruler")
                    }
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ListingImportView { name, source, plan in onPick(name, source, plan) }
                } label: {
                    LedgerRow(title: "Import from a listing", meta: "Zillow, Redfin or Realtor.com link", chevron: true) {
                        IconTile(systemName: "link")
                    }
                }
                .buttonStyle(.plain)
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
        .accessibilityLabel("\(DemoHouse.name), \(Self.summary(DemoHouse.floorPlan))")
        .accessibilityHint("Uses the demo house as your new home")
    }

    static func summary(_ plan: FloorPlan) -> String {
        let bedrooms = plan.rooms.filter { $0.kind == .bedroom }.count
        return "\(bedrooms) bed · \(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m²"
    }
}

struct Furniture: Equatable {
    var items: [LayoutItem]
    /// True when these are fixture items, not the user's.
    var isDemo: Bool
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

    @State private var focusRoom: String?
    @State private var options: [LayoutOption] = []
    @State private var style: LayoutSolver.Style = .byFunction
    @State private var flyInToken = 0
    @State private var savedStyle: LayoutSolver.Style?

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
                    stage.id(Self.stageID)
                    roomStrip.padding(.top, 10)
                    if !furniture.items.isEmpty {
                        controls
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, 36)
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
        .task(id: SolveKey(plan: plan, items: furniture.items)) { solve() }
    }

    private struct SolveKey: Equatable {
        var plan: FloorPlan
        var items: [LayoutItem]
    }

    private func solve() {
        options = LayoutSolver(plan: plan).solveAll(furniture.items)
        // Reopen on the layout the user saved last, if any.
        if let home, let last = store.snapshot.layouts(for: home.id).max(by: { $0.id < $1.id }),
           let match = LayoutSolver.Style.allCases.first(where: { $0.label == last.name }) {
            style = match
            savedStyle = match
        }
        flyInToken += 1
    }

    private func save() async {
        guard let home, let option else { return }
        if await store.saveLayout(option.placements, name: option.name, for: home) { savedStyle = option.style }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            MooveWordmark(height: 22).padding(.bottom, 24)
            PageHeader(eyebrow: "06 — New home", title: name)
            Text("\(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m² · \(option?.placements.count ?? 0) pieces")
                .monoMeta()
                .padding(.top, 10)
            HStack(spacing: 6) {
                MonoTag(text: sourceLabel)
                if !saved { MonoTag(text: "Not saved", tone: Theme.ochreInk) }
            }
            .padding(.top, 14)
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
            FloorPlan3DView(plan: plan, focusRoom: focusRoom, items: furniture.items, placements: option?.placements ?? [], flyInToken: flyInToken)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(focusRoom.map { "3D view of \(name), showing \($0)" } ?? "3D view of \(name)")
                .accessibilityHint("Drag to orbit, pinch to zoom, double-tap to reset")
            HStack(spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(focusRoom.map { "Showing \($0)" } ?? "Drag to orbit · pinch to zoom")
                    .monoText(13)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
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
                Text("\(option.unplaced.count) didn't fit in this layout")
                    .monoText(12.5)
                    .foregroundStyle(Theme.danger)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Pieces

    private struct PieceRow: Identifiable {
        var item: LayoutItem
        var room: String?
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
        let unplaced = (option?.unplaced ?? []).compactMap { byId[$0] }.map { PieceRow(item: $0, room: nil) }
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
                    Text("Items you keep fly in here once they're scanned.").monoMeta()
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
                    .accessibilityHint("Shows \(room) in 3D")
                } else {
                    LedgerRow(title: row.item.name, meta: Self.size(row.item), value: "Didn't fit", valueTint: Theme.danger) {
                        VoxelThumbnail(row.item)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if furniture.isDemo {
                Text("Nothing kept yet, so these are the demo inventory's keeps.")
                    .monoMeta()
                    .padding(.top, 14)
            }
        }
    }

    static func size(_ item: LayoutItem) -> String {
        String(format: "%.1f × %.1f m", item.widthM, item.depthM)
    }
}

#Preview("Picker") {
    NavigationStack { NewHomeView() }.environment(MooveStore.preview())
}

#Preview("Detail") {
    NavigationStack {
        NewHomeDetail(
            name: DemoHouse.name, source: .demo, plan: DemoHouse.floorPlan, home: nil,
            furniture: Furniture(items: DemoFixtures.inventory(owner: "demo").items.map(LayoutItem.init), isDemo: true)
        )
        .mooveScreen()
    }
    .environment(MooveStore.preview())
}
