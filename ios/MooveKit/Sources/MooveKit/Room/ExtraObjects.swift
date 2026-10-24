import Foundation

/// Objects RoomPlan doesn't recognize (bikes, scooters, guitars...), found by an
/// image detector during the scan and measured from LiDAR depth (#73, #82).
/// This file is the pure part: fitting a box to a point cloud, and merging
/// sightings of the same object across camera frames.

/// An upright box fitted to points: center at mid-height, `size` = (width along
/// the box's x, height, depth along its z), rotated `yaw` about +Y. Width ≥ depth.
public struct FittedBox: Equatable, Sendable {
    public var center: SIMD3<Float>
    public var size: SIMD3<Float>
    public var yaw: Float

    public init(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float) {
        self.center = center
        self.size = size
        self.yaw = yaw
    }

    public var transform: RoomTransform { .at(center, yaw: yaw) }
}

public enum BoxFit {
    /// Smallest upright box (by footprint area) around the bulk of the points.
    /// - Stray depth samples are dropped first by a per-axis MAD test (`madThreshold`,
    ///   nil turns it off), which catches a cluster of background hits too big for the
    ///   percentile `trim` alone; the trim then shaves the edges.
    /// - Yaw: a 3° sweep, plus 0.5° steps within ±6° of the points' principal axis when
    ///   the footprint is elongated (`refineYaw`), so an object at 31.4° isn't fitted at 30°.
    /// - The bottom is extended to `floorY` when the object stands on the floor.
    public static func fit(_ points: [SIMD3<Float>], floorY: Float? = nil, trim: Float = 0.05,
                           madThreshold: Float? = 3.5, refineYaw: Bool = true) -> FittedBox? {
        guard points.count >= 12 else { return nil }
        var points = points
        if let madThreshold {
            let kept = rejectOutliers(points, threshold: madThreshold)
            if kept.count >= 12 { points = kept }
        }
        var ys = points.map(\.y).sorted()
        let top = percentile(ys, 1 - trim / 2)
        var bottom = percentile(ys, trim / 2)
        if let floorY, bottom - floorY < 0.25 { bottom = floorY }  // standing on the floor
        ys.removeAll()

        var yaws = (0..<30).map { Float($0) * 3 * .pi / 180 }  // 0°..87°, every 3°
        if refineYaw, let pca = principalYaw(points), pca.anisotropy > 0.2 {
            yaws += (-12...12).map { pca.yaw + Float($0) * 0.5 * .pi / 180 }
        }
        var best: (area: Float, yaw: Float, lo: SIMD2<Float>, hi: SIMD2<Float>)?
        for yaw in yaws {
            let c = cos(yaw), s = sin(yaw)
            // Coordinates in a frame rotated by `yaw` (inverse of RoomTransform.at's rotation).
            let us = points.map { c * $0.x - s * $0.z }.sorted()
            let vs = points.map { s * $0.x + c * $0.z }.sorted()
            let lo = SIMD2(percentile(us, trim), percentile(vs, trim))
            let hi = SIMD2(percentile(us, 1 - trim), percentile(vs, 1 - trim))
            let area = (hi.x - lo.x) * (hi.y - lo.y)
            if best == nil || area < best!.area { best = (area, yaw, lo, hi) }
        }
        guard let b = best else { return nil }
        let mid = (b.lo + b.hi) / 2
        let c = cos(b.yaw), s = sin(b.yaw)
        // Rotate the footprint center back into world space.
        let cx = c * mid.x + s * mid.y, cz = -s * mid.x + c * mid.y
        var width = b.hi.x - b.lo.x, depth = b.hi.y - b.lo.y, yaw = b.yaw
        if depth > width {
            swap(&width, &depth)
            yaw += .pi / 2
        }
        let height = max(top - bottom, 0.05)
        return FittedBox(center: SIMD3(cx, bottom + height / 2, cz),
                         size: SIMD3(max(width, 0.05), height, max(depth, 0.05)), yaw: wrapHalfTurn(yaw))
    }

    /// Drops points whose modified z-score (0.6745 · |x − median| / MAD, Iglewicz–Hoaglin)
    /// exceeds `threshold` on any axis. Points on an object's faces stay well under 3.5;
    /// background hits meters away don't.
    static func rejectOutliers(_ points: [SIMD3<Float>], threshold: Float = 3.5) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return points }
        let kx = inliers(points.map(\.x), threshold: threshold)
        let ky = inliers(points.map(\.y), threshold: threshold)
        let kz = inliers(points.map(\.z), threshold: threshold)
        return points.indices.filter { kx[$0] && ky[$0] && kz[$0] }.map { points[$0] }
    }

    /// Which values are within `threshold` modified z-scores of the median. When more
    /// than half the values are identical (MAD = 0) the mean absolute deviation stands in.
    static func inliers(_ values: [Float], threshold: Float) -> [Bool] {
        let med = median(values)
        let dev = values.map { abs($0 - med) }
        var scale = median(dev) / 0.6745
        if scale <= 1e-6 { scale = dev.reduce(0, +) / Float(max(dev.count, 1)) * 1.2533 }
        guard scale > 1e-6 else { return values.map { _ in true } }
        return dev.map { $0 / scale <= threshold }
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Yaw (`RoomTransform.at` convention) of the main axis of the points' XZ spread,
    /// and how elongated it is (1 − λmin/λmax: 0 round or square, near 1 long and thin).
    static func principalYaw(_ points: [SIMD3<Float>]) -> (yaw: Float, anisotropy: Float)? {
        guard points.count >= 3 else { return nil }
        let n = Float(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n, mz = points.reduce(0) { $0 + $1.z } / n
        var sxx: Float = 0, szz: Float = 0, sxz: Float = 0
        for p in points {
            let dx = p.x - mx, dz = p.z - mz
            sxx += dx * dx; szz += dz * dz; sxz += dx * dz
        }
        let diff = (sxx - szz) / n, tr = (sxx + szz) / n, cov = sxz / n
        let root = (diff * diff / 4 + cov * cov).squareRoot()
        let l1 = tr / 2 + root, l2 = tr / 2 - root
        guard l1 > 1e-9 else { return nil }
        // Main axis at angle θ from +x toward +z; RoomTransform.at(yaw) sends local +x
        // to (cos yaw, −sin yaw), so yaw = −θ.
        let theta = 0.5 * atan2(2 * cov, diff)
        return (wrapHalfTurn(-theta), 1 - max(l2, 0) / l1)
    }

    static func wrapHalfTurn(_ a: Float) -> Float {
        var y = remainder(a, .pi)
        if y < 0 { y += .pi }
        return y
    }

    static func percentile(_ sorted: [Float], _ p: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let i = Int((Float(sorted.count - 1) * min(max(p, 0), 1)).rounded())
        return sorted[i]
    }
}

/// One detection in one camera frame, already turned into world-space points.
public struct Sighting: Sendable {
    public var label: String
    public var confidence: Float
    public var points: [SIMD3<Float>]

    public init(label: String, confidence: Float, points: [SIMD3<Float>]) {
        self.label = label
        self.confidence = confidence
        self.points = points
    }
}

/// Clusters sightings into objects: the same label within reach of an existing
/// object's center joins it (its points sharpen the fit), otherwise it starts a new
/// one. Objects seen only once are dropped as likely false positives, unless they're
/// big and the detector was sure (a scooter glimpsed once, from one side).
public struct SightingMerger: Sendable {
    public struct Track: Sendable {
        /// Stable for the life of the merger.
        public var id: Int
        public var label: String
        public var sightings: Int
        public var bestConfidence: Float
        /// Sum of the sightings' confidences: the label's weight when two labels claim one object.
        public var totalConfidence: Float
        public var points: [SIMD3<Float>]
        public var box: FittedBox
    }

    public private(set) var tracks: [Track] = []
    public var floorY: Float?
    /// Caps memory: keep an even sample of at most this many points per object.
    public var maxPointsPerTrack = 4000
    /// A single sighting counts when the detector was at least this sure...
    public var singleSightingConfidence: Float = 0.6
    /// ...and the object's longest side is at least this long (m). Small one-offs are
    /// mostly misfires; big things are often seen only briefly from one side.
    public var singleSightingMinSize: Float = 0.5

    public init(floorY: Float? = nil) { self.floorY = floorY }

    /// Adds a sighting and returns the id of the track it joined or started (nil if
    /// there were too few points to fit).
    @discardableResult
    public mutating func add(_ s: Sighting) -> Int? {
        guard let box = BoxFit.fit(s.points, floorY: floorY) else { return nil }
        let match = tracks.indices
            .filter { tracks[$0].label == s.label }
            .map { ($0, horizontalDistance(tracks[$0].box.center, box.center)) }
            .filter { $0.1 < max(0.6, max(tracks[$0.0].box.size.x, box.size.x) * 0.6) }
            .min { $0.1 < $1.1 }
        if let (i, _) = match {
            var t = tracks[i]
            t.sightings += 1
            t.bestConfidence = max(t.bestConfidence, s.confidence)
            t.totalConfidence += s.confidence
            t.points = Self.thin(t.points + s.points, to: maxPointsPerTrack)
            t.box = BoxFit.fit(t.points, floorY: floorY) ?? t.box
            tracks[i] = t
            return t.id
        }
        let id = tracks.count
        tracks.append(Track(id: id, label: s.label, sightings: 1, bestConfidence: s.confidence, totalConfidence: s.confidence,
                            points: Self.thin(s.points, to: maxPointsPerTrack), box: box))
        return id
    }

    /// Whether a track has enough evidence to report.
    public func isConfirmed(_ t: Track, minSightings: Int = 2) -> Bool {
        t.sightings >= minSightings
            || (t.bestConfidence >= singleSightingConfidence && max(t.box.size.x, t.box.size.y, t.box.size.z) >= singleSightingMinSize)
    }

    /// The objects found: confirmed tracks, one label per physical object, minus what
    /// RoomPlan already found (`existing`).
    /// - Refits every object with the current `floorY` (known once RoomPlan finishes);
    ///   pass `refit: false` for a cheap live preview.
    /// - When two labels claim the same space (an e-scooter that also scores as a
    ///   bicycle), the label with more total confidence, weighted by how plausible the
    ///   measured size is for it, wins.
    /// - An object mostly inside a RoomPlan object's volume is a duplicate of it. A
    ///   detection in a category RoomPlan also finds (chair, table...) is dropped when
    ///   it overlaps any RoomPlan object noticeably. Objects merely standing on a
    ///   RoomPlan object (a monitor on a table) are kept.
    public func results(minSightings: Int = 2, excluding existing: [RoomGeometry.Object] = [], refit: Bool = true) -> [Track] {
        var kept = tracks.compactMap { t -> Track? in
            var t = t
            if refit { t.box = BoxFit.fit(t.points, floorY: floorY) ?? t.box }
            return isConfirmed(t, minSightings: minSightings) ? t : nil
        }
        // Strongest first, so each object keeps its best label.
        func weight(_ t: Track) -> Float { t.totalConfidence * ObjectVocabulary.plausibility(of: t.label, size: t.box.size) }
        kept.sort { weight($0) > weight($1) }
        var resolved: [Track] = []
        for t in kept {
            if let i = resolved.firstIndex(where: { $0.label != t.label && Self.overlap(t.box, $0.box) > 0.5 }) {
                resolved[i].sightings += t.sightings  // the same object under another label
                continue
            }
            resolved.append(t)
        }
        return resolved.filter { t in
            !existing.contains { o in
                let roomPlan = FittedBox(center: o.transform.position, size: o.dimensions, yaw: o.transform.yaw)
                let inside = Self.overlap(t.box, roomPlan, relativeTo: .first)
                return inside > 0.5 || (ObjectVocabulary.isRoomPlanCategory(t.label) && inside > 0.15)
            }
        }
    }

    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = SIMD2(a.x - b.x, a.z - b.z)
        return (d * d).sum().squareRoot()
    }

    enum Relative { case smaller, first }

    /// Shared volume of two upright boxes, as a share of the smaller one's volume (or
    /// of the first's): the exact intersection of the rotated footprints times the
    /// vertical overlap, so two long things side by side at 45° don't count as overlapping.
    static func overlap(_ a: FittedBox, _ b: FittedBox, relativeTo: Relative = .smaller) -> Float {
        let dy = min(a.center.y + a.size.y / 2, b.center.y + b.size.y / 2) - max(a.center.y - a.size.y / 2, b.center.y - b.size.y / 2)
        guard dy > 0 else { return 0 }
        let fa = RoomGeometry.footprint(width: a.size.x, depth: a.size.z, a.transform)
        let fb = RoomGeometry.footprint(width: b.size.x, depth: b.size.z, b.transform)
        let inter = abs(signedArea(clip(fa, by: fb))) * dy
        let va = a.size.x * a.size.y * a.size.z, vb = b.size.x * b.size.y * b.size.z
        let base = relativeTo == .first ? va : min(va, vb)
        return base > 0 ? min(inter / base, 1) : 0
    }

    static func signedArea(_ p: [SIMD2<Float>]) -> Float {
        guard p.count >= 3 else { return 0 }
        var a: Float = 0
        for i in p.indices {
            let q = p[i], r = p[(i + 1) % p.count]
            a += q.x * r.y - r.x * q.y
        }
        return a / 2
    }

    /// Sutherland–Hodgman: the part of `subject` inside the convex polygon `clipper`.
    static func clip(_ subject: [SIMD2<Float>], by clipper: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard clipper.count >= 3 else { return [] }
        let ccw = signedArea(clipper) >= 0 ? clipper : clipper.reversed()
        func side(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ p: SIMD2<Float>) -> Float {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        var out = subject
        for i in ccw.indices {
            let a = ccw[i], b = ccw[(i + 1) % ccw.count]
            let input = out
            out = []
            guard !input.isEmpty else { break }
            for j in input.indices {
                let p = input[j], q = input[(j + 1) % input.count]
                let sp = side(a, b, p), sq = side(a, b, q)
                if sp >= 0 { out.append(p) }
                if (sp >= 0) != (sq >= 0) { out.append(p + (q - p) * (sp / (sp - sq))) }
            }
        }
        return out
    }

    static func thin(_ points: [SIMD3<Float>], to max: Int) -> [SIMD3<Float>] {
        guard points.count > max else { return points }
        let stride = Double(points.count) / Double(max)
        return (0..<max).map { points[Int(Double($0) * stride)] }
    }
}
