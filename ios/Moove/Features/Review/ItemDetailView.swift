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
    @State private var takingPhoto = false
    @State private var uploadingPhotos = 0

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
        .fullScreenCover(isPresented: $takingPhoto) {
            CameraPicker { jpeg in
                takingPhoto = false
                guard let jpeg else { return }
                uploadingPhotos += 1
                Task {
                    await store.addItemPhoto(jpeg, to: item)
                    uploadingPhotos -= 1
                }
            }
            .ignoresSafeArea()
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
        let local = models.modelURL(for: key)
        let progress = item.modelProgress(hasLocalModel: local != nil)
        Section {
            ModelStatusRow(progress: progress, status: item.modelStatus, syncing: item.modelUrl != nil && local == nil)
            if let url = local {
                if ObjectModelStore.isQuickLookable(url) {
                    Button("View in 3D / AR", systemImage: "arkit") { quickLook = url }
                }
                Button("Rotate in room 90°", systemImage: "rotate.right") { models.rotate(key) }
            }
            // Object Capture first: a walk-around scan beats any single photo.
            if ObjectCaptureFlowView.isSupported {
                Button(local == nil ? "Capture 3D model (best quality)" : "Recapture", systemImage: "cube.transparent") { capturing = true }
            }
            if item.modelSource != .capture {
                Button("Add photos for a better 3D model", systemImage: "camera.badge.ellipsis") { takingPhoto = true }
                    .disabled(uploadingPhotos > 0)
            }
            if models.hasLocalModel(key) {
                // Only a model captured on this phone can be removed here. If it was
                // synced, clear it on the server too, or it would just download again.
                Button("Remove model", systemImage: "trash", role: .destructive) {
                    models.deleteModel(for: key)
                    if item.modelSource == .capture, item.modelUrl != nil {
                        Task { await store.clearItemModel(item) }
                    }
                }
            }
            ItemPhotoStrip(urls: item.photoUrls, uploading: uploadingPhotos)
        } header: {
            Text("3D model")
        } footer: {
            Text(footer(item))
        }
    }

    private func footer(_ item: Item) -> String {
        if item.modelSource == .capture {
            return "Captured with Object Capture: the most accurate model Moove can place in your room."
        }
        var lines = ["Moove builds the model from the clearest image of this item: your photos, or product photos from the web once it knows the exact model. The whole item in frame, from a three-quarter angle, on a plain background works best."]
        if ObjectCaptureFlowView.isSupported {
            lines.append("For the most accurate model, capture it: walk around the item with the camera.")
        }
        return lines.joined(separator: " ")
    }
}

/// "Building", "Ready" and so on, from `item.model_status`.
private struct ModelStatusRow: View {
    let progress: ModelProgress
    let status: ModelStatus
    /// A synced model that this phone is still downloading.
    let syncing: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rebuilding: Bool { status == .running || status == .pending }

    @ViewBuilder private var icon: some View {
        switch progress {
        case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .building: ProgressView()
        case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .needsPhotos: Image(systemName: "camera").foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch progress {
        case .ready(.capture): "Ready: captured on a phone"
        case .ready(.sam3d): "Ready: built from photos"
        case .ready: "Ready"
        case .building: "Building the 3D model…"
        case .queued: "Waiting to build"
        case .failed: "Couldn't build a model"
        case .needsPhotos: "No model yet"
        }
    }

    private var detail: String? {
        switch progress {
        case .ready(.sam3d) where rebuilding: return "Rebuilding with your new photos…"
        case .ready where syncing: return "Downloading…"
        case .ready: return nil
        case .building: return "Picking the best image, then reconstructing. Usually under a minute."
        case .queued: return "Starts once Moove has identified the item."
        case .failed: return "Add a clearer photo: the whole item, nothing in front of it."
        case .needsPhotos: return "Add a photo and Moove builds one."
        }
    }
}

/// The item's photos, oldest (the scan's) first.
private struct ItemPhotoStrip: View {
    let urls: [String]
    let uploading: Int

    var body: some View {
        if !urls.isEmpty || uploading > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, raw in
                        AsyncImage(url: URL(string: raw)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.15)
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    ForEach(0..<uploading, id: \.self) { _ in
                        ProgressView()
                            .frame(width: 64, height: 64)
                            .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 10))
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityLabel("\(urls.count) photo\(urls.count == 1 ? "" : "s")\(uploading > 0 ? ", uploading" : "")")
        }
    }
}
