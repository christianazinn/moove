import Foundation
import Testing
@testable import MooveKit

@Suite struct WideFramePickerTests {
    /// A phone at the room's middle turned `yaw` about +Y (yaw 0 looks along -z), tilted `pitch` down.
    func frame(_ id: Int, yaw: Float, pitch: Float = 0, sharpness: Float = 100, depth: Float? = 3) -> Keyframe {
        let c = cos(yaw), s = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        // Camera -z (forward) = (-s·cp, -sp, -c·cp); +z is its negation.
        let z = SIMD4<Float>(s * cp, sp, c * cp, 0)
        let pose = CameraPose(columns: [SIMD4(0, -1, 0, 0), SIMD4(c, 0, -s, 0), z, SIMD4(0, 1.4, 0, 1)],
                              fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)
        return Keyframe(id: id, pose: pose, sharpness: sharpness,
                        depth: depth.map { DepthGrid(width: 2, height: 2, values: [$0, $0, $0, $0]) })
    }

    @Test func spreadsPhotosAroundTheRoom() {
        // A slow pan: a keyframe every 15°.
        let frames = (0..<24).map { frame($0, yaw: Float($0) * 15 * .pi / 180) }
        let picked = WideFramePicker.pick(frames, count: 4)
        #expect(picked.count == 4)
        let headings = picked.map { Float($0) * 15 }
        for (i, a) in headings.enumerated() {
            for b in headings[(i + 1)...] {
                let d = abs(remainder(a - b, 360))
                #expect(d >= 60, "photos \(a)° and \(b)° overlap")
            }
        }
    }

    @Test func skipsBlurryCloseUpAndTiltedFrames() {
        let frames = [
            frame(0, yaw: 0),
            frame(1, yaw: .pi / 2, sharpness: 10),        // blurred
            frame(2, yaw: .pi, depth: 0.5),               // close-up of something
            frame(3, yaw: -.pi / 2, pitch: 1.0),          // looking at the floor
            frame(4, yaw: .pi * 0.75),
        ]
        #expect(Set(WideFramePicker.pick(frames, count: 4)) == [0, 4])
    }

    @Test func prefersTheSharperOfTwoSimilarViews() {
        let frames = [frame(0, yaw: 0, sharpness: 80), frame(1, yaw: 0.05, sharpness: 150), frame(2, yaw: .pi)]
        let picked = WideFramePicker.pick(frames, count: 4)
        #expect(picked.contains(1) && !picked.contains(0))
        #expect(picked.count == 2)
    }

    @Test func emptyInputs() {
        #expect(WideFramePicker.pick([], count: 4).isEmpty)
        #expect(WideFramePicker.pick([frame(0, yaw: 0)], count: 0).isEmpty)
    }
}
