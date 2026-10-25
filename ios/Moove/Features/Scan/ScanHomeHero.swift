import SwiftUI
import MooveKit

/// Scan home's hero (#130): the latest scanned room as a slowly turning voxel dollhouse,
/// or the recorded demo bedroom (tagged "Demo") before there's a scan.
struct ScanHomeHero: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    var onOpen: (Room) -> Void

    @State private var model: EstimatedRoom?
    @State private var shownKey: Key?

    /// What the hero shows: a room (and its item count, to rebuild as items sync) or the demo.
    private struct Key: Hashable {
        var roomId: UInt64?
        var itemCount: Int
    }

    private var room: Room? {
        store.visibleRooms
            .filter { room in store.visibleItems.contains { $0.roomId == room.id } }
            .max { $0.id < $1.id }
    }

    private var items: [Item] {
        guard let room else { return DemoFixtures.inventory(owner: "demo").items.filter(DemoFixtures.isDemoItem) }
        return store.visibleItems.filter { $0.roomId == room.id }
    }

    private var isDemo: Bool { room == nil || items.allSatisfy(DemoFixtures.isDemoItem) }

    var body: some View {
        let key = Key(roomId: room?.id, itemCount: items.count)
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if let model {
                    FloorPlan3DView(plan: model.plan, items: model.items, placements: model.placements,
                                    wallColor: shellColors?.wallColor, floorColor: shellColors?.floorColor,
                                    autoOrbit: true, interactive: false)
                } else {
                    Theme.surface
                }
                if isDemo {
                    MonoTag(text: "Demo", tone: Theme.ochreInk).padding(14)
                }
            }
            .frame(height: sizeClass == .regular ? 440 : 300)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            // Over the 3D view, so the tap reaches SwiftUI (the view itself takes no gestures).
            .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { if let room { onOpen(room) } } }
            .accessibilityElement()
            .accessibilityLabel(room.map { "\($0.name), \(items.count) objects in 3D" } ?? "Demo bedroom in 3D")
            .accessibilityAddTraits(room == nil ? [] : .isButton)

            HStack(spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(caption).monoText(13.5).foregroundStyle(Theme.text)
            }
        }
        .task(id: key) {
            guard key != shownKey else { return }
            model = await build()
            shownKey = key
        }
    }

    private var caption: String {
        guard let room else { return "Demo bedroom" }
        return "\(room.name) · \(items.count) object\(items.count == 1 ? "" : "s")"
    }

    /// Wall and floor colors: only the demo room's are known here (a real scan's are in-session).
    private var shellColors: ScanColors? { isDemo ? DemoFixtures.scanColors() : nil }

    private func build() async -> EstimatedRoom {
        let items = items
        let name = room?.name ?? DemoFixtures.scanImport().roomName
        let layoutItems = items.map { item in
            item.colors == nil && DemoFixtures.isDemoItem(item) ? LayoutItem(item, colors: DemoFixtures.scanColors()) : LayoutItem(item)
        }
        var geometry: RoomGeometry?
        if isDemo {
            geometry = DemoFixtures.roomGeometry()
        } else if let room {
            geometry = try? await RoomGeometryLoader.load(room: room, snapshot: store.snapshot)
        }
        if let geometry {
            return EstimatedRoom.scanned(name: name, geometry: geometry, items: items, layoutItems: layoutItems)
        }
        return EstimatedRoom.build(name: name, items: layoutItems)
    }
}

/// A scanned room as a card: its three biggest pieces as voxel thumbnails, item count and value.
struct ScanRoomCard: View {
    var room: Room
    var items: [Item]

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: -18) {
                ForEach(items.sorted { $0.volumeM3 > $1.volumeM3 }.prefix(3)) { item in
                    VoxelThumbnail(item, size: 52)
                }
                if items.isEmpty { IconTile(systemName: "cube.transparent") }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text(meta).monoMeta()
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var meta: String {
        let count = "\(items.count) item\(items.count == 1 ? "" : "s")"
        let cents = items.compactMap(\.saleValueCents).reduce(0, +)
        return cents > 0 ? "\(count) · ~$\(cents / 100)" : count
    }
}
