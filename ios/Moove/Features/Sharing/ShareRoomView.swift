import SwiftUI
import UIKit
import MooveKit

/// Shows a room's join code so a second phone can join it (#10).
struct ShareRoomView: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter this code on the other phone under **Inventory → Join a room**. You'll both see and edit the same items, live.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let code = room.joinCode {
                    Text(code)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .kerning(6)
                        .textSelection(.enabled)
                        .accessibilityLabel(code.map(String.init).joined(separator: " "))

                    HStack {
                        Button(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            UIPasteboard.general.string = code
                            copied = true
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: "Join my room in Moove: \(code)") {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView("No code yet", systemImage: "number",
                                           description: Text("This room doesn't have a join code."))
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Share \(room.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ShareRoomView(room: Room(id: 1, owner: "me", name: "Bedroom", joinCode: "ABC234"))
}
