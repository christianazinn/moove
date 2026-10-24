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
                VStack(alignment: .leading, spacing: 4) {
                    Text("No furniture in this scan").blockTitle()
                    Text("The room is saved. Scan again more slowly, or add items by photo, and they'll show up here.")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled(.top)
                .ruled()
                .accessibilityElement(children: .combine)
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
    /// The recorded demo bedroom rather than a live scan: labeled as such.
    var isDemo = false
    /// Set when the room files or photos couldn't be uploaded.
    var uploadProblem: String? = nil
    /// How many items the import sent, for the title before the rows sync back.
    var importedCount: Int? = nil
    var onDone: () -> Void

    /// What the module skipped on import (#177/#180), once the event syncs back.
    private var skips: ScanSkips? {
        guard let room = store.newestRoom(named: roomName),
              let scan = store.snapshot.scans.filter({ $0.roomId == room.id }).max(by: { $0.id < $1.id }) else { return nil }
        return store.snapshot.skips(forScan: scan.id)
    }

    private var itemCount: Int {
        if let importedCount { return max(importedCount - (skips?.count ?? 0), 0) }
        guard let room = store.newestRoom(named: roomName) else { return 0 }
        return store.items.filter { $0.roomId == room.id }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("01 — Scan · Done").eyebrow()
                    if isDemo { MonoTag(text: "Demo scan", tone: Theme.ochreInk) }
                }
                Text(itemCount == 0 ? "Room saved" : "\(itemCount) item\(itemCount == 1 ? "" : "s") added")
                    .pageTitle()
                    .padding(.top, 8)
                Text(lede)
                    .lede()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                if let skips {
                    SkippedObjectsNotice(skips: skips).padding(.top, 16)
                }
                ScanFinishedResults(roomName: roomName, colors: colors)
                    .padding(.top, 28)
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

    private var lede: String {
        if let uploadProblem {
            return "Photos couldn't be uploaded (\(uploadProblem)), so agents can't identify items yet. The room is saved, and the 3D view works on this device."
        }
        if isDemo {
            return store.backendKind == .fixture
                ? "A recorded bedroom, not a live scan. Offline demo: items, prices and colors are fixture data, as if the agents had run."
                : "A recorded bedroom, not a live scan. Agents are identifying and pricing it now; colors are the demo room's."
        }
        return "Agents are identifying and pricing them now."
    }
}

/// "2 objects looked wrong and were skipped", with what was wrong with each (#180).
private struct SkippedObjectsNotice: View {
    var skips: ScanSkips

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(skips.entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry.readable).monoMeta()
                }
                if skips.count > skips.entries.count {
                    Text("and \(skips.count - skips.entries.count) more").monoMeta()
                }
                Text("Their sizes or labels were impossible (a scanning glitch). Everything else was added.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label(skips.summary, systemImage: "exclamationmark.triangle")
                .monoText(13.5)
                .foregroundStyle(Theme.ochreInk)
        }
        .tint(Theme.ochreInk)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }
}
