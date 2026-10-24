import SwiftUI
import QuickLook
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
    /// Memoized `centered()` / `cutaway(at:)`, recomputed only when `geometry` changes.
    @State private var display = RoomDisplayGeometry()

    @State private var style: Style = .model
    @State private var mode: RoomPalette.Mode = .category
    @State private var showLabels = true
    @State private var fullWalls = false
    @State private var selection: String?
    @State private var capturing: RoomGeometry.Object?
    @State private var models = ObjectModelStore.shared

    var body: some View {
        let centered = display.centered(geometry)
        let shown = fullWalls ? centered : display.cutaway(geometry, at: 1.2)
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(white: 0.97), Color(red: 0.88, green: 0.91, blue: 0.97)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Group {
                if style == .model, #available(iOS 18.0, *) {
                    RoomModelView(geometry: shown, items: items, mode: mode, showLabels: showLabels, selection: $selection)
                        .id(fullWalls)  // rebuild the scene when walls change
                } else {
                    RoomPlanView(geometry: centered, items: items, mode: mode, showLabels: showLabels, selection: $selection)
                        .padding(.bottom, 60)
                }
            }
            VStack(spacing: 10) {
                if let id = selection, let object = geometry.objects.first(where: { $0.id == id }) {
                    SelectedObjectCard(object: object, item: items[id], models: models,
                                       capture: { capturing = object }, close: { selection = nil })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                legend
            }
            .padding()
            .animation(.snappy, value: selection)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $style) {
                    ForEach(Style.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
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
        .fullScreenCover(item: $capturing) { object in
            ObjectCaptureFlowView(objectId: object.id, title: items[object.id]?.name ?? object.category.capitalized)
        }
        .onAppear {
            mode = initialMode
            #if DEBUG
            if ProcessInfo.processInfo.environment["MOOVE_ROOM_STYLE"] == "plan" { style = .plan }
            if ProcessInfo.processInfo.environment["MOOVE_ROOM_MODE"] == "decision" { mode = .decision }
            #endif
        }
    }

    private var legend: some View {
        let entries: [(String, UIColor)] = mode == .decision
            ? Disposition.allCases.map { d in (d.label, RoomPalette.decision(Item(id: 0, owner: "", roomId: 0, name: "", category: "", widthM: 0, heightM: 0, depthM: 0, disposition: d))) }
            : Array(Set(geometry.objects.map(\.category))).sorted().map { ($0.capitalized, RoomPalette.category($0)) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(entries, id: \.0) { name, color in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(color)).frame(width: 12, height: 12)
                        Text(name).font(.caption)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial, in: .capsule)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SelectedObjectCard: View {
    let object: RoomGeometry.Object
    let item: Item?
    let models: ObjectModelStore
    let capture: () -> Void
    let close: () -> Void
    @State private var quickLook: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let item {
                    ItemThumbnail(item: item, size: 52)
                } else {
                    Image(systemName: ItemThumbnail.icon(for: object.category))
                        .font(.title2).frame(width: 52, height: 52)
                        .background(Color(RoomPalette.category(object.category)).opacity(0.25), in: .rect(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item?.name ?? object.category.capitalized).font(.headline)
                    Text(size).font(.caption).foregroundStyle(.secondary)
                    if let item {
                        HStack(spacing: 6) {
                            DispositionChip(disposition: item.disposition)
                            if let value = item.estValueCents { Text(value.usd).font(.caption.monospacedDigit()) }
                        }
                    }
                }
                Spacer()
                if let item {
                    NavigationLink(value: item.id) {
                        Image(systemName: "chevron.right.circle.fill").font(.title2)
                    }
                }
                Button("Close", systemImage: "xmark.circle.fill", action: close)
                    .labelStyle(.iconOnly).font(.title2).foregroundStyle(.secondary)
            }
            modelButtons
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .quickLookPreview($quickLook)
    }

    @ViewBuilder private var modelButtons: some View {
        if let url = models.modelURL(for: object.id) {
            HStack {
                Button("View in AR", systemImage: "arkit") { quickLook = url }
                Button("Rotate 90°", systemImage: "rotate.right") { models.rotate(object.id) }
                Spacer()
                Button("Recapture", systemImage: "camera.metering.center.weighted", action: capture)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        } else if ObjectCaptureFlowView.isSupported {
            Button(action: capture) {
                Label("Capture 3D model", systemImage: "cube.transparent").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
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
