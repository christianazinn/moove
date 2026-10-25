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
/// - **relabel** when its top category beats the detector's by the policy's margin (0.2
///   shipped constant, 0.3 in the bundled policy; ≥ 0.5 when the
///   detector's category isn't one the classifier knows) and has at least 0.4, unless the box
///   is clearly the wrong size for it (footprint priors, else RoomPlan's size ranges);
/// - **unknown** (`other`, for vision to name) when the box clearly can't be the
///   detector's category and the classifier doesn't back it, or the detector said "vacuum"
///   and the classifier gives that under 0.5 (mops, brooms, dollies and tripods get called
///   vacuum; real vacuums score 0.57-0.99);
/// - else keep.
/// The head's image-prototype `clutter` class (mops, brooms, tripods...) is set aside for all of
/// that; on its own it rejects sure clutter and sends likely clutter to vision as `other`.
/// Thresholds were tuned on the public benchmark split (the detector's own picks on
/// 912 public crops); see the PR for the iPad numbers. They come from the head's fitted
/// `policy` (`ObjectClassifierLabels.json`, `Policy`) when it has one, else these
/// constants (`Policy.shipped`); a policy can also add a `doubt` band (keep the object,
/// flagged as maybe not an item). Objects RoomPlan found get the
/// stricter reject-only `checkRoomPlan`. Detector finds can carry RoomPlan's category
/// names (a door as "storage", a wall as "refrigerator"); they still get `check`.
public enum ObjectRecheck {
    public enum Verdict: Equatable, Sendable {
        case keep
        case relabel(String, reason: String)
        case reject(reason: String)
        /// The box can't be what the detector said and the classifier can't say either.
        case unknown(reason: String)
        /// Kept, but maybe not an item (non-item mass in the policy's doubt band). The category
        /// is what relabel / unknown would have set (`ObjectSanity.relabelCategory` for
        /// unknown); nil keeps the label. The app tags the object `suspectAttribute`.
        case doubt(String?, reason: String)
    }

    /// Attribute on an object the recheck doubted (`.doubt`), sent with the scan
    /// (`import_scan_v2`) so vision can veto it on a medium-confidence "not an item".
    public static let suspectAttribute = "Recheck.suspect"
    /// Prefix of attributes the recheck adds: not RoomPlan's reading of the object, so naming
    /// and voxel routing ignore them.
    public static let attributePrefix = "Recheck."
    public static func isRecheckAttribute(_ a: String) -> Bool { a.hasPrefix(attributePrefix) }

    /// Thresholds for `check` / `checkRoomPlan`, from the classifier head's `policy` block
    /// (fitted offline; every key optional, missing ones are `shipped`'s).
    public struct Policy: Sendable, Equatable, Decodable {
        /// How the non-item probability (`none` + fixtures) is measured.
        public enum Mass: String, Sendable, Equatable {
            /// The top-ranked group's probability when it's `none` or a fixture, else 0.
            case top
            /// `none` plus every fixture.
            case sum
            /// `none` plus the likeliest single fixture.
            case nonePlusMaxFixture
        }
        public struct Bars: Sendable, Equatable {
            public var mass: Mass
            /// Non-item mass at or above this rejects.
            public var reject: Double
            /// Non-item mass at or above this (and under `reject`) keeps but doubts; nil: off.
            public var doubt: Double?
            public init(mass: Mass, reject: Double, doubt: Double? = nil) {
                self.mass = mass
                self.reject = reject
                self.doubt = doubt
            }
        }

        public var version: Int
        /// Per-crop logits are divided by this before the softmax (`ObjectClassifierHead`).
        public var temperature: Double
        /// Added to every class logit of a category after the temperature; missing = 0.
        public var categoryBias: [String: Double]
        public var detector: Bars
        public var roomPlan: Bars
        public var relabelMargin: Double
        /// Relabel margin by the detector's category group (after `sameAs`).
        public var relabelMarginByDetector: [String: Double]
        public var unknownCategoryThreshold: Double

        public init(version: Int = 1, temperature: Double = 1, categoryBias: [String: Double] = [:],
                    detector: Bars = Bars(mass: .top, reject: ObjectRecheck.rejectThreshold),
                    roomPlan: Bars = Bars(mass: .sum, reject: ObjectRecheck.roomPlanRejectThreshold),
                    relabelMargin: Double = ObjectRecheck.relabelMargin, relabelMarginByDetector: [String: Double] = [:],
                    unknownCategoryThreshold: Double = ObjectRecheck.unknownCategoryThreshold) {
            self.version = version
            self.temperature = temperature
            self.categoryBias = categoryBias
            self.detector = detector
            self.roomPlan = roomPlan
            self.relabelMargin = relabelMargin
            self.relabelMarginByDetector = relabelMarginByDetector
            self.unknownCategoryThreshold = unknownCategoryThreshold
        }

        /// Today's constants: detector top pick ≥ 0.6, RoomPlan none + fixtures ≥ 0.7, no doubt.
        public static let shipped = Policy()

        private enum Keys: String, CodingKey {
            case version, temperature, categoryBias, recheck, detector, roomPlan, relabelMargin, relabelMarginByDetector, unknownCategoryThreshold
            case mass, reject, doubt
        }

        /// The `policy` block (`fit` and other unknown keys ignored). Unknown `mass` names fall
        /// back to that origin's shipped mode.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let s = Policy.shipped
            self.init(version: try c.decodeIfPresent(Int.self, forKey: .version) ?? s.version,
                      temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? s.temperature,
                      categoryBias: try c.decodeIfPresent([String: Double].self, forKey: .categoryBias) ?? s.categoryBias)
            guard c.contains(.recheck), try !c.decodeNil(forKey: .recheck) else { return }
            let r = try c.nestedContainer(keyedBy: Keys.self, forKey: .recheck)
            func bars(_ key: Keys, _ shipped: Bars) throws -> Bars {
                guard r.contains(key), try !r.decodeNil(forKey: key) else { return shipped }
                let b = try r.nestedContainer(keyedBy: Keys.self, forKey: key)
                return Bars(mass: try b.decodeIfPresent(String.self, forKey: .mass).flatMap(Mass.init(rawValue:)) ?? shipped.mass,
                            reject: try b.decodeIfPresent(Double.self, forKey: .reject) ?? shipped.reject,
                            doubt: try b.decodeIfPresent(Double.self, forKey: .doubt) ?? shipped.doubt)
            }
            detector = try bars(.detector, s.detector)
            roomPlan = try bars(.roomPlan, s.roomPlan)
            relabelMargin = try r.decodeIfPresent(Double.self, forKey: .relabelMargin) ?? s.relabelMargin
            relabelMarginByDetector = try r.decodeIfPresent([String: Double].self, forKey: .relabelMarginByDetector) ?? s.relabelMarginByDetector
            unknownCategoryThreshold = try r.decodeIfPresent(Double.self, forKey: .unknownCategoryThreshold) ?? s.unknownCategoryThreshold
        }
    }

    /// Non-item probability by `mode`, and the non-item category carrying most of it (for the
    /// fixture size guard). `top` reads the group ranking the way `check` always has.
    static func nonItemMass(_ scores: [String: Double], _ mode: Policy.Mass) -> (mass: Double, category: String)? {
        switch mode {
        case .top:
            var groups: [String: Double] = [:]
            for (c, p) in scores { groups[group(c), default: 0] += p }
            guard let top = groups.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else { return nil }
            return top.key == notAnObject || fixtures.contains(top.key) ? (top.value, top.key) : (0, top.key)
        case .sum, .nonePlusMaxFixture:
            let parts = scores.filter { $0.key == notAnObject || fixtures.contains($0.key) }
            guard let most = parts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else { return nil }
            let fixture = parts.filter { $0.key != notAnObject }.values.max() ?? 0
            return (mode == .sum ? parts.values.reduce(0, +) : (scores[notAnObject] ?? 0) + fixture, most.key)
        }
    }

    static func describe(_ mode: Policy.Mass) -> String {
        switch mode {
        case .top: "sure"
        case .sum: "none + fixtures"
        case .nonePlusMaxFixture: "none + a fixture"
        }
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
    /// A relabel's target needs at least this much (R5): a margin alone let an unsure crop
    /// (floor lamp: storage 0.32, lamp 0.06) be renamed by whichever group summed the most.
    /// Picked on public listings + thin-clutter dev photos (highest bar with no new errors there).
    public static let relabelFloor = 0.4
    /// Detector categories the classifier must back before they're kept (R5): below this the
    /// object becomes `other` for vision to name, unless a relabel applies.
    public static let confirmBelow: [String: Double] = ["vacuum": 0.5]

    /// Thin floor clutter (mop, broom, dustpan, squeegee, plunger, tripod / light stand), from the
    /// head's image-prototype rows (R5-2). Not a Moove category: `check` sets it aside (the other
    /// scores renormalized without it, so every other rule sees the shipped probabilities) and
    /// only uses it to reject sure clutter or hand an unsure one to vision as `other`. RoomPlan
    /// objects ignore it.
    public static let clutter = "clutter"
    /// Clutter reject: p(clutter) at least this...
    public static let clutterReject = 0.8
    /// ...p(vacuum) under this, with and without the clutter rows (a real vacuum stays a vacuum)...
    public static let clutterVacuumMax = 0.1
    /// ...and the detector's category under this.
    public static let clutterRejectGuard = 0.3
    /// Clutter on top with at least this, and the detector's category under `clutterDeferGuard`: `other`.
    public static let clutterDefer = 0.5
    public static let clutterDeferGuard = 0.5

    /// `scores` without `clutter`, renormalized (unchanged when there's none).
    static func withoutClutter(_ scores: [String: Double]) -> [String: Double] {
        guard let pc = scores[clutter] else { return scores }
        var s = scores
        s[clutter] = nil
        let rest = 1 - pc
        guard rest > 1e-9 else { return s }
        return s.mapValues { $0 / rest }
    }

    static func group(_ category: String) -> String { sameAs[category] ?? category }

    /// RoomPlan's own objects were right 27 of 28 times on the iPad scans, where the classifier
    /// alone got ~75%, so for them it may only reject, and only when this sure.
    public static let roomPlanRejectThreshold = 0.7
    /// RoomPlan categories the classifier has no class for, or that are fixtures already
    /// (a sink is plumbing either way): not rechecked.
    public static let roomPlanUnchecked: Set<String> = ["dishwasher", "oven", "stove", "fireplace", "stairs", "sink", "toilet", "bathtub"]

    /// The recheck for an object RoomPlan found (by origin, not category name): `.reject` when
    /// `none` + fixtures add up to `roomPlanRejectThreshold` (`policy.roomPlan`), `.doubt(nil)`
    /// in the policy's doubt band, else `.keep`. Never relabels.
    public static func checkRoomPlan(category: String, scores: [String: Double], policy: Policy = .shipped) -> Verdict {
        guard !roomPlanUnchecked.contains(category) else { return .keep }
        let scores = withoutClutter(scores)
        let bars = policy.roomPlan
        let p = nonItemMass(scores, bars.mass)?.mass ?? 0
        if p >= bars.reject {
            return .reject(reason: "not an object (\(Int((p * 100).rounded()))% sure), RoomPlan said \(category)")
        }
        if let doubt = bars.doubt, p >= doubt {
            return .doubt(nil, reason: "maybe not an item (\(Int((p * 100).rounded()))% \(describe(bars.mass))), RoomPlan said \(category)")
        }
        return .keep
    }

    // MARK: The detector's label history as a second opinion (R6 chunk B)

    /// How `check(..., history:)` uses `SightingMerger.LabelHistory`. Picked on CA-1M (31 captures,
    /// tools: R6B-dethist/method.py, same rules): β = 1 fixed 1-4 objects per population with no
    /// breaks (β ≥ 2 broke a toaster and a coffee table); the reject gate caught a wall the detector
    /// called a room divider and threw nothing away at 0.4 (0.3 threw away a mirror). Marking
    /// unsure objects `other` only broke right answers, so there's no such rule.
    public struct HistoryPolicy: Sendable, Equatable {
        /// Weight of the detector's label distribution in the pool (0 = classifier only).
        public var beta: Double
        /// Laplace smoothing of that distribution, in confidence units per category.
        public var alpha: Double
        /// The flip-gated reject needs at least this many views...
        public var minViews: Int
        /// ...the top label on fewer than this share of them...
        public var consensusBelow: Double
        /// ...and the classifier's none + fixtures mass at least this (the plain bar is 0.6 on one class).
        public var nonItemReject: Double

        public init(beta: Double = 1, alpha: Double = 0.5, minViews: Int = 2, consensusBelow: Double = 0.67, nonItemReject: Double = 0.4) {
            self.beta = beta
            self.alpha = alpha
            self.minViews = minViews
            self.consensusBelow = consensusBelow
            self.nonItemReject = nonItemReject
        }

        public static let `default` = HistoryPolicy()
    }

    /// `check` with the detector's label history (`RoomGeometry.Object.measured?.labelHistory`):
    /// - **pool**: object categories are reweighted by what the detector said across frames,
    ///   p(c) ∝ p_classifier(c) · p_detector(c)^β, keeping the classifier's none + fixtures mass as
    ///   it is (the detector never says "none", so it can't argue for a reject). Detector labels the
    ///   classifier has no class for ("bin", "stool") add nothing;
    /// - **reject** when the detector kept changing its mind (top label on < `consensusBelow` of
    ///   ≥ `minViews` views) and the classifier leans non-item (≥ `nonItemReject`): phantoms flip,
    ///   real objects mostly don't.
    /// Without a history (RoomPlan objects, old scans) it's exactly `check`.
    public static func check(detectorCategory det: String, scores: [String: Double], width: Double, height: Double, depth: Double,
                             policy: Policy = .shipped, history: SightingMerger.LabelHistory?,
                             historyPolicy hp: HistoryPolicy = .default) -> Verdict {
        guard let history, !history.labels.isEmpty, !scores.isEmpty else {
            return check(detectorCategory: det, scores: scores, width: width, height: height, depth: depth, policy: policy)
        }
        let pooledScores = pooled(scores, with: history, beta: hp.beta, alpha: hp.alpha)
        // The policy's bars (and its doubt band) apply to the pooled scores; pooling leaves the
        // non-item mass as it is, so a doubt here is the classifier's doubt.
        let base = check(detectorCategory: det, scores: pooledScores, width: width, height: height, depth: depth, policy: policy)
        if case .reject = base { return base }
        guard history.views >= hp.minViews, history.consensus < hp.consensusBelow else { return base }
        let nonItem = withoutClutter(pooledScores).filter { $0.key == notAnObject || fixtures.contains($0.key) }.values.reduce(0, +)
        guard nonItem >= hp.nonItemReject else { return base }
        let labels = history.labels.keys.sorted().joined(separator: "/")
        return .reject(reason: "detector unsure (\(labels), \(Int((history.consensus * 100).rounded()))% agree), "
            + "\(Int((nonItem * 100).rounded()))% not an object")
    }

    /// The classifier's object categories reweighted by the detector's label mass (see `check(..., history:)`).
    static func pooled(_ scores: [String: Double], with history: SightingMerger.LabelHistory, beta: Double, alpha: Double) -> [String: Double] {
        guard beta > 0 else { return scores }
        let objects = scores.keys.filter { $0 != notAnObject && !fixtures.contains($0) && $0 != clutter }
        var members: [String: [String]] = [:]
        for c in objects { members[group(c), default: []].append(c) }
        var mass = Dictionary(uniqueKeysWithValues: objects.map { ($0, 0.0) })
        var total = 0.0
        for (label, e) in history.labels {
            guard let ms = members[group(label)] else { continue }
            for c in ms { mass[c, default: 0] += Double(e.totalConfidence) / Double(ms.count) }
            total += Double(e.totalConfidence)
        }
        let k = Double(objects.count)
        var weighted: [String: Double] = [:]
        for c in objects { weighted[c] = (scores[c] ?? 0) * pow(((mass[c] ?? 0) + alpha) / (total + alpha * k), beta) }
        let objectMass = objects.map { scores[$0] ?? 0 }.reduce(0, +)
        let z = weighted.values.reduce(0, +)
        guard z > 0 else { return scores }
        var out = scores
        for (c, w) in weighted { out[c] = w / z * objectMass }
        return out
    }

    /// `scores`: classifier probability per Moove category (all of its categories, summing
    /// to 1, e.g. `ObjectClassifierHead.scores`). Sizes are the box's width, height, depth (m).
    /// `policy`: thresholds (`ObjectClassifierHead.policy`); `.doubt` only when it has a doubt bar.
    public static func check(detectorCategory det: String, scores: [String: Double], width: Double, height: Double, depth: Double,
                             policy: Policy = .shipped) -> Verdict {
        let all = scores
        let scores = withoutClutter(all)
        let bars = policy.detector
        let nonItem = nonItemMass(scores, bars.mass)
        var verdict = decide(detectorCategory: det, scores: scores, width: width, height: height, depth: depth, policy: policy, nonItem: nonItem)
        if let pc = all[clutter] {
            func percent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }
            var allGroups: [String: Double] = [:], groups: [String: Double] = [:]
            for (c, p) in all { allGroups[group(c), default: 0] += p }
            for (c, p) in scores { groups[group(c), default: 0] += p }
            let pSaid = groups[group(det)] ?? 0
            if pc >= clutterReject, (allGroups["vacuum"] ?? 0) < clutterVacuumMax, (scores["vacuum"] ?? 0) < clutterVacuumMax,
               pSaid < clutterRejectGuard {
                return .reject(reason: "clutter (\(percent(pc)), a mop, broom or stand), detector said \(det)")
            }
            let top = allGroups.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
            if case .reject = verdict {} else if top == clutter, pc >= clutterDefer, pSaid < clutterDeferGuard {
                verdict = .unknown(reason: "looks like clutter (\(percent(pc))), detector said \(det)")
            }
        }
        guard let doubt = bars.doubt, let m = nonItem?.mass, m >= doubt else { return verdict }
        let why = "maybe not an item (\(Int((m * 100).rounded()))% \(describe(bars.mass))), detector said \(det)"
        switch verdict {
        case .reject, .doubt: return verdict
        case .keep: return .doubt(nil, reason: why)
        case let .relabel(category, reason): return .doubt(category, reason: "\(why); \(reason)")
        case let .unknown(reason): return .doubt(ObjectSanity.relabelCategory, reason: "\(why); \(reason)")
        }
    }

    /// `check` without the doubt band.
    private static func decide(detectorCategory det: String, scores: [String: Double], width: Double, height: Double, depth: Double,
                               policy: Policy, nonItem: (mass: Double, category: String)?) -> Verdict {
        var groups: [String: Double] = [:]
        for (c, p) in scores { groups[group(c), default: 0] += p }
        let ranked = groups.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard let (top, pTop) = ranked.first.map({ ($0.key, $0.value) }) else { return .keep }

        func clearlyOff(_ category: String, _ p: Double = 0) -> Bool {
            p < sureProbability
                && ObjectSanity.fitsFootprint(category, width: width, height: height, depth: depth, factor: vetoFactor) == false
        }
        /// A relabel target is also checked against RoomPlan's size ranges.
        func targetOff(_ category: String, _ p: Double) -> Bool {
            p < sureProbability
                && ObjectSanity.fitsSizePrior(category, width: width, height: height, depth: depth, factor: vetoFactor) == false
        }
        func percent(_ p: Double) -> String { "\(Int((p * 100).rounded()))%" }

        if policy.detector.mass == .top {
            if top == notAnObject || fixtures.contains(top), pTop >= policy.detector.reject, !clearlyOff(top, pTop) {
                return .reject(reason: top == notAnObject
                    ? "not an object (\(percent(pTop)) sure), detector said \(det)"
                    : "a \(top) (fixture, \(percent(pTop)) sure), detector said \(det)")
            }
        } else if let n = nonItem, n.mass >= policy.detector.reject, !clearlyOff(n.category, n.mass) {
            return .reject(reason: "not an object (\(percent(n.mass)) \(describe(policy.detector.mass))), detector said \(det)")
        }
        let relabelMargin = policy.relabelMargin, unknownCategoryThreshold = policy.unknownCategoryThreshold
        let d = group(det)
        let pDet = groups[d]
        let objects = ranked.filter { $0.key != notAnObject && !fixtures.contains($0.key) }
        guard var (best, pBest) = objects.first.map({ ($0.key, $0.value) }) else { return .keep }
        if objects.count > 1, Set([best, objects[1].key]) == ["table", "storage"], abs(pBest - objects[1].value) < relabelMargin {
            best = height > tableStorageCutM ? "storage" : "table"
            pBest = groups[best] ?? 0
        }
        if best != d {
            let margin = policy.relabelMarginByDetector[d] ?? relabelMargin
            let beats = pDet.map { pBest - $0 >= margin } ?? (pBest >= unknownCategoryThreshold)
            if beats, pBest >= relabelFloor, !targetOff(best, pBest) {
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
        if let bar = confirmBelow[d], (pDet ?? 0) < bar {
            return .unknown(reason: "doesn't look like a \(det) (\(percent(pDet ?? 0)))")
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
        var policy: ObjectRecheck.Policy?
    }

    public let classes: [Class]
    public let dimension: Int
    public let logitScale: Float
    /// The json's fitted `policy` block, else `.shipped`: its temperature and category biases
    /// apply in `classProbabilities`, its thresholds go to `ObjectRecheck.check`.
    public let policy: ObjectRecheck.Policy
    /// `policy.temperature` (1 when it isn't a positive number).
    let temperature: Float
    /// `policy.categoryBias` per class row; nil when there is none.
    let rowCategoryBias: [Float]?
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
        let policy = meta.policy ?? .shipped
        self.policy = policy
        let t = Float(policy.temperature)
        temperature = t.isFinite && t > 0 ? t : 1
        rowCategoryBias = policy.categoryBias.values.contains { $0 != 0 }
            ? meta.classes.map { Float(policy.categoryBias[$0.category] ?? 0) } : nil
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
    /// Logit = (logitScale · cos + bias) / temperature + categoryBias[category] (from `policy`).
    public func classProbabilities(_ embedding: [Float]) -> [Float] {
        guard embedding.count == dimension else { return [] }
        let norm = max(embedding.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-12)
        var logits = classes.indices.map { c -> Float in
            var dot: Float = 0
            let row = c * dimension
            for i in 0..<dimension { dot += weights[row + i] * embedding[i] }
            var logit = logitScale * dot / norm + classes[c].bias
            if temperature != 1 { logit /= temperature }
            if let b = rowCategoryBias { logit += b[c] }
            return logit
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
