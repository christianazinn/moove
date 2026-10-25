import SwiftUI
import MooveKit

/// The Move tab: one page, no segments (Lisa, #335). Top to bottom:
/// 1. **Your new home**: the header (or the picker until a home is chosen), the shared "Moving
///    from" row (or the demo notice when nothing is kept), the 3D stage with the fly-in, layout
///    style + Save layout, and room shots (`Features/NewHome/`).
/// 2. **Getting there**: the truck card with the loaded truck in 3D, the box cards by room with
///    Print labels, and what's delivered (`Features/Pack/`).
/// 3. Folded: furniture notes, supplies, schedule and the placed pieces, closed by default.
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
    @State private var showImport = false
    @State private var showRooms = false
    /// The layout on the stage, for Pieces.
    @State private var layout: LayoutOption?
    @State private var plan: PackingPlan?
    @State private var truckLoad: TruckLoad?
    @State private var openBox: MovingBox?
    /// Folded sections that are open (all closed by default).
    @State private var open: Set<Fold> = []

    enum Fold: String { case furniture, supplies, schedule, pieces }

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
                    home(furniture: furniture, input: input).id(Self.homeAnchor)
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
        .sheet(isPresented: $showImport) { importSheet }
        .sheet(isPresented: $showRooms) { MovingRoomsSheet { showRooms = false } }
        .sheet(isPresented: $showPicker) { pickerSheet }
        .sheet(item: $openBox) { box in
            // Look the box up again so a re-plan while the sheet is open shows fresh contents.
            BoxDetailView(box: plan?.boxes.first { $0.id == box.id } ?? box, checked: checkedBinding, items: input.itemsById)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 1. Your new home

    private func home(furniture: Furniture, input: PackInputs) -> some View {
        VStack(alignment: .leading, spacing: 0) { homeContent(furniture: furniture, input: input) }
    }

    @ViewBuilder
    private func homeContent(furniture: Furniture, input: PackInputs) -> some View {
        if let current {
            NewHomeHeader(current: current, saved: unsaved == nil && store.newHome != nil,
                          onChange: { showPicker = true }, onImport: { showImport = true })
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 28)
            movingFrom(input).padding(.bottom, 16)
            NewHomeStage(name: current.name, plan: current.plan, home: unsaved == nil ? store.newHome : nil,
                         furniture: furniture, layout: $layout)
        } else {
            NewHomePickerContent(onPick: choose)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
            movingFrom(input).padding(.top, 28)
        }
    }

    /// One shared "Moving from" row (it drives the layout, the boxes and the truck), or the demo
    /// notice when nothing is kept yet.
    @ViewBuilder
    private func movingFrom(_ input: PackInputs) -> some View {
        Group {
            if input.demo {
                PackDemoNotice()
            } else if !input.choices.isEmpty {
                MovingFromRow(movingFrom: MovingFrom(choices: input.choices, itemCount: input.items.count), idPrefix: "pack") {
                    showRooms = true
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: 2. Getting there

    private func gettingThere(_ input: PackInputs) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Getting there") {
                if input.demo { MonoTag(text: "Demo items", tone: Theme.ochreInk) }
            }
            if let plan {
                TruckCard(plan: plan, load: truckLoad, items: input.items)
                    .padding(.top, Theme.Space.l)
                BoxesSection(boxes: plan.boxes) { openBox = $0 }
                    .padding(.top, Theme.Space.section)
                if !plan.delivered.isEmpty {
                    DeliveredSection(pieces: plan.delivered)
                        .padding(.top, Theme.Space.section)
                }
            } else {
                LoadingLine(text: "Planning…").frame(maxWidth: .infinity).padding(.vertical, Theme.Space.section)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 48)
    }

    // MARK: 3. Folded

    private func folds(furniture: Furniture) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let plan, !plan.furniture.isEmpty {
                FoldSection(title: "Furniture notes", isOpen: binding(.furniture), id: "pack.furniture") {
                    FurnitureNotesList(notes: plan.furniture)
                }
            }
            if let plan, !plan.supplies.isEmpty {
                FoldSection(title: "Supplies", isOpen: binding(.supplies), id: "pack.supplies") {
                    SuppliesList(lines: plan.supplies)
                }
            }
            if let plan, !plan.schedule.isEmpty {
                FoldSection(title: "Schedule", isOpen: binding(.schedule), id: "pack.schedule") {
                    ScheduleList(steps: plan.schedule, boxes: plan.boxes) { openBox = $0 }
                }
            }
            if let current { pieces(current, furniture: furniture) }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 48)
    }

    private func pieces(_ current: NewHomeChoice.Current, furniture: Furniture) -> some View {
        FoldSection(title: "Pieces", tag: furniture.isDemo ? "Demo items" : nil, isOpen: binding(.pieces), id: "newHome.pieces") {
            PiecesList(plan: current.plan, furniture: furniture, layout: layout)
        }
    }

    private func binding(_ fold: Fold) -> Binding<Bool> {
        Binding(get: { open.contains(fold) }, set: { if $0 { open.insert(fold) } else { open.remove(fold) } })
    }

    // MARK: Sheets and actions

    private var importSheet: some View {
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
    var tag: String? = nil
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
            Text(title).listHeading()
            if let tag { MonoTag(text: tag) }
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
        .ruled()
    }
}

#Preview {
    NavigationStack { MoveView() }.environment(MooveStore.preview())
}
