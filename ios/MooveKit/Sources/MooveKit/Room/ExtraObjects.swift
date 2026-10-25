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
    /// Where the camera was (world space). Used to tell distinct views apart and to
    /// know which side of the object LiDAR saw (#267).
    public var camera: SIMD3<Float>?
    /// Frame timestamp (s).
    public var time: Double?

    public init(label: String, confidence: Float, points: [SIMD3<Float>], camera: SIMD3<Float>? = nil, time: Double? = nil) {
        self.label = label
        self.confidence = confidence
        self.points = points
        self.camera = camera
        self.time = time
    }
}

/// Clusters sightings into objects: the same label within reach of an existing
/// object's center joins it (its points sharpen the fit), otherwise it starts a new
/// one. The box is refitted from the points of every sighting. Objects seen in only one
/// view are dropped as likely false positives unless the detector was very sure, or the
/// object is big, sure enough and something RoomPlan never finds (a scooter glimpsed
/// once, from one side). Sightings from (nearly) the same frame and angle count as one view.
public struct SightingMerger: Sendable {
    public struct Track: Sendable {
        /// Stable for the life of the merger.
        public var id: Int
        public var label: String
        /// Every sighting that joined, including near-duplicates from the same view.
        public var sightings: Int
        /// Distinct views: sightings at least `SightingMerger.minViewGap` seconds or
        /// `minViewAngle` apart from the previous view. This is what confirms a track.
        public var views: Int
        public var bestConfidence: Float
        /// Sum of the sightings' confidences: the label's weight when two labels claim one object.
        public var totalConfidence: Float
        public var points: [SIMD3<Float>]
        public var box: FittedBox
        /// Every label the detector gave this object, frame by frame. A track starts with its own
        /// label only; `results()` folds in the labels of the tracks it merges (and of unconfirmed
        /// tracks under another label in the same space), which used to be thrown away.
        public var labelHistory = LabelHistory()
        /// (merger-wide sighting number, label) per sighting, for `labelHistory.flips`.
        var labelLog: [(order: Int, label: String)] = []
        /// Last counted view (for the distinct-view test).
        var lastView: (time: Double?, camera: SIMD3<Float>?)
        var cameraSum = SIMD3<Float>(repeating: 0)
        var cameraCount = 0
        /// Mean camera position over the sightings (nil without camera poses).
        public var camera: SIMD3<Float>? { cameraCount > 0 ? cameraSum / Float(cameraCount) : nil }

        mutating func noteCamera(_ c: SIMD3<Float>?) {
            guard let c else { return }
            cameraSum += c
            cameraCount += 1
        }
    }

    /// What the detector called one object across the scan's frames: per label, its views,
    /// sightings and confidence, plus how often the label changed between consecutive sightings.
    /// A real object mostly keeps one label; phantoms (a window, a wall, plastic sheeting) flip
    /// between several, so the recheck uses this as a second opinion (`ObjectRecheck.check(..., history:)`).
    /// Stored with the scan (`RoomGeometry.Object.measured`).
    public struct LabelHistory: Codable, Sendable, Equatable {
        public struct Entry: Codable, Sendable, Equatable {
            public var views: Int
            public var sightings: Int
            public var totalConfidence: Float
            public var bestConfidence: Float

            public init(views: Int, sightings: Int, totalConfidence: Float, bestConfidence: Float) {
                self.views = views
                self.sightings = sightings
                self.totalConfidence = totalConfidence
                self.bestConfidence = bestConfidence
            }
        }

        /// Moove category (the detector's, after `ObjectVocabulary`) → its evidence.
        public var labels: [String: Entry]
        /// Label changes between consecutive sightings, in the order they were seen.
        public var flips: Int

        public init(labels: [String: Entry] = [:], flips: Int = 0) {
            self.labels = labels
            self.flips = flips
        }

        /// Distinct views over every label.
        public var views: Int { labels.values.map(\.views).reduce(0, +) }
        public var sightings: Int { labels.values.map(\.sightings).reduce(0, +) }
        /// How many different labels the detector gave.
        public var distinct: Int { labels.count }
        /// The label with the most views (then the most total confidence, then by name).
        public var top: String? {
            labels.max { a, b in
                (a.value.views, a.value.totalConfidence, b.key) < (b.value.views, b.value.totalConfidence, a.key)
            }?.key
        }
        /// Share of the views that carry `top` (1 when the detector never changed its mind).
        public var consensus: Double {
            guard let top, let e = labels[top], views > 0 else { return 1 }
            return Double(e.views) / Double(views)
        }

        /// Adds `other`'s labels (not its flips: those need the merged sighting order).
        mutating func absorb(_ other: LabelHistory) {
            for (label, e) in other.labels {
                if var mine = labels[label] {
                    mine.views += e.views
                    mine.sightings += e.sightings
                    mine.totalConfidence += e.totalConfidence
                    mine.bestConfidence = max(mine.bestConfidence, e.bestConfidence)
                    labels[label] = mine
                } else {
                    labels[label] = e
                }
            }
        }

        static func flips(in log: [(order: Int, label: String)]) -> Int {
            let sorted = log.sorted { $0.order < $1.order }
            return zip(sorted, sorted.dropFirst()).filter { $0.label != $1.label }.count
        }
    }

    public private(set) var tracks: [Track] = []
    /// Sightings added so far (orders the label log across tracks).
    private var sightingCount = 0
    public var floorY: Float?
    /// Caps memory: keep an even sample of at most this many points per object.
    public var maxPointsPerTrack = 4000
    /// A single view counts when the detector was at least this sure...
    /// (0.6, then 0.7 let false positives in from one glance; #267 raised it.)
    public var singleSightingConfidence: Float = 0.85
    /// ...and the object's longest side is at least this long (m). Small one-offs are
    /// mostly misfires.
    public var singleSightingMinSize: Float = 0.5
    /// Big things RoomPlan never finds (scooters, bikes) are often seen only briefly
    /// from one side, so for them one view at this confidence is enough...
    public var bigSingleSightingConfidence: Float = 0.7
    /// ...when the longest side is at least this long (m).
    public var bigSingleSightingMinSize: Float = 1.0
    /// Two sightings are separate views when their frames are this far apart in time (s)...
    public var minViewGap: Double = 0.3
    /// ...or seen from directions this far apart (radians, about the object's center).
    public var minViewAngle: Float = 15 * .pi / 180

    public init(floorY: Float? = nil) { self.floorY = floorY }

    /// Adds a sighting and returns the id of the track it joined or started (nil if
    /// there were too few points to fit).
    @discardableResult
    public mutating func add(_ s: Sighting) -> Int? {
        guard let box = BoxFit.fit(s.points, floorY: floorY) else { return nil }
        sightingCount += 1
        // Compare centers after padding each box away from its camera: one view is only
        // the object's near face, so views from two sides would otherwise sit too far apart.
        let minDepth = ObjectVocabulary.minimumDepth[s.label] ?? 0
        let probe = DetectorPlacement.padDepth(box, to: minDepth, camera: s.camera).center
        let match = tracks.indices
            .filter { tracks[$0].label == s.label }
            .map { ($0, horizontalDistance(DetectorPlacement.padDepth(tracks[$0].box, to: minDepth, camera: tracks[$0].camera).center, probe)) }
            .filter { $0.1 < max(0.6, max(tracks[$0.0].box.size.x, box.size.x) * 0.6) }
            .min { $0.1 < $1.1 }
        if let (i, _) = match {
            var t = tracks[i]
            t.sightings += 1
            let newView = isNewView(s, after: t.lastView, center: t.box.center)
            if newView {
                t.views += 1
                t.lastView = (s.time, s.camera)
            }
            t.labelHistory.absorb(LabelHistory(labels: [s.label: .init(views: newView ? 1 : 0, sightings: 1,
                                                                       totalConfidence: s.confidence, bestConfidence: s.confidence)]))
            t.labelLog.append((sightingCount, s.label))
            t.noteCamera(s.camera)
            t.bestConfidence = max(t.bestConfidence, s.confidence)
            t.totalConfidence += s.confidence
            t.points = Self.thin(t.points + s.points, to: maxPointsPerTrack)
            t.box = BoxFit.fit(t.points, floorY: floorY) ?? t.box
            tracks[i] = t
            return t.id
        }
        let id = tracks.count
        var track = Track(id: id, label: s.label, sightings: 1, views: 1, bestConfidence: s.confidence, totalConfidence: s.confidence,
                          points: Self.thin(s.points, to: maxPointsPerTrack), box: box,
                          labelHistory: LabelHistory(labels: [s.label: .init(views: 1, sightings: 1, totalConfidence: s.confidence, bestConfidence: s.confidence)]),
                          labelLog: [(sightingCount, s.label)], lastView: (s.time, s.camera))
        track.noteCamera(s.camera)
        tracks.append(track)
        return id
    }

    /// Whether `s` is a different view from `last`: far enough apart in time or angle.
    /// Without timestamps or camera poses every sighting counts as its own view.
    func isNewView(_ s: Sighting, after last: (time: Double?, camera: SIMD3<Float>?), center: SIMD3<Float>) -> Bool {
        var known = false
        if let t0 = last.time, let t1 = s.time {
            known = true
            if abs(t1 - t0) >= minViewGap { return true }
        }
        if let c0 = last.camera, let c1 = s.camera {
            known = true
            let a = SIMD2(c0.x - center.x, c0.z - center.z), b = SIMD2(c1.x - center.x, c1.z - center.z)
            let la = (a * a).sum().squareRoot(), lb = (b * b).sum().squareRoot()
            if la > 1e-3, lb > 1e-3 {
                let cosine = min(1, max(-1, (a * b).sum() / (la * lb)))
                if acos(cosine) >= minViewAngle { return true }
            }
        }
        return !known
    }

    /// Whether a track has enough evidence to report.
    public func isConfirmed(_ t: Track, minSightings: Int = 2) -> Bool {
        let longest = max(t.box.size.x, t.box.size.y, t.box.size.z)
        if t.views >= minSightings { return true }
        if t.bestConfidence >= singleSightingConfidence && longest >= singleSightingMinSize { return true }
        return !ObjectVocabulary.isRoomPlanCategory(t.label)
            && t.bestConfidence >= bigSingleSightingConfidence && longest >= bigSingleSightingMinSize
    }

    /// The objects found: confirmed tracks, one label per physical object, minus what
    /// RoomPlan already found (`existing`).
    /// - Refits every object with the current `floorY` (known once RoomPlan finishes);
    ///   pass `refit: false` for a cheap live preview.
    /// - When two labels claim the same space (an e-scooter that also scores as a
    ///   bicycle), the label with more total confidence, weighted by how plausible the
    ///   measured size is for it, wins.
    /// - A detection is a duplicate of a RoomPlan object (any category: an "ottoman"
    ///   RoomPlan calls a table) when their footprints overlap by at least
    ///   `duplicateFootprintOverlap` of the smaller footprint and they share height.
    ///   The detection is first padded to its category's minimum depth away from the
    ///   camera (`DetectorPlacement.padDepth`), since LiDAR only saw its front.
    ///   Objects merely standing on a RoomPlan object (a monitor on a table) are kept.
    /// - Every object's `labelHistory` keeps the labels of the tracks merged into it, and of
    ///   unconfirmed tracks under another label overlapping it by > 0.5 (a "ladder" glimpsed once
    ///   on the "vacuum"); `views` and `sightings` still count only the confirmed ones.
    public func results(minSightings: Int = 2, excluding existing: [RoomGeometry.Object] = [], refit: Bool = true) -> [Track] {
        let all = tracks.map { t -> Track in
            var t = t
            if refit { t.box = BoxFit.fit(t.points, floorY: floorY) ?? t.box }
            return t
        }
        var kept = all.filter { isConfirmed($0, minSightings: minSightings) }
        // Strongest first, so each object keeps its best label.
        func weight(_ t: Track) -> Float { t.totalConfidence * ObjectVocabulary.plausibility(of: t.label, size: t.box.size) }
        kept.sort { weight($0) > weight($1) }
        var resolved: [Track] = []
        func sameSpace(_ t: Track) -> Int? {
            resolved.firstIndex { $0.label != t.label && Self.overlap(t.box, $0.box) > 0.5 }
        }
        for t in kept {
            if let i = sameSpace(t) {
                resolved[i].sightings += t.sightings  // the same object under another label
                resolved[i].views += t.views
                resolved[i].labelHistory.absorb(t.labelHistory)
                resolved[i].labelLog += t.labelLog
                continue
            }
            resolved.append(t)
        }
        for t in all where !isConfirmed(t, minSightings: minSightings) {
            guard let i = sameSpace(t) else { continue }
            resolved[i].labelHistory.absorb(t.labelHistory)
            resolved[i].labelLog += t.labelLog
        }
        for i in resolved.indices {
            resolved[i].labelHistory.flips = LabelHistory.flips(in: resolved[i].labelLog)
        }
        return resolved.filter { t in
            let box = DetectorPlacement.padDepth(t.box, to: ObjectVocabulary.minimumDepth[t.label] ?? 0, camera: t.camera)
            return !existing.contains { o in
                let roomPlan = FittedBox(center: o.transform.position, size: o.dimensions, yaw: o.transform.yaw)
                return Self.isDuplicate(box, of: roomPlan) || (o.category == "bathtub" && Self.standsOverTub(t.box, roomPlan))
            }
        }
    }

    /// Something standing in or over a bathtub is part of the shower (a curtain the detector
    /// calls a "room divider" became a 1.4 m bookshelf in Rio's room), not something you'd move.
    static func standsOverTub(_ a: FittedBox, _ tub: FittedBox) -> Bool {
        let tubTop = tub.center.y + tub.size.y / 2
        return a.center.y - a.size.y / 2 >= tubTop - 0.15 && footprintOverlap(a, tub) >= duplicateFootprintOverlap
    }

    /// Share of the smaller footprint two boxes must cover for a detection to count as a
    /// RoomPlan object's duplicate (#267: 0.5 of the detection's volume let an ottoman
    /// through next to RoomPlan's box for it).
    public static let duplicateFootprintOverlap: Float = 0.25
    /// ...and the share of the shorter box's height they must share (so a monitor
    /// standing on a desk isn't the desk).
    public static let duplicateHeightOverlap: Float = 0.3

    static func isDuplicate(_ a: FittedBox, of b: FittedBox) -> Bool {
        let lo = max(a.center.y - a.size.y / 2, b.center.y - b.size.y / 2)
        let hi = min(a.center.y + a.size.y / 2, b.center.y + b.size.y / 2)
        guard hi - lo >= duplicateHeightOverlap * min(a.size.y, b.size.y) else { return false }
        return footprintOverlap(a, b) >= duplicateFootprintOverlap
    }

    /// Shared footprint area of two upright boxes (exact, rotated rectangles), as a
    /// share of the smaller footprint.
    static func footprintOverlap(_ a: FittedBox, _ b: FittedBox) -> Float {
        func poly(_ box: FittedBox) -> [SIMD2<Float>] {
            let p = RoomGeometry.footprint(width: box.size.x, depth: box.size.z, box.transform)
            return signedArea(p) < 0 ? p.reversed() : p
        }
        let pa = poly(a), pb = poly(b)
        let smaller = min(abs(signedArea(pa)), abs(signedArea(pb)))
        guard smaller > 1e-6 else { return 0 }
        return abs(signedArea(clip(pa, by: pb))) / smaller
    }

    static func signedArea(_ p: [SIMD2<Float>]) -> Float {
        guard p.count >= 3 else { return 0 }
        var s: Float = 0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    /// Sutherland-Hodgman: `subject` clipped to the convex, counter-clockwise `clip`.
    static func clip(_ subject: [SIMD2<Float>], by clip: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var out = subject
        for i in clip.indices where !out.isEmpty {
            let a = clip[i], e = clip[(i + 1) % clip.count] - a
            func side(_ p: SIMD2<Float>) -> Float { e.x * (p.y - a.y) - e.y * (p.x - a.x) }
            let input = out
            out = []
            for j in input.indices {
                let p = input[j], q = input[(j + 1) % input.count]
                let sp = side(p), sq = side(q)
                if sp >= 0 { out.append(p) }
                if (sp >= 0) != (sq >= 0) { out.append(p + (q - p) * (sp / (sp - sq))) }
            }
        }
        return out
    }

    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = SIMD2(a.x - b.x, a.z - b.z)
        return (d * d).sum().squareRoot()
    }

    /// Shared volume of two upright boxes, as a share of the smaller one's volume. Footprints are approximated by their axis-aligned bounds.
    static func overlap(_ a: FittedBox, _ b: FittedBox) -> Float {
        func bounds(_ box: FittedBox) -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
            let pts = RoomGeometry.footprint(width: box.size.x, depth: box.size.z, box.transform)
            let lo = pts.reduce(pts[0]) { pointwiseMin($0, $1) }, hi = pts.reduce(pts[0]) { pointwiseMax($0, $1) }
            return (SIMD3(lo.x, box.center.y - box.size.y / 2, lo.y), SIMD3(hi.x, box.center.y + box.size.y / 2, hi.y))
        }
        let (alo, ahi) = bounds(a), (blo, bhi) = bounds(b)
        let d = pointwiseMax(pointwiseMin(ahi, bhi) - pointwiseMax(alo, blo), SIMD3(repeating: 0))
        let inter = d.x * d.y * d.z
        let ea = ahi - alo, eb = bhi - blo
        let va = ea.x * ea.y * ea.z, vb = eb.x * eb.y * eb.z
        let base = min(va, vb)
        return base > 0 ? inter / base : 0
    }

    static func thin(_ points: [SIMD3<Float>], to max: Int) -> [SIMD3<Float>] {
        guard points.count > max else { return points }
        let stride = Double(points.count) / Double(max)
        return (0..<max).map { points[Int(Double($0) * stride)] }
    }
}
