import Foundation

/// Picks a few keyframes that together show the whole room, for the photo sweep (#92):
/// sharp, level, looking across the room rather than at something close, and facing
/// different ways so each photo adds walls the others don't.
public enum WideFramePicker {
    /// Steeper than this (|forward.y|) is looking at the floor or ceiling.
    public static let maxTilt: Float = 0.5
    /// Median LiDAR depth (m) below this is a close-up, not a room view.
    public static let minDepth: Float = 1.2
    /// Headings closer than this add little; skip them.
    public static let minSeparation: Float = 35 * .pi / 180

    /// Keyframe ids, best first. Fewer than `count` when the scan didn't look around much.
    public static func pick(_ frames: [Keyframe], count: Int = 4) -> [Int] {
        guard count > 0, !frames.isEmpty else { return [] }
        let sharpness = frames.map(\.sharpness).sorted()
        let typical = max(sharpness[sharpness.count / 2], 1e-6)
        let candidates = frames.compactMap { f -> (id: Int, heading: Float, score: Float)? in
            let forward = f.pose.forward
            guard abs(forward.y) <= maxTilt, f.sharpness >= 0.4 * typical else { return nil }
            let depth = f.depth.map(medianDepth)
            if let depth, depth < minDepth { return nil }
            let wide = depth.map { min($0 / 2.5, 1) } ?? 0.6
            return (f.id, atan2(forward.x, forward.z), min(f.sharpness / typical, 2) * wide)
        }
        guard let first = candidates.max(by: { $0.score < $1.score }) else { return [] }
        var chosen = [first]
        while chosen.count < count {
            func spread(_ h: Float) -> Float { chosen.map { headingDistance(h, $0.heading) }.min() ?? .pi }
            let next = candidates
                .filter { c in !chosen.contains { $0.id == c.id } && spread(c.heading) >= minSeparation }
                // Widest gap first; among similar gaps (within 15°), the better photo.
                .max { a, b in
                    let sa = spread(a.heading), sb = spread(b.heading)
                    return abs(sa - sb) < 15 * .pi / 180 ? a.score < b.score : sa < sb
                }
            guard let next else { break }
            chosen.append(next)
        }
        return chosen.map(\.id)
    }

    static func headingDistance(_ a: Float, _ b: Float) -> Float {
        abs(remainder(a - b, 2 * .pi))
    }

    static func medianDepth(_ grid: DepthGrid) -> Float {
        let valid = grid.values.filter { $0.isFinite && $0 > 0 }.sorted()
        return valid.isEmpty ? 0 : valid[valid.count / 2]
    }
}
