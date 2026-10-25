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

    private var room: Room? { store.newestRoom(named: roomName) }

    private var items: [Item] {
        guard let room else { return [] }
        return store.items.filter { $0.roomId == room.id }
    }

    /// Sampled colors, with the demo bedroom's fixture colors filling any gaps for demo items
    /// (the offline demo and "Load demo scan" have no camera frames to sample).
    private var shownColors: ScanColors? {
        guard items.contains(where: DemoFixtures.isDemoItem) else { return colors }
        return (colors ?? .empty).filling(from: DemoFixtures.scanColors())
    }

    var body: some View {
        Group {
            if let room, !items.isEmpty {
                ScanResultsView(room: room, items: items, comps: store.snapshot.comps, geometry: geometry, colors: shownColors, onSelect: onSelect)
            } else if room != nil {
                // The room landed with no items (RoomPlan found no furniture, nothing added by photo).
                Text("No furniture found").blockTitle()
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.accentStrong)
                    Text("Adding items…").monoMeta()
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: room?.id) {
            guard let room else { return }
            // A geometry that fails to load leaves nil: the results estimate a room and say so.
            geometry = try? await RoomGeometryLoader.load(room: room, snapshot: store.snapshot)
        }
    }
}

/// The whole "scan done" page: header, the results above, and a button to the inventory.
/// Shared by a real scan (`ScanFlowView`) and "Load demo scan", so the demo path looks the same.
struct ScanFinishedScreen: View {
    @Environment(MooveStore.self) private var store
    var roomName: String
    var colors: ScanColors? = nil
    /// The recorded demo bedroom rather than a live scan (no tag on screen: the hero already says "Demo bedroom").
    var isDemo = false
    /// Set when the room files or photos couldn't be uploaded.
    var uploadProblem: String? = nil
    /// Item photos still queued for upload (#222); they attach to their items once they land.
    var pendingPhotos = 0
    /// How many items the import sent, for the title before the rows sync back.
    var importedCount: Int? = nil
    /// Detector finds the app's crop classifier left out before the import (`ObjectRecheck`).
    var localSkips: [ScanSkips.Entry] = []
    var onDone: () -> Void

    /// What the module skipped on import (#177/#180), once the event syncs back.
    private var moduleSkips: ScanSkips? {
        guard let room = store.newestRoom(named: roomName),
              let scan = store.snapshot.scans.filter({ $0.roomId == room.id }).max(by: { $0.id < $1.id }) else { return nil }
        return store.snapshot.skips(forScan: scan.id)
    }

    /// The module's skips plus the app's own, as one notice.
    private var skips: ScanSkips? { ScanSkips.combined(moduleSkips, local: localSkips) }

    private var itemCount: Int {
        // Local skips were never sent, so only the module's come off the imported count.
        if let importedCount { return max(importedCount - (moduleSkips?.count ?? 0), 0) }
        guard let room = store.newestRoom(named: roomName) else { return 0 }
        return store.items.filter { $0.roomId == room.id }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(itemCount == 0 ? "Room saved" : "\(itemCount) item\(itemCount == 1 ? "" : "s") added")
                    .pageTitle()
                if let problem {
                    Text(problem).monoMeta().padding(.top, Theme.Space.s)
                }
                if let skips {
                    SkippedObjectsNotice(skips: skips, rechecked: !localSkips.isEmpty).padding(.top, 16)
                }
                ScanFinishedResults(roomName: roomName, colors: colors)
                    .padding(.top, Theme.Space.xl)
                Button("See inventory", action: onDone)
                    .buttonStyle(.pill(.primary))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .mooveScreen()
    }

    /// Only said when something is still off: photos waiting or failed (VoiceOver gets the why).
    private var problem: String? {
        if pendingPhotos > 0 { return "Photos still uploading" }
        return uploadProblem == nil ? nil : "Photos didn't upload"
    }
}

/// "2 objects looked wrong and were skipped", with what was wrong with each (#180).
private struct SkippedObjectsNotice: View {
    var skips: ScanSkips
    /// Some were dropped by the on-device classifier (a wall, door or fixture, not an object).
    var rechecked = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(skips.entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry.readable).monoMeta()
                }
                if skips.count > skips.entries.count {
                    Text("and \(skips.count - skips.entries.count) more").monoMeta()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label(skips.summary, systemImage: "exclamationmark.triangle")
                .monoText(13.5)
                .foregroundStyle(Theme.muted)
        }
        .tint(Theme.muted)
    }
}
