import SwiftUI
import MooveKit

/// Live list of the user's items, grouped by room. Polished in #4.
struct InventoryView: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        List {
            ForEach(store.snapshot.rooms) { room in
                Section(room.name) {
                    NavigationLink(value: room) {
                        Label("View room in 3D", systemImage: "cube.transparent")
                            .foregroundStyle(.tint)
                    }
                    ForEach(store.items.filter { $0.roomId == room.id }) { item in
                        LabeledContent(item.name, value: item.estValueCents?.usd ?? "pricing…")
                    }
                }
            }
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("No items yet", systemImage: "shippingbox", description: Text("Scan a room to build your inventory."))
            }
        }
        .navigationTitle("Inventory")
        .navigationDestination(for: Room.self) { RoomDetailView(room: $0) }
    }
}

#Preview {
    NavigationStack { InventoryView() }.environment(MooveStore.preview())
}
