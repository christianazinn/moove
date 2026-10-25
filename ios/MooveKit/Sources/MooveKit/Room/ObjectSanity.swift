import Foundation

/// Last check on every scanned object's size before `import_scan_v2` (#182).
///
/// RoomPlan and the extra detector both produce the odd impossible box: a real scan
/// had a 2.08 m tall "vacuum" and a 6 cm deep "refrigerator". The module now skips
/// absurd objects instead of rejecting the whole scan (#177), but a box that's merely
/// implausible for its label would still import under a wrong name. So:
/// - **drop** what can't be a movable object at all (non-finite, under 2 cm in any
///   direction, or longer than a room wall);
/// - **relabel** to `other` what's real but the wrong size for its category, so the
///   vision agent or the photo sweep names it from its photo;
/// - keep the rest.
public enum ObjectSanity {
    public enum Result: Equatable, Sendable {
        case ok
        case relabel(String, reason: String)
        case drop(reason: String)
    }

    /// Typical size per category (m): the footprint's short and long side, and height.
    public struct Range: Sendable {
        public var short: ClosedRange<Double>
        public var long: ClosedRange<Double>
        public var height: ClosedRange<Double>
    }

    public static let relabelCategory = StructureCheck.unknownCategory
    /// Slack on every bound, so a slightly loose RoomPlan box isn't renamed.
    public static let tolerance = 0.15
    public static let minSide = 0.02
    public static let maxSide = 8.0

    /// RoomPlan's categories (`String(describing: CapturedRoom.Object.Category)`).
    public static let ranges: [String: Range] = [
        "table": Range(short: 0.3...1.8, long: 0.35...3.6, height: 0.3...1.2),
        "chair": Range(short: 0.3...1.0, long: 0.35...1.3, height: 0.4...1.4),
        "sofa": Range(short: 0.5...2.2, long: 0.8...4.2, height: 0.35...1.3),
        "bed": Range(short: 0.6...2.3, long: 1.2...2.6, height: 0.1...2.0),
        "storage": Range(short: 0.1...1.3, long: 0.25...3.6, height: 0.15...2.7),
        "refrigerator": Range(short: 0.4...1.0, long: 0.45...1.3, height: 0.45...2.1),
        "television": Range(short: 0.02...0.6, long: 0.4...2.3, height: 0.25...1.5),
        "stove": Range(short: 0.4...1.0, long: 0.45...1.6, height: 0.3...1.2),
        "oven": Range(short: 0.4...1.0, long: 0.45...1.2, height: 0.3...1.2),
        "dishwasher": Range(short: 0.4...0.8, long: 0.45...0.9, height: 0.55...0.95),
        "washerDryer": Range(short: 0.4...0.95, long: 0.5...1.1, height: 0.6...2.0),
        "sink": Range(short: 0.3...1.0, long: 0.35...2.6, height: 0.1...1.2),
        "toilet": Range(short: 0.3...0.9, long: 0.4...1.0, height: 0.35...1.1),
        "bathtub": Range(short: 0.5...1.3, long: 0.9...2.3, height: 0.25...0.9),
    ]

    /// Footprint priors for detector categories (short × long × height, m), one entry per
    /// common shape (a kick scooter and an e-scooter are both "scooter"). Detector boxes are
    /// noisy (partial views, merged neighbors), so `check` doesn't enforce these;
    /// `ObjectRecheck` uses them only to veto a label the box clearly can't be.
    public static let footprints: [String: [Range]] = [
        "scooter": [Range(short: 0.40...0.65, long: 0.95...1.25, height: 1.00...1.30),    // e-scooter
                    Range(short: 0.10...0.45, long: 0.55...1.00, height: 0.60...1.05)],   // kick scooter
        "vacuum": [Range(short: 0.25...0.40, long: 0.28...0.45, height: 1.00...1.20),     // upright
                   Range(short: 0.18...0.30, long: 0.20...0.32, height: 1.00...1.32),     // stick
                   Range(short: 0.28...0.36, long: 0.28...0.36, height: 0.07...0.11)],    // robot
        "mop": [Range(short: 0.03...0.20, long: 0.15...0.45, height: 1.10...1.50)],       // mop / broom
        "bicycle": [Range(short: 0.40...0.80, long: 1.50...1.90, height: 0.90...1.20)],
        "stroller": [Range(short: 0.45...0.70, long: 0.75...1.05, height: 0.95...1.10)],
        "box": [Range(short: 0.30...0.34, long: 0.40...0.43, height: 0.30...0.34),        // moving boxes: small
                Range(short: 0.44...0.47, long: 0.45...0.48, height: 0.39...0.42),        // medium
                Range(short: 0.44...0.47, long: 0.45...0.62, height: 0.58...0.63)],       // large
        // Fixtures (not movable; `ObjectRecheck` rejects them).
        "radiator": [Range(short: 0.05...0.25, long: 0.40...2.00, height: 0.30...0.90)],
        "shower curtain": [Range(short: 0.02...0.30, long: 1.50...2.00, height: 1.60...2.00)],
    ]

    /// Whether a box fits one of `category`'s `footprints`, each bound widened by
    /// `factor` (`lower / factor ... upper * factor`; 1.15 ≈ `tolerance`). Nil without a prior.
    public static func fitsFootprint(_ category: String, width: Double, height: Double, depth: Double, factor: Double = 1 + tolerance) -> Bool? {
        guard let shapes = footprints[category] else { return nil }
        let v = [min(width, depth), max(width, depth), height]
        return shapes.contains { r in
            zip(v, [r.short, r.long, r.height]).allSatisfy { x, b in x >= b.lowerBound / factor && x <= b.upperBound * factor }
        }
    }

    /// `fitsFootprint`, falling back to RoomPlan's `ranges` for categories without a footprint
    /// (table, storage, bed, television...). `ObjectRecheck` uses it on a relabel's target, so the
    /// classifier can't rename a 9 cm tall backpack "table". Nil without either prior.
    public static func fitsSizePrior(_ category: String, width: Double, height: Double, depth: Double, factor: Double = 1 + tolerance) -> Bool? {
        if let fits = fitsFootprint(category, width: width, height: height, depth: depth, factor: factor) { return fits }
        guard let r = ranges[category] else { return nil }
        let v = [min(width, depth), max(width, depth), height]
        return zip(v, [r.short, r.long, r.height]).allSatisfy { x, b in x >= b.lowerBound / factor && x <= b.upperBound * factor }
    }

    public static func check(category: String, width: Double, height: Double, depth: Double) -> Result {
        let dims = [width, height, depth]
        guard dims.allSatisfy(\.isFinite) else { return .drop(reason: "size isn't a number") }
        if let small = dims.min(), small < minSide {
            return .drop(reason: "\(cm(small)) thin")
        }
        if let big = dims.max(), big > maxSide {
            return .drop(reason: String(format: "%.0f m long", big))
        }
        guard category != relabelCategory else { return .ok }
        let short = min(width, depth), long = max(width, depth)
        if let r = ranges[category] {
            if let why = outside(short, r.short, "footprint") ?? outside(long, r.long, "length") ?? outside(height, r.height, "height") {
                return .relabel(relabelCategory, reason: "\(why) for a \(category)")
            }
        } else if let h = StructureCheck.doubleHeightRange(category), let why = outside(height, h, "height") {
            // The detector's extra classes (#98) only have a height range.
            return .relabel(relabelCategory, reason: "\(why) for a \(category)")
        }
        return .ok
    }

    private static func outside(_ v: Double, _ r: ClosedRange<Double>, _ what: String) -> String? {
        if v < r.lowerBound * (1 - tolerance) { return "\(cm(v)) \(what) is too small" }
        if v > r.upperBound * (1 + tolerance) { return "\(cm(v)) \(what) is too big" }
        return nil
    }

    private static func cm(_ m: Double) -> String {
        m < 1 ? "\(Int((m * 100).rounded())) cm" : String(format: "%.2f m", m)
    }
}

extension StructureCheck {
    /// `heightRange` is Float (it works on detector boxes); this is just a Double view for ObjectSanity.
    fileprivate static func doubleHeightRange(_ category: String) -> ClosedRange<Double>? {
        heightRange[category].map { Double($0.lowerBound)...Double($0.upperBound) }
    }
}
