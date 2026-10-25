import Foundation

/// Every color on the Listings poster wall, in one place, so the whole look can be swapped by
/// editing this file only (colors are 0xRRGGBB; the app turns them into SwiftUI colors).
///
/// The default is a quiet poster set that sits on the app's cream/walnut theme: three muted,
/// paper-toned swatches (clay, kraft, slate) printed on cream paper.
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
    public static let current = PosterPalette.harbor

    /// The app's restyle palette (#121F26 · #4F7889 · #7FA8A3 · #D1D6C8 · #F4F0D7): slate, sage and mist
    /// posters on cream paper, against a pale mist wall (harbor ink in dark mode).
    public static let harbor = PosterPalette(
        swatches: [
            Swatch(name: "slate", color: 0x46707F, onColor: 0xF4F0D7, accent: 0x7FA8A3),
            Swatch(name: "sage", color: 0x7FA8A3, onColor: 0x121F26, accent: 0x46707F),
            Swatch(name: "mist", color: 0xD1D6C8, onColor: 0x121F26, accent: 0x46707F),
        ],
        paper: 0xF4F0D7,
        paperInk: 0x121F26,
        wallLight: 0xDCE6E1,
        wallDark: 0x263C47,
        wallSpeckleLight: 0xD8DBC9,
        wallSpeckleDark: 0x2E4652,
        tape: 0xE9E4C6,
        stampInk: [
            .needsOK: 0x8F5E0A,
            .drafting: 0x4A5A60,
            .posting: 0x4A5A60,
            .live: 0x3E6474,
            .posted: 0x3E6474,
            .sold: 0x9A3B2E,
            .failed: 0xA24D35,
            .denied: 0x5E4A50,
        ]
    )

    public static let retroCream = PosterPalette(
        // Three muted, paper-toned swatches (Lisa: "a bit less color overall"): clay, kraft, slate.
        swatches: [
            Swatch(name: "clay", color: 0x8C5A4A, onColor: 0xFFF4E2, accent: 0xC9A97C),
            Swatch(name: "kraft", color: 0xC9A97C, onColor: 0x2B2118, accent: 0x8C5A4A),
            Swatch(name: "slate", color: 0x5F6670, onColor: 0xFFF4E2, accent: 0xC9A97C),
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
            .live: 0x4F5660,
            .posted: 0x4F5660,
            .sold: 0x9A3B2E,
            .failed: 0xA24D35,
            .denied: 0x5E4A50,
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
