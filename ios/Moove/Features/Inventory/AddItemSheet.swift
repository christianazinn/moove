import SwiftUI
import UIKit
import MooveKit

// Inventory's **+ Add item**: take a photo (or pick one) of something the scan missed, pick the
// room, and the worker's vision agent names it from the photo, then pricing runs. Existing
// reducers only: `add_item` with the uploaded photo's URL (`details_status` starts pending, so
// vision picks it up), `create_room` for "New room…", and `add_item_photo` when the upload has
// to wait (`AddedItemPhotos`).

/// A photo just taken, waiting for the sheet.
struct AddItemDraft: Identifiable {
    let id = UUID()
    let jpeg: Data
    /// The room whose "+" was tapped.
    let preferredRoomId: UInt64?
}

struct AddItemSheet: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let draft: AddItemDraft

    private enum RoomChoice: Hashable {
        case existing(UInt64)
        case new
    }

    @State private var room: RoomChoice?
    @State private var newRoomName = ""
    @State private var name = ""
    @State private var size: AddedItem.Size?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        let rooms = store.snapshot.roomsNewestFirst(store.visibleRooms)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    preview
                    roomPicker(rooms)
                    field("Name (optional)") {
                        TextField("We'll name it from the photo", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .accessibilityIdentifier("additem.name")
                    }
                    sizeChips
                    if let error {
                        Text(error)
                            .monoMeta()
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("additem.error")
                    }
                    Button {
                        Task { await save() }
                    } label: {
                        Text(saving ? "Adding…" : "Add")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.primary))
                    .disabled(saving || !canSave)
                    .accessibilityIdentifier("additem.save")
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 16)
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
            }
            .mooveScreen()
        }
        .interactiveDismissDisabled(saving)
        .onAppear {
            if room == nil {
                room = AddedItem.defaultRoom(rooms, preferred: draft.preferredRoomId).map { .existing($0.id) } ?? .new
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var preview: some View {
        if let image = UIImage(data: draft.jpeg) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .accessibilityLabel("Your photo")
        }
    }

    @ViewBuilder private func roomPicker(_ rooms: [Room]) -> some View {
        field("Room") {
            Picker("Room", selection: Binding(get: { room ?? .new }, set: { room = $0 })) {
                ForEach(rooms) { r in
                    Text(r.name).tag(RoomChoice.existing(r.id))
                }
                Text("New room…").tag(RoomChoice.new)
            }
            .pickerStyle(.menu)
            .tint(Theme.text)
            .accessibilityIdentifier("additem.room")
            if room == .new {
                TextField("Room name, e.g. Garage", text: $newRoomName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("New room name")
                    .accessibilityIdentifier("additem.newRoom")
            }
        }
    }

    private var sizeChips: some View {
        field("Size (optional)") {
            HStack(spacing: 6) {
                ChoiceChip(title: "Not sure", selected: size == nil) { size = nil }
                ForEach(AddedItem.Size.allCases) { s in
                    ChoiceChip(title: s.label, selected: size == s) { size = s }
                        .accessibilityIdentifier("additem.size.\(s.rawValue)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Size")
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).eyebrow()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trimmedRoomName: String { newRoomName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        room != .new || (!trimmedRoomName.isEmpty && trimmedRoomName.count <= AddedItem.maxRoomNameLength)
    }

    // MARK: Save

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        // Keep the photo on the device: the offline demo shows it from here, and a photo that
        // can't upload yet waits here (`AddedItemPhotos`).
        guard let file = AddedItemPhotos.save(draft.jpeg, id: draft.id) else {
            error = "Couldn't save the photo on this phone."
            return
        }
        let roomId: UInt64
        switch room {
        case .existing(let id)?:
            roomId = id
        default:
            guard let created = await store.createRoom(named: trimmedRoomName) else {
                error = "Couldn't create the room. \(takeError())"
                return
            }
            room = .existing(created.id)
            roomId = created.id
        }
        let scanObjectId = AddedItem.newScanObjectId()
        let itemName = AddedItem.name(typed: name)
        let photoUrl = await upload(file)
        let object = AddedItem.object(scanObjectId: scanObjectId, name: itemName, size: size, photoUrl: photoUrl)
        guard await store.addItem(roomId: roomId, name: itemName, object: object) else {
            error = "Couldn't add the item. \(takeError())"
            return
        }
        if photoUrl == nil {
            AddedItemPhotos.shared.enqueue(scanObjectId: scanObjectId, file: file, store: store)
        } else if store.backendKind == .fixture, let item = await store.item(withScanObjectId: scanObjectId) {
            store.simulateIdentify(itemId: item.id)
        }
        dismiss()
    }

    /// The photo's URL for `add_item`: a file URL in the offline demo, the worker's upload URL
    /// live. Nil when there's no upload server or it didn't answer: the item is added anyway and
    /// the photo waits in `AddedItemPhotos`.
    private func upload(_ file: URL) async -> String? {
        if store.backendKind == .fixture { return try? await LocalUploader().upload(file, contentType: "image/jpeg") }
        guard store.uploadBaseURL != nil else { return nil }
        // One short try here; the queue keeps trying in the background.
        let uploader = HTTPUploader(policy: UploadRetryPolicy(maxAttempts: 2), timeout: 15)
        return try? await uploader.upload(file, contentType: "image/jpeg")
    }

    private func takeError() -> String {
        defer { store.lastError = nil }
        return store.lastError ?? "Try again."
    }
}

/// Photos of added items that couldn't upload yet (offline, no worker URL, server down). They
/// keep trying every 20 s while the app runs and are attached with `add_item_photo`, which
/// queues vision. Saved in UserDefaults so they survive a relaunch. Same idea as the scan's
/// `ScanSession.pendingPhotos` (#222), keyed by the item's `scan_object_id`.
@MainActor
@Observable
final class AddedItemPhotos {
    static let shared = AddedItemPhotos()
    private static let defaultsKey = "moove.addedItemPhotos"

    /// scan_object_id → file name in `folder`.
    private(set) var waiting: [String: String]
    @ObservationIgnored private var drain: Task<Void, Never>?

    private init() {
        waiting = (UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
    }

    static var folder: URL { URL.documentsDirectory.appending(path: "added-items", directoryHint: .isDirectory) }

    /// Writes the JPEG under Documents/added-items; nil on failure.
    static func save(_ jpeg: Data, id: UUID) -> URL? {
        let file = folder.appending(path: "\(id.uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try jpeg.write(to: file)
            return file
        } catch {
            return nil
        }
    }

    func isWaiting(_ item: Item) -> Bool { item.scanObjectId.map { waiting[$0] != nil } ?? false }

    /// The local copy, for the row's thumbnail while it waits.
    func localPhoto(for item: Item) -> URL? {
        item.scanObjectId.flatMap { waiting[$0] }.map { Self.folder.appending(path: $0) }
    }

    func enqueue(scanObjectId: String, file: URL, store: MooveStore) {
        waiting[scanObjectId] = file.lastPathComponent
        persist()
        resume(store: store)
    }

    /// Starts the retry loop if anything is waiting (Inventory calls this on appear).
    func resume(store: MooveStore) {
        guard !waiting.isEmpty, drain == nil else { return }
        drain = Task { [weak self, weak store] in
            while let self, let store, !self.waiting.isEmpty, !Task.isCancelled {
                await self.tryOnce(store: store)
                if self.waiting.isEmpty { break }
                try? await Task.sleep(for: .seconds(20))
            }
            self?.drain = nil
        }
    }

    private func tryOnce(store: MooveStore) async {
        guard store.backendKind == .spacetime, store.status == .connected, store.uploadBaseURL != nil else { return }
        for (id, fileName) in waiting {
            let file = Self.folder.appending(path: fileName)
            guard FileManager.default.fileExists(atPath: file.path) else { forget(id); continue }
            // The row may not have synced yet; after 10 min without it, it was deleted.
            guard let item = store.snapshot.items.first(where: { $0.scanObjectId == id }) else {
                let made = (try? FileManager.default.attributesOfItem(atPath: file.path)[.creationDate]) as? Date
                if let made, made < .now.addingTimeInterval(-600) { forget(id) }
                continue
            }
            guard let url = try? await HTTPUploader().upload(file, contentType: "image/jpeg") else { return }
            if await store.addItemPhoto(itemId: item.id, url: url) {
                forget(id)
            } else {
                store.lastError = nil  // quiet: it tries again
            }
        }
    }

    private func forget(_ id: String) {
        waiting[id] = nil
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(waiting, forKey: Self.defaultsKey)
    }
}
