import SwiftUI
import MooveKit

/// Debug/settings sheet: backend toggle (demo fallback) and connection info.
struct SettingsView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    Picker("Data source", selection: Binding(
                        get: { store.backendKind },
                        set: { kind in Task { await store.switchBackend(to: kind, token: nil) } }
                    )) {
                        ForEach(MooveStore.BackendKind.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent("Status", value: statusText)
                    LabeledContent("Server", value: "\(AppConfig.current.spacetimeHost) / \(AppConfig.current.spacetimeDB)")
                    if let me = store.snapshot.me {
                        LabeledContent("Identity", value: String(me.prefix(16)) + "…")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var statusText: String {
        switch store.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting(let n): "Reconnecting (\(n))"
        case .failed(let why): "Failed: \(why)"
        }
    }
}
