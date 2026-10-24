import Foundation
@preconcurrency import ARKit
import CoreML
import Vision
import MooveKit

/// Finds everyday objects RoomPlan doesn't recognize (bikes, suitcases, plants...)
/// during the RoomPlan scan (#73). About twice a second it takes RoomPlan's own
/// ARKit frame, runs Apple's Core ML YOLOv3 (COCO) through Vision, and turns
/// each detection's LiDAR depth into world-space points. MooveKit's
/// `SightingMerger` clusters those into measured objects.
///
/// Off (nil) when the model isn't bundled: run ios/scripts/fetch-models.sh.
final class ExtraObjectDetector: @unchecked Sendable {
    /// COCO label → Moove category, for things RoomPlan doesn't cover and that are
    /// worth moving or selling. People, pets and RoomPlan's own furniture are left out.
    static let categories: [String: String] = [
        "bicycle": "bicycle", "motorbike": "motorcycle", "bench": "bench", "suitcase": "suitcase",
        "skis": "skis", "snowboard": "snowboard", "skateboard": "skateboard", "surfboard": "surfboard",
        "pottedplant": "plant", "microwave": "microwave", "laptop": "laptop", "vase": "vase",
        "teddy bear": "teddy bear", "backpack": "backpack",
    ]
    /// LiDAR mostly sees the near side, so thin objects come out too shallow from
    /// one angle; these minimum depths (m) keep their footprints realistic.
    static let minimumDepth: [String: Float] = [
        "bicycle": 0.45, "motorcycle": 0.7, "bench": 0.35, "suitcase": 0.2, "plant": 0.25,
        "microwave": 0.3, "laptop": 0.2, "skateboard": 0.2, "surfboard": 0.08, "skis": 0.08, "snowboard": 0.08,
    ]
    static let minimumConfidence: Float = 0.45

    private let request: VNCoreMLRequest
    private let queue = DispatchQueue(label: "moove.extra-objects", qos: .userInitiated)
    private let lock = NSLock()
    private var merger = SightingMerger()
    private var busy = false
    private(set) var usedDepth = 0, usedRaycast = 0

    init?() {
        guard let url = Bundle.main.url(forResource: "YOLOv3Int8LUT", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let vision = try? VNCoreMLModel(for: model) else { return nil }
        request = VNCoreMLRequest(model: vision)
        request.imageCropAndScaleOption = .scaleFill
    }

    /// Labels found at least twice so far, for the live "Also found" chips.
    var foundSoFar: [String] {
        lock.withLock { merger.tracks.filter { $0.sightings >= 2 }.map(\.label) }
    }

    /// Call often (e.g. from a timer); frames are skipped while one is processing.
    func offer(_ session: ARSession) {
        let claimed = lock.withLock { () -> Bool in
            if busy { return false }
            busy = true
            return true
        }
        guard claimed else { return }
        guard let frame = session.currentFrame else {
            lock.withLock { busy = false }
            return
        }
        queue.async { [weak self] in
            defer { self?.lock.withLock { self?.busy = false } }
            self?.process(frame, session: session)
        }
    }

    /// The measured objects, minus anything overlapping RoomPlan's own objects.
    func results(floorY: Float, excluding roomPlanObjects: [RoomGeometry.Object]) -> [RoomGeometry.Object] {
        let tracks = lock.withLock { () -> [SightingMerger.Track] in
            merger.floorY = floorY
            return merger.results(excluding: roomPlanObjects)
        }
        return tracks.map { t in
            var size = t.box.size
            size.z = max(size.z, Self.minimumDepth[t.label] ?? 0.05)
            return RoomGeometry.Object(id: UUID().uuidString, category: t.label, dimensions: size, transform: t.box.transform)
        }
    }

    // MARK: Frames

    private func process(_ frame: ARFrame, session: ARSession) {
        // The back camera's sensor image is landscape; `.right` makes it upright for a
        // portrait phone so the detector sees objects the right way up.
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results as? [VNRecognizedObjectObservation] else { return }
        for obs in observations {
            guard let top = obs.labels.first, top.confidence >= Self.minimumConfidence,
                  let category = Self.categories[top.identifier] else { continue }
            let points = depthPoints(frame, box: obs.boundingBox) ?? raycastPoints(frame, session: session, box: obs.boundingBox)
            guard points.count >= 12 else { continue }
            lock.withLock { merger.add(Sighting(label: category, confidence: top.confidence, points: points)) }
        }
    }

    /// Vision's box is normalized in the upright image with a bottom-left origin.
    /// Returns the same point in the sensor image, normalized with a top-left origin.
    static func sensorPoint(uprightX x: CGFloat, y: CGFloat) -> CGPoint {
        // Upright = sensor rotated 90° clockwise, so upright bottom-left is sensor bottom-right.
        CGPoint(x: 1 - y, y: 1 - x)
    }

    /// World points from the LiDAR depth map inside the detection, keeping the
    /// nearest surface (the object) and dropping the background behind it.
    private func depthPoints(_ frame: ARFrame, box: CGRect) -> [SIMD3<Float>]? {
        guard let depth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let map = depth.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        var confidence: (UnsafeRawPointer, Int)?
        if let conf = depth.confidenceMap {
            CVPixelBufferLockBaseAddress(conf, .readOnly)
            if let p = CVPixelBufferGetBaseAddress(conf) { confidence = (UnsafeRawPointer(p), CVPixelBufferGetBytesPerRow(conf)) }
        }
        defer { if let conf = depth.confidenceMap { CVPixelBufferUnlockBaseAddress(conf, .readOnly) } }

        // Sample the middle 80% of the box: the edges are mostly background.
        let inner = box.insetBy(dx: box.width * 0.1, dy: box.height * 0.1)
        var samples: [(u: CGFloat, v: CGFloat, d: Float)] = []
        let steps = 28
        for i in 0..<steps {
            for j in 0..<steps {
                let ux = inner.minX + inner.width * (CGFloat(i) + 0.5) / CGFloat(steps)
                let uy = inner.minY + inner.height * (CGFloat(j) + 0.5) / CGFloat(steps)
                let s = Self.sensorPoint(uprightX: ux, y: uy)
                let px = min(max(Int(s.x * CGFloat(w)), 0), w - 1), py = min(max(Int(s.y * CGFloat(h)), 0), h - 1)
                if let (cp, cRow) = confidence, cp.load(fromByteOffset: py * cRow + px, as: UInt8.self) < UInt8(ARConfidenceLevel.medium.rawValue) { continue }
                let d = base.load(fromByteOffset: py * rowBytes + px * MemoryLayout<Float32>.size, as: Float32.self)
                guard d.isFinite, d > 0.2, d < 8 else { continue }
                samples.append((s.x, s.y, d))
            }
        }
        guard samples.count >= 12 else { return [] }
        lock.withLock { usedDepth += 1 }
        // The object is the nearest big surface; keep depths near the 30th percentile.
        let sorted = samples.map(\.d).sorted()
        let near = sorted[sorted.count * 3 / 10]
        let image = frame.camera.imageResolution
        let k = frame.camera.intrinsics
        let toWorld = frame.camera.transform
        return samples.compactMap { s -> SIMD3<Float>? in
            guard abs(s.d - near) < 0.6 else { return nil }
            // Unproject: image pixel + depth -> camera space (x right, y up, looking down -z).
            let u = Float(s.u * image.width), v = Float(s.v * image.height)
            let x = (u - k[2][0]) / k[0][0] * s.d
            let y = -(v - k[2][1]) / k[1][1] * s.d
            let world = toWorld * SIMD4(x, y, -s.d, 1)
            return SIMD3(world.x, world.y, world.z)
        }
    }

    /// Fallback when the session has no scene depth: raycast a grid onto ARKit's
    /// estimated surfaces. Coarser, but still gives position and rough size.
    private func raycastPoints(_ frame: ARFrame, session: ARSession, box: CGRect) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for i in 0..<6 {
            for j in 0..<6 {
                let ux = box.minX + box.width * (CGFloat(i) + 0.5) / 6
                let uy = box.minY + box.height * (CGFloat(j) + 0.5) / 6
                let query = frame.raycastQuery(from: Self.sensorPoint(uprightX: ux, y: uy), allowing: .estimatedPlane, alignment: .any)
                if let hit = session.raycast(query).first {
                    points.append(SIMD3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z))
                }
            }
        }
        if !points.isEmpty { lock.withLock { usedRaycast += 1 } }
        return points
    }
}
