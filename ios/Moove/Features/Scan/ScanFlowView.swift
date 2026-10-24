import SwiftUI
import RoomPlan
import MooveKit

/// Full-screen scan: RoomPlan capture → photo each object → upload → items.
struct ScanFlowView: View {
    @Environment(MooveStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var session = ScanSession()
    @State private var stopRequested = false
    @State private var photographing: ScanSession.DetectedObject?
    /// Extra objects (#73) spotted so far during the scan.
    @State private var found: [String] = []

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if session.phase != .finished { Button("Cancel") { dismiss() } }
                    }
                }
        }
        .fullScreenCover(item: $photographing) { object in
            CameraPicker { jpeg in
                if let jpeg {
                    if object.manual { session.addManual(object, photo: jpeg) } else { session.setPhoto(jpeg, for: object) }
                }
                photographing = nil
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .capturing:
            RoomCaptureContainer(stopRequested: $stopRequested, onFound: { found = $0 }) { result, extras in
                switch result {
                case .success(let room): session.captured(room, extras: extras)
                case .failure(let error): session.phase = .failed(error.localizedDescription)
                }
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) { foundChips }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { stopRequested = true }.disabled(stopRequested)
                }
            }
        case .reviewing:
            if let geometry = session.geometry {
                RoomVisualizationView(geometry: geometry)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 6) {
                            Text("\(geometry.objects.count) pieces of furniture, \(geometry.walls.count) walls, \(geometry.openings.count) doors & windows")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button {
                                session.phase = .photos
                            } label: {
                                Text("Looks right: photograph items").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding()
                        .background(.bar)
                    }
            }
        case .photos:
            photoChecklist
        case .uploading(let done, let total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Uploading \(done) of \(total)…")
            }
            .padding(40)
        case .finished:
            ContentUnavailableView {
                Label("\(session.objects.count) items added", systemImage: "checkmark.circle.fill")
            } description: {
                if let problem = session.uploadProblem {
                    Text("Photos couldn't be uploaded (\(problem)), so agents can't identify items yet. The room is saved, and the 3D view works on this device.")
                } else {
                    Text("Agents are identifying and pricing them now.")
                }
            } actions: {
                Button("See inventory") { dismiss() }.buttonStyle(.borderedProminent)
            }
        case .failed(let why):
            ContentUnavailableView {
                Label("Scan problem", systemImage: "exclamationmark.triangle")
            } description: {
                Text(why)
            } actions: {
                if !session.objects.isEmpty {
                    Button("Try upload again") { session.phase = .photos }
                }
                Button("Close") { dismiss() }
            }
        }
    }

    private var photoChecklist: some View {
        List {
            Section {
                TextField("Room name", text: $session.roomName)
            } footer: {
                Text("Take a photo of each item so Moove can tell what it is, its brand and its condition.")
            }
            if session.objects.isEmpty {
                Section {
                    Label("RoomPlan didn't recognize any furniture", systemImage: "exclamationmark.magnifyingglass")
                        .font(.headline)
                    Text("It detects beds, sofas, chairs, tables, storage, appliances, TVs and similar, and needs each one in view for a moment. Add your items by photo below, or cancel and scan again more slowly. The room itself is saved either way.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    photographing = .manual()
                } label: {
                    Label("Add an item by photo", systemImage: "camera.badge.ellipsis")
                }
            } footer: {
                Text("For anything RoomPlan missed: small things, decor, items on shelves. Moove identifies it from the photo.")
            }
            Section("\(session.photos.count) of \(session.objects.count) photographed") {
                ForEach(session.objects) { object in
                    Button { photographing = object } label: {
                        HStack(spacing: 12) {
                            photoThumb(object)
                            VStack(alignment: .leading) {
                                Text(object.manual ? "New item" : object.category.capitalized).foregroundStyle(.primary)
                                Text(dims(object)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: session.photos[object.id] == nil ? "camera" : "checkmark.circle.fill")
                                .foregroundStyle(session.photos[object.id] == nil ? Color.accentColor : .green)
                        }
                    }
                    .swipeActions {
                        if object.manual {
                            Button("Remove", systemImage: "trash", role: .destructive) { session.remove(object) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Photograph items")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await session.submit(to: store, uploader: uploader) }
            } label: {
                Text(session.objects.isEmpty ? "Save room" : "Add \(session.objects.count) item\(session.objects.count == 1 ? "" : "s")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
    }

    /// "Also found: Bicycle, Plant" while scanning, for things RoomPlan doesn't outline.
    @ViewBuilder private var foundChips: some View {
        if !found.isEmpty {
            let counts = Dictionary(grouping: found, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }
            HStack(spacing: 6) {
                Text("Also found:").font(.caption.weight(.semibold))
                ForEach(counts, id: \.0) { name, n in
                    Label(n > 1 ? "\(name.capitalized) ×\(n)" : name.capitalized, systemImage: ItemThumbnail.icon(for: name))
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(.bottom, 110)
            .transition(.opacity)
        }
    }

    private var uploader: Uploader {
        if store.backendKind == .fixture { return LocalUploader() }
        guard let base = AppConfig.current.uploadBaseURL else { return LocalUploader() }
        return HTTPUploader(baseURL: base, token: nil)
    }

    private func photoThumb(_ object: ScanSession.DetectedObject) -> some View {
        Group {
            if let url = session.photos[object.id], let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: ItemThumbnail.icon(for: object.category))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func dims(_ o: ScanSession.DetectedObject) -> String {
        if o.manual { return "Added by photo" }
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(1))) }
        return "\(f(o.widthM)) × \(f(o.depthM)) × \(f(o.heightM)) m"
    }
}
