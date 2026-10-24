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

    private var capturing: Bool { session.phase == .capturing }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        // The capture phase draws its own Cancel over the camera.
                        if session.phase != .finished && !capturing { Button("Cancel") { dismiss() } }
                    }
                }
                .toolbar(capturing ? .hidden : .automatic, for: .navigationBar)
        }
        .tint(Theme.accentStrong)
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
            ZStack(alignment: .top) {
                RoomCaptureContainer(stopRequested: $stopRequested, recorder: session.frameRecorder, onFound: { found = $0 }) { result, extras in
                    switch result {
                    case .success(let room): session.captured(room, extras: extras)
                    case .failure(let error): session.phase = .failed(error.localizedDescription)
                    }
                }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) { foundChips }
                captureChrome
            }
        case .reviewing:
            if let geometry = session.geometry {
                RoomVisualizationView(geometry: geometry)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(geometry.objects.count) pieces of furniture, \(geometry.walls.count) walls, \(geometry.openings.count) doors & windows")
                                .monoMeta()
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                session.phase = .photos
                            } label: {
                                Text("Looks right: photograph items").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.pill(.primary))
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bg)
                        .ruled(.top)
                    }
            }
        case .photos:
            photoChecklist
        case .uploading(let done, let total):
            VStack(alignment: .leading, spacing: 16) {
                Text("01 — Scan · Uploading").eyebrow()
                Text("Uploading \(done) of \(total)…").blockTitle()
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(Theme.accentFill)
                    .accessibilityLabel("Uploading \(done) of \(total)")
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mooveScreen()
        case .finished:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("01 — Scan · Done").eyebrow()
                    Text("\(session.objects.count) items added").pageTitle().padding(.top, 8)
                    Text(session.uploadProblem.map { "Photos couldn't be uploaded (\($0)), so agents can't identify items yet. The room is saved, and the 3D view works on this device." }
                         ?? "Agents are identifying and pricing them now.")
                        .lede()
                        .padding(.top, 10)
                    ScanFinishedResults(roomName: session.roomName, colors: session.colors)
                        .padding(.top, 28)
                    Button("See inventory") { dismiss() }
                        .buttonStyle(.pill(.primary))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .mooveScreen()
        case .failed(let why):
            ScanStatusPanel(
                eyebrow: "01 — Scan · Problem",
                systemImage: "exclamationmark.triangle",
                tint: Theme.danger,
                title: "Scan problem",
                message: why
            ) {
                if !session.objects.isEmpty {
                    Button("Try upload again") { session.phase = .photos }.buttonStyle(.pill(.primary))
                }
                Button("Close") { dismiss() }.buttonStyle(.pill(.outline))
            }
        }
    }

    /// Cancel and Done over the live camera: pills on the page color so they read on any scene.
    private var captureChrome: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.outline, compact: true))
                .background(Capsule().fill(Theme.bg).padding(.vertical, 4))
            Spacer()
            Button("Done") { stopRequested = true }
                .buttonStyle(.pill(.primary, compact: true))
                .disabled(stopRequested)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    private var photoChecklist: some View {
        List {
            Section {
                PageHeader(
                    eyebrow: "01 — Scan · Photos",
                    title: "Photograph each item.",
                    lede: "Take a photo of each item so Moove can tell what it is, its brand and its condition."
                )
                .padding(.top, 16)
                .padding(.bottom, 28)
                .chromeRow()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Room name").eyebrow()
                    TextField("Room name", text: $session.roomName)
                        .monoText(16, weight: .bold)
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                        .ruled()
                }
                .chromeRow()
                if session.objects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("RoomPlan didn't recognize any furniture", systemImage: "exclamationmark.magnifyingglass")
                            .blockTitle()
                        Text("It detects beds, sofas, chairs, tables, storage, appliances, TVs and similar, and needs each one in view for a moment. Add your items by photo below, or cancel and scan again more slowly. The room itself is saved either way.")
                            .sansText(14.5)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 28)
                    .chromeRow()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        photographing = .manual()
                    } label: {
                        Label("Add an item by photo", systemImage: "camera.badge.ellipsis").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.outline))
                    Text("For anything RoomPlan missed: small things, decor, items on shelves. Moove identifies it from the photo.")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)
                .chromeRow()
            }
            .listSectionSeparator(.hidden)
            Section {
                ListHeader(title: "Photographed", count: "\(session.photos.count) of \(session.objects.count)")
                    .padding(.top, 40)
                    .chromeRow()
                ForEach(session.objects) { object in
                    let done = session.photos[object.id] != nil
                    Button { photographing = object } label: {
                        HStack(spacing: 16) {
                            photoThumb(object)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(object.manual ? "New item" : object.category.capitalized).blockTitle()
                                Text(dims(object)).monoMeta()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: done ? "checkmark.circle.fill" : "camera")
                                .font(.system(size: 17, weight: done ? .regular : .light))
                                .foregroundStyle(done ? Theme.accentStrong : Theme.text)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if object.manual {
                            Button("Remove", systemImage: "trash", role: .destructive) { session.remove(object) }
                        }
                    }
                    .ledgerListRow()
                }
            }
            .listSectionSeparator(.hidden)
            Color.clear.frame(height: 24).chromeRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle("Photograph items")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                Task { await session.submit(to: store, uploader: uploader) }
            } label: {
                Text(session.objects.isEmpty ? "Save room" : "Add \(session.objects.count) item\(session.objects.count == 1 ? "" : "s")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .background(Theme.bg)
            .ruled(.top)
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
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .accessibilityHidden(true)
    }

    private func dims(_ o: ScanSession.DetectedObject) -> String {
        if o.manual { return "Added by photo" }
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(1))) }
        return "\(f(o.widthM)) × \(f(o.depthM)) × \(f(o.heightM)) m"
    }
}

/// Finished / failed: a quiet centered block with an icon, mono heading, message and pill actions.
private struct ScanStatusPanel<Actions: View>: View {
    var eyebrow: String
    var systemImage: String
    var tint: Color
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).eyebrow().padding(.bottom, 16)
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(tint)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(title)
                .pageTitle()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .lede()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 10) { actions }
                .padding(.top, 28)
        }
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .mooveScreen()
    }
}

private extension View {
    /// A non-interactive row (heading, note, field): no separator, page background, gutter insets.
    func chromeRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.bg)
    }

    /// An item row: page background and a full-width rule-colored separator.
    func ledgerListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowBackground(Theme.bg)
            .listRowSeparatorTint(Theme.line)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
