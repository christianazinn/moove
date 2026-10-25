import Foundation

/// Every color on the Listings poster wall, in one place, so the whole look can be swapped by
/// editing this file only (colors are 0xRRGGBB; the app turns them into SwiftUI colors).
///
/// The default is a warm, slightly retro poster set that sits on the app's cream/walnut theme:
/// tomato, mustard, sage, teal, dusty blue and plum, printed on cream paper.
public struct PosterPalette: Sendable, Equatable {
    /// One poster color: the ink printed on it, and a second color it pairs with (price, banner, pin).
    public struct Swatch: Sendable, Equatable {
        public var name: String
        /// The poster's main color.
        public var color: UInt32
        /// Text printed on `color` (cream on dark swatches, walnut on light ones).
        public var onColor: UInt32
        /// A pairing color for details (pushpin, rules, the banner on a cream poster).
        public var accent: UInt32

        public init(name: String, color: UInt32, onColor: UInt32, accent: UInt32) {
            self.name = name
            self.color = color
            self.onColor = onColor
            self.accent = accent
        }
    }

    /// Poster colors, in the order listings are dealt them (by listing id).
    public var swatches: [Swatch]
    /// Cream poster paper, and the walnut ink printed on it.
    public var paper: UInt32
    public var paperInk: UInt32
    /// The wall behind the posters (light, dark mode) and its faint plaster speckle.
    public var wallLight: UInt32
    public var wallDark: UInt32
    public var wallSpeckleLight: UInt32
    public var wallSpeckleDark: UInt32
    /// Masking tape at the top of some posters.
    public var tape: UInt32
    /// Rubber-stamp ink per status.
    public var stampInk: [PosterStamp.Kind: UInt32]

    public init(swatches: [Swatch], paper: UInt32, paperInk: UInt32, wallLight: UInt32, wallDark: UInt32,
                wallSpeckleLight: UInt32, wallSpeckleDark: UInt32, tape: UInt32, stampInk: [PosterStamp.Kind: UInt32]) {
        self.swatches = swatches
        self.paper = paper
        self.paperInk = paperInk
        self.wallLight = wallLight
        self.wallDark = wallDark
        self.wallSpeckleLight = wallSpeckleLight
        self.wallSpeckleDark = wallSpeckleDark
        self.tape = tape
        self.stampInk = stampInk
    }

    /// Ink for a status stamp (graphite if a kind is missing from `stampInk`).
    public func ink(for kind: PosterStamp.Kind) -> UInt32 { stampInk[kind] ?? 0x4A4136 }

    /// The palette the app uses. Swap this to restyle every poster.
    public static let current = PosterPalette.retroCream

    public static let retroCream = PosterPalette(
        swatches: [
            Swatch(name: "tomato", color: 0xC2452D, onColor: 0xFFF4E2, accent: 0xE8B04A),
            Swatch(name: "mustard", color: 0xE3A72F, onColor: 0x2B2118, accent: 0xC4482E),
            Swatch(name: "sage", color: 0x93A882, onColor: 0x1F2A1A, accent: 0x7A4364),
            Swatch(name: "teal", color: 0x2A746F, onColor: 0xFFF4E2, accent: 0xE3A72F),
            Swatch(name: "dusty blue", color: 0x86A2BC, onColor: 0x1E2633, accent: 0xC2452D),
            Swatch(name: "plum", color: 0x7A4364, onColor: 0xFFF4E2, accent: 0xE8B04A),
        ],
        paper: 0xF6EBD5,
        paperInk: 0x2B2118,
        wallLight: 0xE7DCC8,
        wallDark: 0x17130F,
        wallSpeckleLight: 0xD6C9B1,
        wallSpeckleDark: 0x241E18,
        tape: 0xEDE2C4,
        stampInk: [
            .needsOK: 0x8F5E0A,
            .drafting: 0x5C554B,
            .posting: 0x5C554B,
            .live: 0x24706B,
            .posted: 0x24706B,
            .sold: 0xB3261E,
            .failed: 0xA24D35,
            .denied: 0x6A2E4C,
        ]
    )
}

extension PosterPalette {
    /// WCAG contrast ratio between two 0xRRGGBB colors (1...21).
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { Double((hex >> UInt32($0)) & 0xFF) / 255 }
            let linear = channels.map { $0 <= 0.039_28 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
