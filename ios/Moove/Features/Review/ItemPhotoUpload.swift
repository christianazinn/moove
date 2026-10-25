import Foundation
import MooveKit

/// Uploads a camera photo of an item and attaches it: "Add photo" (vision runs again) or
/// "Wrong item? Reclassify from a photo" (`reclassify`: vision identifies it from this photo,
/// `MooveStore.reclassifyItem`). Used by Item detail and Inventory's long-press menu.
enum ItemPhotoUpload {
    /// nil when it landed, else why not (for the status line).
    @MainActor
    static func attach(_ jpeg: Data, to item: Item, reclassify: Bool, store: MooveStore) async -> String? {
        let file = FileManager.default.temporaryDirectory.appending(path: "item-\(item.id)-\(UUID().uuidString).jpg")
        do {
            try jpeg.write(to: file)
            // Offline demo: keep the file on the device, as the scan does.
            let uploader: Uploader = store.uploadBaseURL == nil ? LocalUploader() : HTTPUploader()
            let url = try await uploader.upload(file, contentType: "image/jpeg")
            let ok = reclassify
                ? await store.reclassifyItem(item, photoUrl: url)
                : await store.addItemPhoto(itemId: item.id, url: url)
            if ok { return nil }
            defer { store.lastError = nil }
            return store.lastError ?? "not saved"
        } catch {
            return (error as? UploadFailure)?.message ?? error.localizedDescription
        }
    }
}
