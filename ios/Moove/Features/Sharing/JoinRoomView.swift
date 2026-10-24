import SwiftUI
import MooveKit

/// Joins someone else's room by its 6-character code (#10). The room and its
/// items then arrive through the `room_member` subscription.
struct JoinRoomView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var joining = false
    @State private var error: String?
    @State private var joined = false
    @FocusState private var focused: Bool

    private static let length = 6

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABC123", text: $code)
                        .font(.system(.title, design: .monospaced, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .focused($focused)
                        .onSubmit(join)
                        .onChange(of: code) { _, new in
                            let clean = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(Self.length))
                            if clean != new { code = clean }
                            error = nil
                        }
                } header: {
                    Text("Room code")
                } footer: {
                    if store.backendKind == .fixture {
                        Text("Offline demo: try \(DemoFixtures.roommateJoinCode).")
                    } else {
                        Text("Ask the room's owner to tap Share room in their Inventory.")
                    }
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                if joined {
                    Label("Joined. The room will appear in your inventory.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }

                Button(action: join) {
                    HStack {
                        Text("Join")
                        if joining { Spacer(); ProgressView() }
                    }
                }
                .disabled(code.count != Self.length || joining || joined)
            }
            .navigationTitle("Join a room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func join() {
        guard code.count == Self.length, !joining else { return }
        joining = true
        error = nil
        Task {
            let ok = await store.joinRoom(code: code)
            joining = false
            if ok {
                joined = true
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            } else {
                // Show it here instead of in the app-wide banner.
                let detail = store.lastError ?? ""
                store.lastError = nil
                error = detail.localizedCaseInsensitiveContains("no room") || detail.contains("noSuchRoomCode")
                    ? "No room has that code. Check it and try again."
                    : "Couldn't join: \(detail)"
            }
        }
    }
}

#Preview {
    JoinRoomView().environment(MooveStore.preview())
}
