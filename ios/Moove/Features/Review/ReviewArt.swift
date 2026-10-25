import SwiftUI
import UIKit
import MooveKit

/// An item's picture on Review rows: always its voxel model, so a row is never blank. The photo
/// goes on top only once it has actually loaded (`.replace`). A dead tunnel URL, a fixture URL or
/// a missing file just leaves the model showing. (The flip cards load the photo themselves, big,
/// with `ItemPhotoLoader`.)
struct ItemArt: View {
    enum Photo { case none, replace }

    let item: Item
    var size: CGFloat
    var photo: Photo = .replace

    var body: some View {
        VoxelThumbnail(item, size: size, tile: false)
            .overlay {
                if photo == .replace {
                    ItemPhoto(urls: item.photoUrls) { image in
                        image.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    }
                }
            }
    }
}

/// Draws `content` with the first of `urls` that loads, and nothing until (or unless) one does.
struct ItemPhoto<Content: View>: View {
    let urls: [String]
    @ViewBuilder var content: (Image) -> Content
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image { content(Image(uiImage: image)).transition(.opacity) }
        }
        .task(id: urls) {
            let loaded = await ItemPhotoLoader.load(urls)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

/// Loads item photos: upload-server URLs (moved onto the current tunnel host when the stored one
/// is stale, then as stored), and `file://` URLs from the offline demo (re-rooted in this
/// install's Documents folder, since the app container path changes on reinstall). Cached per launch.
@MainActor
enum ItemPhotoLoader {
    private static var cache: [String: UIImage] = [:]
    /// URLs that failed recently, so a dead host isn't hit by every row on every redraw.
    private static var failed: [String: Date] = [:]

    static func load(_ urls: [String]) async -> UIImage? {
        for raw in urls {
            if let hit = cache[raw] { return hit }
            if let at = failed[raw], Date().timeIntervalSince(at) < 60 { continue }
            for url in candidates(raw) {
                guard let data = await fetch(url), let image = UIImage(data: data) else { continue }
                let small = image.preparingThumbnail(of: fitting(image.size, max: 900)) ?? image
                if cache.count > 200 { cache.removeAll() }
                cache[raw] = small
                return small
            }
            failed[raw] = Date()
        }
        return nil
    }

    static func candidates(_ raw: String) -> [URL] {
        guard let stored = URL(string: raw) else { return [] }
        if stored.isFileURL {
            var out: [URL] = []
            if FileManager.default.fileExists(atPath: stored.path) { out.append(stored) }
            if let range = stored.path.range(of: "/Documents/"),
               let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let moved = docs.appending(path: String(stored.path[range.upperBound...]))
                if moved != stored, FileManager.default.fileExists(atPath: moved.path) { out.append(moved) }
            }
            return out
        }
        let current = ListingURL.resolve(raw, simulated: false, uploadBase: AppConfig.effectiveUploadBaseURL)
        return [current, stored].compactMap { $0 }.reduce(into: [URL]()) { out, url in
            if !out.contains(url), url.scheme == "https" || url.scheme == "http" { out.append(url) }
        }
    }

    private static func fetch(_ url: URL) async -> Data? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let result = try? await URLSession.shared.data(for: request),
              let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return result.0
    }

    private static func fitting(_ size: CGSize, max side: CGFloat) -> CGSize {
        let scale = min(1, side / Swift.max(size.width, size.height, 1))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
