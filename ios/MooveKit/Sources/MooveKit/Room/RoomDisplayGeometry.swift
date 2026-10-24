import Foundation

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
