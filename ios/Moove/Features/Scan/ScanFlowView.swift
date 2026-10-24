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
                if let jpeg { session.setPhoto(jpeg, for: object) }
                photographing = nil
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .capturing:
            RoomCaptureContainer(stopRequested: $stopRequested) { result in
                switch result {
                case .success(let room): session.captured(room)
                case .failure(let error): session.phase = .failed(error.localizedDescription)
                }
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { stopRequested = true }.disabled(stopRequested)
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
                Text("Agents are identifying and pricing them now.")
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
            Section("\(session.photos.count) of \(session.objects.count) photographed") {
                ForEach(session.objects) { object in
                    Button { photographing = object } label: {
                        HStack(spacing: 12) {
                            photoThumb(object)
                            VStack(alignment: .leading) {
                                Text(object.category.capitalized).foregroundStyle(.primary)
                                Text(dims(object)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: session.photos[object.id] == nil ? "camera" : "checkmark.circle.fill")
                                .foregroundStyle(session.photos[object.id] == nil ? Color.accentColor : .green)
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
                Text("Add \(session.objects.count) items").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .disabled(session.objects.isEmpty)
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
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(1))) }
        return "\(f(o.widthM)) × \(f(o.depthM)) × \(f(o.heightM)) m"
    }
}
