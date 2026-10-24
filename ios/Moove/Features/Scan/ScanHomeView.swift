import SwiftUI
import RoomPlan
import MooveKit

struct ScanHomeView: View {
    @Environment(MooveStore.self) private var store
    @AppStorage("moove.tab") private var tab = "scan"
    @State private var scanning = false
    @State private var loadingDemo = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Scan a room", systemImage: "camera.viewfinder").font(.title2.bold())
                    Text("Walk slowly around the room with the camera. Moove finds each piece of furniture and measures it, then you snap a photo of each one.")
                        .foregroundStyle(.secondary)
                    Button {
                        scanning = true
                    } label: {
                        Text("Start scan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!RoomCaptureSession.isSupported)
                    if !RoomCaptureSession.isSupported {
                        Text("This device has no LiDAR scanner. Use an iPhone 12 Pro or iPad Pro (2020) or later, or load the demo scan.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 8)
            }
            Section {
                Button {
                    loadingDemo = true
                    Task {
                        let imported = await store.importScan(DemoFixtures.scanImport())
                        loadingDemo = false
                        if imported { tab = "inventory" }
                    }
                } label: {
                    Label(loadingDemo ? "Loading…" : "Load demo scan", systemImage: "tray.and.arrow.down")
                }
                .disabled(loadingDemo)
            } footer: {
                Text("Imports a recorded bedroom through the same path as a real scan. Use it if a live scan fails on stage.")
            }
            if !store.snapshot.rooms.isEmpty {
                Section("Scanned rooms") {
                    ForEach(store.snapshot.rooms) { room in
                        NavigationLink(value: room) {
                            LabeledContent(room.name, value: "\(store.items.filter { $0.roomId == room.id }.count) items")
                        }
                    }
                }
            }
        }
        .navigationTitle("Scan")
        .navigationDestination(for: Room.self) { RoomDetailView(room: $0) }
        .fullScreenCover(isPresented: $scanning, onDismiss: {
            if !store.items.isEmpty { tab = "inventory" }
        }) {
            ScanFlowView()
        }
    }
}
