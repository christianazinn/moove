import SwiftUI
import MooveKit

/// Adds an item by hand (`add_item`): something the scan missed or that wasn't in the room.
/// A photo is optional; with one, the vision agent names it more precisely and pricing follows.
struct AddItemView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The rooms the user can add to, and the one to start on.
    var rooms: [Room]
    @State var roomId: UInt64

    @State private var name = ""
    @State private var kind = ManualItem.kinds[0]
    /// Set once the user picks a kind, so typing the name stops changing it.
    @State private var pickedKind = false
    @State private var photo: Data?
    @State private var takingPhoto = false
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(
                        eyebrow: "02 — Inventory · Add",
                        title: "Add an item.",
                        lede: "Something the scan missed, or that's in another room. Add a photo and Moove identifies and prices it."
                    )

                    Text("Name").eyebrow().padding(.top, 28)
                    TextField("e.g. Road bike", text: $name)
                        .monoText(17, maxScale: 1.6)
                        .foregroundStyle(Theme.text)
                        .submitLabel(.done)
                        .focused($focused)
                        .frame(minHeight: 48)
                        .ruled()
                        .accessibilityIdentifier("addItem.name")
                        .onChange(of: name) { _, new in
                            if !pickedKind, let suggested = ManualItem.suggestedKind(for: new) { kind = suggested }
                        }

                    field("What is it") {
                        Picker("What is it", selection: Binding(get: { kind }, set: { kind = $0; pickedKind = true })) {
                            ForEach(ManualItem.kinds) { Text($0.label).tag($0) }
                        }
                        .accessibilityIdentifier("addItem.kind")
                    }
                    if rooms.count > 1 {
                        field("Room") {
                            Picker("Room", selection: $roomId) {
                                ForEach(rooms) { Text($0.name).tag($0.id) }
                            }
                            .accessibilityIdentifier("addItem.room")
                        }
                    }
                    Text(sizeText).monoMeta().padding(.top, 10)

                    photoRow.padding(.top, 28)

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .monoText(13.5)
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 14)
                    }

                    Button(action: save) {
                        HStack(spacing: 8) {
                            Text(saving ? "Adding…" : "Add item")
                            if saving { ProgressView().controlSize(.small) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.primary))
                    .disabled(saving)
                    .accessibilityIdentifier("addItem.save")
                    .padding(.top, 24)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .mooveScreen()
            .onAppear { focused = true }
            .fullScreenCover(isPresented: $takingPhoto) {
                CameraPicker { jpeg in
                    takingPhoto = false
                    if let jpeg { photo = jpeg }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func field(_ title: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(title).monoText(15, maxScale: 1.6).foregroundStyle(Theme.text)
            Spacer()
            control().tint(Theme.text)
        }
        .frame(minHeight: 48)
        .ruled()
        .padding(.top, 8)
    }

    /// From the chosen kind only, so the size always matches what the item is filed as.
    private var size: (w: Double, h: Double, d: Double) { ManualItem.defaultSize(category: kind.category) }

    private var sizeText: String {
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(1))) }
        return "Typical size: \(f(size.w)) × \(f(size.d)) × \(f(size.h)) m (W × D × H), used for packing and the new home"
    }

    @ViewBuilder private var photoRow: some View {
        HStack(spacing: 14) {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                    .accessibilityLabel("Photo added")
            }
            Button {
                takingPhoto = true
            } label: {
                Label(photo == nil ? "Add photo" : "Retake photo", systemImage: "camera")
            }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityHint("Moove identifies and prices the item from the photo")
            .accessibilityIdentifier("addItem.photo")
            Spacer(minLength: 0)
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            var url: String?
            if let photo {
                let file = FileManager.default.temporaryDirectory.appending(path: "new-item-\(UUID().uuidString).jpg")
                do {
                    try photo.write(to: file)
                    // Offline demo: keep the file on the device, as the scan does.
                    let uploader: Uploader = store.uploadBaseURL == nil ? LocalUploader() : HTTPUploader()
                    url = try await uploader.upload(file, contentType: "image/jpeg")
                } catch {
                    self.error = "Couldn't upload the photo: \((error as? UploadFailure)?.message ?? error.localizedDescription)"
                    return
                }
            }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.addItem(roomId: roomId, name: trimmed.isEmpty ? kind.label : trimmed, category: kind.category, size: size, photoUrl: url) {
                dismiss()
            } else {
                error = store.lastError ?? "Not saved"
                store.lastError = nil
            }
        }
    }
}

#Preview {
    AddItemView(rooms: [Room(id: 1, owner: "me", name: "Bedroom")], roomId: 1).environment(MooveStore.preview())
}
