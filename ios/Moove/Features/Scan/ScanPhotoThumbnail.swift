import SwiftUI
import ImageIO

/// A scan photo decoded at thumbnail size, off the main thread. The photos are
/// 1600px JPEGs, and decoding each one full size for a 44pt row stalls the list.
struct ScanPhotoThumbnail: View {
    let url: URL
    /// Bump when the photo at `url` is retaken: the file is overwritten in place.
    var version = 0
    /// Display size in points (the longer side).
    var points: CGFloat = 44
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var key: String { "\(url.path)#\(version)" }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: key) {
            let key = key
            if let cached = ThumbnailCache.images.object(forKey: key as NSString) {
                image = cached
                return
            }
            image = nil
            // 2x the pixel size, so scaledToFill's crop stays sharp.
            let maxPixels = Int((points * displayScale * 2).rounded(.up))
            let url = url
            guard let decoded = await Task.detached(priority: .utility, operation: {
                Self.decode(url, maxPixels: maxPixels)
            }).value, !Task.isCancelled else { return }
            let thumb = UIImage(cgImage: decoded.image)
            ThumbnailCache.images.setObject(thumb, forKey: key as NSString)
            image = thumb
        }
    }

    /// A decoded CGImage handed from the background decode to the main actor. It's
    /// immutable once created, so sharing it is safe.
    private struct Decoded: @unchecked Sendable { let image: CGImage }

    nonisolated private static func decode(_ url: URL, maxPixels: Int) -> Decoded? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map(Decoded.init)
    }
}

@MainActor
private enum ThumbnailCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()
}
