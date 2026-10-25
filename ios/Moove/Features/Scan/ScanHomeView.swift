import SwiftUI
import RoomPlan
import MooveKit

struct ScanHomeView: View {
    @Environment(MooveStore.self) private var store
    @AppStorage("moove.tab") private var tab = "scan"
    @State private var scanning = false
    @State private var loadingDemo = false
    /// The demo scan landed: show its results like a real scan's.
    @State private var demoFinished = false
    @State private var openRoom: Room?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Scan a room.")
                ScanHomeHero { openRoom = $0 }.padding(.top, Theme.Space.xl)
                startScan.padding(.top, Theme.Space.xl)
                if !store.visibleRooms.isEmpty {
                    VStack(spacing: Theme.Space.s) {
                        ForEach(store.visibleRooms) { room in
                            NavigationLink(value: room) {
                                ScanRoomCard(room: room, items: store.visibleItems.filter { $0.roomId == room.id })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, Theme.Space.section)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Room.self) { RoomDetailView(room: $0) }
        .navigationDestination(item: $openRoom) { RoomDetailView(room: $0) }
        .mooveScreen()
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            if !store.items.isEmpty { tab = "inventory" }
        }) {
            ScanFlowView()
        }
        .fullScreenCover(isPresented: $demoFinished, onDismiss: { tab = "inventory" }) {
            NavigationStack {
                ScanFinishedScreen(roomName: demo.roomName, isDemo: true, importedCount: demo.objects.count) { demoFinished = false }
            }
            .tint(Theme.accentStrong)
        }
    }

    private var startScan: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                scanning = true
            } label: {
                Label("Scan a room", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .disabled(!RoomCaptureSession.isSupported)
            demoScan
            if !RoomCaptureSession.isSupported {
                ScanNotice(
                    text: "No LiDAR on this device",
                    systemImage: "exclamationmark.triangle",
                    tint: Theme.muted
                )
            }
        }
    }

    private var demo: ScanImport {
        var scan = DemoFixtures.scanImport()
        #if DEBUG
        // UI test hook (#180): two impossible objects, which the import skips and reports.
        if ProcessInfo.processInfo.environment["MOOVE_DEMO_BAD_OBJECTS"] != nil {
            scan.objects += [
                ScanObject(scanObjectId: "bad-nan", category: "table", widthM: .nan, heightM: 0.7, depthM: 0.6),
                ScanObject(scanObjectId: "bad-huge", category: "storage", widthM: 40, heightM: 2.4, depthM: 0.4),
            ]
        }
        // UI test hook: one object nobody could name, for Review's "Needs a name".
        if ProcessInfo.processInfo.environment["MOOVE_DEMO_UNNAMED"] != nil {
            scan.objects.append(ScanObject(scanObjectId: "unnamed-1", category: "other", widthM: 0.5, heightM: 0.4, depthM: 0.5))
        }
        #endif
        return scan
    }

    private var demoScan: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                loadingDemo = true
                Task {
                    let imported = await store.importScan(demo)
                    loadingDemo = false
                    guard imported else { return }
                    // Same finished screen as a real scan, then the same color write a real
                    // scan does after sampling (here the demo room's fixture colors).
                    demoFinished = true
                    await store.flagDemoSentimental(roomName: demo.roomName)
                    await store.saveScanColors(DemoFixtures.scanColors(), roomName: demo.roomName)
                    // Offline there's no worker: play the room photo sweep so the demo shows it.
                    await store.simulateSweep(roomName: demo.roomName)
                }
            } label: {
                Label(loadingDemo ? "Loading…" : "Load demo scan", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.outline))
            .disabled(loadingDemo)
            .accessibilityHint("Imports a recorded bedroom, the same way a real scan does")
        }
    }
}

/// Attention notice: mono text on the raised surface with a colored left edge (as on the listing page).
private struct ScanNotice: View {
    var text: String
    var systemImage: String
    var tint: Color = Theme.muted

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(text)
                .monoText(13)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: UnevenRoundedRectangle(bottomTrailingRadius: Theme.Radius.chip, topTrailingRadius: Theme.Radius.chip))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .accessibilityElement(children: .combine)
    }
}
