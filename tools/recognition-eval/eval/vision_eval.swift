// Runs the three on-device Vision methods on every image in the bench manifest and
// writes one JSON line per image to stdout:
//   det:  all detector observations [label, label.conf * obs.conf, box] (app's score)
//   vnc:  VNClassifyImageRequest top-120 [identifier, confidence]
//   fp:   VNGenerateImageFeaturePrintRequest vector (Float)
//   ms_det / ms_vnc / ms_fp: wall time per request (ms)
// Usage: swift -O vision_eval.swift <manifest.jsonl> <bench root> <compiled .mlmodelc>
import Foundation
import Vision
import CoreML

let args = CommandLine.arguments
let manifest = args[1], root = args[2], modelURL = URL(fileURLWithPath: args[3])

let cfg = MLModelConfiguration()
cfg.computeUnits = .all
let ml = try MLModel(contentsOf: modelURL, configuration: cfg)
let vmodel = try VNCoreMLModel(for: ml)

func now() -> Double { Date().timeIntervalSince1970 * 1000 }

let lines = try String(contentsOfFile: manifest, encoding: .utf8).split(separator: "\n")
var out = FileHandle.standardOutput
for line in lines {
    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let path = obj["path"] as? String else { continue }
    let url = URL(fileURLWithPath: root + "/" + path)
    var rec: [String: Any] = ["path": path]
    autoreleasepool {
        // Detector: same request options as ExtraObjectDetector (scaleFit letterbox).
        let det = VNCoreMLRequest(model: vmodel)
        det.imageCropAndScaleOption = .scaleFit
        let vnc = VNClassifyImageRequest()
        let fp = VNGenerateImageFeaturePrintRequest()
                do {
            // Separate handlers so no method reuses another's cached analysis (VNClassify and
            // the feature print share a backbone); timings include image decode.
            var t = now(); try VNImageRequestHandler(url: url, options: [:]).perform([det]); rec["ms_det"] = now() - t
            let obs = (det.results as? [VNRecognizedObjectObservation]) ?? []
            rec["det"] = obs.compactMap { o -> [Any]? in
                guard let top = o.labels.first else { return nil }
                let b = o.boundingBox
                return [top.identifier, Double(top.confidence * o.confidence), [b.minX, b.minY, b.width, b.height]]
            }
            t = now(); try VNImageRequestHandler(url: url, options: [:]).perform([vnc]); rec["ms_vnc"] = now() - t
            rec["vnc"] = (vnc.results ?? []).prefix(120).map { [$0.identifier, Double($0.confidence)] }
            t = now(); try VNImageRequestHandler(url: url, options: [:]).perform([fp]); rec["ms_fp"] = now() - t
            if let f = fp.results?.first as? VNFeaturePrintObservation {
                var v = [Float](repeating: 0, count: f.elementCount)
                f.data.withUnsafeBytes { raw in
                    if f.elementType == .float { for i in 0..<f.elementCount { v[i] = raw.load(fromByteOffset: i * 4, as: Float.self) } }
                    else { for i in 0..<f.elementCount { v[i] = Float(raw.load(fromByteOffset: i * 8, as: Double.self)) } }
                }
                rec["fp"] = v
                rec["fp_rev"] = fp.revision
            }
        } catch { rec["error"] = "\(error)" }
    }
    let data = try JSONSerialization.data(withJSONObject: rec)
    out.write(data); out.write("\n".data(using: .utf8)!)
}
