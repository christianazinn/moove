import SwiftUI
import MooveKit

/// The user's things as a tabbed binder (Lisa, #335): one page per function hall (MooveKit
/// `FunctionHall`) behind a colored index tab, each page a wall of wooden shelves the items
/// stand on (`InventoryBinder.shelves`). Tap an item for its placard (`MuseumLabel`).
/// Room-level actions (share, 3D, hide, add) sit on the Rooms strip on top.
struct InventoryView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sharing: Room?
    @State private var showJoin = false
    @State private var showHidden = false
    /// Room id → (scan object id → the scanner's category), from each room's scan geometry,
    /// for the "was: storage" marker on items a later pass renamed (#267).
    @State private var scannedCategories: [UInt64: [String: String]] = [:]
    /// Fix-it rename from an exhibit's long-press menu.
    @State private var renaming: Item?
    @State private var newName = ""
    /// Exhibit whose "Delete item" is waiting on the confirm.
    @State private var deleting: Item?
    /// Add item (by hand) sheet, opened on this room.
    @State private var addingTo: Room?
    /// Rename room alert (room chip ⋯), open on this room.
    @State private var renamingRoom: Room?
    /// Item detail, pushed by tapping an exhibit.
    @State private var opened: UInt64?
    /// The binder page picked (a tab, a swipe); falls back to the first page.
    @State private var page: FunctionHall?
    /// Which way the last page turn went, for the slide.
    @State private var turnedForward = true
    /// A horizontal drag in progress on the page.
    @State private var dragX: CGFloat = 0
    /// The item whose placard sheet is up, and what to do once it closes.
    @State private var placard: PlacardRef?
    @State private var afterPlacard: AfterPlacard?
    /// Placard story being edited.
    @State private var editingStory: Item?
    /// The user's own placard stories (item id → line), on this device only.
    @AppStorage(ItemStories.defaultsKey) private var storiesJSON = ""
    /// Rooms Inventory is narrowed to (tap a room card); empty shows every room.
    @AppStorage(InventoryFocus.defaultsKey) private var focusJSON = ""

    var body: some View {
        let rooms = store.snapshot.roomsNewestFirst(store.visibleRooms)
        let stories = ItemStories.decode(storiesJSON)
        let focus = InventoryFocus.active(InventoryFocus.decode(focusJSON), rooms: rooms)
        let shown = InventoryFocus.items(store.visibleItems, focus: focus)
        screen(rooms: rooms, stories: stories, focus: focus, shown: shown)
            .sheet(item: $placard, onDismiss: runAfterPlacard) { placardSheet($0, shown: shown, stories: stories) }
            // A piece added by hand or by photo: turn to its page so it's in view.
            .onChange(of: store.visibleItems.map(\.id)) { old, new in itemsChanged(from: old, to: new) }
    }

    private func screen(rooms: [Room], stories: [UInt64: String], focus: Set<UInt64>, shown: [Item]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if store.visibleItems.isEmpty {
                    emptyState.padding(.top, 32)
                } else {
                    totals(shown).padding(.top, 24)
                }
                if !rooms.isEmpty {
                    roomsStrip(rooms, focus: focus).padding(.top, 24)
                }
                sweepNotes(rooms)
                binderSection(shown, stories: stories)
                hiddenRoomsFooter.padding(.top, Theme.Space.section)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Room.self) { RoomDetailView(room: $0) }
        .navigationDestination(item: $opened) { ItemDetailView(itemId: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Join a room", systemImage: "person.2.badge.plus") { showJoin = true }
            }
            if let newest = rooms.first {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add item", systemImage: "plus") { addingTo = newest }
                        .accessibilityIdentifier("inventory.addItem")
                }
            }
        }
        .sheet(item: $addingTo) { room in AddItemView(rooms: rooms, roomId: room.id) }
        .sheet(item: $sharing) { ShareRoomView(room: $0) }
        .roomRenameAlert($renamingRoom)
        .sheet(isPresented: $showJoin) { JoinRoomView() }
        .sheet(item: $editingStory) { item in
            StoryEditor(item: item, current: stories[item.id]) { text in
                storiesJSON = ItemStories.setting(text, for: item.id, in: storiesJSON)
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { item in
            TextField("Name", text: $newName)
            Button("Save") { Task { await store.renameItem(item, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deleting?.name ?? "item")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { item in
            Button("Delete", role: .destructive) { Task { await store.deleteItem(item) } }
                .accessibilityIdentifier("inventory.confirmDelete")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from this room for everyone sharing it. This can't be undone.")
        }
        #if DEBUG
        // Screenshot/UI-test hook: MOOVE_OPEN_SHEET=share|join.
        .task {
            let sheet = ProcessInfo.processInfo.environment["MOOVE_OPEN_SHEET"]
            if sheet == "join" { showJoin = true }
            if sheet == "share" {
                for _ in 0..<20 where store.snapshot.rooms.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                sharing = store.snapshot.rooms.first(where: isMine)
            }
        }
        #endif
        .task(id: geometryKey) { await loadScannedCategories() }
        .mooveScreen()
        .animation(.default, value: store.items)
        .animation(.default, value: store.hiddenRoomIds)
    }

    @ViewBuilder
    private func placardSheet(_ ref: PlacardRef, shown: [Item], stories: [UInt64: String]) -> some View {
        if let item = store.visibleItems.first(where: { $0.id == ref.id }) {
            let hall = FunctionHall.of(item)
            let hallItems = shown.filter { FunctionHall.of($0) == hall }
            let isTop = hallItems.count > 1 && MuseumLabel.topPiece(hallItems) == item.id
            let info = exhibitInfo(item, story: stories[item.id], isTop: isTop, compCounts: store.snapshot.compCounts)
            PlacardSheet(info: info,
                         onEditStory: { closePlacard(then: .story(item)) },
                         onOpen: { closePlacard(then: .open(item.id)) },
                         onRename: { closePlacard(then: .rename(item)) },
                         onDelete: { closePlacard(then: .delete(item)) })
        } else {
            // Removed while open ("Not a real item"): nothing to show.
            Color.clear.onAppear { placard = nil }
        }
    }

    private func itemsChanged(from old: [UInt64], to new: [UInt64]) {
        guard !old.isEmpty else { return }
        let added = Set(new).subtracting(old)
        let picked = store.visibleItems.first { added.contains($0.id) && ($0.origin == .manual || $0.origin == .photo) }
        if let picked { turn(to: FunctionHall.of(picked), forward: true) }
    }

    // MARK: Rooms strip

    /// One chip per visible room, newest scan first, carrying the room's actions.
    private func roomsStrip(_ rooms: [Room], focus: Set<UInt64>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(focus.isEmpty ? "Rooms · tap to focus" : "Showing \(focus.count) of \(rooms.count) rooms")
                    .eyebrow()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !focus.isEmpty {
                    Button("Show all rooms") { focusJSON = "" }
                        .monoText(13, weight: .bold, maxScale: 1.4)
                        .foregroundStyle(Theme.accentInk)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("inventory.showAllRooms")
                }
            }
            // Wraps rather than scrolls sideways, so every room's actions stay on screen.
            ChipFlow(spacing: 10) {
                ForEach(rooms) { roomChip($0, focus: focus) }
            }
        }
    }

    private func roomChip(_ room: Room, focus: Set<UInt64>) -> some View {
        let shared = !isMine(room)
        let count = store.visibleItems.filter { $0.roomId == room.id }.count
        let focused = focus.contains(room.id)
        return VStack(alignment: .leading, spacing: 6) {
            // Tapping the name narrows Inventory to this room (and any others picked)
            Button {
                focusJSON = InventoryFocus.encode(InventoryFocus.toggling(room.id, in: focus))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(room.name).blockTitle().lineLimit(2)
                        if focused {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentStrong).accessibilityHidden(true)
                        }
                    }
                    roomMeta(room, shared: shared, count: count)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(room.name), \(count) items")
            .accessibilityValue(focused ? "Shown" : focus.isEmpty ? "" : "Not shown")
            .accessibilityHint(focused ? "Stops focusing on this room" : "Shows only the rooms you pick")
            .accessibilityIdentifier("inventory.focus.\(room.id)")
            HStack(spacing: 6) {
                if !shared {
                    Button { sharing = room } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .buttonStyle(.pill(.outline, compact: true))
                    .accessibilityLabel("Share \(room.name)")
                }
                NavigationLink(value: room) {
                    Label("3D", systemImage: "cube.transparent")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityLabel("View room in 3D")
                Menu {
                    Button("Add item here", systemImage: "plus") { addingTo = room }
                    if !shared {
                        Button("Rename room", systemImage: "pencil") { renamingRoom = room }
                            .accessibilityIdentifier("inventory.renameRoom.\(room.id)")
                    }
                    hideButton(room)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.muted)
                .accessibilityLabel("More for \(room.name)")
            }
            .fixedSize()
        }
        .padding(12)
        .frame(minWidth: 180, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(focused ? Theme.accentStrong : .clear, lineWidth: 2))
        .opacity(focus.isEmpty || focused ? 1 : 0.55)
        .contextMenu { hideButton(room) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Hide room") { store.setRoom(room.id, hidden: true) }
        .accessibilityAction(named: "Rename room") { if !shared { renamingRoom = room } }
    }

    /// Room photo sweep (#92): the worker is naming "other" boxes and adding missed items.
    /// Hidden after 5 min so a scan whose worker was down doesn't spin forever.
    @ViewBuilder
    private func sweepNotes(_ rooms: [Room]) -> some View {
        let sweeping = rooms.filter { room in
            guard let scan = store.snapshot.latestScan(ofRoom: room.id) else { return false }
            return scan.sweepStatus?.isActive == true && scan.createdAt > .now.addingTimeInterval(-300)
        }
        if !sweeping.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Identifying items from room photos…").monoMeta()
            }
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Binder

    @ViewBuilder
    private func binderSection(_ shown: [Item], stories: [UInt64: String]) -> some View {
        let halls = FunctionHall.halls(shown)
        if !halls.isEmpty {
            binder(halls, stories: stories).padding(.top, 28)
        }
    }

    /// Index tabs (iPhone: folder tabs over the page; iPad: down the page's right edge) and
    /// the open page.
    @ViewBuilder
    private func binder(_ halls: [(hall: FunctionHall, items: [Item])], stories: [UInt64: String]) -> some View {
        let tabs = InventoryBinder.tabs(halls)
        let current = InventoryBinder.page(page, in: tabs)
        let entry = halls.first { $0.hall == current } ?? halls[0]
        let tab = tabs.first { $0.hall == entry.hall } ?? tabs[0]
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 0) {
                pageStack(entry, tab: tab, tabs: tabs, stories: stories)
                VStack(spacing: 4) {
                    ForEach(tabs) { t in
                        BinderTabButton(tab: t, selected: t.hall == entry.hall, edge: .trailing) { pick(t.hall, tabs: tabs) }
                    }
                }
                .frame(width: 168)
                .padding(.top, 24)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Pages")
            }
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(tabs) { t in
                                BinderTabButton(tab: t, selected: t.hall == entry.hall) { pick(t.hall, tabs: tabs) }.id(t.hall)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Pages")
                    .accessibilityIdentifier("inventory.tabs")
                    .onChange(of: entry.hall) { _, hall in
                        withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(hall, anchor: .center) }
                    }
                }
                pageStack(entry, tab: tab, tabs: tabs, stories: stories)
            }
        }
    }

    /// The open page; slides in from the side it was turned from (a crossfade with Reduce
    /// Motion), and follows a horizontal swipe.
    private func pageStack(_ entry: (hall: FunctionHall, items: [Item]), tab: BinderTab, tabs: [BinderTab],
                           stories: [UInt64: String]) -> some View {
        let slide: AnyTransition = reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: turnedForward ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity)
        return ZStack(alignment: .top) {
            binderPage(entry.hall, entry.items, tab: tab, stories: stories)
                .id(entry.hall)
                .transition(slide)
        }
        .offset(x: dragX)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { v in
                    guard !reduceMotion, abs(v.translation.width) > abs(v.translation.height) * 1.2 else { return }
                    dragX = v.translation.width * 0.35
                }
                .onEnded { v in
                    withAnimation(.spring(duration: 0.3)) { dragX = 0 }
                    let dx = v.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(v.translation.height) * 1.5 else { return }
                    turn(dx < 0 ? 1 : -1, tabs: tabs)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityScrollAction { edge in
            // VoiceOver three-finger swipe turns the page.
            switch edge {
            case .trailing: turn(1, tabs: tabs)
            case .leading: turn(-1, tabs: tabs)
            default: break
            }
        }
    }

    private func binderPage(_ hall: FunctionHall, _ items: [Item], tab: BinderTab, stories: [UInt64: String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader(hall, items)
            if dynamicTypeSize.isAccessibilitySize {
                pageList(items, stories: stories).padding(.top, 12)
            } else {
                pageShelves(items, stories: stories).padding(.top, 8)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 18)
        // Pages share a height, like a binder's, so turning one doesn't make the screen jump.
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 560, alignment: .topLeading)
        .background(pageBackground)
        // The open tab's color runs along the page edge it's attached to.
        .overlay(alignment: sizeClass == .regular ? .trailing : .top) { tabEdge(tab) }
        .overlay(alignment: .leading) { BinderHoles().padding(.leading, 5) }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
        .mooveShadow(.lifted)
    }

    private var pageBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            .fill(LinearGradient(colors: [BinderColors.wall, BinderColors.wallShade], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private func tabEdge(_ tab: BinderTab) -> some View {
        let tint = BinderColors.tint(tab.tint)
        if sizeClass == .regular {
            Rectangle().fill(tint).frame(width: 4).padding(.vertical, 6)
        } else {
            Rectangle().fill(tint).frame(height: 4).padding(.horizontal, 6)
        }
    }

    private func pageHeader(_ hall: FunctionHall, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hall.name)
                .displayTitle(26)
                .fixedSize(horizontal: false, vertical: true)
            Text(FunctionHall.subtitle(items)).monoMeta()
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("inventory.hall.\(hall.rawValue)")
    }

    /// Largest text sizes: a plain list, one row per item.
    private func pageList(_ items: [Item], stories: [UInt64: String]) -> some View {
        let compCounts = store.snapshot.compCounts
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                let price = priceText(item, compCounts: compCounts)
                shelfItem(item, price: price, hasStory: stories[item.id] != nil) {
                    listRow(item, price: price)
                }
                .ruled()
            }
        }
    }

    private func listRow(_ item: Item, price: String) -> some View {
        HStack(spacing: 12) {
            ShelfSprite(item: item, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).blockTitle().fixedSize(horizontal: false, vertical: true)
                Text(price).monoMeta()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func pageShelves(_ items: [Item], stories: [UInt64: String]) -> some View {
        let regular = sizeClass == .regular
        let shelves = InventoryBinder.shelves(items, capacity: InventoryBinder.capacity(regularWidth: regular),
                                              maxPerShelf: InventoryBinder.maxPerShelf(regularWidth: regular))
        return VStack(spacing: 6) {
            ForEach(Array(shelves.enumerated()), id: \.offset) { _, shelf in
                ShelfRow(shelf: shelf) { item in
                    shelfColumn(item, on: shelf, stories: stories)
                }
            }
        }
    }

    private func shelfColumn(_ item: Item, on shelf: Shelf, stories: [UInt64: String]) -> some View {
        let index = shelf.items.firstIndex(of: item) ?? 0
        let price = priceText(item, compCounts: store.snapshot.compCounts)
        return shelfItem(item, price: price, hasStory: stories[item.id] != nil) {
            ShelfItemColumn(item: item, tier: shelf.tier, price: price, tilt: index % 2 == 0 ? -2 : 2)
        }
    }

    /// One item: a single button that opens its placard; long-press keeps the fix-it menu.
    private func shelfItem<Content: View>(_ item: Item, price: String, hasStory: Bool,
                                         @ViewBuilder label: () -> Content) -> some View {
        let room = store.snapshot.rooms.first { $0.id == item.roomId }
        let tag = item.originTag(inSharedRoom: room.map { !isMine($0) } ?? false)
        return Button { placard = PlacardRef(id: item.id) } label: { label() }
            .buttonStyle(.plain)
            // Fix-it (long press): rename, what is it, turn, remove a misread scan item. Delete asks first.
            .contextMenu {
                Button("Open", systemImage: "info.circle") { opened = item.id }
                Button(hasStory ? "Edit story" : "Add a story", systemImage: "text.quote") { editingStory = item }
                Divider()
                ItemFixMenu(item: item) { startRename(item) }
                Divider()
                Button("Delete item", systemImage: "trash", role: .destructive) { deleting = item }
                    .accessibilityIdentifier("inventory.delete.\(item.id)")
            }
            .accessibilityLabel(itemLabel(item, price: price, tag: tag))
            .accessibilityHint("Shows its placard")
            .accessibilityAction(named: "Open details") { opened = item.id }
            .accessibilityAction(named: "Edit story") { editingStory = item }
            .accessibilityAction(named: "Rename") { startRename(item) }
            .accessibilityAction(named: "Turn around") { Task { await store.turn(item) } }
            .accessibilityAction(named: "Delete") { deleting = item }
            .accessibilityIdentifier("inventory.item.\(item.id)")
    }

    /// "Desk lamp, $40, Scanned with LiDAR" (+ ", Possibly sentimental").
    private func itemLabel(_ item: Item, price: String, tag: Item.OriginTag) -> String {
        var parts: [String] = [item.name, price, tag.accessibilityLabel]
        if item.maybeSentimental { parts.append("Possibly sentimental") }
        return parts.joined(separator: ", ")
    }

    /// "$120", "≈$40" when only one or two comparable listings back it.
    private func priceText(_ item: Item, compCounts: [UInt64: Int]) -> String {
        let rough = item.saleValueCents != nil && Item.isRoughEstimate(compCount: compCounts[item.id] ?? 0)
        return rough ? "≈\(item.priceText)" : item.priceText
    }

    private func pick(_ hall: FunctionHall, tabs: [BinderTab]) {
        let from = tabs.firstIndex { $0.hall == InventoryBinder.page(page, in: tabs) } ?? 0
        let to = tabs.firstIndex { $0.hall == hall } ?? 0
        turn(to: hall, forward: to >= from)
    }

    private func turn(_ delta: Int, tabs: [BinderTab]) {
        let current = InventoryBinder.page(page, in: tabs)
        guard let next = InventoryBinder.turn(from: current, by: delta, in: tabs), next != current else { return }
        turn(to: next, forward: delta > 0)
    }

    private func turn(to hall: FunctionHall, forward: Bool) {
        turnedForward = forward
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35)) { page = hall }
    }

    // MARK: Placard

    private func closePlacard(then action: AfterPlacard) {
        afterPlacard = action
        placard = nil
    }

    private func runAfterPlacard() {
        guard let action = afterPlacard else { return }
        afterPlacard = nil
        switch action {
        case .open(let id): opened = id
        case .story(let item): editingStory = item
        case .rename(let item): startRename(item)
        case .delete(let item): deleting = item
        }
    }

    private func exhibitInfo(_ item: Item, story: String?, isTop: Bool, compCounts: [UInt64: Int]) -> ExhibitInfo {
        // "≈" marks an estimate from only one or two comparable listings
        let rough = item.saleValueCents != nil && Item.isRoughEstimate(compCount: compCounts[item.id] ?? 0)
        let room = store.snapshot.rooms.first { $0.id == item.roomId }
        let catalog = MuseumLabel.catalogLine(item)
        let catalogued = store.snapshot.scanDate(ofRoom: item.roomId) ?? item.updatedAt
        return ExhibitInfo(
            item: item,
            roomName: room.map { store.displayName(of: $0) } ?? "",
            story: story,
            autoStory: MuseumLabel.autoStory(item, isTopPiece: isTop),
            catalog: catalog,
            acquired: MuseumLabel.acquiredLine(cataloguedAt: catalogued, story: story),
            price: rough ? "≈\(item.priceText)" : item.priceText,
            priceTint: item.saleValueCents == nil ? Theme.muted : Theme.text,
            tag: item.originTag(inSharedRoom: room.map { !isMine($0) } ?? false),
            featured: isTop
        )
    }

    private func startRename(_ item: Item) {
        newName = item.name
        renaming = item
    }

    private func hideButton(_ room: Room) -> some View {
        Button("Hide room", systemImage: "eye.slash") { store.setRoom(room.id, hidden: true) }
    }

    /// "Demo · Today 10:42 · 12 items · Shared by Sam": which scan this room is.
    private func roomMeta(_ room: Room, shared: Bool, count: Int) -> some View {
        let demo = store.snapshot.isDemoRoom(room.id)
        let date = store.snapshot.scanDate(ofRoom: room.id).map { ScanDateLabel.text($0) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if demo {
                    MonoTag(text: "Demo", tone: Theme.ochreInk)
                        .accessibilityLabel("Demo scan")
                }
                Text(count == 1 ? "1 item" : "\(count) items").monoText(12, maxScale: 1.8).foregroundStyle(Theme.muted)
            }
            if let date {
                Text(date).monoText(12, maxScale: 1.8).foregroundStyle(Theme.muted).accessibilityLabel("Scanned \(date)")
            }
            if shared {
                Label("Shared by \(ownerName(of: room))", systemImage: "person.2")
                    .monoText(12, maxScale: 1.8).foregroundStyle(Theme.muted)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Hidden rooms

    @ViewBuilder
    private var hiddenRoomsFooter: some View {
        let hidden = store.snapshot.roomsNewestFirst(store.hiddenRooms)
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showHidden.toggle()
                } label: {
                    Label(showHidden ? "Hide hidden rooms" : "Show hidden rooms (\(hidden.count))",
                          systemImage: showHidden ? "chevron.up" : "eye")
                }
                .buttonStyle(.pill(.outline, compact: true))
                if showHidden {
                    ForEach(hidden) { room in
                        let count = store.items.filter { $0.roomId == room.id }.count
                        let date = store.snapshot.scanDate(ofRoom: room.id).map { ScanDateLabel.text($0) }
                        let demo = store.snapshot.isDemoRoom(room.id)
                        LedgerRow(
                            title: room.name,
                            meta: [demo ? "Demo" : nil, date, "\(count) items"].compactMap { $0 }.joined(separator: " · ")
                        ) {
                            IconTile(systemName: "eye.slash")
                        } trailing: {
                            Button("Unhide") { store.setRoom(room.id, hidden: false) }
                                .buttonStyle(.pill(.outline, compact: true))
                                .accessibilityLabel("Unhide \(room.name)")
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    // MARK: Scan geometry (rename marker)

    /// Changes when a visible room's newest scan changes.
    private var geometryKey: [String] {
        store.visibleRooms.map { room in
            "\(room.id):\(store.snapshot.latestScan(ofRoom: room.id)?.capturedRoomJsonUrl ?? "")"
        }
    }

    private func loadScannedCategories() async {
        var out: [UInt64: [String: String]] = [:]
        for room in store.visibleRooms where !store.snapshot.isDemoRoom(room.id) {
            guard store.snapshot.latestScan(ofRoom: room.id)?.capturedRoomJsonUrl?.isEmpty == false,
                  let geometry = try? await RoomGeometryLoader.load(room: room, snapshot: store.snapshot) else { continue }
            out[room.id] = Dictionary(geometry.objects.map { ($0.id, $0.category) }, uniquingKeysWith: { a, _ in a })
        }
        scannedCategories = out
    }

    private var emptyState: some View {
        EmptyState(title: "No items yet", detail: "Scan a room to build your inventory, or join a shared one with its code.") {
            Button("Join a room") { showJoin = true }
                .buttonStyle(.pill(.outline, compact: true))
        }
    }

    /// Rooms are mine unless someone shared them with me through a join code (#10).
    private func isMine(_ room: Room) -> Bool { room.owner == store.snapshot.me }

    /// The owner's name when their user row is visible; the live app only subscribes
    /// to its own user row, so shared rooms usually say "someone".
    private func ownerName(of room: Room) -> String {
        store.snapshot.users.first { $0.identity == room.owner }?.name ?? "someone"
    }

    /// Item count, room count and estimated value between rules, split by hairlines.
    private func totals(_ shown: [Item]) -> some View {
        let priced = shown.compactMap(\.saleValueCents)
        return HStack(spacing: 0) {
            // No "Rooms" figure: the Rooms chips right below show them.
            StatFigure(label: "Items", value: "\(shown.count)")
                .padding(.vertical, 18).padding(.trailing, 14)
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Est. value", value: priced.reduce(0, +).usd, tint: Theme.accentStrong)
                .padding(.vertical, 18).padding(.leading, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .ruled(.top)
        .ruled()
    }
}

#Preview {
    NavigationStack { InventoryView() }.environment(MooveStore.preview())
}

/// The item a placard sheet is showing.
struct PlacardRef: Identifiable, Hashable {
    let id: UInt64
}

/// What a placard's button asked for, run once the sheet is gone.
enum AfterPlacard {
    case open(UInt64)
    case story(Item)
    case rename(Item)
    case delete(Item)
}
