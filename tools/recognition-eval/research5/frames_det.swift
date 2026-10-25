// Runs the Moove detector on full keyframes exactly like ExtraObjectDetector (scaleFit,
// orientation .right = upright portrait). One JSON line per frame: {path, det:[[label, score, [x,y,w,h] upright bottom-left]]}
// Usage: frames_det <model.mlmodelc> <file with one image path per line>
import Foundation
import Vision
import CoreML
let a = CommandLine.arguments
let cfg = MLModelConfiguration(); cfg.computeUnits = .all
let vm = try VNCoreMLModel(for: try MLModel(contentsOf: URL(fileURLWithPath: a[1]), configuration: cfg))
for p in try String(contentsOfFile: a[2], encoding: .utf8).split(separator: "\n") {
    autoreleasepool {
        let r = VNCoreMLRequest(model: vm); r.imageCropAndScaleOption = .scaleFit
        var rec: [String: Any] = ["path": String(p)]
        do {
            try VNImageRequestHandler(url: URL(fileURLWithPath: String(p)), orientation: .right, options: [:]).perform([r])
            rec["det"] = ((r.results as? [VNRecognizedObjectObservation]) ?? []).compactMap { o -> [Any]? in
                guard let t = o.labels.first else { return nil }
                let b = o.boundingBox
                return [t.identifier, Double(t.confidence * o.confidence), [b.minX, b.minY, b.width, b.height]]
            }
        } catch { rec["error"] = "\(error)" }
        let d = try! JSONSerialization.data(withJSONObject: rec)
        FileHandle.standardOutput.write(d); FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
}
