import SwiftUI
import MooveKit

/// The Move tab: one page, no segments (Lisa, #335). Top to bottom:
/// 1. **Your new home**: the name + Change home (or the picker until a home is chosen), the
///    Rooms button ("Rooms in this move", `RoomsSheet`), the 3D stage with the fly-in and Rearrange; the one "By function" layout
///    saves itself (`Features/NewHome/`).
/// 2. **Getting there**: the truck in 3D (tap it for full screen) with Load the truck, the box
///    cards by room with Print labels, and what's delivered (`Features/Pack/`).
/// 3. Folded: the placed pieces, closed by default.
///
/// The old "newhome" and "pack" screen keys land here (`TabGroup.segment(for:)`); "pack" scrolls
/// to Getting there.
struct MoveView: View {
    @Environment(MooveStore.self) private var store
    @AppStorage("moove.tab") private var tab = "move"
    @AppStorage("moove.pack.checked") private var checkedRaw = ""

    /// Shown when the save to `newHome` failed (e.g. live backend not ready), so the demo still works.
    @State private var unsaved: NewHomeChoice.Current?
    @State private var showPicker = false
    @State private var showRooms = false
    /// The layout on the stage, for Pieces.
    @State private var layout: LayoutOption?
    @State private var plan: PackingPlan?
    @State private var truckLoad: TruckLoad?
    @State private var openBox: MovingBox?
    /// Folded sections that are open (all closed by default).
    @State private var open: Set<Fold> = []

    enum Fold: String { case pieces }

    static let homeAnchor = "move.home"
    static let gettingThereAnchor = "move.gettingThere"

    private var current: NewHomeChoice.Current? {
        if let unsaved { return unsaved }
        guard let home = store.newHome, let plan = home.floorPlan else { return nil }
        return NewHomeChoice.Current(name: home.name, source: home.source, plan: plan)
    }

    var body: some View {
        let move = store.moveItems
        let input = PackInputs.current(store, move: move)
        let furniture = NewHomeChoice.furniture(move)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    home(furniture: furniture).id(Self.homeAnchor)
                    gettingThere(input).id(Self.gettingThereAnchor)
                    folds(furniture: furniture)
                }
                .padding(.bottom, 40)
            }
            .onAppear { jump(proxy) }
            .onChange(of: tab) { jump(proxy) }
        }
        .navigationTitle("Move")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .onChange(of: store.newHome?.id) { unsaved = nil }
        .onChange(of: input, initial: true) { _, new in
            let next = PackingPlanner.plan(items: new.items, destinationRoom: new.rooms, bought: new.bought)
            plan = next
            truckLoad = TruckLoader.load(plan: next, items: new.items)
        }
        .sheet(isPresented: $showRooms) { RoomsSheet() }
        .sheet(isPresented: $showPicker) { pickerSheet }
        .sheet(item: $openBox) { box in
            // Look the box up again so a re-plan while the sheet is open shows fresh contents.
            BoxDetailView(box: plan?.boxes.first { $0.id == box.id } ?? box, checked: checkedBinding, items: input.itemsById)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 1. Your new home

    private func home(furniture: Furniture) -> some View {
        VStack(alignment: .leading, spacing: 0) { homeContent(furniture: furniture) }
    }

    @ViewBuilder
    private func homeContent(furniture: Furniture) -> some View {
        if let current {
            NewHomeHeader(current: current, onChange: { showPicker = true })
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 20)
                .padding(.bottom, 16)
            roomsButton.padding(.bottom, 20)
            NewHomeStage(name: current.name, plan: current.plan, home: unsaved == nil ? store.newHome : nil,
                         furniture: furniture, layout: $layout, demoTag: furniture.isDemo)
        } else {
            NewHomePickerContent(onPick: choose)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
            roomsButton.padding(.top, 28)
        }
    }

    /// The Rooms button (it drives the layout, the boxes and the truck), once there are rooms.
    @ViewBuilder
    private var roomsButton: some View {
        if !store.snapshot.rooms.isEmpty {
            RoomsButton { showRooms = true }.padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: 2. Getting there

    private func gettingThere(_ input: PackInputs) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MoveHeading(title: "Getting there")
            if let plan {
                // The 3D house carries the Demo tag when there is one; else the truck does.
                TruckCard(plan: plan, load: truckLoad, items: input.items, demoTag: input.demo && current == nil)
                    .padding(.top, 4)
                BoxesSection(boxes: plan.boxes) { openBox = $0 }
                    .padding(.top, 56)
                if !plan.delivered.isEmpty {
                    DeliveredSection(pieces: plan.delivered)
                        .padding(.top, 56)
                }
            } else {
                LoadingLine(text: "Planning…").frame(maxWidth: .infinity).padding(.vertical, Theme.Space.section)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 72)
    }

    // MARK: 3. Folded

    private func folds(furniture: Furniture) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current { pieces(current, furniture: furniture) }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 72)
    }

    private func pieces(_ current: NewHomeChoice.Current, furniture: Furniture) -> some View {
        FoldSection(title: "Pieces", isOpen: binding(.pieces), id: "newHome.pieces") {
            PiecesList(plan: current.plan, furniture: furniture, layout: layout)
        }
    }

    private func binding(_ fold: Fold) -> Binding<Bool> {
        Binding(get: { open.contains(fold) }, set: { if $0 { open.insert(fold) } else { open.remove(fold) } })
    }

    // MARK: Sheets and actions

    private var pickerSheet: some View {
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

    private var checkedBinding: Binding<Set<String>> {
        Binding(get: { PackChecks.decode(checkedRaw) }, set: { checkedRaw = PackChecks.encode($0) })
    }

    private func choose(_ name: String, _ source: NewHomeSource, _ plan: FloorPlan) {
        // Show it right away; cleared when the saved row syncs back (onChange above).
        unsaved = NewHomeChoice.Current(name: name, source: source, plan: plan)
        Task { await store.createNewHome(name: name, source: source, plan: plan) }
    }

    /// A deep link to "pack" scrolls to Getting there, "newhome" to the top; then the key becomes
    /// "move" so coming back later doesn't jump again.
    private func jump(_ proxy: ScrollViewProxy) {
        guard tab == "pack" || tab == "newhome" else { return }
        let anchor = tab == "pack" ? Self.gettingThereAnchor : Self.homeAnchor
        tab = "move"
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))  // let the page lay out first
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
        }
    }
}

/// A section folded behind its header (title, chevron; no counts), closed until tapped.
struct FoldSection<Content: View>: View {
    var title: String
    @Binding var isOpen: Bool
    /// Names the header button (`<id>.fold`).
    var id: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(isOpen ? "Folds \(title) away" : "Shows \(title)")
            .accessibilityIdentifier("\(id).fold")
            if isOpen {
                content.transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).sansText(16).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // A hairline, lighter than a section rule.
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5) }
    }
}

/// A section heading on Move: the title alone, no rule, no count.
struct MoveHeading: View {
    var title: String

    var body: some View {
        Text(title)
            .listHeading()
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }
}

#Preview {
    NavigationStack { MoveView() }.environment(MooveStore.preview())
}
