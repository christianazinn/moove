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
        .onChange(of: store.newHome?.id) { unsaved = nil }
        .toolbar {
            if current != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Change", systemImage: "house.and.flag") { showPicker = true }
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
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPicker = false } }
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
        List {
            Section {
                Button { onPick(DemoHouse.name, .demo, DemoHouse.floorPlan) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        FloorPlanSketch(plan: DemoHouse.floorPlan)
                            .frame(height: 170)
                        Text(DemoHouse.name).font(.headline)
                        Text(summary(DemoHouse.floorPlan)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Demo house")
            }
            Section {
                NavigationLink {
                    ManualRoomsEditor { name, plan in onPick(name, .manual, plan) }
                } label: {
                    Label("Enter room sizes", systemImage: "ruler")
                }
                Label {
                    VStack(alignment: .leading) {
                        Text("Import from Zillow")
                        Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "link")
                }
                .foregroundStyle(.secondary)
            } header: {
                Text("Your place")
            }
        }
        .navigationTitle("Pick your new home")
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
        FloorPlan3DView(plan: plan, focusRoom: focusRoom, items: furniture.items, placements: option?.placements ?? [], flyInToken: flyInToken)
            .ignoresSafeArea(edges: .horizontal)
            .overlay(alignment: .top) { header }
            .safeAreaInset(edge: .bottom) { controls }
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

    private var controls: some View {
        VStack(spacing: 0) {
            if !furniture.items.isEmpty {
                HStack(spacing: 10) {
                    Picker("Layout", selection: $style) {
                        ForEach(LayoutSolver.Style.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Fly in", systemImage: "arrow.triangle.turn.up.right.diamond") { flyInToken += 1 }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                    Button(savedStyle == style ? "Saved" : "Save") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!saved || savedStyle == style || option == nil)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                HStack {
                    if let option, !option.unplaced.isEmpty {
                        Label("\(option.unplaced.count) didn't fit", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    if furniture.isDemo { Text("Demo items: nothing kept yet") }
                    Spacer()
                    Text("\(option?.placements.count ?? 0) items")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 6)
            }
            roomStrip
        }
        .background(.bar)
    }

    private func save() async {
        guard let home, let option else { return }
        if await store.saveLayout(option.placements, name: option.name, for: home) { savedStyle = option.style }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text("\(plan.rooms.count) rooms · \(Int(plan.totalAreaM2.rounded())) m²").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(sourceLabel).font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
            if !saved {
                Image(systemName: "icloud.slash").foregroundStyle(.orange).accessibilityLabel("Not saved yet")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var sourceLabel: String {
        switch source {
        case .demo: "DEMO HOUSE"
        case .manual: "ENTERED BY YOU"
        case .zillow: "FROM ZILLOW"
        }
    }

    private var roomStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Whole home", systemImage: "house", selected: focusRoom == nil) { focusRoom = nil }
                ForEach(plan.rooms.filter { $0.kind != .hallway }) { room in
                    chip("\(room.name) · \(room.widthM, specifier: "%.1f")×\(room.depthM, specifier: "%.1f")", systemImage: nil, selected: focusRoom == room.name) {
                        focusRoom = room.name
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    private func chip(_ title: LocalizedStringKey, systemImage: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: Capsule())
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
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
