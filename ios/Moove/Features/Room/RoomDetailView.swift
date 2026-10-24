import SwiftUI
import MooveKit

/// A scanned room in 3D / plan view, colored live from the inventory.
struct RoomDetailView: View {
    @Environment(MooveStore.self) private var store
    let room: Room
    @State private var geometry: RoomGeometry?
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if let geometry {
                RoomVisualizationView(geometry: geometry, items: itemsByScanObject, initialMode: .decision)
            } else if !loaded {
                ProgressView {
                    Text("Loading room…").monoMeta()
                }
                .tint(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mooveScreen()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No 3D scan for this room").blockTitle()
                    Text(failure ?? "This room was added without a RoomPlan scan.")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled(.top)
                .ruled()
                .accessibilityElement(children: .combine)
                .padding(.horizontal, Theme.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mooveScreen()
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UInt64.self) { ItemDetailView(itemId: $0) }
        .task(id: room.id) {
            do {
                geometry = try await RoomGeometryLoader.load(room: room, snapshot: store.snapshot)
            } catch {
                failure = error.localizedDescription
            }
            loaded = true
        }
    }

    private var itemsByScanObject: [String: Item] {
        var map: [String: Item] = [:]
        for item in store.items where item.roomId == room.id {
            if let key = item.scanObjectId { map[key] = item }
        }
        return map
    }
}
