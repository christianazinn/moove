import SwiftUI
import MooveKit

/// After a scan: the room you just scanned as a voxel dollhouse (real walls, doors,
/// windows and object positions when the scan's geometry loads) with its inventory below.
/// Updates live as the vision and pricing agents fill in names and values.
struct ScanFinishedResults: View {
    @Environment(MooveStore.self) private var store
    /// Name the scan was saved under; the newest room with this name is the one just scanned.
    var roomName: String
    /// Colors sampled from the scan's camera frames (`ScanSession.colors`), if ready.
    var colors: ScanColors? = nil
    var onSelect: (Item) -> Void = { _ in }

    @State private var geometry: RoomGeometry?

    private var room: Room? {
        store.snapshot.rooms.filter { $0.name == roomName && $0.home == .old }.max { $0.id < $1.id }
    }

    private var items: [Item] {
        guard let room else { return [] }
        return store.items.filter { $0.roomId == room.id }
    }

    var body: some View {
        Group {
            if let room, !items.isEmpty {
                ScanResultsView(room: room, items: items, comps: store.snapshot.comps, geometry: geometry, colors: colors, onSelect: onSelect)
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accentStrong)
                    Text("Adding your items…").monoMeta()
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: room?.id) {
            guard let room else { return }
            geometry = try? await RoomGeometryLoader.load(room: room, snapshot: store.snapshot)
        }
    }
}
