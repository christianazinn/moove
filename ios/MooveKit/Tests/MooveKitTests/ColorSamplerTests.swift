import Foundation
import Testing
@testable import MooveKit

/// Synthetic scenes drawn by a tiny ray caster, then sampled back.
@Suite struct ColorSamplerTests {
    // MARK: Scene

    struct SceneBox {
        var center: SIMD3<Double>
        var size: SIMD3<Double>
        var color: SIMD3<UInt8>
    }

    static let blue = SIMD3<UInt8>(40, 70, 200)
    static let red = SIMD3<UInt8>(210, 30, 30)
    static let grey = SIMD3<UInt8>(120, 120, 120)
    static let yellow = SIMD3<UInt8>(250, 240, 60)

    /// A camera at `eye` looking at `target` (ARKit convention: x right, y up, looking down −z).
    static func camera(eye: SIMD3<Double>, target: SIMD3<Double>, width: Int = 160, height: Int = 120) -> ScanCamera {
        func norm(_ v: SIMD3<Double>) -> SIMD3<Double> { v / (v * v).sum().squareRoot() }
        func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        }
        let f = norm(target - eye)
        let right = norm(cross(f, SIMD3(0, 1, 0)))
        let up = cross(right, f)
        func c(_ v: SIMD3<Double>, _ w: Float) -> SIMD4<Float> { SIMD4(Float(v.x), Float(v.y), Float(v.z), w) }
        return ScanCamera(transform: RoomTransform(columns: [c(right, 0), c(up, 0), c(-f, 0), c(eye, 1)]),
                          fx: 110, fy: 110, cx: Double(width) / 2, cy: Double(height) / 2, width: width, height: height)
    }

    /// Ray-casts axis-aligned boxes and the floor plane y = 0 (grey); background black.
    static func render(_ cam: ScanCamera, boxes: [SceneBox], floor: SIMD3<UInt8>? = grey) -> RGBImage {
        let cols = cam.transform.columns
        func v(_ c: SIMD4<Float>) -> SIMD3<Double> { SIMD3(Double(c.x), Double(c.y), Double(c.z)) }
        let eye = v(cols[3])
        var px = [UInt8](repeating: 0, count: cam.width * cam.height * 3)
        for y in 0..<cam.height {
            for x in 0..<cam.width {
                let dc = SIMD3((Double(x) + 0.5 - cam.cx) / cam.fx, -(Double(y) + 0.5 - cam.cy) / cam.fy, -1.0)
                let d = v(cols[0]) * dc.x + v(cols[1]) * dc.y + v(cols[2]) * dc.z
                var best = Double.infinity
                var color = SIMD3<UInt8>(0, 0, 0)
                for b in boxes {
                    var t0 = 0.0, t1 = Double.infinity, hit = true
                    for a in 0..<3 {
                        let lo = b.center[a] - b.size[a] / 2, hi = b.center[a] + b.size[a] / 2
                        if abs(d[a]) < 1e-12 {
                            if eye[a] < lo || eye[a] > hi { hit = false; break }
                        } else {
                            var n = (lo - eye[a]) / d[a], f = (hi - eye[a]) / d[a]
                            if n > f { swap(&n, &f) }
                            t0 = max(t0, n); t1 = min(t1, f)
                            if t0 > t1 { hit = false; break }
                        }
                    }
                    if hit, t0 < best { best = t0; color = b.color }
                }
                if let floor, d.y < 0 {
                    let t = -eye.y / d.y
                    if t < best { best = t; color = floor }
                }
                let i = (y * cam.width + x) * 3
                px[i] = color.x; px[i + 1] = color.y; px[i + 2] = color.z
            }
        }
        return RGBImage(width: cam.width, height: cam.height, pixels: px)
    }

    static func rgb(_ c: VoxelColor?) -> SIMD3<Int>? {
        c.map { SIMD3(Int($0 >> 16 & 0xFF), Int($0 >> 8 & 0xFF), Int($0 & 0xFF)) }
    }

    static func close(_ c: VoxelColor?, _ want: SIMD3<UInt8>, tolerance: Int = 12) -> Bool {
        guard let got = rgb(c) else { return false }
        return abs(got.x - Int(want.x)) <= tolerance && abs(got.y - Int(want.y)) <= tolerance && abs(got.z - Int(want.z)) <= tolerance
    }

    /// A 4 m blue back wall at z = −3 (normal +z), a floor from z −3 to 0.5, a red 0.6 m cube.
    static func room(extraObjects: [RoomGeometry.Object] = []) -> RoomGeometry {
        RoomGeometry(
            walls: [RoomGeometry.Surface(id: "back", kind: .wall, dimensions: SIMD3(4, 2.5, 0.1), transform: .at(SIMD3(0, 1.25, -3)))],
            floors: [RoomGeometry.Floor(id: "f", outline: [SIMD2(-2, -3), SIMD2(2, -3), SIMD2(2, 0.5), SIMD2(-2, 0.5)], elevation: 0)],
            objects: [RoomGeometry.Object(id: "cube", category: "storage", dimensions: SIMD3(0.6, 0.6, 0.6), transform: .at(SIMD3(0, 0.3, -1.5)))]
                + extraObjects
        )
    }

    static let wallBox = SceneBox(center: SIMD3(0, 1.25, -3), size: SIMD3(4, 2.5, 0.1), color: blue)
    static let cubeBox = SceneBox(center: SIMD3(0, 0.3, -1.5), size: SIMD3(0.6, 0.6, 0.6), color: red)

    static let cameras = [
        camera(eye: SIMD3(0, 1.4, 0.3), target: SIMD3(0, 0.8, -2)),
        camera(eye: SIMD3(-1.0, 1.5, 0.2), target: SIMD3(0, 0.6, -1.8)),
        camera(eye: SIMD3(1.0, 1.3, 0.0), target: SIMD3(0, 0.7, -2)),
    ]

    // MARK: Tests

    @Test func projectsPointAheadToImageCenter() throws {
        let cam = Self.camera(eye: SIMD3(0, 1, 0), target: SIMD3(0, 1, -5))
        let p = try #require(cam.project(SIMD3(0, 1, -2)))
        #expect(abs(p.u - 80) < 1e-6 && abs(p.v - 60) < 1e-6 && abs(p.depth - 2) < 1e-6)
        // Up in the world is up in the image (smaller v); right is right.
        let q = try #require(cam.project(SIMD3(0.5, 1.5, -2)))
        #expect(q.u > 80 && q.v < 60)
        #expect(cam.project(SIMD3(0, 1, 2)) == nil)  // behind
        #expect(cam.project(SIMD3(0, 1, -0.05)) == nil)  // too close
    }

    @Test func scaledIntrinsicsProjectToTheSameRelativeSpot() throws {
        let cam = Self.camera(eye: SIMD3(0, 1, 0), target: SIMD3(0, 1, -5))
        let small = cam.scaled(toWidth: 80, height: 60)
        let a = try #require(cam.project(SIMD3(0.3, 1.2, -2))), b = try #require(small.project(SIMD3(0.3, 1.2, -2)))
        #expect(abs(a.u / 2 - b.u) < 1e-9 && abs(a.v / 2 - b.v) < 1e-9)
    }

    @Test func keyframeRuleNeedsMoveOrTurn() {
        let a = Self.camera(eye: SIMD3(0, 1, 0), target: SIMD3(0, 1, -5))
        #expect(a.isNewView(since: nil))
        #expect(!a.isNewView(since: a))
        #expect(!Self.camera(eye: SIMD3(0.3, 1, 0), target: SIMD3(0.3, 1, -5)).isNewView(since: a))
        #expect(Self.camera(eye: SIMD3(0.6, 1, 0), target: SIMD3(0.6, 1, -5)).isNewView(since: a))
        #expect(Self.camera(eye: SIMD3(0, 1, 0), target: SIMD3(-3, 1, -5)).isNewView(since: a))  // ~31° turn
        #expect(!Self.camera(eye: SIMD3(0, 1, 0), target: SIMD3(-1, 1, -5)).isNewView(since: a))  // ~11°
    }

    @Test func redCubeInFrontOfBlueWall() throws {
        let frames = Self.cameras.map { ScanFrame(camera: $0, image: Self.render($0, boxes: [Self.wallBox, Self.cubeBox])) }
        let colors = ColorSampler.sample(Self.room(), frames: frames)
        #expect(Self.close(colors.wallColor, Self.blue), "wall \(String(describing: Self.rgb(colors.wallColor)))")
        #expect(Self.close(colors.floorColor, Self.grey), "floor \(String(describing: Self.rgb(colors.floorColor)))")
        let cube = try #require(colors.objectColors["cube"])
        #expect(Self.close(cube.primary, Self.red), "cube \(String(describing: Self.rgb(cube.primary)))")
        #expect(cube.secondary == nil)
    }

    @Test func framesAtAnotherResolutionUseScaledIntrinsics() throws {
        // Intrinsics recorded for 320 × 240, image decoded at 160 × 120.
        let frames = Self.cameras.map { cam in
            ScanFrame(camera: cam.scaled(toWidth: 320, height: 240), image: Self.render(cam, boxes: [Self.wallBox, Self.cubeBox]))
        }
        let colors = ColorSampler.sample(Self.room(), frames: frames)
        #expect(Self.close(colors.wallColor, Self.blue))
        #expect(Self.close(try #require(colors.objectColors["cube"]).primary, Self.red))
    }

    @Test func occludedWallSamplesAreSkipped() throws {
        // A bright yellow wardrobe hides the left half of the wall's upper band. Unoccluded, its
        // samples would win the 75th–90th luma band; with the occlusion test the wall stays blue.
        let wardrobe = SceneBox(center: SIMD3(-1.0, 1.15, -2.6), size: SIMD3(1.6, 2.3, 0.5), color: Self.yellow)
        let geometry = Self.room(extraObjects: [
            RoomGeometry.Object(id: "wardrobe", category: "storage", dimensions: SIMD3(1.6, 2.3, 0.5), transform: .at(SIMD3(-1.0, 1.15, -2.6))),
        ])
        let frames = Self.cameras.map { ScanFrame(camera: $0, image: Self.render($0, boxes: [Self.wallBox, Self.cubeBox, wardrobe])) }
        let colors = ColorSampler.sample(geometry, frames: frames)
        #expect(Self.close(colors.wallColor, Self.blue), "wall \(String(describing: Self.rgb(colors.wallColor)))")
        #expect(Self.close(try #require(colors.objectColors["wardrobe"]).primary, Self.yellow))

        // Control: without the wardrobe in the geometry its pixels leak into the wall color.
        let leaky = ColorSampler.sample(Self.room(), frames: frames)
        #expect(!Self.close(leaky.wallColor, Self.blue))
    }

    @Test func boxBlocksSegmentThroughItButNotEndingOnIt() {
        let box = Box(id: "b", dimensions: SIMD3(1, 1, 1), transform: .at(SIMD3(0, 0.5, -2), yaw: 0.4))
        #expect(box.blocks(from: SIMD3(0, 0.5, 0), to: SIMD3(0, 0.5, -4)))
        #expect(!box.blocks(from: SIMD3(0, 0.5, 0), to: SIMD3(0, 0.5, -1)))  // stops short
        #expect(!box.blocks(from: SIMD3(0, 3, 0), to: SIMD3(0, 3, -4)))  // passes above
        // A point on the box's own front face isn't hidden by the box.
        let front = Box(id: "f", dimensions: SIMD3(1, 1, 1), transform: .at(SIMD3(0, 0.5, -2)))
        #expect(!front.blocks(from: SIMD3(0, 0.5, 0), to: SIMD3(0, 0.5, -1.5)))
    }

    @Test func percentileBandBeatsMedianForShadowedWall() {
        // 60% of the samples are in shadow, 40% lit; a few glare highlights on top.
        var samples = [SIMD3<Double>](repeating: SIMD3(0.3, 0.3, 0.3), count: 60)
        samples += [SIMD3<Double>](repeating: SIMD3(0.8, 0.8, 0.8), count: 36)
        samples += [SIMD3<Double>](repeating: SIMD3(1, 1, 1), count: 4)
        let band = ColorSampler.percentileBandMean(samples, from: 0.75, to: 0.90)
        #expect(abs(band.x - 0.8) < 1e-9)
        let median = ColorSampler.percentileBandMean(samples, from: 0.5, to: 0.5)
        #expect(abs(median.x - 0.3) < 1e-9)
        // Uniform ramp: mean of the 75–90% band.
        let ramp = (0...100).map { SIMD3(Double($0) / 100, Double($0) / 100, Double($0) / 100) }
        #expect(abs(ColorSampler.percentileBandMean(ramp, from: 0.75, to: 0.90).x - 0.825) < 1e-9)
    }

    @Test func kMeansFindsPrimaryAndSecondary() throws {
        let red = SIMD3(0.8, 0.1, 0.1), white = SIMD3(0.95, 0.95, 0.95)
        var samples = (0..<70).map { i in red + SIMD3(repeating: Double(i % 5) * 0.01) }
        samples += (0..<30).map { i in white - SIMD3(repeating: Double(i % 3) * 0.01) }
        let (primary, secondary) = ColorSampler.dominantColors(samples)
        #expect(abs(primary.x - 0.82) < 0.03 && primary.y < 0.2)
        let s = try #require(secondary)
        #expect(s.x > 0.9 && s.y > 0.9)
        // A tiny second cluster isn't reported.
        let mostlyRed = Array(samples[0..<70]) + Array(samples[70..<75])
        #expect(ColorSampler.dominantColors(mostlyRed).1 == nil)
        // One color: no secondary.
        #expect(ColorSampler.dominantColors([SIMD3<Double>](repeating: red, count: 10)).1 == nil)
    }

    @Test func okLabRoundTrips() {
        for c in [SIMD3(0.1, 0.5, 0.9), SIMD3(1.0, 1.0, 1.0), SIMD3(0.8, 0.2, 0.1)] {
            let back = OKLab(srgb: c).srgb
            #expect(abs(back.x - c.x) < 1e-4 && abs(back.y - c.y) < 1e-4 && abs(back.z - c.z) < 1e-4)
        }
    }

    @Test func packNeverReturnsEmpty() {
        #expect(ColorSampler.pack(SIMD3(0, 0, 0)) == 0x010101)
        #expect(ColorSampler.pack(SIMD3(1, 0, 0.5)) == 0xFF0080)
    }

    @Test func noFramesNoColors() {
        #expect(ColorSampler.sample(Self.room(), frames: []).isEmpty)
    }

    @Test func layoutItemCarriesColorsIntoVoxelSpec() {
        var item = Item(id: 7, owner: "me", roomId: 1, scanObjectId: "cube", name: "Box", category: "storage",
                        widthM: 0.6, heightM: 0.6, depthM: 0.6)
        let colors = ScanColors(objectColors: ["cube": .init(primary: 0xD21E1E, secondary: 0x202020)])
        let spec = VoxelItemSpec(LayoutItem(item, colors: colors))
        #expect(spec.primaryColor == 0xD21E1E && spec.secondaryColor == 0x202020)
        item.scanObjectId = nil
        #expect(VoxelItemSpec(LayoutItem(item, colors: colors)).primaryColor == nil)
    }
}
