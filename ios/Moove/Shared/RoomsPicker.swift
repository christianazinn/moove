import SwiftUI
import MooveKit

// "Rooms in this move": the app's one room selection (MooveStore `roomPicks`, MooveKit
// `RoomSelection`, UserDefaults `moove.rooms`). The same Rooms button sits at the top of
// Inventory and Move and opens the same checklist; Inventory, Review and Move all read it.

/// What a room row's ⋯ asked the screen to do once the sheet is gone.
enum RoomAction {
    case share, view3D, addItem
}

/// A compact pill: "Rooms" and the selected rooms' names. Opens `RoomsSheet`.
struct RoomsButton: View {
    @Environment(MooveStore.self) private var store
    var onTap: () -> Void

    var body: some View {
        let names = store.roomChoices.filter(\.selected).map(\.room.name)
        let list = names.isEmpty ? "None" : names.joined(separator: ", ")
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text("Rooms")
                Text(list).fontWeight(.regular).foregroundStyle(Theme.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.pill(.outline, compact: true))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rooms: \(list)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Choose which rooms are in this move")
        .accessibilityIdentifier("rooms.button")
    }
}

/// The checklist of room names (newest scan first) with Select all / None. Long-press or ⋯ on a
/// row has Rename, and Share / 3D / Add item when the screen passes `onAction`.
struct RoomsSheet: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onAction: ((RoomAction, Room) -> Void)?
    @State private var renaming: Room?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    allNone.padding(.bottom, 8)
                    ForEach(store.roomChoices) { row($0) }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 16)
            }
            .mooveScreen()
            .navigationTitle("Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .monoText(13, weight: .bold, maxScale: 1.4)
                        .accessibilityIdentifier("rooms.done")
                }
            }
            .roomRenameAlert($renaming)
        }
    }

    private var allNone: some View {
        let choices = store.roomChoices
        return HStack(spacing: 10) {
            Button("Select all") { store.selectAllRooms(true) }
                .buttonStyle(.pill(.outline, compact: true))
                .disabled(choices.allSatisfy(\.selected))
            Button("None") { store.selectAllRooms(false) }
                .buttonStyle(.pill(.outline, compact: true))
                .disabled(!choices.contains(where: \.selected))
            Spacer(minLength: 0)
        }
    }

    private func row(_ c: RoomSelection.Choice) -> some View {
        HStack(spacing: 4) {
            Button { store.toggleRoom(c.id) } label: { rowLabel(c) }
                .buttonStyle(.plain)
                .contextMenu { actions(c.room) }
                .accessibilityLabel(spoken(c.room))
                .accessibilityAddTraits(c.selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(c.selected ? "Leaves this room out" : "Puts this room in")
                .accessibilityIdentifier("rooms.room.\(c.id)")
            if hasActions(c.room) {
                Menu { actions(c.room) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.muted)
                .accessibilityLabel("\(c.room.name) actions")
                .accessibilityIdentifier("rooms.actions.\(c.id)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5) }
    }

    private func rowLabel(_ c: RoomSelection.Choice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: c.selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(c.selected ? Theme.text : Theme.faint)
                .accessibilityHidden(true)
            Text(c.room.name)
                .sansText(16)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actions(_ room: Room) -> some View {
        let mine = isMine(room)
        if let onAction {
            if mine { Button("Share \(room.name)", systemImage: "person.badge.plus") { onAction(.share, room) } }
            Button("View room in 3D", systemImage: "cube.transparent") { onAction(.view3D, room) }
            Button("Add item here", systemImage: "plus") { onAction(.addItem, room) }
        }
        if mine {
            Button("Rename room", systemImage: "pencil") { renaming = room }
                .accessibilityIdentifier("inventory.renameRoom.\(room.id)")
        }
    }

    private func hasActions(_ room: Room) -> Bool { onAction != nil || isMine(room) }

    /// Rooms are mine unless someone shared them with me through a join code (#10).
    private func isMine(_ room: Room) -> Bool { room.owner == store.snapshot.me }

    /// "Living room, shared by Sam": the row prints only the name.
    private func spoken(_ room: Room) -> String {
        guard !isMine(room) else { return room.name }
        let owner = store.snapshot.users.first { $0.identity == room.owner }?.name ?? "someone"
        return "\(room.name), shared by \(owner)"
    }
}
