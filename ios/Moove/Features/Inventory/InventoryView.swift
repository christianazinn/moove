import SwiftUI
import MooveKit

/// The user's things as a small museum (Lisa, #inventory-museum): items hang in halls by
/// what they're for (MooveKit `FunctionHall`), each a framed voxel exhibit with a placard
/// (`MuseumLabel`). Room-level actions (share, 3D, hide, add) sit on the Rooms strip on top.
struct InventoryView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// Item detail, pushed by tapping an exhibit.
    @State private var opened: UInt64?
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
                ForEach(FunctionHall.halls(shown), id: \.hall) { entry in
                    hallSection(entry.hall, entry.items, stories: stories)
                }
                hiddenRoomsFooter.padding(.top, 40)
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
            .strokeBorder(focused ? Theme.accentStrong : .clear, lineWidth: 2))
        .opacity(focus.isEmpty || focused ? 1 : 0.55)
        .contextMenu { hideButton(room) }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Hide room") { store.setRoom(room.id, hidden: true) }
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

    // MARK: Halls

    private var columns: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return sizeClass == .regular ? 3 : 2
    }

    @ViewBuilder
    private func hallSection(_ hall: FunctionHall, _ items: [Item], stories: [UInt64: String]) -> some View {
        let top = MuseumLabel.topPiece(items)
        let compCounts = store.snapshot.compCounts
        let infos = items.map { exhibitInfo($0, story: stories[$0.id], isTop: $0.id == top && items.count > 1, compCounts: compCounts) }
        VStack(alignment: .leading, spacing: 4) {
            Text(hall.title)
                .serifText(24, weight: .semibold)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(FunctionHall.subtitle(items)).monoMeta()
        }
        .padding(.top, 40)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inventory.hall.\(hall.rawValue)")
        MasonryColumns(infos: infos, columns: columns) { info in
            exhibit(info)
        }
    }

    private func exhibitInfo(_ item: Item, story: String?, isTop: Bool, compCounts: [UInt64: Int]) -> ExhibitInfo {
        // "≈" marks an estimate from only one or two comparable listings
        let rough = item.saleValueCents != nil && Item.isRoughEstimate(compCount: compCounts[item.id] ?? 0)
        let room = store.snapshot.rooms.first { $0.id == item.roomId }
        var catalog = MuseumLabel.catalogLine(item)
        if let was = wasCategory(item) { catalog += " · was: \(was)" }
        let catalogued = store.snapshot.scanDate(ofRoom: item.roomId) ?? item.updatedAt
        return ExhibitInfo(
            item: item,
            roomName: room?.name ?? "",
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

    private func exhibit(_ info: ExhibitInfo) -> some View {
        let item = info.item
        return ExhibitCard(info: info) { editingStory = item }
            .onTapGesture { opened = item.id }
            // Fix-it (long press): rename, what is it, turn, remove a misread scan item. Delete asks first.
            .contextMenu {
                Button("Open", systemImage: "info.circle") { opened = item.id }
                Button(info.story == nil ? "Add a story" : "Edit story", systemImage: "text.quote") { editingStory = item }
                Divider()
                ItemFixMenu(item: item) { startRename(item) }
                Divider()
                Button("Delete item", systemImage: "trash", role: .destructive) { deleting = item }
                    .accessibilityIdentifier("inventory.delete.\(item.id)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction { opened = item.id }
            .accessibilityAction(named: "Open details") { opened = item.id }
            .accessibilityAction(named: "Edit story") { editingStory = item }
            .accessibilityAction(named: "Rename") { startRename(item) }
            .accessibilityAction(named: "Turn around") { Task { await store.turn(item) } }
            .accessibilityAction(named: "Delete") { deleting = item }
            .accessibilityIdentifier("inventory.item.\(item.id)")
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

    /// The scanner's own category when a later pass renamed the item ("was: storage").
    private func wasCategory(_ item: Item) -> String? {
        guard let scanned = item.scanObjectId.flatMap({ scannedCategories[item.roomId]?[$0] }) else { return nil }
        return item.renamedFrom(scannedCategory: scanned)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("No items yet").blockTitle()
            Text("Scan a room to build your inventory, or join a shared one with its code.").monoMeta()
            Button("Join a room") { showJoin = true }
                .buttonStyle(.pill(.outline, compact: true))
                .padding(.top, 12)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
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
            StatFigure(label: "Items", value: "\(shown.count)")
                .padding(.vertical, 18).padding(.trailing, 14)
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Rooms", value: "\(store.visibleRooms.count)")
                .padding(.vertical, 18).padding(.horizontal, 14)
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
