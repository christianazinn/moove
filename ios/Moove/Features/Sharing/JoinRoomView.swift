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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(
                        eyebrow: "02 — Inventory · Join",
                        title: "Join a room.",
                        lede: store.backendKind == .fixture
                            ? "Offline demo: try \(DemoFixtures.roommateJoinCode)."
                            : "Ask the room's owner to tap Share in their Inventory, then enter the 6-character code."
                    )
                    Text("Room code").eyebrow().padding(.top, 28)
                    TextField("ABC123", text: $code)
                        .monoText(32, weight: .bold, maxScale: 1.4)
                        .kerning(6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.text)
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
                        .frame(minHeight: 56)
                        .ruled()
                        .accessibilityLabel("Room code")
                        .accessibilityHint("Six letters and numbers")

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .monoText(13.5)
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 14)
                    }
                    if joined {
                        Label("Joined. The room will appear in your inventory.", systemImage: "checkmark.circle")
                            .monoText(13.5)
                            .foregroundStyle(Theme.accentStrong)
                            .padding(.top, 14)
                    }

                    Button(action: join) {
                        HStack(spacing: 8) {
                            Text(joining ? "Joining…" : "Join")
                            if joining { ProgressView().controlSize(.small) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.primary))
                    .disabled(code.count != Self.length || joining || joined)
                    .padding(.top, 24)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Join")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .mooveScreen()
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
