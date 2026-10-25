import SwiftUI
import MooveKit

/// Inventory room chip ⋯ → **Rename room**: an alert with the room's name in a text field.
/// `MooveStore.renameRoom` calls `rename_room` (#370), or keeps the name on this device until
/// the module has it, so every screen shows the new name either way.
struct RoomRenameAlert: ViewModifier {
    @Binding var room: Room?
    @Environment(MooveStore.self) private var store
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert("Rename room", isPresented: Binding(get: { room != nil }, set: { if !$0 { room = nil } }), presenting: room) { room in
                TextField("Room name", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("inventory.roomName.field")
                Button("Save") {
                    let newName = name
                    Task { await store.renameRoom(room, to: newName) }
                }
                .accessibilityIdentifier("inventory.roomName.save")
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("What do you call this room? Moove shows this name everywhere.")
            }
            .onChange(of: room?.id) {
                if let room { name = store.displayName(of: room) }
            }
    }
}

extension View {
    /// Presents the Rename room alert while `room` is set.
    func roomRenameAlert(_ room: Binding<Room?>) -> some View {
        modifier(RoomRenameAlert(room: room))
    }
}
