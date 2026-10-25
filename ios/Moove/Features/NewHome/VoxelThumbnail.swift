import CoreGraphics
import Foundation
import MooveKit
import SwiftUI

/// A small isometric voxel drawing of one piece on a rounded tile, for list rows
/// (the prototype's 56 pt `.thumb`).
///
/// The model is built, projected and rasterized once per (spec, pixel size), off the main
/// actor, and cached (`VoxelSpriteCache`); `body` only looks the bitmap up and shows it, so
/// scrolling a shelf of these or flipping a Review card never re-runs the mesher or redraws
/// hundreds of face paths. Until the first bitmap for a spec is ready a quiet placeholder
/// fills the same frame (no layout jump).
@MainActor
struct VoxelThumbnail: View {
    var spec: VoxelItemSpec
    var size: CGFloat = 56
    /// Draw the rounded tile behind the model (off for models that sit on other art).
    var tile = true

    @Environment(\.displayScale) private var displayScale
    /// The bitmap this view fetched itself (kept so a cache eviction never blanks a visible view).
    @State private var loaded: VoxelSpriteImage?

    init(spec: VoxelItemSpec, size: CGFloat = 56, tile: Bool = true) {
        self.spec = spec
        self.size = size
        self.tile = tile
    }

    init(_ item: LayoutItem, size: CGFloat = 56) {
        self.init(spec: VoxelItemSpec(item), size: size)
    }

    /// With the item's attributes, material and stored colors (`item.colors`); a demo bedroom
    /// item with none stored uses the demo room's fixture colors.
    init(_ item: Item, size: CGFloat = 56, tile: Bool = true) {
        var spec = VoxelItemSpec(item)
        if item.colors == nil, DemoFixtures.isDemoItem(item), let c = DemoFixtures.scanColors().colors(for: item) {
            spec.primaryColor = c.primary
            spec.secondaryColor = c.secondary
        }
        self.init(spec: spec, size: size, tile: tile)
    }

    var body: some View {
        let key = VoxelSpriteCache.Key(spec: spec, size: size, scale: displayScale)
        let image = loaded?.key == key ? loaded : VoxelSpriteCache.cachedImage(for: key)
        ZStack {
            if let image {
                Image(decorative: image.cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface2.opacity(0.6))
                    .padding(size * VoxelSpriteCache.insetFraction)
            }
        }
        .frame(width: size, height: size)
        .background(tile ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityHidden(true)
        .task(id: key) {
            if loaded?.key == key { return }
            if let hit = VoxelSpriteCache.cachedImage(for: key) {
                loaded = hit
                return
            }
            let made = await Task.detached(priority: .userInitiated) { VoxelSpriteCache.image(for: key) }.value
            if !Task.isCancelled { loaded = made }
        }
    }
}

/// One rasterized sprite. CGImage is immutable, so sharing it across threads is safe.
final class VoxelSpriteImage: @unchecked Sendable {
    let key: VoxelSpriteCache.Key
    let cgImage: CGImage
    var cost: Int { cgImage.bytesPerRow * cgImage.height }

    init(key: VoxelSpriteCache.Key, cgImage: CGImage) {
        self.key = key
        self.cgImage = cgImage
    }
}

/// Sprites (voxel model -> iso polygons) by spec, and their bitmaps by (spec, pixel size).
/// Thread-safe and bounded; meant to be filled off the main actor. Sprite colors are fixed
/// (not light/dark adaptive), so the color scheme is not part of the key; the tile behind
/// the model is drawn by the view.
enum VoxelSpriteCache {
    /// The model's margin inside its frame, as a fraction of the side.
    static let insetFraction: CGFloat = 0.14
    /// Bitmap sides are rounded up to this many pixels, so views whose size wobbles by a
    /// fraction of a point (geometry-driven posters) share one bitmap.
    static let pixelStep = 16
    static let maxSprites = 400
    static let maxImageBytes = 48 * 1024 * 1024

    struct Key: Hashable, Sendable {
        var spec: VoxelItemSpec
        /// Bitmap side in pixels.
        var pixels: Int
        /// Hairline width in pixels (0.5 pt at the view's size).
        var lineWidth: Double

        init(spec: VoxelItemSpec, size: CGFloat, scale: CGFloat) {
            self.spec = spec
            let raw = max(1, Int((max(size, 1) * max(scale, 1)).rounded(.up)))
            pixels = (raw + VoxelSpriteCache.pixelStep - 1) / VoxelSpriteCache.pixelStep * VoxelSpriteCache.pixelStep
            lineWidth = 0.5 * Double(pixels) / Double(max(size, 1))
        }
    }

    private static let store = Store()

    /// The bitmap if it is already made. Cheap; safe to call from `body`.
    static func cachedImage(for key: Key) -> VoxelSpriteImage? {
        store.image(key)
    }

    /// The bitmap, made now if needed. Does the real work, so call it off the main actor.
    static func image(for key: Key) -> VoxelSpriteImage? {
        if let hit = store.image(key) { return hit }
        guard let cg = rasterize(sprite(for: key.spec), pixels: key.pixels, lineWidth: key.lineWidth) else { return nil }
        let made = VoxelSpriteImage(key: key, cgImage: cg)
        store.insert(made)
        return made
    }

    /// The projected model, built once per spec and shared by every size.
    static func sprite(for spec: VoxelItemSpec) -> IsoSprite {
        if let hit = store.sprite(spec) { return hit }
        let made = IsoSprite.render(VoxelModels.build(spec))
        store.insert(made, for: spec)
        return made
    }

    /// Draws the faces back to front, filled and stroked with a hairline in the same color
    /// (it hides the seams between neighboring faces), exactly as the old per-frame Canvas did.
    static func rasterize(_ sprite: IsoSprite, pixels: Int, lineWidth: Double) -> CGImage? {
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let full = CGFloat(pixels)
        // y down, like the sprite and SwiftUI.
        ctx.translateBy(x: 0, y: full)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.setLineWidth(CGFloat(lineWidth))
        let inset = full * insetFraction
        let side = full - inset * 2
        var lastColor: VoxelColor?
        for face in sprite.faces where face.points.count >= 3 {
            if face.color != lastColor {
                let c = face.color
                let rgb = [CGFloat((c >> 16) & 0xFF) / 255, CGFloat((c >> 8) & 0xFF) / 255, CGFloat(c & 0xFF) / 255, 1]
                if let color = CGColor(colorSpace: space, components: rgb) {
                    ctx.setFillColor(color)
                    ctx.setStrokeColor(color)
                }
                lastColor = c
            }
            ctx.beginPath()
            let first = face.points[0]
            ctx.move(to: CGPoint(x: inset + CGFloat(first.x) * side, y: inset + CGFloat(first.y) * side))
            for pt in face.points.dropFirst() {
                ctx.addLine(to: CGPoint(x: inset + CGFloat(pt.x) * side, y: inset + CGFloat(pt.y) * side))
            }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
        return ctx.makeImage()
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var sprites: [VoxelItemSpec: IsoSprite] = [:]
        private var images: [Key: VoxelSpriteImage] = [:]
        /// Insertion order, oldest first, for eviction.
        private var imageOrder: [Key] = []
        private var imageBytes = 0

        func sprite(_ spec: VoxelItemSpec) -> IsoSprite? {
            lock.lock(); defer { lock.unlock() }
            return sprites[spec]
        }

        func insert(_ sprite: IsoSprite, for spec: VoxelItemSpec) {
            lock.lock(); defer { lock.unlock() }
            if sprites.count >= VoxelSpriteCache.maxSprites { sprites.removeAll(keepingCapacity: true) }
            sprites[spec] = sprite
        }

        func image(_ key: Key) -> VoxelSpriteImage? {
            lock.lock(); defer { lock.unlock() }
            return images[key]
        }

        func insert(_ image: VoxelSpriteImage) {
            lock.lock(); defer { lock.unlock() }
            guard images[image.key] == nil else { return }
            images[image.key] = image
            imageOrder.append(image.key)
            imageBytes += image.cost
            while imageBytes > VoxelSpriteCache.maxImageBytes, imageOrder.count > 1 {
                let old = imageOrder.removeFirst()
                if let gone = images.removeValue(forKey: old) { imageBytes -= gone.cost }
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(DemoFixtures.inventory(owner: "demo").items.prefix(4)) { item in
            VoxelThumbnail(item)
        }
    }
    .padding()
    .background(Theme.bg)
}

#Preview("Extra categories (#183)") {
    let specs: [(String, String)] = [
        ("guitar", "Acoustic guitar"), ("guitar", "Electric guitar"), ("piano", "Upright piano"), ("piano", "Grand piano"),
        ("keyboard instrument", "Keyboard"), ("drums", "Drum kit"), ("vacuum", "Upright vacuum"), ("vacuum", "Robot vacuum"),
        ("monitor", "Monitor"), ("scooter", "Kick scooter"), ("scooter", "Electric scooter"), ("bag", "Backpack"),
        ("bag", "Duffel bag"), ("golf clubs", "Golf bag"), ("treadmill", "Treadmill"), ("exercise bike", "Exercise bike"),
        ("skateboard", "Skateboard"), ("surfboard", "Surfboard"), ("air purifier", "Air purifier"), ("bicycle", "Bicycle"),
    ]
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(60)), count: 5), spacing: 8) {
        ForEach(specs.indices, id: \.self) { i in
            VoxelThumbnail(spec: VoxelItemSpec(category: specs[i].0, name: specs[i].1, widthM: 0, depthM: 0, heightM: 0))
        }
    }
    .padding()
    .background(Theme.bg)
}
