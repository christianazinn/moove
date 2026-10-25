import Foundation
import CoreGraphics
import CoreML
import Vision
import MooveKit

/// Second-stage classifier for the extra detector's finds: Meta's PE-Core-S/16-384 image
/// tower (Apache-2.0) as Core ML, 8-bit palettized (~23 MB), 384×384 RGB in (normalization
/// baked in) → L2-normalized 512-d embedding out. MooveKit's `ObjectClassifierHead` turns
/// embeddings into probabilities over Moove categories + `none`, and `ObjectRecheck`
/// decides keep / relabel / reject.
///
/// Off (nil) when the model isn't bundled: run ios/scripts/fetch-models.sh. ~10 ms per crop
/// on an M5's Neural Engine; call off the main thread.
final class ObjectClassifier: @unchecked Sendable {
    private let model: VNCoreMLModel
    let head: ObjectClassifierHead

    init?() {
        guard let url = Bundle.main.url(forResource: "ObjectClassifier", withExtension: "mlmodelc"),
              let head = ObjectClassifierHead.bundled else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        guard let ml = try? MLModel(contentsOf: url, configuration: config),
              let vision = try? VNCoreMLModel(for: ml) else { return nil }
        model = vision
        self.head = head
    }

    /// Image embedding of one crop, or nil if the model failed on it.
    func embedding(of image: CGImage) -> [Float]? {
        let request = VNCoreMLRequest(model: model)
        // Squash to 384×384 like PE-Core's own preprocessing (resize_mode "squash").
        request.imageCropAndScaleOption = .scaleFill
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let array = (request.results?.first as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue,
              array.count == head.dimension else { return nil }
        return (0..<array.count).map { array[$0].floatValue }
    }

    /// Probability per Moove category (and `none`), averaged over an object's crops.
    /// Empty if no crop could be classified.
    func scores(_ crops: [CGImage]) -> [String: Double] {
        head.scores(crops.compactMap(embedding(of:)))
    }
}
