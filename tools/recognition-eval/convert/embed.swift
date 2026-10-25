// Embeds every bench image with the Core ML classifier through Vision, the way the app
// runs it (VNCoreMLRequest, .scaleFill = squash resize, like PE-Core's preprocessing).
// Usage: swift -O embed.swift <manifest.jsonl> <bench root> <compiled .mlmodelc> <out prefix> [cpuAndNeuralEngine|all|cpuOnly]
// Writes <out>.f32 (N x 512 float32), <out>.paths (one per line), <out>.ms (one per line).
import Foundation
import Vision
import CoreML

let args = CommandLine.arguments
let manifest = args[1], root = args[2], modelURL = URL(fileURLWithPath: args[3]), out = args[4]
let cfg = MLModelConfiguration()
switch args.count > 5 ? args[5] : "cpuAndNeuralEngine" {
case "all": cfg.computeUnits = .all
case "cpuOnly": cfg.computeUnits = .cpuOnly
default: cfg.computeUnits = .cpuAndNeuralEngine
}
let ml = try MLModel(contentsOf: modelURL, configuration: cfg)
let vmodel = try VNCoreMLModel(for: ml)

let lines = try String(contentsOfFile: manifest, encoding: .utf8).split(separator: "\n")
var emb = Data(), paths: [String] = [], times: [String] = []
for line in lines {
    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let path = obj["path"] as? String else { continue }
    autoreleasepool {
        let req = VNCoreMLRequest(model: vmodel)
        req.imageCropAndScaleOption = .scaleFill
        let t = Date()
        var v = [Float](repeating: .nan, count: 512)
        if (try? VNImageRequestHandler(url: URL(fileURLWithPath: root + "/" + path), options: [:]).perform([req])) != nil,
           let a = (req.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue {
            for i in 0..<min(512, a.count) { v[i] = a[i].floatValue }
        }
        times.append(String(format: "%.2f", Date().timeIntervalSince(t) * 1000))
        v.withUnsafeBufferPointer { emb.append(Data(buffer: $0)) }
        paths.append(path)
    }
}
try emb.write(to: URL(fileURLWithPath: out + ".f32"))
try paths.joined(separator: "\n").write(toFile: out + ".paths", atomically: true, encoding: .utf8)
try times.joined(separator: "\n").write(toFile: out + ".ms", atomically: true, encoding: .utf8)
print("embedded", paths.count)
