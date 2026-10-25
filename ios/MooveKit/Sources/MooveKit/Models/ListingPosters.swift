import Foundation

// Listings as posters on a wall (Sell & Buy > Listings): the pure part. Which colors and type
// treatment each poster gets, how much it tilts, which status stamp it wears, what the tear-off
// tabs say, and how posters are dealt into masonry columns. Everything is deterministic per
// listing id, so a poster looks the same on every launch and on every phone.

/// How a poster is printed.
public enum PosterTreatment: String, Sendable, CaseIterable {
    /// The whole sheet in the swatch color, text in its `onColor`, a cream "FOR SALE" banner.
    case solid
    /// Cream paper, a swatch-colored banner and price.
    case paper
    /// Swatch color on top behind the art, cream paper below for the words.
    case split
}

/// What holds the poster to the wall.
public enum PosterFastener: String, Sendable, CaseIterable {
    case pin, tape
}

/// A poster's look, chosen from the listing id.
public struct PosterStyle: Sendable, Equatable {
    public var swatch: PosterPalette.Swatch
    public var treatment: PosterTreatment
    /// Banner line at the top ("FOR SALE").
    public var headline: String
    public var fastener: PosterFastener
    /// Clockwise tilt in degrees, within ±`PosterWall.maxTilt`. 0 when the wall is laid out straight.
    public var tiltDegrees: Double

    /// Background of the sheet.
    public func sheet(paper: UInt32) -> UInt32 { treatment == .solid ? swatch.color : paper }
    /// Main text on the sheet.
    public func ink(paperInk: UInt32) -> UInt32 { treatment == .solid ? swatch.onColor : paperInk }
    /// Behind the art at the top (`split` paints it in the swatch color).
    public func artBackground(paper: UInt32) -> UInt32 { treatment == .paper ? paper : swatch.color }
    /// Banner fill and its text.
    public func banner(paper: UInt32, paperInk: UInt32) -> (fill: UInt32, text: UInt32) {
        treatment == .solid ? (paper, paperInk) : (swatch.color, swatch.onColor)
    }
    /// The big price.
    public func priceInk(paperInk: UInt32) -> UInt32 {
        switch treatment {
        case .solid: swatch.onColor
        case .paper, .split: swatch.color.isLight ? paperInk : swatch.color
        }
    }
}

/// The status, as a rubber stamp on the poster.
public struct PosterStamp: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case needsOK, drafting, posting, live, posted, sold, failed, denied
    }

    public var kind: Kind
    /// What the stamp says ("SOLD", "NEEDS YOUR OK").
    public var text: String
    /// SOLD is a big diagonal stamp across the art; the others are small ones by the price.
    public var isBig: Bool
    /// Stamp rotation in degrees.
    public var angleDegrees: Double
    /// Drafting and posting posters are still a pencil sketch: dashed outline, faded art.
    public var isSketch: Bool
    /// A failed poster has its corner torn off.
    public var isTorn: Bool
    /// A denied poster is crossed out.
    public var isCrossedOut: Bool
}

public enum PosterWall {
    /// The most a poster tilts either way, in degrees.
    public static let maxTilt = 1.5
    /// Banner lines, picked per listing.
    public static let headlines = ["FOR SALE", "MOVING SALE", "MUST GO", "GOOD HOME WANTED", "PICK ME UP"]

    /// The poster for a listing. `straight` (accessibility text sizes) drops the tilt.
    public static func style(forListingId id: UInt64, palette: PosterPalette = .current, straight: Bool = false) -> PosterStyle {
        let h = mix(id)
        let swatches = palette.swatches.isEmpty ? PosterPalette.retroCream.swatches : palette.swatches
        // By id rather than by hash, so listings made one after another get different colors.
        let swatch = swatches[Int(id % UInt64(swatches.count))]
        let treatments = PosterTreatment.allCases
        return PosterStyle(
            swatch: swatch,
            treatment: treatments[Int((h >> 8) % UInt64(treatments.count))],
            headline: headlines[Int((h >> 16) % UInt64(headlines.count))],
            fastener: (h >> 24) % 3 == 0 ? .tape : .pin,
            tiltDegrees: straight ? 0 : tilt(forListingId: id)
        )
    }

    /// A small, deterministic tilt: at least 0.3° so it reads as pinned by hand, at most `maxTilt`,
    /// in steps of 0.1°.
    public static func tilt(forListingId id: UInt64) -> Double {
        let h = mix(id ^ 0x9E37_79B9)
        let steps = Int(h % 13) // 0...12 -> 0.3...1.5
        let magnitude = 0.3 + Double(steps) * 0.1
        let signed = (h >> 32) & 1 == 0 ? magnitude : -magnitude
        return (signed * 10).rounded() / 10
    }

    /// The stamp for a status. A simulated listing is never stamped LIVE (it isn't on eBay).
    public static func stamp(for status: ListingStatus, simulated: Bool) -> PosterStamp {
        switch status {
        case .awaitingApproval:
            PosterStamp(kind: .needsOK, text: "NEEDS YOUR OK", isBig: false, angleDegrees: -6, isSketch: false, isTorn: false, isCrossedOut: false)
        case .draft:
            PosterStamp(kind: .drafting, text: "DRAFTING", isBig: false, angleDegrees: -4, isSketch: true, isTorn: false, isCrossedOut: false)
        case .posting:
            PosterStamp(kind: .posting, text: "POSTING…", isBig: false, angleDegrees: -4, isSketch: true, isTorn: false, isCrossedOut: false)
        case .posted:
            simulated
                ? PosterStamp(kind: .posted, text: "POSTED", isBig: false, angleDegrees: -5, isSketch: false, isTorn: false, isCrossedOut: false)
                : PosterStamp(kind: .live, text: "LIVE", isBig: false, angleDegrees: -5, isSketch: false, isTorn: false, isCrossedOut: false)
        case .sold:
            PosterStamp(kind: .sold, text: "SOLD", isBig: true, angleDegrees: -18, isSketch: false, isTorn: false, isCrossedOut: false)
        case .failed:
            PosterStamp(kind: .failed, text: "FAILED", isBig: false, angleDegrees: 5, isSketch: false, isTorn: true, isCrossedOut: false)
        case .rejected:
            PosterStamp(kind: .denied, text: "DENIED", isBig: false, angleDegrees: 6, isSketch: false, isTorn: false, isCrossedOut: true)
        }
    }

    /// "eBay", "FB Marketplace", or the platform as stored.
    public static func platformName(_ platform: String) -> String {
        switch platform.lowercased() {
        case "ebay": "eBay"
        case "fb", "facebook", "fb_marketplace", "facebook_marketplace": "FB Marketplace"
        case "craigslist": "Craigslist"
        case "": "eBay"
        default: platform
        }
    }

    /// What the tear-off tabs at the bottom say: "eBay · simulated", or "eBay #395718204163" for a real post.
    public static func tabText(for listing: Listing) -> String {
        let name = platformName(listing.platform)
        if listing.simulated { return "\(name) · simulated" }
        if let number = listing.displayExternalId { return "\(name) #\(number)" }
        return name
    }

    /// Columns on the wall: one at accessibility text sizes, three on iPad, two on iPhone.
    public static func columns(regularWidth: Bool, accessibilitySize: Bool) -> Int {
        accessibilitySize ? 1 : (regularWidth ? 3 : 2)
    }

    /// Masonry: deals values into `columns` columns, each to the shortest so far, keeping order
    /// within a column. `weight` is a poster's relative height (a sold or failed poster with a
    /// reason runs a little taller).
    public static func deal<T>(_ values: [T], columns: Int, weight: (T) -> Double = { _ in 1 }) -> [[T]] {
        let n = max(1, columns)
        var out = Array(repeating: [T](), count: n)
        var heights = Array(repeating: 0.0, count: n)
        for v in values {
            let i = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            out[i].append(v)
            heights[i] += weight(v)
        }
        return out.filter { !$0.isEmpty }
    }

    /// The flyer header's figures: live posts, what the live ones are listed at, and what sold.
    public struct Totals: Sendable, Equatable {
        public var liveCount: Int
        public var listedCents: Int64
        public var soldCents: Int64
    }

    public static func totals(_ listings: [Listing]) -> Totals {
        let live = listings.filter { $0.status == .posted }
        let sold = listings.filter { $0.status == .sold }
        return Totals(liveCount: live.count,
                      listedCents: live.map(\.priceCents).reduce(0, +),
                      soldCents: sold.map(\.priceCents).reduce(0, +))
    }

    /// SplitMix64: a stable hash (Swift's `Hasher` is seeded per launch).
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension UInt32 {
    /// Whether a 0xRRGGBB color is light enough for dark text (relative luminance over ~0.5).
    public var isLight: Bool {
        let r = Double((self >> 16) & 0xFF) / 255, g = Double((self >> 8) & 0xFF) / 255, b = Double(self & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5
    }
}
