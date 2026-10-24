import ARKit
import CoreImage
import Foundation
import ImageIO
import MooveKit

/// A kept camera frame: a small JPEG plus the camera that took it, with intrinsics
/// already scaled to the JPEG's size. The JPEG stays in the sensor's landscape orientation.
struct RecordedFrame: Sendable {
    let jpeg: Data
    let camera: ScanCamera
}

/// Keeps up to 40 keyframes from RoomPlan's own ARSession while it scans, for sampling
/// real wall and furniture colors afterwards (`ColorSampler`).
///
/// RoomPlan owns the session's delegate, so this polls `currentFrame` every 0.5 s instead,
/// and keeps a frame only when the camera moved > 0.5 m or turned > 25° since the last one.
@MainActor
final class ScanFrameRecorder {
    static let maxFrames = 40
    static let longSide: CGFloat = 640
    static let interval: Duration = .milliseconds(500)

    private(set) var frames: [RecordedFrame] = []
    private weak var session: ARSession?
    private var task: Task<Void, Never>?
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    func start(_ session: ARSession) {
        self.session = session
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self, !Task.isCancelled else { return }
                self.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() {
        guard frames.count < Self.maxFrames, let frame = session?.currentFrame else { return }
        let arCamera = frame.camera
        guard case .normal = arCamera.trackingState else { return }
        let size = arCamera.imageResolution
        let k = arCamera.intrinsics  // column-major: fx = [0][0], fy = [1][1], cx = [2][0], cy = [2][1]
        let camera = ScanCamera(
            transform: RoomTransform(arCamera.transform),
            fx: Double(k[0][0]), fy: Double(k[1][1]), cx: Double(k[2][0]), cy: Double(k[2][1]),
            width: Int(size.width), height: Int(size.height)
        )
        guard camera.isNewView(since: frames.last?.camera) else { return }

        let scale = min(1, Self.longSide / max(size.width, size.height))
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0,
              let jpeg = context.jpegRepresentation(
                  of: image.cropped(to: extent), colorSpace: srgb,
                  options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.8])
        else { return }
        frames.append(RecordedFrame(jpeg: jpeg, camera: camera.scaled(toWidth: Int(extent.width), height: Int(extent.height))))
    }
}

/// Decodes the recorded frames and runs `ColorSampler` off the main actor.
enum ScanColorAnalysis {
    /// Sampling resolution: plenty for patch means, and keeps 40 decoded frames under ~10 MB.
    static let sampleLongSide = 320

    static func run(geometry: RoomGeometry, frames: [RecordedFrame], saveTo folder: URL? = nil) async -> ScanColors {
        await Task.detached(priority: .utility) {
            if let folder { save(frames, to: folder) }
            let decoded = frames.compactMap { f in
                decode(f.jpeg, maxSide: sampleLongSide).map { ScanFrame(camera: f.camera, image: $0) }
            }
            return ColorSampler.sample(geometry, frames: decoded)
        }.value
    }

    /// JPEG → RGB at most `maxSide` px on the long side, rows top to bottom, no rotation.
    nonisolated static func decode(_ data: Data, maxSide: Int) -> RGBImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = cg.width, h = cg.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? RGBImage(width: w, height: h, rgba: rgba) : nil
    }

    /// frames/NN.jpg + frames/cameras.json next to the scan, so a device scan can be
    /// replayed through `ColorSampler` in a test.
    nonisolated static func save(_ frames: [RecordedFrame], to folder: URL) {
        let dir = folder.appending(path: "frames", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, f) in frames.enumerated() {
            try? f.jpeg.write(to: dir.appending(path: String(format: "%02d.jpg", i)))
        }
        try? JSONEncoder().encode(frames.map(\.camera)).write(to: dir.appending(path: "cameras.json"))
    }
}
