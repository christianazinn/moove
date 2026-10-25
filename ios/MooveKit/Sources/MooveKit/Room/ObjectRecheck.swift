import Foundation

/// Second opinion on the extra detector's finds (#73, #82), from an on-device crop
/// classifier (PE-Core-S/16-384, Apache-2.0; the app's `ObjectClassifier`).
///
/// The detector mislabels often: on 120 real iPad photos it called an e-scooter, a
/// step ladder and a light stand "vacuum", every cardboard box a "bin", radiators
/// "heaters", and turned walls, door frames and plastic sheeting into objects. The
/// classifier looks at 1-3 crops of each detector object and votes over Moove categories
/// plus `none` (wall, door, floor, clutter...) and fixtures (radiator, shower curtain,
/// towel rack). `check` fuses that with the detector's category and the LiDAR box:
/// - **reject** when `none` or a fixture is the classifier's top pick with ≥ 60%;
/// - **relabel** when its top category beats the detector's by ≥ 0.2 (≥ 0.5 when the
///   detector's category isn't one the classifier knows), unless the box is clearly the
///   wrong size for it;
/// - **unknown** (`other`, for vision to name) when the box clearly can't be the
///   detector's category and the classifier doesn't back it;
/// - else keep.
/// Thresholds were tuned on the public benchmark split (the detector's own picks on
/// 912 public crops); see the PR for the iPad numbers. Objects RoomPlan found get the
/// stricter reject-only `checkRoomPlan`. Detector finds can carry RoomPlan's category
/// names (a door as "storage", a wall as "refrigerator"); they still get `check`.
public enum ObjectRecheck {
    public enum Verdict: Equatable, Sendable {
        case keep
        case relabel(String, reason: String)
        case reject(reason: String)
        /// The box can't be what the detector said and the classifier can't say either.
        case unknown(reason: String)
    }

    /// Classifier category for "not a movable object".
    public static let notAnObject = "none"
    /// Built into the room: not moved, so not inventoried.
    public static let fixtures: Set<String> = ["radiator", "shower curtain", "towel rack"]
    /// Categories the classifier can't tell apart reliably and that mean the same thing for a
    /// move, so neither relabels the other.
    public static let sameAs: [String: String] = ["backpack": "bag", "monitor": "television", "shelf": "storage", "ceiling fan": "fan"]

    public static let rejectThreshold = 0.6
    public static let relabelMargin = 0.2
    /// Relabel bar when the classifier has no class for the detector's category (e.g. "bin").
    public static let unknownCategoryThreshold = 0.5
    /// The size veto only fires when a box is outside a prior by more than this factor:
    /// detector boxes are often partial (a scooter seen from the side measured 26 cm tall).
    public static let vetoFactor = 2.0
    /// A classifier this sure beats the size veto.
    public static let sureProbability = 0.9
    /// Table vs. storage within `relabelMargin`: taller than this is storage.
    public static let tableStorageCutM = 0.9

    static func group(_ category: String) -> String { sameAs[category] ?? category }

    /// RoomPlan's own objects were right 27 of 28 times on the iPad scans, where the classifier
    /// alone got ~75%, so for them it may only reject, and only when this sure.
    public static let roomPlanRejectThreshold = 0.7
    /// RoomPlan categories the classifier has no class for, or that are fixtures already
    /// (a sink is plumbing either way): not rechecked.
    public static let roomPlanUnchecked: Set<String> = ["dishwasher", "oven", "stove", "fireplace", "stairs", "sink", "toilet", "bathtub"]

    /// The recheck for an object RoomPlan found (by origin, not category name): `.reject` when
    /// `none` + fixtures add up to `roomPlanRejectThreshold`, else `.keep`. Never relabels.
    public static func checkRoomPlan(category: String, scores: [String: Double]) -> Verdict {
        guard !roomPlanUnchecked.contains(category) else { return .keep }
        let p = scores.filter { $0.key == notAnObject || fixtures.contains($0.key) }.values.reduce(0, +)
        guard p >= roomPlanRejectThreshold else { return .keep }
        return .reject(reason: "not an object (\(Int((p * 100).rounded()))% sure), RoomPlan said \(category)")
    }

    /// `scores`: classifier probability per Moove category (all of its categories, summing
    /// to 1, e.g. `ObjectClassifierHead.scores`). Sizes are the box's width, height, depth (m).
    public static func check(detectorCategory det: String, scores: [String: Double], width: Double, height: Double, depth: Double) -> Verdict {
        var groups: [String: Double] = [:]
        for (c, p) in scores { groups[group(c), default: 0] += p }
        let ranked = groups.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard let (top, pTop) = ranked.first.map({ ($0.key, $0.value) }) else { return .keep }

        func clearlyOff(_ category: String, _ p: Double = 0) -> Bool {
            p < sureProbability
                && ObjectSanity.fitsFootprint(category, width: width, height: height, depth: depth, factor: vetoFactor) == false
        }
        func percent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }

        if top == notAnObject || fixtures.contains(top), pTop >= rejectThreshold, !clearlyOff(top, pTop) {
            return .reject(reason: top == notAnObject
                ? "not an object (\(percent(pTop)) sure), detector said \(det)"
                : "a \(top) (fixture, \(percent(pTop)) sure), detector said \(det)")
        }
        let d = group(det)
        let pDet = groups[d]
        let objects = ranked.filter { $0.key != notAnObject && !fixtures.contains($0.key) }
        guard var (best, pBest) = objects.first.map({ ($0.key, $0.value) }) else { return .keep }
        if objects.count > 1, Set([best, objects[1].key]) == ["table", "storage"], abs(pBest - objects[1].value) < relabelMargin {
            best = height > tableStorageCutM ? "storage" : "table"
            pBest = groups[best] ?? 0
        }
        if best != d {
            let beats = pDet.map { pBest - $0 >= relabelMargin } ?? (pBest >= unknownCategoryThreshold)
            if beats, !clearlyOff(best, pBest) {
                // The member the classifier liked more, e.g. monitor vs. television.
                let category = scores.filter { group($0.key) == best }
                    .max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? best
                let vs = pDet.map { " vs \(det) \(percent($0))" } ?? ""
                return .relabel(category, reason: "looks like a \(category) (\(percent(pBest))\(vs))")
            }
        }
        if clearlyOff(det), (pDet ?? 0) < 0.5 {
            return .unknown(reason: "box can't be a \(det)")
        }
        return .keep
    }
}

/// The classifier's head: its label matrix (PE-Core text embeddings of each class's
/// prompts, fine-tuned as a linear probe) applied to image embeddings from the Core ML
/// image tower. Pure Swift so it's testable on Linux; the app only runs the image tower.
public struct ObjectClassifierHead: Sendable {
    public struct Class: Decodable, Sendable {
        public var id: String
        /// Moove category, or `none`.
        public var category: String
        /// Added to the logit (the shipped head nudges `none`/fixtures up by 1).
        public var bias: Float
    }

    private struct Meta: Decodable {
        var dimension: Int
        var logitScale: Float
        var classes: [Class]
    }

    public let classes: [Class]
    public let dimension: Int
    public let logitScale: Float
    /// Row-major classes × dimension, L2-normalized rows.
    let weights: [Float]
    /// Every category, sorted.
    public let categories: [String]

    /// `json`: ObjectClassifierLabels.json; `matrix`: ObjectClassifierLabels.f16 (float16, little-endian).
    public init(json: Data, matrix: Data) throws {
        let meta = try JSONDecoder().decode(Meta.self, from: json)
        guard matrix.count == meta.classes.count * meta.dimension * 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        classes = meta.classes
        dimension = meta.dimension
        logitScale = meta.logitScale
        weights = matrix.withUnsafeBytes { raw in
            (0..<(matrix.count / 2)).map { Self.float(fromHalf: UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self))) }
        }
        categories = Array(Set(meta.classes.map(\.category))).sorted()
    }

    /// The head that ships with MooveKit (Resources/ObjectClassifierLabels.*).
    public static let bundled: ObjectClassifierHead? = {
        guard let j = Bundle.module.url(forResource: "ObjectClassifierLabels", withExtension: "json"),
              let m = Bundle.module.url(forResource: "ObjectClassifierLabels", withExtension: "f16"),
              let json = try? Data(contentsOf: j), let matrix = try? Data(contentsOf: m) else { return nil }
        return try? ObjectClassifierHead(json: json, matrix: matrix)
    }()

    /// Softmax over the classes for one image embedding (any length-`dimension` vector; it's normalized here).
    public func classProbabilities(_ embedding: [Float]) -> [Float] {
        guard embedding.count == dimension else { return [] }
        let norm = max(embedding.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-12)
        var logits = classes.indices.map { c -> Float in
            var dot: Float = 0
            let row = c * dimension
            for i in 0..<dimension { dot += weights[row + i] * embedding[i] }
            return logitScale * dot / norm + classes[c].bias
        }
        let top = logits.max() ?? 0
        logits = logits.map { exp($0 - top) }
        let sum = logits.reduce(0, +)
        return logits.map { $0 / sum }
    }

    /// Probability per category (classes of one category summed), averaged over the crops
    /// of one object. Empty when there are no usable embeddings.
    public func scores(_ embeddings: [[Float]]) -> [String: Double] {
        let probs = embeddings.map(classProbabilities).filter { !$0.isEmpty }
        guard !probs.isEmpty else { return [:] }
        var out = Dictionary(uniqueKeysWithValues: categories.map { ($0, 0.0) })
        for p in probs {
            for (c, v) in zip(classes, p) { out[c.category, default: 0] += Double(v) / Double(probs.count) }
        }
        return out
    }

    /// IEEE 754 half → Float (Float16 isn't available on every platform MooveKit builds for).
    static func float(fromHalf h: UInt16) -> Float {
        let sign = UInt32(h >> 15) << 31
        let exp = Int((h >> 10) & 0x1F), frac = UInt32(h & 0x3FF)
        if exp == 0 {
            let v = Float(frac) * pow(2, -24)  // zero / subnormal
            return sign != 0 ? -v : v
        }
        if exp == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (frac << 13)) }
        return Float(bitPattern: sign | (UInt32(exp + 112) << 23) | (frac << 13))
    }
}
