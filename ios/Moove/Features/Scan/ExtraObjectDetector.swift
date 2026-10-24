import Foundation
@preconcurrency import ARKit
import CoreML
import Vision
import MooveKit

/// Finds the everyday objects RoomPlan doesn't recognize (scooters, bikes, guitars,
/// vacuums, lamps, boxes...) during the RoomPlan scan (#73, #82). About three times a
/// second it takes RoomPlan's own ARKit frame and runs Moove's object detector through
/// Vision. The detector is YOLOE-11L with 127 household text prompts baked in
/// (`ObjectVocabulary`). Each detection's LiDAR depth becomes world-space points, and
/// MooveKit's `SightingMerger` clusters those into measured objects.
///
/// Off (nil) when the model isn't bundled: run ios/scripts/fetch-models.sh.
final class ExtraObjectDetector: @unchecked Sendable {
    private let request: VNCoreMLRequest
    private let queue = DispatchQueue(label: "moove.extra-objects", qos: .userInitiated)
    private let lock = NSLock()
    private var merger = SightingMerger()
    private var busy = false
    private(set) var usedDepth = 0, usedRaycast = 0, framesRun = 0

    init?() {
        guard let url = Bundle.main.url(forResource: "MooveObjects", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let vision = try? VNCoreMLModel(for: model) else { return nil }
        request = VNCoreMLRequest(model: vision)
        // Letterbox like the model was trained: on test photos this beat stretching
        // (guitar 0.90 vs. read as a cello, a vacuum found at 0.77 vs. missed).
        request.imageCropAndScaleOption = .scaleFit
    }

    /// Categories confirmed so far, for the live "Also found" chips.
    var foundSoFar: [String] {
        lock.withLock { merger.results(refit: false).map(\.label) }
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

    /// The measured objects, minus anything RoomPlan already found.
    func results(floorY: Float, excluding roomPlanObjects: [RoomGeometry.Object]) -> [RoomGeometry.Object] {
        let tracks = lock.withLock { () -> [SightingMerger.Track] in
            merger.floorY = floorY
            return merger.results(excluding: roomPlanObjects)
        }
        return tracks.map { t in
            var size = t.box.size
            size.z = max(size.z, ObjectVocabulary.minimumDepth[t.label] ?? 0.05)
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
        lock.withLock { framesRun += 1 }
        let raw = observations.compactMap { obs -> (label: String, confidence: Float, box: NormRect)? in
            guard let top = obs.labels.first else { return nil }
            // Vision rescales the class scores to sum to 1 and reports the sum as the
            // observation's confidence. YOLOE's scores are independent sigmoids, so undo it.
            let b = obs.boundingBox  // upright, normalized, bottom-left origin
            return (top.identifier, top.confidence * obs.confidence,
                    NormRect(x: Float(b.minX), y: Float(1 - b.maxY), width: Float(b.width), height: Float(b.height)))
        }
        for d in DetectionFilter.filter(raw) {
            let box = CGRect(x: CGFloat(d.box.x), y: CGFloat(1 - d.box.maxY), width: CGFloat(d.box.width), height: CGFloat(d.box.height))
            let points = depthPoints(frame, box: box) ?? raycastPoints(frame, session: session, box: box)
            guard points.count >= 12 else { continue }
            lock.withLock { _ = merger.add(Sighting(label: d.category, confidence: d.confidence, points: points)) }
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
