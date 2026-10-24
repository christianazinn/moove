import SwiftUI
import QuickLook
import MooveKit

/// One item: photo, what the vision agent saw, why it was sorted this way,
/// and the comps behind its price.
struct ItemDetailView: View {
    @Environment(MooveStore.self) private var store
    let itemId: UInt64
    @State private var models = ObjectModelStore.shared
    @State private var capturing = false
    @State private var quickLook: URL?

    var body: some View {
        if let item = store.items.first(where: { $0.id == itemId }) {
            content(item)
        } else {
            ContentUnavailableView("Item removed", systemImage: "shippingbox")
        }
    }

    private func content(_ item: Item) -> some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ItemThumbnail(item: item, size: 160)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Decision") {
                Picker("Disposition", selection: Binding(
                    get: { item.disposition },
                    set: { d in Task { await store.setDisposition(d, for: item) } }
                )) {
                    ForEach(Disposition.choices, id: \.self) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    if item.disposition == .undecided { Text("Undecided").tag(Disposition.undecided) }
                }
                .pickerStyle(.menu)
                LabeledContent("Decided by", value: item.dispositionSource == .user ? "You" : "Moove (auto)")
                if let reason = item.dispositionReason {
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
                Toggle("Possibly sentimental", isOn: Binding(
                    get: { item.maybeSentimental },
                    set: { v in Task { await store.setSentimental(v, for: item) } }
                ))
            }
            modelSection(item)
            Section("Details") {
                LabeledContent("Estimated value", value: item.estValueCents?.usd ?? "Pricing…")
                LabeledContent("Category", value: item.category)
                if let material = item.material { LabeledContent("Material", value: material) }
                if let brand = item.brand { LabeledContent("Brand", value: brand) }
                if let condition = item.condition { LabeledContent("Condition", value: "\(condition) / 5") }
                LabeledContent("Size", value: dims(item))
                if item.fragile { Label("Fragile", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            let comps = store.snapshot.comps(for: item.id)
            if !comps.isEmpty {
                Section("Comparable listings") {
                    ForEach(comps) { comp in
                        if let url = URL(string: comp.url) {
                            Link(destination: url) {
                                LabeledContent(comp.title, value: comp.priceCents.usd)
                            }
                        }
                        Text(comp.source.uppercased()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(item.name)
        .quickLookPreview($quickLook)
        .task(id: item.modelUrl) {
            if let remote = item.modelUrl.flatMap(URL.init(string:)) { await models.fetchRemote(remote, for: modelKey(item)) }
        }
        .fullScreenCover(isPresented: $capturing) {
            ObjectCaptureFlowView(objectId: modelKey(item), title: item.name) { file in
                Task { await store.publishCapturedModel(scanObjectId: modelKey(item), file: file) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dims(_ item: Item) -> String {
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(2))) }
        return "\(f(item.widthM)) × \(f(item.depthM)) × \(f(item.heightM)) m"
    }

    /// Models are keyed by the RoomPlan object id so the room view can place them.
    private func modelKey(_ item: Item) -> String { item.scanObjectId ?? "item-\(item.id)" }

    @ViewBuilder private func modelSection(_ item: Item) -> some View {
        let key = modelKey(item)
        if let url = models.modelURL(for: key) {
            Section("3D model") {
                if ObjectModelStore.isQuickLookable(url) {
                    Button("View in 3D / AR", systemImage: "arkit") { quickLook = url }
                }
                if item.modelSource == .sam3d, item.modelUrl != nil {
                    Label("Built by SAM 3D from the photo. Capture it for a more accurate model.", systemImage: "wand.and.stars")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Rotate in room 90°", systemImage: "rotate.right") { models.rotate(key) }
                Button("Recapture", systemImage: "camera.metering.center.weighted") { capturing = true }
                    .disabled(!ObjectCaptureFlowView.isSupported)
                Button("Remove model", systemImage: "trash", role: .destructive) { models.deleteModel(for: key) }
            }
        } else if ObjectCaptureFlowView.isSupported {
            Section {
                Button("Capture 3D model", systemImage: "cube.transparent") { capturing = true }
            } footer: {
                Text("Walk around the item with the camera. Moove builds a 3D model on this phone and places it in your room.")
            }
        }
    }
}
