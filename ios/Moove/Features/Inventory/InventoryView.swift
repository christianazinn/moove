import SwiftUI
import MooveKit

/// Live list of the user's items, grouped by room. Polished in #4.
struct InventoryView: View {
    @Environment(MooveStore.self) private var store
    @State private var sharing: Room?
    @State private var showJoin = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "02 — Inventory",
                    title: "Everything you own.",
                    lede: "Every item Moove found, room by room. Prices fill in as the agents finish."
                )
                if store.items.isEmpty {
                    emptyState.padding(.top, 32)
                } else {
                    totals.padding(.top, 28)
                }
                ForEach(store.snapshot.rooms) { room in
                    let items = store.items.filter { $0.roomId == room.id }
                    ListHeader(title: room.name, count: "\(items.count)") {
                        HStack(spacing: 8) {
                            if isMine(room) {
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
                        }
                        .fixedSize()
                    }
                    .padding(.top, 40)
                    if !isMine(room) {
                        Label("Shared by \(ownerName(of: room))", systemImage: "person.2")
                            .monoMeta()
                            .padding(.vertical, 8)
                    }
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
                    ForEach(items) { item in
                        LedgerRow(
                            title: item.name,
                            meta: item.origin == .roomPhotos ? "\(item.category.capitalized) · from room photos" : item.category.capitalized,
                            value: item.priceText,
                            valueTint: item.estValueCents == nil ? Theme.muted : Theme.text
                        ) {
                            ItemThumbnail(item: item, size: 56)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
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
        }
        .sheet(item: $sharing) { ShareRoomView(room: $0) }
        .sheet(isPresented: $showJoin) { JoinRoomView() }
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
        .mooveScreen()
        .animation(.default, value: store.items)
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
        let priced = store.items.compactMap(\.estValueCents)
        return HStack(spacing: 0) {
            StatFigure(label: "Items", value: "\(store.items.count)")
                .padding(.vertical, 18).padding(.trailing, 14)
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Rooms", value: "\(store.snapshot.rooms.count)")
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
