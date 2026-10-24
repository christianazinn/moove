import Foundation

/// Objects RoomPlan doesn't recognize (bikes, suitcases, plants...), found by an
/// image detector during the scan and measured from LiDAR depth (#73).
/// This file is the pure part: fitting a box to a point cloud, and merging
/// sightings of the same object across camera frames.

/// An upright box fitted to points: center at mid-height, `size` = (width along
/// the box's x, height, depth along its z), rotated `yaw` about +Y. Width ≥ depth.
public struct FittedBox: Equatable, Sendable {
    public var center: SIMD3<Float>
    public var size: SIMD3<Float>
    public var yaw: Float

    public var transform: RoomTransform { .at(center, yaw: yaw) }
}

public enum BoxFit {
    /// Smallest upright box (by footprint area) around the bulk of the points.
    /// Percentile trimming ignores stray depth samples (background, edges);
    /// the bottom is extended to `floorY` when the object stands on the floor.
    public static func fit(_ points: [SIMD3<Float>], floorY: Float? = nil, trim: Float = 0.05) -> FittedBox? {
        guard points.count >= 12 else { return nil }
        var ys = points.map(\.y).sorted()
        let top = percentile(ys, 1 - trim / 2)
        var bottom = percentile(ys, trim / 2)
        if let floorY, bottom - floorY < 0.25 { bottom = floorY }  // standing on the floor
        ys.removeAll()

        var best: (area: Float, yaw: Float, lo: SIMD2<Float>, hi: SIMD2<Float>)?
        for step in 0..<30 {  // 0°..87°, every 3°
            let yaw = Float(step) * 3 * .pi / 180
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
                         size: SIMD3(max(width, 0.05), height, max(depth, 0.05)), yaw: yaw)
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
/// one. Objects seen only once are dropped as likely false positives.
public struct SightingMerger: Sendable {
    public struct Track: Sendable {
        public var label: String
        public var sightings: Int
        public var bestConfidence: Float
        public var points: [SIMD3<Float>]
        public var box: FittedBox
    }

    public private(set) var tracks: [Track] = []
    public var floorY: Float?
    /// Caps memory: keep an even sample of at most this many points per object.
    public var maxPointsPerTrack = 4000

    public init(floorY: Float? = nil) { self.floorY = floorY }

    public mutating func add(_ s: Sighting) {
        guard let box = BoxFit.fit(s.points, floorY: floorY) else { return }
        let match = tracks.indices
            .filter { tracks[$0].label == s.label }
            .map { ($0, horizontalDistance(tracks[$0].box.center, box.center)) }
            .filter { $0.1 < max(0.6, max(tracks[$0.0].box.size.x, box.size.x) * 0.6) }
            .min { $0.1 < $1.1 }
        if let (i, _) = match {
            var t = tracks[i]
            t.sightings += 1
            t.bestConfidence = max(t.bestConfidence, s.confidence)
            t.points = Self.thin(t.points + s.points, to: maxPointsPerTrack)
            t.box = BoxFit.fit(t.points, floorY: floorY) ?? t.box
            tracks[i] = t
        } else {
            tracks.append(Track(label: s.label, sightings: 1, bestConfidence: s.confidence,
                                points: Self.thin(s.points, to: maxPointsPerTrack), box: box))
        }
    }

    /// Objects seen at least `minSightings` times that don't sit on top of something
    /// RoomPlan already found (its boxes in `existing`, as footprints).
    /// Refits every object with the current `floorY` (known once RoomPlan finishes),
    /// then filters as above.
    public func results(minSightings: Int = 2, excluding existing: [RoomGeometry.Object] = []) -> [Track] {
        tracks.compactMap { t -> Track? in
            var t = t
            t.box = BoxFit.fit(t.points, floorY: floorY) ?? t.box
            guard t.sightings >= minSightings, !existing.contains(where: { overlapRatio(t.box, $0) > 0.5 }) else { return nil }
            return t
        }
    }

    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = SIMD2(a.x - b.x, a.z - b.z)
        return (d * d).sum().squareRoot()
    }

    /// Share of the fitted box's footprint (approximated by its axis-aligned
    /// bounds) covered by a RoomPlan object's footprint bounds.
    private func overlapRatio(_ box: FittedBox, _ o: RoomGeometry.Object) -> Float {
        func bounds(_ pts: [SIMD2<Float>]) -> (SIMD2<Float>, SIMD2<Float>) {
            (pts.reduce(pts[0]) { pointwiseMin($0, $1) }, pts.reduce(pts[0]) { pointwiseMax($0, $1) })
        }
        let (alo, ahi) = bounds(RoomGeometry.footprint(width: box.size.x, depth: box.size.z, box.transform))
        let (blo, bhi) = bounds(RoomGeometry.footprint(width: o.dimensions.x, depth: o.dimensions.z, o.transform))
        let lo = pointwiseMax(alo, blo), hi = pointwiseMin(ahi, bhi)
        let inter = max(hi.x - lo.x, 0) * max(hi.y - lo.y, 0)
        let area = (ahi.x - alo.x) * (ahi.y - alo.y)
        return area > 0 ? inter / area : 0
    }

    static func thin(_ points: [SIMD3<Float>], to max: Int) -> [SIMD3<Float>] {
        guard points.count > max else { return points }
        let stride = Double(points.count) / Double(max)
        return (0..<max).map { points[Int(Double($0) * stride)] }
    }
}
