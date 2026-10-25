import SwiftUI
import MooveKit

/// The room as a voxel dollhouse (the app's one 3D look, decision 0108 / #236), with a menu to
/// pick a piece and a card for the selected one. No style picker: the Plan and RoomPlan-boxes
/// styles were removed (Lisa).
struct RoomVisualizationView: View {
    let geometry: RoomGeometry
    /// Inventory items keyed by `scanObjectId`.
    var items: [String: Item] = [:]
    /// The room's name and all its items (also ones with no scanned box).
    var roomName = "Room"
    var roomItems: [Item] = []

    @State private var selection: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            // The camera frames the room before the view has a size (as if 0.8 wide), so
            // a tall full-screen view crops the walls; a square leaves room on the sides.
            RoomVoxelView(geometry: geometry, roomName: roomName, items: roomItems)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 60)
                // `.accessibilityChildren` around the ARView stops it drawing, so VoiceOver
                // gets the furniture list from a clear overlay instead.
                .overlay { furnitureForVoiceOver(Color.clear.allowsHitTesting(false)) }
            if let id = selection, let object = geometry.objects.first(where: { $0.id == id }) {
                SelectedObjectCard(object: object, item: items[id]) { selection = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 16)
            }
        }
        .animation(.snappy, value: selection)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The voxel view can't be tapped, so it lists the pieces instead (to open one's card).
                if !items.isEmpty { pieceMenu }
            }
        }
        .mooveScreen()
    }

    /// The 3D scene draws pixels VoiceOver can't read, so expose each piece of furniture as its
    /// own element: swipe through them, double-tap to select (which opens the item card below).
    private func furnitureForVoiceOver(_ content: some View) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            // On the combined element: `.ignore` hides identifiers set inside it.
            .accessibilityIdentifier("room.voxel")
            .accessibilityChildren {
                ForEach(geometry.objects) { object in
                    Text(accessibilityName(object))
                        .accessibilityAddTraits(selection == object.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selection = object.id }
                }
            }
    }

    /// Pick a piece to show its card (Rename, What is it?).
    private var pieceMenu: some View {
        Menu {
            ForEach(geometry.objects.filter { items[$0.id] != nil }) { object in
                Button(items[object.id]?.name ?? object.category.capitalized) { selection = object.id }
            }
        } label: {
            Label("Items", systemImage: "list.bullet")
        }
        .accessibilityLabel("Pick an item")
        .accessibilityIdentifier("room.items")
    }

    private var accessibilitySummary: String {
        let n = geometry.objects.count
        return "Voxel model of the room: \(n) item\(n == 1 ? "" : "s"), \(geometry.walls.count) walls, \(geometry.openings.count) doors and windows"
    }

    private func accessibilityName(_ object: RoomGeometry.Object) -> String {
        let item = items[object.id]
        var parts = [item?.name ?? object.category.capitalized]
        if let item { parts.append(item.disposition.label) }
        if let value = item?.saleValueCents { parts.append(value.usd) }
        let d = object.dimensions
        parts.append(String(format: "%.1f by %.1f meters", d.x, d.z))
        return parts.joined(separator: ", ")
    }
}

private struct SelectedObjectCard: View {
    @Environment(MooveStore.self) private var store
    let object: RoomGeometry.Object
    let item: Item?
    let close: () -> Void
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            if let item { relabel(item) }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("room.selection")
        .alert("Rename", isPresented: $renaming, presenting: item) { item in
            TextField("Name", text: $newName)
            Button("Save") { Task { await store.renameItem(item, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Relabel straight from the 3D view: the model rebuilds from the new name or kind.
    private func relabel(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Button {
                newName = item.name
                renaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityLabel("Rename \(item.name)")
            .accessibilityIdentifier("room.selection.rename")
            Menu {
                let current = ItemFix.quickKind(in: item.attributes)
                ForEach(ItemFix.QuickKind.allCases) { kind in
                    Toggle(kind == .other ? "Other (automatic)" : kind.label, isOn: Binding(
                        get: { kind == current },
                        set: { _ in Task { await store.setQuickKind(kind, for: item) } }))
                }
            } label: {
                Label("What is it?", systemImage: "questionmark.circle")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityIdentifier("room.selection.kind")
            Spacer(minLength: 0)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            if let item {
                ItemThumbnail(item: item, size: 56)
            } else {
                Image(systemName: ItemThumbnail.icon(for: object.category))
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 56, height: 56)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .accessibilityHidden(true)
            }
            // One line: name and value. Size and decision are in the VoiceOver label.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item?.name ?? object.category.capitalized).blockTitle().lineLimit(2)
                Spacer(minLength: 4)
                if let value = item?.saleValueCents { Text(value.usd).rowValue() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullLabel)
            if let item {
                NavigationLink(value: item.id) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surface))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Item details")
            }
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
    }

    private var fullLabel: String {
        var parts = [item?.name ?? object.category.capitalized, size]
        if let item { parts.append(item.disposition.label) }
        if let value = item?.saleValueCents { parts.append(value.usd) }
        return parts.joined(separator: ", ")
    }

    private var size: String {
        let f = { (v: Float) in Double(v).formatted(.number.precision(.fractionLength(2))) }
        let d = object.dimensions
        return "\(f(d.x)) × \(f(d.z)) × \(f(d.y)) m"
    }
}

#Preview {
    NavigationStack {
        RoomVisualizationView(geometry: DemoFixtures.roomGeometry(),
                              items: Dictionary(uniqueKeysWithValues: DemoFixtures.inventory(owner: "me").items.map { ($0.scanObjectId!, $0) }))
    }
}
