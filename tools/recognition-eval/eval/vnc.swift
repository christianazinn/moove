import Vision
import Foundation
for path in CommandLine.arguments.dropFirst() {
  let req = VNClassifyImageRequest()
  let h = VNImageRequestHandler(url: URL(fileURLWithPath: path))
  let t0 = Date()
  try h.perform([req])
  let ms = Date().timeIntervalSince(t0) * 1000
  let top = (req.results ?? []).prefix(5).map { "\($0.identifier) \(String(format: "%.2f", $0.confidence))" }
  let parts = path.split(separator: "/")
  print(parts[2], parts.last!.prefix(8), String(format: "%.0fms", ms), top.joined(separator: " | "))
}
