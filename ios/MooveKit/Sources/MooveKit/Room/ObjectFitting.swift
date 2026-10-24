import Foundation

/// Sturdier fitting and fusion for the extra objects of #73, on top of
/// `BoxFit` and `SightingMerger` in ExtraObjects.swift:
/// - MAD outlier rejection on depth points (per axis, or by range from the camera),
/// - a 2D PCA yaw that seeds a fine yaw search next to `BoxFit`'s 3° sweep,
/// - 3D IoU of upright boxes (rotated footprint intersection × vertical overlap),
/// - `TrackFuser`: timestamped sightings, confirmed after ≥3 frames over ≥2 s.
public enum ObjectFitting {
    // MARK: MAD outlier rejection

    /// Drops points whose modified z-score (0.6745 · |x − median| / MAD, Iglewicz–Hoaglin)
    /// exceeds `threshold` on any axis. Points on a box's faces stay well under 3.5;
    /// background hits meters away don't.
    public static func rejectOutliers(_ points: [SIMD3<Float>], threshold: Float = 3.5) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return points }
        let kx = inliers(points.map(\.x), threshold: threshold)
        let ky = inliers(points.map(\.y), threshold: threshold)
        let kz = inliers(points.map(\.z), threshold: threshold)
        return points.indices.filter { kx[$0] && ky[$0] && kz[$0] }.map { points[$0] }
    }

    /// Same test on each point's distance from `origin` (the camera for one frame's
    /// depth points), so a detection box that also covers the wall behind the object
    /// keeps only the object's depth band.
    public static func rejectRangeOutliers(_ points: [SIMD3<Float>], from origin: SIMD3<Float>, threshold: Float = 3.5) -> [SIMD3<Float>] {
        guard points.count >= 3 else { return points }
        let keep = inliers(points.map { length($0 - origin) }, threshold: threshold)
        return points.indices.filter { keep[$0] }.map { points[$0] }
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
        let s = values.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    // MARK: PCA yaw

    /// Yaw (same convention as `RoomTransform.at`) of the main axis of the points'
    /// XZ spread, and how elongated that spread is (1 − λmin/λmax: 0 round or square,
    /// near 1 long and thin). Nil for fewer than 3 points or no spread.
    public static func principalYaw(_ points: [SIMD3<Float>]) -> (yaw: Float, anisotropy: Float)? {
        guard points.count >= 3 else { return nil }
        let n = Float(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n, mz = points.reduce(0) { $0 + $1.z } / n
        var sxx: Float = 0, szz: Float = 0, sxz: Float = 0
        for p in points {
            let dx = p.x - mx, dz = p.z - mz
            sxx += dx * dx; szz += dz * dz; sxz += dx * dz
        }
        sxx /= n; szz /= n; sxz /= n
        let tr = sxx + szz, diff = sxx - szz
        let root = (diff * diff / 4 + sxz * sxz).squareRoot()
        let l1 = tr / 2 + root, l2 = tr / 2 - root
        guard l1 > 1e-9 else { return nil }
        // Main eigenvector direction in XZ, at angle θ from +x toward +z.
        let theta = 0.5 * atan2(2 * sxz, diff)
        // RoomTransform.at(yaw) sends local +x to (cos yaw, −sin yaw) in XZ, so yaw = −θ.
        return (wrapHalfTurn(-theta), 1 - max(l2, 0) / l1)
    }

    /// How far apart two box yaws are, in [0, π/4]: a box's yaw only matters mod 90°.
    public static func yawDifference(_ a: Float, _ b: Float) -> Float {
        abs(remainder(a - b, .pi / 2))
    }

    static func wrapHalfTurn(_ a: Float) -> Float {
        var y = remainder(a, .pi)
        if y < 0 { y += .pi }
        return y
    }

    // MARK: Box fit

    /// `BoxFit.fit` with MAD rejection first and a finer yaw search: the 3° sweep plus
    /// 0.5° steps within ±6° of the PCA yaw (when the footprint is elongated enough for
    /// PCA to mean something). Picks the smallest trimmed footprint, as `BoxFit` does.
    public static func fit(_ points: [SIMD3<Float>], floorY: Float? = nil, trim: Float = 0.05,
                           madThreshold: Float? = 3.5) -> FittedBox? {
        guard points.count >= 12 else { return nil }
        var pts = points
        if let madThreshold {
            let kept = rejectOutliers(points, threshold: madThreshold)
            if kept.count >= 12 { pts = kept }
        }
        var yaws = (0..<30).map { Float($0) * 3 * .pi / 180 }
        if let pca = principalYaw(pts), pca.anisotropy > 0.2 {
            yaws += (-12...12).map { pca.yaw + Float($0) * 0.5 * .pi / 180 }
        }
        return fit(pts, yaws: yaws, floorY: floorY, trim: trim)
    }

    /// Smallest trimmed footprint among the given yaws; height and floor snap as `BoxFit`.
    static func fit(_ points: [SIMD3<Float>], yaws: [Float], floorY: Float?, trim: Float) -> FittedBox? {
        guard points.count >= 12, !yaws.isEmpty else { return nil }
        let ys = points.map(\.y).sorted()
        let top = BoxFit.percentile(ys, 1 - trim / 2)
        var bottom = BoxFit.percentile(ys, trim / 2)
        if let floorY, bottom - floorY < 0.25 { bottom = floorY }

        var best: (area: Float, yaw: Float, lo: SIMD2<Float>, hi: SIMD2<Float>)?
        for yaw in yaws {
            let c = cos(yaw), s = sin(yaw)
            let us = points.map { c * $0.x - s * $0.z }.sorted()
            let vs = points.map { s * $0.x + c * $0.z }.sorted()
            let lo = SIMD2(BoxFit.percentile(us, trim), BoxFit.percentile(vs, trim))
            let hi = SIMD2(BoxFit.percentile(us, 1 - trim), BoxFit.percentile(vs, 1 - trim))
            let area = (hi.x - lo.x) * (hi.y - lo.y)
            if best == nil || area < best!.area { best = (area, yaw, lo, hi) }
        }
        guard let b = best else { return nil }
        let mid = (b.lo + b.hi) / 2
        let c = cos(b.yaw), s = sin(b.yaw)
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

    // MARK: 3D IoU

    /// Intersection over union of two upright boxes (center at mid-height, `size` =
    /// width/height/depth, rotated about +Y): exact rotated-footprint intersection
    /// times vertical overlap.
    public static func iou(center a: SIMD3<Float>, size sa: SIMD3<Float>, yaw ya: Float,
                           center b: SIMD3<Float>, size sb: SIMD3<Float>, yaw yb: Float) -> Float {
        let fa = RoomGeometry.footprint(width: sa.x, depth: sa.z, .at(a, yaw: ya))
        let fb = RoomGeometry.footprint(width: sb.x, depth: sb.z, .at(b, yaw: yb))
        let overlapY = max(0, min(a.y + sa.y / 2, b.y + sb.y / 2) - max(a.y - sa.y / 2, b.y - sb.y / 2))
        let inter = polygonArea(clip(fa, by: fb)) * overlapY
        let union = sa.x * sa.y * sa.z + sb.x * sb.y * sb.z - inter
        return union > 0 ? inter / union : 0
    }

    public static func iou(_ box: FittedBox, _ o: RoomGeometry.Object) -> Float {
        iou(center: box.center, size: box.size, yaw: box.yaw,
            center: o.transform.position, size: o.dimensions, yaw: o.transform.yaw)
    }

    public static func iou(_ a: FittedBox, _ b: FittedBox) -> Float {
        iou(center: a.center, size: a.size, yaw: a.yaw, center: b.center, size: b.size, yaw: b.yaw)
    }

    /// Whether RoomPlan already found this object: 3D IoU with one of its boxes above `threshold`.
    public static func isDuplicate(_ box: FittedBox, of existing: [RoomGeometry.Object], threshold: Float = 0.3) -> Bool {
        existing.contains { iou(box, $0) > threshold }
    }

    /// Absolute area of a simple polygon (shoelace).
    static func polygonArea(_ p: [SIMD2<Float>]) -> Float {
        abs(signedArea(p))
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
                if (sp >= 0) != (sq >= 0) {
                    let t = sp / (sp - sq)
                    out.append(p + (q - p) * t)
                }
            }
        }
        return out
    }

    static func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
}

/// Like `SightingMerger`, but sightings carry their frame time and an object only
/// counts once it has been seen in at least 3 frames spread over at least 2 s, each
/// time within 0.5 m of where it was (same label). Several detections of one object
/// in the same frame add points but count as one sighting.
public struct TrackFuser: Sendable {
    public struct Track: Sendable {
        public var label: String
        /// Distinct frames this object was seen in.
        public var sightings: Int
        public var bestConfidence: Float
        public var firstSeen: TimeInterval
        public var lastSeen: TimeInterval
        public var points: [SIMD3<Float>]
        public var box: FittedBox

        public var duration: TimeInterval { lastSeen - firstSeen }

        /// The same object as a `SightingMerger.Track`, for code built on the merger.
        public var mergerTrack: SightingMerger.Track {
            SightingMerger.Track(label: label, sightings: sightings, bestConfidence: bestConfidence, points: points, box: box)
        }
    }

    public private(set) var tracks: [Track] = []
    public var floorY: Float?
    /// Horizontal distance between box centers for a sighting to join a track.
    public var matchRadius: Float = 0.5
    /// Caps memory: keep an even sample of at most this many points per object.
    public var maxPointsPerTrack = 4000
    /// MAD threshold for `ObjectFitting.fit`; nil turns rejection off.
    public var madThreshold: Float? = 3.5

    public init(floorY: Float? = nil) { self.floorY = floorY }

    /// Adds one detection seen in the frame at `time` (seconds, any monotonic clock).
    public mutating func add(_ s: Sighting, at time: TimeInterval) {
        guard let box = ObjectFitting.fit(s.points, floorY: floorY, madThreshold: madThreshold) else { return }
        let match = tracks.indices
            .filter { tracks[$0].label == s.label }
            .map { ($0, Self.horizontalDistance(tracks[$0].box.center, box.center)) }
            .filter { $0.1 <= matchRadius }
            .min { $0.1 < $1.1 }
        if let (i, _) = match {
            var t = tracks[i]
            if time != t.lastSeen && time != t.firstSeen { t.sightings += 1 }
            t.firstSeen = min(t.firstSeen, time)
            t.lastSeen = max(t.lastSeen, time)
            t.bestConfidence = max(t.bestConfidence, s.confidence)
            t.points = SightingMerger.thin(t.points + s.points, to: maxPointsPerTrack)
            t.box = ObjectFitting.fit(t.points, floorY: floorY, madThreshold: madThreshold) ?? t.box
            tracks[i] = t
        } else {
            tracks.append(Track(label: s.label, sightings: 1, bestConfidence: s.confidence, firstSeen: time, lastSeen: time,
                                points: SightingMerger.thin(s.points, to: maxPointsPerTrack), box: box))
        }
    }

    /// Tracks seen in at least `minSightings` frames over at least `minDuration` seconds,
    /// refit with the current `floorY`, minus those whose 3D IoU with a RoomPlan object
    /// in `existing` exceeds `maxIoU`.
    public func confirmed(minSightings: Int = 3, minDuration: TimeInterval = 2,
                          excluding existing: [RoomGeometry.Object] = [], maxIoU: Float = 0.3) -> [Track] {
        tracks.compactMap { t -> Track? in
            guard t.sightings >= minSightings, t.duration >= minDuration else { return nil }
            var t = t
            t.box = ObjectFitting.fit(t.points, floorY: floorY, madThreshold: madThreshold) ?? t.box
            return ObjectFitting.isDuplicate(t.box, of: existing, threshold: maxIoU) ? nil : t
        }
    }

    static func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = SIMD2(a.x - b.x, a.z - b.z)
        return (d * d).sum().squareRoot()
    }
}
