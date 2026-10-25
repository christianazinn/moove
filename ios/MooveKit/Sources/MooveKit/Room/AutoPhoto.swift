import Foundation

/// Auto photos (#82): during the scan the app keeps a keyframe now and then (a JPEG plus
/// the camera pose and a small depth grid). Afterwards every object's 3D box, from
/// RoomPlan or the extra detector, is projected into each keyframe, and the best-framed
/// crop (big, unclipped, unoccluded, sharp, centered) becomes the object's photo.
/// This file is the pure part: projection, scoring and picking.

/// A camera at one moment: ARKit's camera-to-world transform and pinhole intrinsics,
/// for the back camera's landscape sensor image (`imageWidth` × `imageHeight` px).
public struct CameraPose: Sendable, Equatable {
    /// Camera-to-world, as 4 columns (x right, y up, looking down -z in camera space).
    public var columns: [SIMD4<Float>]
    public var fx, fy, cx, cy: Float
    public var imageWidth, imageHeight: Float

    public init(columns: [SIMD4<Float>], fx: Float, fy: Float, cx: Float, cy: Float, imageWidth: Float, imageHeight: Float) {
        precondition(columns.count == 4)
        self.columns = columns
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var position: SIMD3<Float> { SIMD3(columns[3].x, columns[3].y, columns[3].z) }
    /// Viewing direction in world space (camera -z).
    public var forward: SIMD3<Float> { -SIMD3(columns[2].x, columns[2].y, columns[2].z) }

    /// World point → camera space (inverse of a rigid transform: transpose the rotation).
    func toCamera(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let d = p - position
        func axis(_ i: Int) -> SIMD3<Float> { SIMD3(columns[i].x, columns[i].y, columns[i].z) }
        return SIMD3((d * axis(0)).sum(), (d * axis(1)).sum(), (d * axis(2)).sum())
    }

    /// Where a world point lands in the **upright** (portrait) image, normalized with a
    /// top-left origin, and its depth in front of the camera (m). Nil when behind it.
    /// Upright = the sensor image rotated 90° clockwise (a portrait phone), the same
    /// convention as the detector's `.right` orientation.
    public func project(_ p: SIMD3<Float>) -> (point: SIMD2<Float>, depth: Float)? {
        let c = toCamera(p)
        let depth = -c.z
        guard depth > 0.05 else { return nil }
        let u = fx * c.x / depth + cx, v = cy - fy * c.y / depth  // sensor pixels, top-left origin
        return (Self.upright(sensor: SIMD2(u / imageWidth, v / imageHeight)), depth)
    }

    /// Normalized sensor (landscape) point → normalized upright (portrait) point, both top-left origin.
    public static func upright(sensor s: SIMD2<Float>) -> SIMD2<Float> { SIMD2(1 - s.y, s.x) }
    /// Inverse of `upright(sensor:)`.
    public static func sensor(upright u: SIMD2<Float>) -> SIMD2<Float> { SIMD2(u.y, 1 - u.x) }
}

/// Low-resolution LiDAR depth (m) in the sensor's landscape orientation, row-major.
public struct DepthGrid: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        precondition(values.count == width * height)
        self.width = width
        self.height = height
        self.values = values
    }

    /// Depth at a normalized sensor point, or nil if unknown (0, NaN or out of range).
    public func depth(atSensor p: SIMD2<Float>) -> Float? {
        let x = Int(p.x * Float(width)), y = Int(p.y * Float(height))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let d = values[y * width + x]
        return d.isFinite && d > 0 ? d : nil
    }
}

public struct Keyframe: Sendable {
    public var id: Int
    public var pose: CameraPose
    /// `Sharpness.score` of the frame; only compared between keyframes of one scan.
    public var sharpness: Float
    public var depth: DepthGrid?

    public init(id: Int, pose: CameraPose, sharpness: Float, depth: DepthGrid?) {
        self.id = id
        self.pose = pose
        self.sharpness = sharpness
        self.depth = depth
    }
}

public enum Sharpness {
    /// Variance of the Laplacian of a grayscale image (row-major luma). Higher = sharper;
    /// motion blur and defocus flatten edges and bring it down.
    public static func score(luma: [UInt8], width: Int, height: Int) -> Float {
        guard width >= 3, height >= 3, luma.count >= width * height else { return 0 }
        var sum: Double = 0, sumSq: Double = 0, n: Double = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let i = y * width + x
                let l = 4 * Int(luma[i]) - Int(luma[i - 1]) - Int(luma[i + 1]) - Int(luma[i - width]) - Int(luma[i + width])
                sum += Double(l)
                sumSq += Double(l * l)
                n += 1
            }
        }
        let mean = sum / n
        return Float(sumSq / n - mean * mean)
    }
}

/// Decides which frames to keep as keyframes: enough camera movement since the last
/// one (a new view), and not moving so fast that the frame is blurred.
public struct KeyframeGate: Sendable {
    public var minMove: Float = 0.25           // m
    public var minTurn: Float = 12 * .pi / 180  // rad
    public var maxTurnSpeed: Float = 80 * .pi / 180  // rad/s
    public var maxKeyframes = 160
    public private(set) var kept: [CameraPose] = []
    private var previous: (pose: CameraPose, time: Double)?

    public init() {}

    /// Call for each candidate frame (time in seconds). Returns true when it should be
    /// stored; it's then remembered as the last keyframe.
    public mutating func offer(_ pose: CameraPose, time: Double) -> Bool {
        defer { previous = (pose, time) }
        guard kept.count < maxKeyframes else { return false }
        if let (p, t) = previous, time > t {
            let speed = Self.angle(p.forward, pose.forward) / Float(time - t)
            if speed > maxTurnSpeed { return false }
        }
        if let last = kept.last {
            let moved = simdLength(pose.position - last.position)
            let turned = Self.angle(pose.forward, last.forward)
            guard moved >= minMove || turned >= minTurn else { return false }
        }
        kept.append(pose)
        return true
    }

    static func angle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let c = (a * b).sum() / max(simdLength(a) * simdLength(b), 1e-6)
        return acos(min(max(c, -1), 1))
    }
}

func simdLength(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }

/// How an object looks in one keyframe.
public struct CropCandidate: Sendable, Equatable {
    public var keyframeID: Int
    /// The object's projected bounds, clipped to the image (upright, normalized, top-left origin).
    public var rect: NormRect
    /// Share of the projected bounds inside the image (1 = not cut off).
    public var visible: Float
    /// Share of depth samples inside the object where something nearer is in the way.
    public var occluded: Float
    /// Distance from the camera to the object's nearest corner (m).
    public var distance: Float
    public var sharpness: Float
}

public enum CropPicker {
    /// Projects an upright box (`size` = width, height, depth; centered `transform`) into a keyframe.
    public static func candidate(size: SIMD3<Float>, transform: RoomTransform, in frame: Keyframe) -> CropCandidate? {
        var pts: [SIMD2<Float>] = []
        var nearest = Float.infinity
        for corner in RoomGeometry.corners(of: size, transform) {
            // A corner behind the camera means it's inside or right up against the object.
            guard let (p, d) = frame.pose.project(corner) else { return nil }
            pts.append(p)
            nearest = min(nearest, d)
        }
        let lo = pts.reduce(pts[0]) { pointwiseMin($0, $1) }, hi = pts.reduce(pts[0]) { pointwiseMax($0, $1) }
        let full = NormRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)
        guard full.area > 0 else { return nil }
        let rect = full.clipped
        let visible = rect.area / full.area
        guard visible > 0 else { return nil }

        // Occlusion: sample depth across the middle of the box. LiDAR seeing something
        // clearly nearer than the box's nearest corner means another thing is in front.
        var occluded: Float = 0
        if let depth = frame.depth {
            var hits = 0, total = 0
            let inner = NormRect(x: rect.x + rect.width * 0.15, y: rect.y + rect.height * 0.15, width: rect.width * 0.7, height: rect.height * 0.7)
            for i in 0..<5 {
                for j in 0..<5 {
                    let u = SIMD2(inner.x + inner.width * (Float(i) + 0.5) / 5, inner.y + inner.height * (Float(j) + 0.5) / 5)
                    guard let d = depth.depth(atSensor: CameraPose.sensor(upright: u)) else { continue }
                    total += 1
                    if d < nearest - 0.2 { hits += 1 }
                }
            }
            occluded = total > 0 ? Float(hits) / Float(total) : 0
        }
        return CropCandidate(keyframeID: frame.id, rect: rect, visible: visible, occluded: occluded,
                             distance: nearest, sharpness: frame.sharpness)
    }

    /// Higher is better; 0 = unusable. `typicalSharpness` is the scan's median keyframe sharpness.
    public static func score(_ c: CropCandidate, typicalSharpness: Float) -> Float {
        guard c.visible >= 0.7, c.occluded <= 0.4, c.rect.area >= 0.01, c.distance >= 0.3 else { return 0 }
        return quality(c, typicalSharpness: typicalSharpness)
    }

    /// `score` without its hard gates.
    static func quality(_ c: CropCandidate, typicalSharpness: Float) -> Float {
        let size = min(c.rect.area / 0.2, 1)  // filling a fifth of the frame or more is plenty
        let clip = c.visible * c.visible * c.visible
        let clear = (1 - c.occluded) * (1 - c.occluded)
        let sharp = typicalSharpness > 0 ? min(max(c.sharpness / typicalSharpness, 0.25), 1.25) : 1
        let off = simdLength(SIMD3(c.rect.center.x - 0.5, c.rect.center.y - 0.5, 0))
        let centered = 1 - 0.5 * off
        return size * clip * clear * sharp * centered
    }

    /// The best view of a box across the keyframes, or nil if none shows it well.
    public static func best(size: SIMD3<Float>, transform: RoomTransform, in frames: [Keyframe]) -> CropCandidate? {
        top(size: size, transform: transform, in: frames, count: 1, relaxed: false).first
    }

    /// Looser gates for extra classifier views when fewer than wanted pass `score`'s.
    static func passesRelaxed(_ c: CropCandidate) -> Bool {
        c.visible >= 0.4 && c.occluded <= 0.7 && c.rect.area >= 0.003 && c.distance >= 0.3
    }

    /// The `count` best views of a box (best first, one per keyframe), e.g. extra crops for
    /// the object classifier. With `relaxed`, views that only pass `passesRelaxed` fill up
    /// the list (after every strict one) when too few pass the strict gates.
    public static func top(size: SIMD3<Float>, transform: RoomTransform, in frames: [Keyframe], count: Int, relaxed: Bool = true) -> [CropCandidate] {
        let sharp = frames.map(\.sharpness).sorted()
        let typical = sharp.isEmpty ? 0 : sharp[sharp.count / 2]
        let all = frames.compactMap { candidate(size: size, transform: transform, in: $0) }
        let strict = all.map { ($0, score($0, typicalSharpness: typical)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        guard relaxed, strict.count < count else { return Array(strict.prefix(count)) }
        // Rank the rest by the same score with the gates opened up.
        let taken = Set(strict.map(\.keyframeID))
        let loose = all.filter { !taken.contains($0.keyframeID) && passesRelaxed($0) }
            .map { ($0, quality($0, typicalSharpness: typical)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        return Array((strict + loose).prefix(count))
    }

    /// The region to cut out: the object plus a margin of context, at least
    /// `minSide` of the frame on each side, kept inside the image.
    public static func cropRect(_ c: CropCandidate, margin: Float = 0.12, minSide: Float = 0.2) -> NormRect {
        let w = min(max(c.rect.width * (1 + 2 * margin), minSide), 1)
        let h = min(max(c.rect.height * (1 + 2 * margin), minSide), 1)
        let x = min(max(c.rect.center.x - w / 2, 0), 1 - w)
        let y = min(max(c.rect.center.y - h / 2, 0), 1 - h)
        return NormRect(x: x, y: y, width: w, height: h)
    }
}
