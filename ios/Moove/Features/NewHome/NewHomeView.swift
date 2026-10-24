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
                        .font(.mono(13, weight: .bold))
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
                        Button("Cancel") { showPicker = false }.font(.mono(13))
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

/// Where the new home comes from.
struct NewHomePicker: View {
    var onPick: (_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("New home").eyebrow().padding(.bottom, 10)
                Text("Where are you moving?")
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.bottom, 6)
                Text("Pick the new place so Moove can lay out what you keep.")
                    .monoMeta()
                    .padding(.bottom, 24)

                Button { onPick(DemoHouse.name, .demo, DemoHouse.floorPlan) } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        FloorPlanSketch(plan: DemoHouse.floorPlan)
                            .frame(height: 190)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(DemoHouse.name).blockTitle()
                                Text(summary(DemoHouse.floorPlan)).monoMeta()
                            }
                            Spacer()
                            Text("Use").font(.mono(13, weight: .bold))
                                .padding(.horizontal, 16).frame(minHeight: 34)
                                .foregroundStyle(Theme.accentInk)
                                .background(Capsule().fill(Theme.accent))
                        }
                    }
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ruled()

                NavigationLink {
                    ManualRoomsEditor { name, plan in onPick(name, .manual, plan) }
                } label: {
                    row(icon: "ruler", title: "Enter room sizes", meta: "Type each room as width × depth", enabled: true)
                }
                .buttonStyle(.plain)

                row(icon: "link", title: "Import from a listing", meta: "Zillow, Redfin · coming soon", enabled: false)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Pick your new home")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
    }

    private func row(icon: String, title: String, meta: String, enabled: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .light))
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).blockTitle()
                Text(meta).monoMeta()
            }
            Spacer()
            if enabled { Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Theme.faint) }
        }
        .padding(.vertical, 16)
        .opacity(enabled ? 1 : 0.5)
        .contentShape(Rectangle())
        .ruled()
    }

    private func summary(_ plan: FloorPlan) -> String {
        let bedrooms = plan.rooms.filter { $0.kind == .bedroom }.count
        return "\(bedrooms) bed · \(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m²"
    }
}

struct Furniture: Equatable {
    var items: [LayoutItem]
    /// True when these are fixture items, not the user's.
    var isDemo: Bool
}

/// 3D view with the kept items arranged in it, a layout picker, and a strip of
/// room chips; tapping a chip flies the camera there.
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

    private var saved: Bool { home != nil }
    private var option: LayoutOption? { options.first { $0.style == style } }

    var body: some View {
        VStack(spacing: 0) {
            header
            FloorPlan3DView(plan: plan, focusRoom: focusRoom, items: furniture.items, placements: option?.placements ?? [], flyInToken: flyInToken)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                .padding(.horizontal, 16)
            controls
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text("\(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m² · \(option?.placements.count ?? 0) pieces")
                    .monoMeta()
            }
            Spacer()
            if !saved { MonoTag(text: "Not saved", tone: Theme.ochre) }
            MonoTag(text: sourceLabel)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var sourceLabel: String {
        switch source {
        case .demo: "Demo house"
        case .manual: "Entered by you"
        case .zillow: "From Zillow"
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !furniture.items.isEmpty {
                Text("Layout").eyebrow().padding(.top, 16).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        PillPicker(options: LayoutSolver.Style.allCases, selection: $style) { $0.label }
                    }
                    Button { flyInToken += 1 } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.pill(.outline, compact: true))
                        .accessibilityLabel("Play fly-in again")
                    Button(savedStyle == style ? "Saved" : "Save") { Task { await save() } }
                        .buttonStyle(.pill(.primary, compact: true))
                        .disabled(!saved || savedStyle == style || option == nil)
                }
                HStack(spacing: 10) {
                    if let option, !option.unplaced.isEmpty {
                        Text("\(option.unplaced.count) didn't fit").font(.mono(12)).foregroundStyle(Theme.danger)
                    }
                    if furniture.isDemo { Text("Demo items · nothing kept yet").font(.mono(12)).foregroundStyle(Theme.faint) }
                }
                .padding(.top, 8)
            }
            Text("Rooms").eyebrow().padding(.top, 16).padding(.bottom, 8)
            roomStrip
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func save() async {
        guard let home, let option else { return }
        if await store.saveLayout(option.placements, name: option.name, for: home) { savedStyle = option.style }
    }

    private var roomStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Whole home", meta: nil, selected: focusRoom == nil) { focusRoom = nil }
                ForEach(plan.rooms.filter { $0.kind != .hallway }) { room in
                    chip(room.name, meta: String(format: "%.1f×%.1f", room.widthM, room.depthM), selected: focusRoom == room.name) {
                        focusRoom = room.name
                    }
                }
            }
        }
    }

    private func chip(_ title: String, meta: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.mono(12.5, weight: selected ? .bold : .regular))
                if let meta { Text(meta).font(.mono(11.5)).foregroundStyle(selected ? Theme.accentInk.opacity(0.75) : Theme.faint) }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(selected ? Theme.accentInk : Theme.text)
            .background(Capsule().fill(selected ? Theme.accent : Theme.surface))
        }
        .buttonStyle(.plain)
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
    }
    .environment(MooveStore.preview())
}
