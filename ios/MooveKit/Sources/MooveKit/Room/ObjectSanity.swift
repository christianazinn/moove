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
