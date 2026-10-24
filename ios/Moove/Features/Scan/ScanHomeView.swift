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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "01 — Scan",
                    title: "Scan a room.",
                    lede: "Walk slowly around the room with the camera. Moove finds each piece of furniture and measures it, then you snap a photo of each one."
                )
                startScan.padding(.top, 28)
                demoScan.padding(.top, 40)
                if !store.snapshot.rooms.isEmpty {
                    ListHeader(title: "Scanned rooms", count: "\(store.snapshot.rooms.count)")
                        .padding(.top, 40)
                    ForEach(store.snapshot.rooms) { room in
                        NavigationLink(value: room) {
                            LedgerRow(
                                title: room.name,
                                value: "\(store.items.filter { $0.roomId == room.id }.count) items",
                                chevron: true
                            ) {
                                IconTile(systemName: "cube.transparent")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Room.self) { RoomDetailView(room: $0) }
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
        VStack(alignment: .leading, spacing: 14) {
            Button {
                scanning = true
            } label: {
                Label("Start scan", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .disabled(!RoomCaptureSession.isSupported)
            if !RoomCaptureSession.isSupported {
                ScanNotice(
                    text: "This device has no LiDAR scanner. Use an iPhone 12 Pro or iPad Pro (2020) or later, or load the demo scan.",
                    systemImage: "exclamationmark.triangle",
                    tint: Theme.danger
                )
            }
        }
    }

    private var demo: ScanImport { DemoFixtures.scanImport() }

    private var demoScan: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeader(title: "Demo scan") { MonoTag(text: "Demo", tone: Theme.ochreInk) }
            Text("Imports a recorded bedroom through the same path as a real scan and shows its 3D results. Use it if a live scan fails on stage.")
                .monoMeta()
                .fixedSize(horizontal: false, vertical: true)
            Button {
                loadingDemo = true
                Task {
                    let imported = await store.importScan(demo)
                    loadingDemo = false
                    guard imported else { return }
                    // Same finished screen as a real scan, then the same color write a real
                    // scan does after sampling (here the demo room's fixture colors).
                    demoFinished = true
                    await store.saveScanColors(DemoFixtures.scanColors(), roomName: demo.roomName)
                }
            } label: {
                Label(loadingDemo ? "Loading…" : "Load demo scan", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.outline))
            .disabled(loadingDemo)
        }
    }
}

/// Attention notice: mono text on the raised surface with a colored left edge (as on the listing page).
private struct ScanNotice: View {
    var text: String
    var systemImage: String
    var tint: Color = Theme.ochre

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
        .background(Theme.surface, in: UnevenRoundedRectangle(bottomTrailingRadius: Theme.radiusSmall, topTrailingRadius: Theme.radiusSmall))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .accessibilityElement(children: .combine)
    }
}
