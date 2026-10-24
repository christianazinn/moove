import MooveKit

/// What New Home solves: a plan and the pieces going into it.
struct SolveKey: Hashable, Sendable {
    var plan: FloorPlan
    var items: [LayoutItem]
}

/// Solved layouts per (plan, items), so re-opening New Home (or switching back to a plan) shows
/// the layout at once instead of solving again. A few entries only: each key is one home + one
/// set of moving pieces.
@MainActor
enum LayoutCache {
    private static var entries: [SolveKey: [LayoutOption]] = [:]
    /// Oldest first, for dropping the least recently used.
    private static var order: [SolveKey] = []
    static let limit = 6

    static func options(for key: SolveKey) -> [LayoutOption]? {
        guard let hit = entries[key] else { return nil }
        touch(key)
        return hit
    }

    static func store(_ options: [LayoutOption], for key: SolveKey) {
        entries[key] = options
        touch(key)
        while order.count > limit { entries[order.removeFirst()] = nil }
    }

    private static func touch(_ key: SolveKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
