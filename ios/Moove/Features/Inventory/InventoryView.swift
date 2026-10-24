import SwiftUI
import MooveKit

/// Live list of the user's items, grouped by room. Polished in #4.
struct InventoryView: View {
    @Environment(MooveStore.self) private var store

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
                        NavigationLink(value: room) {
                            Label("3D", systemImage: "cube.transparent")
                        }
                        .buttonStyle(.pill(.outline, compact: true))
                        .accessibilityLabel("View room in 3D")
                    }
                    .padding(.top, 40)
                    ForEach(items) { item in
                        LedgerRow(
                            title: item.name,
                            meta: item.category.capitalized,
                            value: item.estValueCents?.usd ?? "pricing…",
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
        .mooveScreen()
        .animation(.default, value: store.items)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No items yet").blockTitle()
            Text("Scan a room to build your inventory.").monoMeta()
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
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
