import Foundation

/// Numbers a live backend's connection attempts so late events from an old one are dropped.
///
/// `connect` starts by tearing the previous connection down and cancelling its tasks, but a
/// cancelled task still runs its exit path (e.g. "connection closed" -> `.failed`) on another
/// thread whenever the scheduler gets to it, which can be after the new connection has already
/// reported `.connected`. Each connection's tasks capture the generation they were started in,
/// and only the current generation may change status, rows or the connect result.
/// Not thread-safe by itself: keep it behind the backend's lock.
public struct ConnectionGeneration: Sendable, Equatable {
    public private(set) var current: UInt64 = 0

    public init() {}

    /// Starts a new generation (call on connect and on disconnect). Everything older is stale.
    @discardableResult
    public mutating func advance() -> UInt64 {
        current &+= 1
        return current
    }

    /// True only for events from the connection that is live now.
    public func isCurrent(_ generation: UInt64) -> Bool { generation == current }
}
