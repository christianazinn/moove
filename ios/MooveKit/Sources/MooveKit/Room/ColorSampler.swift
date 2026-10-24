import Foundation

// Real colors from the scan's camera frames (#76). The app keeps ~40 keyframes during
// RoomPlan capture (JPEG + camera pose + intrinsics); this file projects points on the
// scanned walls, floor and object boxes into those frames and reads the pixels there.
// Pure math on plain buffers, so it runs and is tested on Linux.
//
// Camera convention (ARKit `ARCamera`): `transform` is camera → world. In camera space x
// points right along the image's long side, y up, and the camera looks down −z. The
// intrinsics (fx, fy, cx, cy) are in pixels of the stored image, origin top-left, so a
// camera-space point (x, y, z) lands at u = fx·x/(−z) + cx, v = fy·(−y)/(−z) + cy.
// The image is kept in the sensor's native (landscape) orientation; never rotate it.
//
// World space is the ARSession's, which RoomPlan's `CapturedRoom` (and so `RoomGeometry`,
// before `centered()`) shares. That is Apple's documented behavior for RoomCaptureSession
// running on its own ARSession, but check it on a device: a wrong frame shows up as wall
// colors that look like furniture.

/// An 8-bit RGB image, rows top to bottom. The app decodes frames into this; tests draw into it.
public struct RGBImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// width × height × 3 bytes, R G B.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3, "RGBImage needs width × height × 3 bytes")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// From RGBA (or RGBX) bytes, dropping alpha. `bytesPerRow` defaults to width × 4.
    public init(width: Int, height: Int, rgba: [UInt8], bytesPerRow: Int? = nil) {
        let stride = bytesPerRow ?? width * 4
        var out = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let s = y * stride + x * 4, d = (y * width + x) * 3
                out[d] = rgba[s]
                out[d + 1] = rgba[s + 1]
                out[d + 2] = rgba[s + 2]
            }
        }
        self.init(width: width, height: height, pixels: out)
    }

    /// Mean color (0...1 sRGB) of the (2r+1)² patch around (x, y), or nil if it leaves the image.
    func patchMean(x: Int, y: Int, radius r: Int) -> SIMD3<Double>? {
        guard x - r >= 0, y - r >= 0, x + r < width, y + r < height else { return nil }
        var sum = SIMD3<Double>(0, 0, 0)
        for py in (y - r)...(y + r) {
            for px in (x - r)...(x + r) {
                let i = (py * width + px) * 3
                sum += SIMD3(Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
            }
        }
        let n = Double((2 * r + 1) * (2 * r + 1))
        return sum / (n * 255)
    }
}

/// Where a frame was taken from and how it maps to pixels (ARKit pinhole model).
public struct ScanCamera: Codable, Sendable, Equatable {
    /// Camera → world (ARKit `ARCamera.transform`).
    public var transform: RoomTransform
    /// Pixel focal lengths and principal point, for an image `width` × `height`.
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var width: Int
    public var height: Int

    public init(transform: RoomTransform, fx: Double, fy: Double, cx: Double, cy: Double, width: Int, height: Int) {
        self.transform = transform
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
    }

    /// The same camera for the image resized to `width` × `height` (intrinsics scaled per axis).
    public func scaled(toWidth w: Int, height h: Int) -> ScanCamera {
        let sx = Double(w) / Double(max(width, 1)), sy = Double(h) / Double(max(height, 1))
        return ScanCamera(transform: transform, fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy, width: w, height: h)
    }

    public var position: SIMD3<Double> { v3(transform.position) }
    /// The viewing direction (camera −z) in world space.
    public var forward: SIMD3<Double> { let z = transform.columns[2]; return -SIMD3(Double(z.x), Double(z.y), Double(z.z)) }

    /// World point → camera space (x right, y up, looking down −z).
    func toCamera(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let c = transform.columns
        let d = p - position
        // Inverse of a rigid transform: Rᵀ (p − t). Columns of R are the camera axes.
        return SIMD3(vdot(v3(c[0]), d), vdot(v3(c[1]), d), vdot(v3(c[2]), d))
    }

    /// Pixel (u, v) and depth in front of the camera, or nil when behind it, nearer than
    /// `minDepth`, or outside the image.
    public func project(_ world: SIMD3<Double>, minDepth: Double = 0.1) -> (u: Double, v: Double, depth: Double)? {
        let p = toCamera(world)
        let depth = -p.z
        guard depth > minDepth else { return nil }
        let u = fx * p.x / depth + cx, v = fy * -p.y / depth + cy
        guard u >= 0, v >= 0, u < Double(width), v < Double(height) else { return nil }
        return (u, v, depth)
    }

    /// Keyframe rule: keep a frame when the camera moved more than `moveM` or turned more
    /// than `turnDeg` since the last kept one (or there is none yet).
    public func isNewView(since last: ScanCamera?, moveM: Double = 0.5, turnDeg: Double = 25) -> Bool {
        guard let last else { return true }
        if vlen(position - last.position) > moveM { return true }
        let c = min(1, max(-1, vdot(forward, last.forward)))
        return acos(c) * 180 / .pi > turnDeg
    }
}

/// One keyframe ready for sampling.
public struct ScanFrame: Sendable {
    public var camera: ScanCamera
    public var image: RGBImage

    /// `camera` may describe a different resolution than `image` (e.g. intrinsics for the
    /// stored 640 px JPEG, decoded smaller); it is rescaled to the image.
    public init(camera: ScanCamera, image: RGBImage) {
        self.camera = camera.width == image.width && camera.height == image.height
            ? camera : camera.scaled(toWidth: image.width, height: image.height)
        self.image = image
    }
}

/// Colors measured from a scan's photos. Any of them can be missing (nothing seen well enough).
public struct ScanColors: Codable, Sendable, Equatable {
    public struct ObjectColor: Codable, Sendable, Hashable {
        /// The larger color cluster on the object's top and visible sides.
        public var primary: VoxelColor
        /// A clearly different second cluster (legs, cushions, a frame), if there is one.
        public var secondary: VoxelColor?

        public init(primary: VoxelColor, secondary: VoxelColor? = nil) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    public var wallColor: VoxelColor?
    public var floorColor: VoxelColor?
    /// Keyed by `RoomGeometry.Object.id` (= `Item.scanObjectId`).
    public var objectColors: [String: ObjectColor]

    public init(wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil, objectColors: [String: ObjectColor] = [:]) {
        self.wallColor = wallColor
        self.floorColor = floorColor
        self.objectColors = objectColors
    }

    public static let empty = ScanColors()

    public var isEmpty: Bool { wallColor == nil && floorColor == nil && objectColors.isEmpty }

    /// The colors for an item, matched by its scan object id.
    public func colors(for item: Item) -> ObjectColor? {
        item.scanObjectId.flatMap { objectColors[$0] }
    }
}

public enum ColorSampler {
    /// Minimum samples before a color is trusted.
    static let minWallSamples = 6
    static let minFloorSamples = 6
    static let minObjectSamples = 6
    /// A surface must face the camera at least this much (|n · toCamera|).
    static let minFacing = 0.3

    /// Samples wall, floor and object colors from `frames`. `geometry` must be in the
    /// frames' world space (the raw scan, not `centered()`).
    public static func sample(_ geometry: RoomGeometry, frames: [ScanFrame]) -> ScanColors {
        guard !frames.isEmpty else { return .empty }
        let objectBoxes = geometry.objects.map { Box(id: $0.id, dimensions: $0.dimensions, transform: $0.transform) }
        let wallBoxes = geometry.walls.map {
            Box(id: $0.id, dimensions: SIMD3($0.dimensions.x, $0.dimensions.y, max($0.dimensions.z, 0.05)), transform: $0.transform)
        }
        let occluders = objectBoxes + wallBoxes

        // Walls: the upper middle band of each wall, where furniture rarely is, minus doors and windows.
        var wallSamples: [SIMD3<Double>] = []
        for wall in geometry.walls {
            let points = wallPoints(wall, openings: geometry.openings)
            wallSamples += collect(points, frames: frames, occluders: occluders, skipping: wall.id)
        }
        let wall = wallSamples.count >= minWallSamples ? percentileBandMean(wallSamples, from: 0.75, to: 0.90) : nil

        // Floor: a grid over the floor outline; furniture boxes hide what's under them.
        let floorSamples = collect(floorPoints(geometry), frames: frames, occluders: occluders, skipping: nil)
        let floor = floorSamples.count >= minFloorSamples ? percentileBandMean(floorSamples, from: 0.25, to: 0.75) : nil

        // Objects: grid on the top face and the four sides, culled by facing per frame.
        var objects: [String: ScanColors.ObjectColor] = [:]
        let background = [wall, floor].compactMap { $0 }.map(OKLab.init(srgb:))
        for box in objectBoxes {
            var samples = collect(box.facePoints(), frames: frames, occluders: occluders, skipping: box.id)
            guard samples.count >= minObjectSamples else { continue }
            // A box is bigger than the thing in it (a chair's box is mostly air), so pixels that
            // match the wall or floor are probably background. Drop them unless that's most of it.
            let labs = samples.map(OKLab.init(srgb:))
            let foreground = samples.indices.filter { i in !background.contains { $0.distance(to: labs[i]) < 0.04 } }
            if foreground.count >= max(minObjectSamples, samples.count * 2 / 5) { samples = foreground.map { samples[$0] } }
            let (primary, secondary) = dominantColors(samples)
            objects[box.id] = ScanColors.ObjectColor(primary: pack(primary), secondary: secondary.map(pack))
        }
        return ScanColors(wallColor: wall.map(pack), floorColor: floor.map(pack), objectColors: objects)
    }

    // MARK: Sample points

    struct SamplePoint {
        var position: SIMD3<Double>
        /// Unit normal for the facing test; nil = facing doesn't matter.
        var normal: SIMD3<Double>?
        /// True for two-sided surfaces (walls): |n · v| is tested instead of n · v.
        var twoSided = false
    }

    static func wallPoints(_ wall: RoomGeometry.Surface, openings: [RoomGeometry.Surface]) -> [SamplePoint] {
        let w = Double(wall.dimensions.x), h = Double(wall.dimensions.y)
        guard w > 0.2, h > 0.5 else { return [] }
        let normal = vnorm(v3(wall.transform.columns[2]))
        let columns = max(3, Int((w * 0.7 / 0.25).rounded()))
        var out: [SamplePoint] = []
        for i in 0..<columns {
            let fx = 0.15 + 0.7 * (Double(i) + 0.5) / Double(columns)
            for fy in [0.62, 0.72, 0.82] {
                let local = SIMD3<Float>(Float((fx - 0.5) * w), Float((fy - 0.5) * h), 0)
                let p = v3(wall.transform.apply(local))
                if openings.contains(where: { inside(p, $0) }) { continue }
                out.append(SamplePoint(position: p, normal: normal, twoSided: true))
            }
        }
        return out
    }

    /// True when `p` is within an opening's rectangle (5 cm margin, 30 cm either side of its plane).
    static func inside(_ p: SIMD3<Double>, _ opening: RoomGeometry.Surface) -> Bool {
        let local = Box.toLocal(p, opening.transform)
        return abs(local.x) < Double(opening.dimensions.x) / 2 + 0.05
            && abs(local.y) < Double(opening.dimensions.y) / 2 + 0.05
            && abs(local.z) < 0.3
    }

    static func floorPoints(_ g: RoomGeometry, spacing: Double = 0.3) -> [SamplePoint] {
        let y = Double(g.floorY)
        var out: [SamplePoint] = []
        for outline in g.floorOutlines where outline.count >= 3 {
            let poly = outline.map { SIMD2(Double($0.x), Double($0.y)) }
            let xs = poly.map(\.x), zs = poly.map(\.y)
            guard let x0 = xs.min(), let x1 = xs.max(), let z0 = zs.min(), let z1 = zs.max() else { continue }
            var x = x0 + spacing / 2
            while x < x1 {
                var z = z0 + spacing / 2
                while z < z1 {
                    if contains(poly, SIMD2(x, z)) { out.append(SamplePoint(position: SIMD3(x, y, z), normal: SIMD3(0, 1, 0))) }
                    z += spacing
                }
                x += spacing
            }
        }
        return out
    }

    static func contains(_ poly: [SIMD2<Double>], _ p: SIMD2<Double>) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Patch means at every point in every frame where it is in view, facing the camera
    /// and not hidden behind an occluder (except the box with id `skipping`, the surface itself).
    static func collect(_ points: [SamplePoint], frames: [ScanFrame], occluders: [Box], skipping: String?) -> [SIMD3<Double>] {
        let blockers = occluders.filter { $0.id != skipping }
        var out: [SIMD3<Double>] = []
        for frame in frames {
            let eye = frame.camera.position
            let radius = max(1, Int((Double(frame.image.width) / 320).rounded()))
            for point in points {
                let toCamera = eye - point.position
                let distance = vlen(toCamera)
                guard distance > 0.1 else { continue }
                if let n = point.normal {
                    let facing = vdot(n, toCamera / distance)
                    guard (point.twoSided ? abs(facing) : facing) >= minFacing else { continue }
                }
                guard let px = frame.camera.project(point.position) else { continue }
                if blockers.contains(where: { $0.blocks(from: eye, to: point.position) }) { continue }
                if let c = frame.image.patchMean(x: Int(px.u), y: Int(px.v), radius: radius) { out.append(c) }
            }
        }
        return out
    }

    // MARK: Aggregation

    /// Rec. 709 luma of an sRGB color.
    static func luma(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    /// Mean of the samples whose luma rank falls in [from, to] (fractions). For walls the
    /// 75th–90th band keeps the lit paint and drops shadows, posters, lamps and glare; a
    /// plain median reads too dark.
    static func percentileBandMean(_ samples: [SIMD3<Double>], from lo: Double, to hi: Double) -> SIMD3<Double> {
        guard samples.count > 3 else { return samples.reduce(SIMD3(0, 0, 0), +) / Double(max(samples.count, 1)) }
        let sorted = samples.sorted { luma($0) < luma($1) }
        let n = sorted.count
        let a = min(n - 1, max(0, Int((Double(n - 1) * lo).rounded())))
        let b = min(n - 1, max(a, Int((Double(n - 1) * hi).rounded())))
        let band = sorted[a...b]
        return band.reduce(SIMD3(0, 0, 0), +) / Double(band.count)
    }

    /// k-means with k = 2 in OKLab. Returns the larger cluster's mean and, when the other
    /// cluster is both big enough (≥ 20%) and clearly different, its mean too.
    static func dominantColors(_ samples: [SIMD3<Double>]) -> (SIMD3<Double>, SIMD3<Double>?) {
        let labs = samples.map(OKLab.init(srgb:))
        guard let first = labs.first else { return (SIMD3(0.5, 0.5, 0.5), nil) }
        let mean = OKLab.mean(labs)
        // Deterministic seeds: the sample farthest from the mean, then the one farthest from it.
        var c0 = labs.max { $0.distance(to: mean) < $1.distance(to: mean) } ?? first
        var c1 = labs.max { $0.distance(to: c0) < $1.distance(to: c0) } ?? first
        guard c0.distance(to: c1) > 1e-6 else { return (first.srgb, nil) }
        var assignment = [Bool](repeating: false, count: labs.count)
        for _ in 0..<12 {
            var changed = false
            for (i, l) in labs.enumerated() {
                let one = l.distance(to: c1) < l.distance(to: c0)
                if one != assignment[i] { assignment[i] = one; changed = true }
            }
            let a = labs.indices.filter { !assignment[$0] }.map { labs[$0] }
            let b = labs.indices.filter { assignment[$0] }.map { labs[$0] }
            if !a.isEmpty { c0 = OKLab.mean(a) }
            if !b.isEmpty { c1 = OKLab.mean(b) }
            if !changed { break }
        }
        let n1 = assignment.filter { $0 }.count, n0 = labs.count - n1
        let (big, small, nSmall) = n0 >= n1 ? (c0, c1, n1) : (c1, c0, n0)
        let distinct = Double(nSmall) / Double(labs.count) >= 0.2 && big.distance(to: small) >= 0.06
        return (big.srgb, distinct ? small.srgb : nil)
    }

    /// 0...1 sRGB → 0xRRGGBB, never 0 (0 means empty in `VoxelGrid`).
    static func pack(_ c: SIMD3<Double>) -> VoxelColor {
        func byte(_ v: Double) -> VoxelColor { VoxelColor(min(255, max(0, (v * 255).rounded()))) }
        let packed = byte(c.x) << 16 | byte(c.y) << 8 | byte(c.z)
        return packed == 0 ? 0x010101 : packed
    }
}

// MARK: - Boxes

/// An oriented box (an object, or a wall slab) for occlusion tests and face sampling.
struct Box {
    var id: String
    var half: SIMD3<Double>
    var transform: RoomTransform

    init(id: String, dimensions: SIMD3<Float>, transform: RoomTransform) {
        self.id = id
        half = v3(dimensions) / 2
        self.transform = transform
    }

    /// World → box-local (inverse of a rigid transform).
    static func toLocal(_ p: SIMD3<Double>, _ t: RoomTransform) -> SIMD3<Double> {
        let c = t.columns, d = p - v3(t.position)
        return SIMD3(vdot(v3(c[0]), d), vdot(v3(c[1]), d), vdot(v3(c[2]), d))
    }

    static func directionToLocal(_ v: SIMD3<Double>, _ t: RoomTransform) -> SIMD3<Double> {
        let c = t.columns
        return SIMD3(vdot(v3(c[0]), v), vdot(v3(c[1]), v), vdot(v3(c[2]), v))
    }

    /// True when the segment from `a` to `b` passes through the box before reaching `b`
    /// (slab test in the box's frame). The last 5 cm before `b` don't count, so a point
    /// resting on or against the box isn't hidden by it.
    func blocks(from a: SIMD3<Double>, to b: SIMD3<Double>) -> Bool {
        let o = Self.toLocal(a, transform)
        let d = Self.directionToLocal(b - a, transform)
        let len = vlen(d)
        guard len > 1e-9 else { return false }
        var t0 = 0.0, t1 = 1 - min(0.5, 0.05 / len)
        for axis in 0..<3 {
            let oi = o[axis], di = d[axis], h = half[axis]
            if abs(di) < 1e-12 {
                if abs(oi) > h { return false }
            } else {
                var near = (-h - oi) / di, far = (h - oi) / di
                if near > far { swap(&near, &far) }
                t0 = max(t0, near)
                t1 = min(t1, far)
                if t0 > t1 { return false }
            }
        }
        return true
    }

    /// A 5 × 5 grid (inset 15%) on the top face and each side face, with outward normals.
    /// RoomPlan doesn't say which side is an object's front, so all four sides are offered
    /// and the per-frame facing test keeps the ones the camera actually saw.
    func facePoints(grid n: Int = 5) -> [ColorSampler.SamplePoint] {
        let c = transform.columns
        let axes = [vnorm(v3(c[0])), vnorm(v3(c[1])), vnorm(v3(c[2]))]
        let fractions = (0..<n).map { -0.7 + 1.4 * (Double($0) + 0.5) / Double(n) }  // ±70% of the half extent
        // (normal axis, sign, the two in-face axes)
        let faces: [(Int, Double, Int, Int)] = [(1, 1, 0, 2), (2, 1, 0, 1), (2, -1, 0, 1), (0, 1, 2, 1), (0, -1, 2, 1)]
        var out: [ColorSampler.SamplePoint] = []
        let center = v3(transform.position)
        for (axis, sign, u, v) in faces {
            guard half[u] > 0.01, half[v] > 0.01 else { continue }
            for fu in fractions {
                for fv in fractions {
                    let p = center + axes[axis] * (sign * half[axis]) + axes[u] * (fu * half[u]) + axes[v] * (fv * half[v])
                    out.append(ColorSampler.SamplePoint(position: p, normal: axes[axis] * sign))
                }
            }
        }
        return out
    }
}

// MARK: - OKLab (Björn Ottosson's published formulas, public domain)

struct OKLab: Equatable {
    var l: Double
    var a: Double
    var b: Double

    init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    init(srgb c: SIMD3<Double>) {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(c.x), g = linear(c.y), bl = linear(c.z)
        let lms = SIMD3(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl,
                        0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl,
                        0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        let l_ = cbrt(lms.x), m_ = cbrt(lms.y), s_ = cbrt(lms.z)
        l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    }

    var srgb: SIMD3<Double> {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let r = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let g = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bl = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func gamma(_ v: Double) -> Double {
            let x = min(1, max(0, v))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        return SIMD3(gamma(r), gamma(g), gamma(bl))
    }

    func distance(to o: OKLab) -> Double {
        let dl = l - o.l, da = a - o.a, db = b - o.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    static func mean(_ xs: [OKLab]) -> OKLab {
        let n = Double(max(xs.count, 1))
        return OKLab(l: xs.reduce(0) { $0 + $1.l } / n, a: xs.reduce(0) { $0 + $1.a } / n, b: xs.reduce(0) { $0 + $1.b } / n)
    }
}

// MARK: - Small vector helpers (no simd module on Linux)

@inline(__always) private func v3(_ v: SIMD3<Float>) -> SIMD3<Double> { SIMD3(Double(v.x), Double(v.y), Double(v.z)) }
@inline(__always) private func v3(_ v: SIMD4<Float>) -> SIMD3<Double> { SIMD3(Double(v.x), Double(v.y), Double(v.z)) }
@inline(__always) private func vdot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { (a * b).sum() }
@inline(__always) private func vlen(_ v: SIMD3<Double>) -> Double { vdot(v, v).squareRoot() }
@inline(__always) private func vnorm(_ v: SIMD3<Double>) -> SIMD3<Double> { let l = vlen(v); return l > 1e-12 ? v / l : v }
