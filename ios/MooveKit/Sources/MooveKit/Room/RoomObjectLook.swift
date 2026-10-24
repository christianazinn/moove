import Foundation

/// What the 3D room view last drew for one piece of furniture: its color,
/// whether it is selected, its label, and which captured 3D model (if any)
/// it shows. The view keeps one per object and, on each update, only rebuilds the parts of the scene that changed.
public struct RoomObjectLook: Sendable, Equatable {
    /// RGBA, 0...1.
    public var color: SIMD4<Float>
    public var selected: Bool
    /// The label's text, or nil when it is hidden.
    public var label: String?
    /// Label font size in room meters.
    public var labelSize: Float
    /// Identifies the captured model shown in place of the stand-in (its file
    /// and rotation), or nil when there is none. Models load after the scene is
    /// built, so a change here rebuilds the whole object.
    public var model: String?

    public init(color: SIMD4<Float>, selected: Bool, label: String?, labelSize: Float, model: String? = nil) {
        self.color = color
        self.selected = selected
        self.label = label
        self.labelSize = labelSize
        self.model = model
    }

    /// Which parts of an object's scene need redoing.
    public struct Changes: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        /// Materials (color, or the selection glow).
        public static let color = Changes(rawValue: 1 << 0)
        /// Selection pop (scale).
        public static let selection = Changes(rawValue: 1 << 1)
        /// The floating name tag (added, removed or retyped).
        public static let label = Changes(rawValue: 1 << 2)
        /// The captured model (attached, swapped, rotated or removed).
        public static let model = Changes(rawValue: 1 << 3)
        public static let all: Changes = [.color, .selection, .label, .model]
    }

    /// What changed since `old`; everything when nothing was applied yet.
    public func changes(since old: RoomObjectLook?) -> Changes {
        guard let old else { return .all }
        // A different body means its materials and selection state start over.
        if model != old.model { return .all }
        var changes: Changes = []
        if color != old.color || selected != old.selected { changes.insert(.color) }
        if selected != old.selected { changes.insert(.selection) }
        if label != old.label || (label != nil && labelSize != old.labelSize) { changes.insert(.label) }
        return changes
    }

    /// The name tag for an object: its item's name (or category), with a heart
    /// when it might be sentimental.
    public static func labelText(for object: RoomGeometry.Object, item: Item?) -> String {
        var text = item?.name ?? object.category.capitalized
        if item?.maybeSentimental == true { text += " ♥" }
        return text
    }
}

/// Memoizes the derived geometries the room screen draws (`centered()` and
/// `cutaway(at:)`), so SwiftUI body passes don't recompute them. Recomputes
/// only when the source geometry or cut height changes. Not thread-safe:
/// keep one per view (e.g. in `@State`).
public final class RoomDisplayGeometry {
    private var source: RoomGeometry?
    private var centeredValue: RoomGeometry?
    private var cutawayValue: (height: Float, geometry: RoomGeometry)?
    /// How many times a derived geometry was computed (for tests).
    private(set) var computations = 0

    public init() {}

    /// `geometry.centered()`, cached.
    public func centered(_ geometry: RoomGeometry) -> RoomGeometry {
        if source != geometry {
            source = geometry
            centeredValue = nil
            cutawayValue = nil
        }
        if let centeredValue { return centeredValue }
        computations += 1
        let value = geometry.centered()
        centeredValue = value
        return value
    }

    /// `geometry.centered().cutaway(at: height)`, cached.
    public func cutaway(_ geometry: RoomGeometry, at height: Float) -> RoomGeometry {
        let centered = centered(geometry)
        if let cutawayValue, cutawayValue.height == height { return cutawayValue.geometry }
        computations += 1
        let value = centered.cutaway(at: height)
        cutawayValue = (height, value)
        return value
    }
}
