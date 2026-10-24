import SwiftUI
import MooveKit

/// 3D model / floor plan switcher with coloring and label controls, and a
/// card for the selected piece of furniture.
struct RoomVisualizationView: View {
    enum Style: String, CaseIterable, Identifiable {
        case model, plan
        var id: String { rawValue }
        var label: String { self == .model ? "3D" : "Plan" }
    }

    let geometry: RoomGeometry
    /// Inventory items keyed by `scanObjectId`.
    var items: [String: Item] = [:]
    var initialMode: RoomPalette.Mode = .category

    @State private var style: Style = .model
    @State private var mode: RoomPalette.Mode = .category
    @State private var showLabels = true
    @State private var fullWalls = false
    @State private var selection: String?

    var body: some View {
        let centered = geometry.centered()
        let shown = fullWalls ? centered : centered.cutaway(at: 1.2)
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            Group {
                if style == .model, #available(iOS 18.0, *) {
                    RoomModelView(geometry: shown, items: items, mode: mode, showLabels: showLabels, selection: $selection)
                        .id(fullWalls)  // rebuild the scene when walls change
                } else {
                    RoomPlanView(geometry: centered, items: items, mode: mode, showLabels: showLabels, selection: $selection)
                        .padding(.bottom, 60)
                }
            }
            // The 3D scene and the plan canvas draw pixels VoiceOver can't read, so
            // expose each piece of furniture as its own element: swipe through them,
            // double-tap to select (which opens the item card below).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityChildren {
                ForEach(geometry.objects) { object in
                    Text(accessibilityName(object))
                        .accessibilityAddTraits(selection == object.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { selection = object.id }
                }
            }
            VStack(spacing: 10) {
                if let id = selection, let object = geometry.objects.first(where: { $0.id == id }) {
                    SelectedObjectCard(object: object, item: items[id]) { selection = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                legend
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 16)
            .animation(.snappy, value: selection)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                PillPicker(options: Style.allCases, selection: $style) { $0.label }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("View")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Color by", selection: $mode) {
                        ForEach(RoomPalette.Mode.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Labels", isOn: $showLabels)
                    Toggle("Full-height walls", isOn: $fullWalls)
                } label: {
                    Label("Display", systemImage: "paintpalette")
                }
            }
        }
        .mooveScreen()
        .onAppear {
            mode = initialMode
            #if DEBUG
            if ProcessInfo.processInfo.environment["MOOVE_ROOM_STYLE"] == "plan" { style = .plan }
            if ProcessInfo.processInfo.environment["MOOVE_ROOM_MODE"] == "decision" { mode = .decision }
            #endif
        }
    }

    private var accessibilitySummary: String {
        let n = geometry.objects.count
        return "\(style == .model ? "3D model" : "Floor plan") of the room: \(n) item\(n == 1 ? "" : "s"), \(geometry.walls.count) walls, \(geometry.openings.count) doors and windows"
    }

    private func accessibilityName(_ object: RoomGeometry.Object) -> String {
        let item = items[object.id]
        var parts = [item?.name ?? object.category.capitalized]
        if let item { parts.append(item.disposition.label) }
        if let value = item?.estValueCents { parts.append(value.usd) }
        let d = object.dimensions
        parts.append(String(format: "%.1f by %.1f meters", d.x, d.z))
        return parts.joined(separator: ", ")
    }

    private var legend: some View {
        let entries: [(String, UIColor)] = mode == .decision
            ? Disposition.allCases.map { d in (d.label, RoomPalette.decision(Item(id: 0, owner: "", roomId: 0, name: "", category: "", widthM: 0, heightM: 0, depthM: 0, disposition: d))) }
            : Array(Set(geometry.objects.map(\.category))).sorted().map { ($0.capitalized, RoomPalette.category($0)) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(entries, id: \.0) { name, color in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(color)).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(name).monoText(11.5, maxScale: 1.5).foregroundStyle(Theme.text)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Capsule().fill(Theme.bg))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SelectedObjectCard: View {
    let object: RoomGeometry.Object
    let item: Item?
    let close: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let item {
                ItemThumbnail(item: item, size: 56)
            } else {
                Image(systemName: ItemThumbnail.icon(for: object.category))
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.text)
                    .frame(width: 56, height: 56)
                    .background(Color(RoomPalette.category(object.category)).opacity(0.3),
                                in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item?.name ?? object.category.capitalized).blockTitle().lineLimit(2)
                Text(size).monoMeta()
                if let item {
                    HStack(spacing: 8) {
                        DispositionChip(disposition: item.disposition)
                        if let value = item.estValueCents { Text(value.usd).rowValue() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let item {
                NavigationLink(value: item.id) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.accentFill))
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
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
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
