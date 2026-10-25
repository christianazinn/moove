import Foundation
@preconcurrency import ARKit
import CoreImage
import ImageIO
import MooveKit

/// Auto photos (#82). During the scan it keeps a keyframe whenever the camera has a
/// new, steady view: an upright JPEG on disk plus the camera pose, a small LiDAR depth
/// grid and a sharpness score. When the scan ends, `photos(for:)` projects each object's
/// 3D box (RoomPlan's or the extra detector's) into every keyframe, picks the
/// best-framed view with MooveKit's `CropPicker`, and cuts it out as a JPEG.
/// It runs even without the detector model, so RoomPlan's objects get photos too.
final class AutoPhotographer: @unchecked Sendable {
    static let maxPhotoSide: CGFloat = 1600

    private let queue = DispatchQueue(label: "moove.keyframes", qos: .utility)
    private let lock = NSLock()
    private let folder: URL
    private let context = CIContext()
    private var gate = KeyframeGate()
    private var keyframes: [Keyframe] = []
    private var busy = false

    init() {
        folder = FileManager.default.temporaryDirectory.appending(path: "moove-keyframes/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    var keyframeCount: Int { lock.withLock { keyframes.count } }

    /// Call often (e.g. from the detection timer); cheap when the view hasn't changed.
    func offer(_ session: ARSession) {
        guard let frame = session.currentFrame, case .normal = frame.camera.trackingState else { return }
        let pose = Self.pose(frame.camera)
        let accepted = lock.withLock { () -> Int? in
            if busy { return nil }
            guard gate.offer(pose, time: frame.timestamp) else { return nil }
            busy = true
            return gate.kept.count - 1
        }
        guard let id = accepted else { return }
        queue.async { [weak self] in
            defer { self?.lock.withLock { self?.busy = false } }
            self?.store(frame, pose: pose, id: id)
        }
    }

    private func store(_ frame: ARFrame, pose: CameraPose, id: Int) {
        let upright = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(of: upright, colorSpace: space,
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]),
              (try? jpeg.write(to: url(id))) != nil else { return }
        let keyframe = Keyframe(id: id, pose: pose, sharpness: Self.sharpness(frame.capturedImage),
                                depth: Self.depthGrid(frame.smoothedSceneDepth ?? frame.sceneDepth))
        lock.withLock { keyframes.append(keyframe) }
    }

    private func url(_ id: Int) -> URL { folder.appending(path: "\(id).jpg") }

    /// Best crop of each object as JPEG data, by object id. Slow-ish (decodes a few
    /// keyframes); call off the main thread.
    func photos(for objects: [RoomGeometry.Object]) -> [String: Data] {
        queue.sync {}  // let a keyframe that's being written finish
        let frames = lock.withLock { keyframes }
        var out: [String: Data] = [:]
        for object in objects {
            guard let best = CropPicker.best(size: object.dimensions, transform: object.transform, in: frames),
                  let image = CIImage(contentsOf: url(best.keyframeID)) else { continue }
            let r = CropPicker.cropRect(best)
            let e = image.extent
            // NormRect has a top-left origin; Core Image's is bottom-left.
            let rect = CGRect(x: e.minX + CGFloat(r.x) * e.width, y: e.minY + CGFloat(1 - r.maxY) * e.height,
                              width: CGFloat(r.width) * e.width, height: CGFloat(r.height) * e.height).integral
            var crop = image.cropped(to: rect)
            let scale = min(1, Self.maxPhotoSide / max(rect.width, rect.height))
            if scale < 1 { crop = crop.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            crop = crop.transformed(by: CGAffineTransform(translationX: -crop.extent.minX, y: -crop.extent.minY))
            if let space = CGColorSpace(name: CGColorSpace.sRGB),
               let jpeg = context.jpegRepresentation(of: crop, colorSpace: space,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]) {
                out[object.id] = jpeg
            }
        }
        return out
    }

    /// Views of each object for `ObjectClassifier`, by object id: its auto photo's framing
    /// (`photos(for:)`), plus tight crops (no margin) of its `count` best keyframes, with
    /// looser gates when too few pass (`CropPicker.top`). On real scans, averaging the auto
    /// photo with 3 extra views beat the auto photo alone. Call off the main thread.
    func classifierCrops(for objects: [RoomGeometry.Object], count: Int = 3) -> [String: [CGImage]] {
        queue.sync {}
        let frames = lock.withLock { keyframes }
        var images: [Int: CIImage] = [:]
        var out: [String: [CGImage]] = [:]
        for object in objects {
            let auto = CropPicker.best(size: object.dimensions, transform: object.transform, in: frames)
            let views = CropPicker.top(size: object.dimensions, transform: object.transform, in: frames, count: count)
            let rects = auto.map { [($0, CropPicker.cropRect($0))] } ?? []
            out[object.id] = (rects + views.map { ($0, CropPicker.cropRect($0, margin: 0)) }).compactMap { view, r in
                guard let image = images[view.keyframeID] ?? CIImage(contentsOf: url(view.keyframeID)) else { return nil }
                images[view.keyframeID] = image
                let e = image.extent
                let rect = CGRect(x: e.minX + CGFloat(r.x) * e.width, y: e.minY + CGFloat(1 - r.maxY) * e.height,
                                  width: CGFloat(r.width) * e.width, height: CGFloat(r.height) * e.height).integral
                return context.createCGImage(image, from: rect)
            }
        }
        return out
    }

    /// A few whole keyframes that together show the room (`WideFramePicker`), as JPEG,
    /// longest side ≤ `maxPhotoSide`, for the worker's photo sweep (#92). Call off the main thread.
    func roomPhotos(count: Int = 4) -> [Data] {
        queue.sync {}
        let frames = lock.withLock { keyframes }
        return WideFramePicker.pick(frames, count: count).compactMap { id in
            guard var image = CIImage(contentsOf: url(id)) else { return nil }
            let scale = min(1, Self.maxPhotoSide / max(image.extent.width, image.extent.height))
            if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return context.jpegRepresentation(of: image, colorSpace: space,
                                              options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
        }
    }

    // MARK: Frame data

    static func pose(_ camera: ARCamera) -> CameraPose {
        let t = camera.transform, k = camera.intrinsics
        return CameraPose(columns: [t.columns.0, t.columns.1, t.columns.2, t.columns.3],
                          fx: k[0][0], fy: k[1][1], cx: k[2][0], cy: k[2][1],
                          imageWidth: Float(camera.imageResolution.width), imageHeight: Float(camera.imageResolution.height))
    }

    /// Sharpness of the middle of the luma plane at full resolution (blur shows there first).
    static func sharpness(_ buffer: CVPixelBuffer) -> Float {
        guard CVPixelBufferGetPlaneCount(buffer) > 0 else { return 0 }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let sw = min(320, w), sh = min(240, h), x0 = (w - sw) / 2, y0 = (h - sh) / 2
        var luma = [UInt8](repeating: 0, count: sw * sh)
        for y in 0..<sh {
            for x in 0..<sw { luma[y * sw + x] = base.load(fromByteOffset: (y0 + y) * row + x0 + x, as: UInt8.self) }
        }
        return Sharpness.score(luma: luma, width: sw, height: sh)
    }

    /// LiDAR depth shrunk 4× (64×48 for a 256×192 map), for occlusion checks.
    static func depthGrid(_ depth: ARDepthData?) -> DepthGrid? {
        guard let map = depth?.depthMap else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map), row = CVPixelBufferGetBytesPerRow(map)
        let gw = max(w / 4, 1), gh = max(h / 4, 1)
        var values = [Float](repeating: 0, count: gw * gh)
        for y in 0..<gh {
            for x in 0..<gw {
                values[y * gw + x] = base.load(fromByteOffset: (y * 4 + 2) * row + (x * 4 + 2) * MemoryLayout<Float32>.size, as: Float32.self)
            }
        }
        return DepthGrid(width: gw, height: gh, values: values)
    }
}
