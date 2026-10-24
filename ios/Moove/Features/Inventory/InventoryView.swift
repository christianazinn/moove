import SwiftUI
import MooveKit

/// Live list of the user's items, grouped by room. Polished in #4.
struct InventoryView: View {
    @Environment(MooveStore.self) private var store
    @State private var sharing: Room?
    @State private var showJoin = false
    @State private var showHidden = false
    /// Room id → (scan object id → the scanner's category), from each room's scan geometry,
    /// for the "was: storage" marker on items a later pass renamed (#267).
    @State private var scannedCategories: [UInt64: [String: String]] = [:]
    /// Fix-it rename from a row's long-press menu.
    @State private var renaming: Item?
    @State private var newName = ""
    /// Row whose "Delete item" is waiting on the confirm.
    @State private var deleting: Item?
    /// Add item (by hand) sheet, opened on this room.
    @State private var addingTo: Room?

    var body: some View {
        let rooms = store.snapshot.roomsNewestFirst(store.visibleRooms)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "02 — Inventory",
                    title: "Everything you own.",
                    lede: "Every item Moove found, room by room. Prices fill in as the agents finish."
                )
                if store.visibleItems.isEmpty {
                    emptyState.padding(.top, 32)
                } else {
                    totals.padding(.top, 28)
                }
                ForEach(rooms) { room in
                    roomSection(room)
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

    // MARK: Room sections

    @ViewBuilder
    private func roomSection(_ room: Room) -> some View {
        let items = store.items.filter { $0.roomId == room.id }
        let shared = !isMine(room)
        ListHeader(title: room.name, count: "\(items.count)") {
            HStack(spacing: 8) {
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
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.muted)
                .accessibilityLabel("More for \(room.name)")
            }
            .fixedSize()
        }
        .padding(.top, 40)
        .contextMenu { hideButton(room) }
        .accessibilityAction(named: "Hide room") { store.setRoom(room.id, hidden: true) }
        roomMeta(room, shared: shared).padding(.vertical, 8)
        if let scan = store.snapshot.latestScan(ofRoom: room.id), scan.sweepStatus?.isActive == true,
           scan.createdAt > .now.addingTimeInterval(-300) {
            // Room photo sweep (#92): the worker is naming "other" boxes and adding missed items.
            // Hidden after 5 min so a scan whose worker was down doesn't spin forever.
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Identifying items from room photos…").monoMeta()
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
        let compCounts = store.snapshot.compCounts
        ForEach(items) { item in
            let tag = item.originTag(inSharedRoom: shared)
            // "≈" marks an estimate from only one or two comparable listings
            let rough = item.saleValueCents != nil && Item.isRoughEstimate(compCount: compCounts[item.id] ?? 0)
            LedgerRow(
                title: item.name,
                meta: meta(for: item),
                value: rough ? "≈\(item.priceText)" : item.priceText,
                valueTint: item.saleValueCents == nil ? Theme.muted : Theme.text,
                tag: tag.label,
                tagAccessibilityLabel: tag.accessibilityLabel
            ) {
                ItemThumbnail(item: item, size: 56)
            }
            .accessibilityElement(children: .combine)
            // Fix-it (long press): rename, what is it, turn, remove a misread scan item. Delete asks first.
            .contextMenu {
                ItemFixMenu(item: item) { startRename(item) }
                Divider()
                Button("Delete item", systemImage: "trash", role: .destructive) { deleting = item }
                    .accessibilityIdentifier("inventory.delete.\(item.id)")
            }
            .accessibilityAction(named: "Rename") { startRename(item) }
            .accessibilityAction(named: "Turn around") { Task { await store.turn(item) } }
            .accessibilityAction(named: "Delete") { deleting = item }
            .accessibilityIdentifier("inventory.item.\(item.id)")
        }
    }

    private func startRename(_ item: Item) {
        newName = item.name
        renaming = item
    }

    private func hideButton(_ room: Room) -> some View {
        Button("Hide room", systemImage: "eye.slash") { store.setRoom(room.id, hidden: true) }
    }

    /// "Demo · Today 10:42 · Shared by Sam": which scan this section is.
    @ViewBuilder
    private func roomMeta(_ room: Room, shared: Bool) -> some View {
        let demo = store.snapshot.isDemoRoom(room.id)
        let date = store.snapshot.scanDate(ofRoom: room.id).map { ScanDateLabel.text($0) }
        if demo || date != nil || shared {
            HStack(spacing: 8) {
                if demo {
                    MonoTag(text: "Demo", tone: Theme.ochreInk)
                        .accessibilityLabel("Demo scan")
                }
                if let date {
                    Text(date).monoMeta().accessibilityLabel("Scanned \(date)")
                }
                if shared {
                    Label("Shared by \(ownerName(of: room))", systemImage: "person.2").monoMeta()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    private func meta(for item: Item) -> String {
        let category = item.category.capitalized
        guard let scanned = item.scanObjectId.flatMap({ scannedCategories[item.roomId]?[$0] }),
              let was = item.renamedFrom(scannedCategory: scanned) else { return category }
        return "\(category) · was: \(was)"
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
    private var totals: some View {
        let priced = store.visibleItems.compactMap(\.saleValueCents)
        return HStack(spacing: 0) {
            StatFigure(label: "Items", value: "\(store.visibleItems.count)")
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
