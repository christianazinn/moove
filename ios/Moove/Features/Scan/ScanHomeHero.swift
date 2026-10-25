import SwiftUI
import UIKit
import MooveKit

/// Scan home's hero (#130): the latest scanned room as a slowly turning voxel dollhouse,
/// or the recorded demo bedroom (tagged "Demo") before there's a scan.
struct ScanHomeHero: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    var onOpen: (Room) -> Void

    @State private var model: EstimatedRoom?
    @State private var shownKey: Key?
    /// The pieces drop in once the launch splash is over (the empty shell shows until then).
    @State private var dropReady = false

    /// What the hero shows: a room (and its item count, to rebuild as items sync) or the demo.
    struct Key: Hashable {
        var roomId: UInt64?
        var itemCount: Int
    }

    /// The hero's inputs, read from the store.
    struct Source {
        var room: Room?
        var items: [Item]
        var key: Key { Key(roomId: room?.id, itemCount: items.count) }
        var isDemo: Bool { room == nil || items.allSatisfy(DemoFixtures.isDemoItem) }

        @MainActor init(_ store: MooveStore) {
            room = store.visibleRooms
                .filter { room in store.visibleItems.contains { $0.roomId == room.id } }
                .max { $0.id < $1.id }
            if let room {
                items = store.visibleItems.filter { $0.roomId == room.id }
            } else {
                items = DemoFixtures.inventory(owner: "demo").items.filter(DemoFixtures.isDemoItem)
            }
        }
    }

    private var source: Source { Source(store) }
    private var room: Room? { source.room }
    private var items: [Item] { source.items }
    private var isDemo: Bool { source.isDemo }

    var body: some View {
        let source = source
        let key = source.key
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if let model {
                    FloorPlan3DView(plan: model.plan, items: model.items, placements: dropReady ? model.placements : [],
                                    wallColor: shellColors?.wallColor, floorColor: shellColors?.floorColor,
                                    autoOrbit: true, entrance: .dropIn, interactive: false)
                } else {
                    Theme.surface
                }
            }
            .frame(height: sizeClass == .regular ? 440 : 300)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            // Over the 3D view, so the tap reaches SwiftUI (the view itself takes no gestures).
            .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { if let room { onOpen(room) } } }
            .accessibilityElement()
            .accessibilityLabel(room.map { "\($0.name), \(items.count) objects in 3D" } ?? "Demo bedroom in 3D")
            .accessibilityAddTraits(room == nil ? [] : .isButton)

            Text(caption).monoText(13.5).foregroundStyle(Theme.muted).accessibilityHidden(true)
        }
        .task(id: key) {
            if key != shownKey {
                // Built ahead (started at launch by `ScanHeroPreload`): the layout, the shell and
                // every piece's model, so the drop only moves finished entities.
                let built = await ScanHeroPreload.model(for: source, store: store)
                guard !Task.isCancelled else { return }
                model = built
                shownKey = key
            }
            await ScanHeroPreload.afterSplash()
            guard !Task.isCancelled else { return }
            dropReady = true
        }
    }

    private var caption: String {
        room?.name ?? "Demo bedroom"
    }

    /// Wall and floor colors: only the demo room's are known here (a real scan's are in-session).
    private var shellColors: ScanColors? { ScanHeroPreload.shellColors(isDemo: isDemo) }
}

/// Builds the Scan hero's room before it's on screen: started at app launch (under the launch
/// splash), so by the time the splash is gone the layout, the house shell and every piece's voxel
/// model are made and the hero only has to drop them in. Not a gate: the hero waits for it.
@MainActor
enum ScanHeroPreload {
    private static var current: (key: ScanHomeHero.Key, task: Task<EstimatedRoom, Never>)?
    private static var launchedAt: ContinuousClock.Instant?

    /// Starts building what the hero will show now (the latest room, else the demo bedroom).
    static func start(_ store: MooveStore) {
        _ = task(for: ScanHomeHero.Source(store), store: store)
    }

    /// The hero's room for `source`, with its shell and models ready to show.
    static func model(for source: ScanHomeHero.Source, store: MooveStore) async -> EstimatedRoom {
        await task(for: source, store: store).value
    }

    private static func task(for source: ScanHomeHero.Source, store: MooveStore) -> Task<EstimatedRoom, Never> {
        // First use is at launch (the app's preload hook, or the hero itself if it gets here first).
        if launchedAt == nil { launchedAt = .now }
        if let current, current.key == source.key { return current.task }
        let task = Task { await build(source, store: store) }
        current = (source.key, task)
        return task
    }

    static func shellColors(isDemo: Bool) -> ScanColors? { isDemo ? DemoFixtures.scanColors() : nil }

    /// Returns once the launch splash (~2.4 s from launch, `LaunchSplash`) has played, so the
    /// hero's drop is seen whole. Immediate when the splash is skipped or long gone.
    static func afterSplash() async {
        guard let launchedAt, !skipsSplash else { return }
        let end = launchedAt + .milliseconds(2400)
        if end > ContinuousClock.now { try? await Task.sleep(until: end, clock: .continuous) }
    }

    /// Mirrors `LaunchSplash`'s skips (UI tests, screenshot harness, VoiceOver); Reduce Motion
    /// has no drop to wait for.
    private static var skipsSplash: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["MOOVE_UI_TEST_RESET"] != nil || env["MOOVE_ROOM_PREVIEW"] != nil
            || env["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-moove.skipSplash")
            || UIAccessibility.isVoiceOverRunning || UIAccessibility.isReduceMotionEnabled
    }

    private static func build(_ source: ScanHomeHero.Source, store: MooveStore) async -> EstimatedRoom {
        let items = source.items, isDemo = source.isDemo
        let name = source.room?.name ?? DemoFixtures.scanImport().roomName
        let layoutItems = items.map { item in
            item.colors == nil && DemoFixtures.isDemoItem(item) ? LayoutItem(item, colors: DemoFixtures.scanColors()) : LayoutItem(item)
        }
        var geometry: RoomGeometry?
        if isDemo {
            geometry = DemoFixtures.roomGeometry()
        } else if let room = source.room {
            geometry = try? await RoomGeometryLoader.load(room: room, snapshot: store.snapshot)
        }
        // The layout (solver + prop placer) is pure MooveKit work: off the main actor.
        let found = geometry
        let model = await Task.detached(priority: .userInitiated) {
            if let found {
                return EstimatedRoom.scanned(name: name, geometry: found, items: items, layoutItems: layoutItems)
            }
            return EstimatedRoom.build(name: name, items: layoutItems)
        }.value
        let colors = shellColors(isDemo: isDemo)
        await NewHomeScene.prepare(model.plan, wallColor: colors?.wallColor, floorColor: colors?.floorColor)
        await VoxelEntity.prepare(model.items, placements: model.placements)
        return model
    }
}

/// A scanned room as a card: its biggest piece as a voxel thumbnail and the room's name (the count
/// and value stay in the VoiceOver label).
struct ScanRoomCard: View {
    var room: Room
    var items: [Item]

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let biggest = items.max(by: { $0.volumeM3 < $1.volumeM3 }) {
                    VoxelThumbnail(biggest, size: 44)
                } else {
                    IconTile(systemName: "cube.transparent", size: 44)
                }
            }
            .accessibilityHidden(true)
            Text(room.name).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(room.name), \(meta)")
        .accessibilityAddTraits(.isButton)
    }

    private var meta: String {
        let count = "\(items.count) item\(items.count == 1 ? "" : "s")"
        let cents = items.compactMap(\.saleValueCents).reduce(0, +)
        return cents > 0 ? "\(count) · ~$\(cents / 100)" : count
    }
}
