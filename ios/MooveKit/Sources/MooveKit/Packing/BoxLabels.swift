import Foundation

// Printable box labels: what each label says and where it sits on the page. The app draws them
// into a PDF (UIKit); everything here is plain data so it can be tested on Linux.

/// The text and colors on one printed box label.
public struct BoxLabel: Sendable, Hashable, Identifiable {
    /// The box number.
    public var id: Int
    /// "07"
    public var number: String
    /// Destination room, upper-cased for the color band ("BEDROOM 2").
    public var room: String
    public var roomColor: VoxelColor
    /// S, M, L, D, P, W or T.
    public var sizeGlyph: String
    /// "Medium box · 12 kg"
    public var sizeLine: String
    /// Up to `maxContentLines` lines ("Paperbacks × 20"), scanned things first.
    public var contents: [String]
    /// Lines left off ("+ 3 more").
    public var moreCount: Int
    /// In print order: KEEP WITH YOU, OPEN FIRST, FRAGILE, THIS SIDE UP.
    public var badges: [Badge]
    /// What the QR code encodes: `moove://box/<n>`.
    public var qrPayload: String

    public enum Badge: String, Sendable, Hashable, CaseIterable {
        case keepWithYou = "KEEP WITH YOU"
        case openFirst = "OPEN FIRST"
        case fragile = "FRAGILE"
        case thisSideUp = "THIS SIDE UP"

        /// Warnings print in red; the others in green.
        public var isWarning: Bool { self == .fragile || self == .thisSideUp }
    }

    public static let maxContentLines = 5

    public init(box: MovingBox) {
        id = box.id
        number = box.id < 10 ? "0\(box.id)" : "\(box.id)"
        room = (box.room.isEmpty ? "Any room" : box.room).uppercased()
        roomColor = box.roomColor
        sizeGlyph = box.size.glyph
        sizeLine = "\(box.size.label) · \(Int(box.weightKg.rounded())) kg"
        // Scanned things first: they're what you'll look for.
        let ordered = box.contents.filter { $0.itemId != nil } + box.contents.filter { $0.itemId == nil }
        let lines = ordered.map { $0.quantity > 1 ? "\($0.name) × \($0.quantity)" : $0.name }
        contents = Array(lines.prefix(Self.maxContentLines))
        moreCount = max(0, lines.count - Self.maxContentLines)
        var badges: [Badge] = []
        if box.keepWithYou { badges.append(.keepWithYou) }
        if box.openFirst && !box.keepWithYou { badges.append(.openFirst) }
        if box.fragile { badges.append(.fragile) }
        if box.thisSideUp { badges.append(.thisSideUp) }
        self.badges = badges
        qrPayload = Self.qrPayload(box: box.id)
    }

    public static func qrPayload(box: Int) -> String { "moove://box/\(box)" }

    /// One label per box, in box-number order.
    public static func labels(for boxes: [MovingBox]) -> [BoxLabel] {
        boxes.sorted { $0.id < $1.id }.map(BoxLabel.init)
    }
}

/// A rectangle in PDF points (72 per inch), origin top-left.
public struct LabelRect: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Paper for printed labels.
public enum BoxLabelLayout: String, Sendable, CaseIterable, Identifiable {
    /// One 4 × 6 in shipping label per page (thermal label printers, index cards).
    case fourBySix
    /// US Letter, two labels per page, cut along the middle.
    case letterTwoUp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fourBySix: return "4 × 6 in labels"
        case .letterTwoUp: return "Letter, 2 per page"
        }
    }

    /// Page size in points.
    public var pageSize: (width: Double, height: Double) {
        switch self {
        case .fourBySix: return (288, 432)
        case .letterTwoUp: return (612, 792)
        }
    }

    public var labelsPerPage: Int { self == .fourBySix ? 1 : 2 }

    /// Margin around each label, in points.
    var margin: Double { self == .fourBySix ? 14 : 30 }

    public func pageCount(labels: Int) -> Int { (labels + labelsPerPage - 1) / labelsPerPage }

    /// Where label `index` goes: its page (0-based) and its rectangle on that page.
    public func slot(_ index: Int) -> (page: Int, rect: LabelRect) {
        let page = index / labelsPerPage
        let (w, h) = pageSize
        switch self {
        case .fourBySix:
            return (page, LabelRect(x: margin, y: margin, width: w - margin * 2, height: h - margin * 2))
        case .letterTwoUp:
            let half = h / 2
            let row = Double(index % 2)
            return (page, LabelRect(x: margin, y: row * half + margin, width: w - margin * 2, height: half - margin * 2))
        }
    }
}
