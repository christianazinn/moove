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
    /// The row whose "Name it…" sheet is open.
    @State private var naming: ScanSession.DetectedObject?
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
        .sheet(item: $naming) { object in
            ScanLabelSheet(title: object.label == nil ? "Name it" : "Rename", label: object.label) { label in
                session.setLabel(label, for: object)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .capturing:
            ZStack(alignment: .top) {
                RoomCaptureContainer(stopRequested: $stopRequested, recorder: session.frameRecorder, onFound: { found = $0 }) { result, extras, photographer in
                    switch result {
                    case .success(let room): session.captured(room, extras: extras, photographer: photographer)
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
                        Button {
                            session.phase = .photos
                        } label: {
                            Text("Looks right").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pill(.primary))
                        .accessibilityLabel("Looks right: \(geometry.objects.count) items, \(geometry.walls.count) walls. Check photos")
                        .padding(.horizontal, Theme.gutter)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bg)
                    }
            }
        case .photos:
            photoChecklist
        case .uploading(let done, let total):
            VStack(alignment: .leading, spacing: 16) {
                Text("Uploading…").blockTitle()
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(Theme.accentFill)
                    .accessibilityLabel("Uploading \(done) of \(total)")
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mooveScreen()
        case .finished:
            ScanFinishedScreen(roomName: session.roomName, colors: session.colors, uploadProblem: session.uploadProblem, pendingPhotos: session.pendingPhotos.count,
                               importedCount: session.objects.count, localSkips: session.recheckSkips) { dismiss() }
        case .failed(let why):
            ScanStatusPanel(
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
                ScanRoomNameField(session: session)
                    .padding(.top, Theme.Space.l)
                    .chromeRow()
                if session.objects.isEmpty {
                    Text("No furniture found")
                        .blockTitle()
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
                }
                .padding(.top, 28)
                .chromeRow()
            }
            .listSectionSeparator(.hidden)
            Section {
                Color.clear.frame(height: Theme.Space.xl).chromeRow()
                if session.autoPhotosPending {
                    LoadingLine(text: "Picking photos…")
                        .padding(.vertical, 8)
                        .chromeRow()
                }
                ForEach(session.objects) { object in
                    let done = session.photos[object.id] != nil
                    let unnamed = object.category == ObjectSanity.relabelCategory && object.label == nil
                    HStack(spacing: 8) {
                        Button { photographing = object } label: {
                            HStack(spacing: 16) {
                                photoThumb(object)
                                // One line: the name. Size, "named by you" and "auto" are in the VoiceOver label.
                                Text(title(object)).blockTitle()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(object, done: done))
                        .accessibilityHint(done ? "Retakes the photo" : "Takes a photo")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Name it") { naming = object }
                        if unnamed {
                            Button("Name it") { naming = object }
                                .buttonStyle(.pill(.outline, compact: true))
                                .accessibilityLabel("Name \(title(object))")
                                .accessibilityIdentifier("scan.nameIt.\(object.id.uuidString)")
                        }
                        Button { photographing = object } label: {
                            Image(systemName: done ? "checkmark.circle.fill" : "camera")
                                .font(.system(size: 17, weight: done ? .regular : .light))
                                .foregroundStyle(done ? Theme.accentStrong : Theme.muted)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)  // same as tapping the row
                    }
                    .contextMenu {
                        Button(object.label == nil ? "Name it…" : "Rename…", systemImage: "pencil") { naming = object }
                        if object.label != nil {
                            Button("Let Moove name it", systemImage: "sparkles") { session.setLabel(nil, for: object) }
                        }
                    }
                    .swipeActions {
                        if object.manual {
                            Button("Remove", systemImage: "trash", role: .destructive) { session.remove(object) }
                        }
                        Button("Name it", systemImage: "pencil") { naming = object }
                            .tint(Theme.accentStrong)
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
        }
    }

    /// "Also found: Bicycle, Plant" while scanning, for things RoomPlan doesn't outline.
    /// One small chip per kind in a row that scrolls sideways (newest first), so a busy room
    /// doesn't squeeze every name into one line; past `maxFoundChips` it ends in "+N more".
    @ViewBuilder private var foundChips: some View {
        if !found.isEmpty {
            let counts = Self.foundCounts(found)
            let shown = counts.prefix(Self.maxFoundChips)
            let more = counts.count - shown.count
            HStack(spacing: 8) {
                Text("Also found")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: .capsule)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shown, id: \.name) { c in
                            Text(c.n > 1 ? "\(c.name.capitalized) ×\(c.n)" : c.name.capitalized)
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: .capsule)
                                .transition(.scale.combined(with: .opacity))
                        }
                        if more > 0 {
                            Text("+\(more) more")
                                .font(.caption.weight(.semibold))
                                .fixedSize()
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: .capsule)
                        }
                    }
                    .padding(.trailing, 16)
                }
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Also found: " + counts.map { $0.n > 1 ? "\($0.n) \($0.name)" : $0.name }.joined(separator: ", "))
            .padding(.bottom, 110)
            .animation(.snappy, value: found)
            .transition(.opacity)
        }
    }

    static let maxFoundChips = 4

    /// Kinds with their counts, newest kind first (the detector reports in the order it confirms).
    static func foundCounts(_ found: [String]) -> [(name: String, n: Int)] {
        var order: [String] = []
        var n: [String: Int] = [:]
        for f in found {
            if n[f] == nil { order.append(f) }
            n[f, default: 0] += 1
        }
        return order.reversed().map { (name: $0, n: n[$0]!) }
    }

    private var uploader: Uploader {
        if store.backendKind == .fixture { return LocalUploader() }
        guard store.uploadBaseURL != nil else { return LocalUploader() }
        // Two quick tries while the user waits on "Uploading…"; photos that still fail are
        // queued and retried in the background for 15 minutes (ScanSession.pendingPhotos).
        return HTTPUploader(policy: UploadRetryPolicy(maxAttempts: 2))
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    /// "Chair, 0.5 by 0.5 by 0.9 meters, photographed automatically".
    private func accessibilityLabel(_ o: ScanSession.DetectedObject, done: Bool) -> String {
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(1))) }
        let name = o.manual ? "\(title(o)), added by photo" : "\(title(o)), \(f(o.widthM)) by \(f(o.depthM)) by \(f(o.heightM)) meters"
        let state = !done ? "no photo yet" : session.autoPhotos.contains(o.id) ? "photographed automatically from the scan" : "photographed"
        let named = o.label != nil ? ", named by you" : o.category == ObjectSanity.relabelCategory && !o.manual ? ", Moove names it from its photo" : ""
        return "\(name)\(named), \(state)"
    }

    private func title(_ o: ScanSession.DetectedObject) -> String {
        if let named = o.label?.title { return named }
        if o.manual { return "New item" }
        return o.category == ObjectSanity.relabelCategory ? "Unidentified item" : o.category.capitalized
    }
}

/// Finished / failed: a quiet centered block with an icon, mono heading, message and pill actions.
private struct ScanStatusPanel<Actions: View>: View {
    var systemImage: String
    var tint: Color
    var title: String
    var message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
