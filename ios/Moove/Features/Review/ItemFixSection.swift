import SwiftUI
import MooveKit

/// "Fix it" on Item detail: correct a misread scan item in a tap or two. Rename, pick what it
/// is, turn it around, or remove it. Writes go through `MooveStore` (existing reducers:
/// `rename_item`, `set_item_attributes`, `delete_item`); every 3D view re-derives from the item.
struct ItemFixSection: View {
    @Environment(MooveStore.self) private var store
    let item: Item
    @State private var name = ""
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ListHeader(title: "Fix it").padding(.top, 40)
        rename
        kindChips
        turnButtons
        notReal
    }

    // MARK: Rename

    private var rename: some View {
        HStack(spacing: 8) {
            TextField("Name", text: $name)
                .monoText(15)
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit(save)
                .accessibilityLabel("Item name")
                .accessibilityIdentifier("item.fix.name")
            if trimmed != item.name && !trimmed.isEmpty {
                Button("Save", action: save)
                    .buttonStyle(.pill(.primary, compact: true))
                    .accessibilityLabel("Save name")
                    .accessibilityIdentifier("item.fix.saveName")
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .ruled()
        .onAppear { name = item.name }
        .onChange(of: item.name) { _, new in if !nameFocused { name = new } }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        nameFocused = false
        let new = trimmed
        guard !new.isEmpty else { name = item.name; return }
        Task { await store.renameItem(item, to: new) }
    }

    // MARK: What is it?

    private var kindChips: some View {
        let current = ItemFix.quickKind(in: item.attributes)
        return VStack(alignment: .leading, spacing: 6) {
            Text("What is it?").monoText(13.5).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 0) {
                ForEach(ItemFix.QuickKind.allCases) { kind in
                    ChoiceChip(title: kind.label, selected: kind == current) {
                        Task { await store.setQuickKind(kind, for: item) }
                    }
                    .accessibilityLabel(kind == .other ? "Other, automatic" : "It's a \(kind.label)")
                    .accessibilityIdentifier("item.fix.kind.\(kind.rawValue)")
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What is it?")
    }

    // MARK: Turn

    private var turnButtons: some View {
        let turn = item.userTurnDeg
        return HStack(spacing: 8) {
            Button { Task { await store.turn(item) } } label: {
                Label("Turn around", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityIdentifier("item.fix.turnAround")
            Button { Task { await store.turn(item, by90: true) } } label: {
                Label("90°", systemImage: "rotate.right")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityLabel("Rotate 90 degrees")
            .accessibilityIdentifier("item.fix.rotate90")
            Spacer(minLength: 8)
            if turn != 0 {
                Text("Turned \(turn)°").monoMeta()
                    .accessibilityLabel("Turned \(turn) degrees")
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .ruled()
    }

    // MARK: Not a real item

    @ViewBuilder private var notReal: some View {
        HStack(spacing: 8) {
            if confirmingDelete {
                Text("Remove it?").monoText(13.5).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Button("Cancel") { confirmingDelete = false }
                    .buttonStyle(.pill(.text, compact: true))
                    .accessibilityIdentifier("item.fix.cancelDelete")
                Button("Remove") { Task { await store.deleteItem(item) } }
                    .buttonStyle(.pill(.danger, compact: true))
                    .accessibilityLabel("Remove \(item.name)")
                    .accessibilityIdentifier("item.fix.confirmDelete")
            } else {
                Button { confirmingDelete = true } label: {
                    Label("Not a real item", systemImage: "trash")
                }
                .buttonStyle(.pill(.text, compact: true))
                .foregroundStyle(Theme.danger)
                .accessibilityHint("Asks before removing it")
                .accessibilityIdentifier("item.fix.delete")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .ruled()
    }
}

/// The same fixes as a menu, for long-pressing an Inventory row, plus "Not a <category>? Take a
/// photo" (reclassify from a retake). "Not a real item" is a submenu whose one entry is the confirm.
struct ItemFixMenu: View {
    @Environment(MooveStore.self) private var store
    let item: Item
    var onRename: () -> Void
    /// "Not a vacuum? Take a photo": opens the camera for a reclassify retake (`ItemReclassify`).
    var onReclassify: (() -> Void)? = nil

    var body: some View {
        Button("Rename", systemImage: "pencil", action: onRename)
        if let onReclassify {
            Button(ItemReclassify.menuTitle(for: item), systemImage: "camera.viewfinder", action: onReclassify)
        }
        Menu {
            ForEach(ItemFix.QuickKind.allCases) { kind in
                Button(kind.label) { Task { await store.setQuickKind(kind, for: item) } }
            }
        } label: {
            Label("What is it?", systemImage: "questionmark.circle")
        }
        Button("Turn around", systemImage: "arrow.uturn.backward") { Task { await store.turn(item) } }
        Button("Rotate 90°", systemImage: "rotate.right") { Task { await store.turn(item, by90: true) } }
        Menu {
            Button("Remove \(item.name)", systemImage: "trash", role: .destructive) {
                Task { await store.deleteItem(item) }
            }
        } label: {
            Label("Not a real item", systemImage: "trash")
        }
    }
}
