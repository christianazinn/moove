import Foundation
import Testing
@testable import MooveKit

/// The head's fitted `policy` block: decoding, temperature / category bias, doubt band.
@Suite struct ObjectRecheckPolicyTests {
    typealias Policy = ObjectRecheck.Policy

    func policy(_ json: String) throws -> Policy {
        try JSONDecoder().decode(Policy.self, from: Data(json.utf8))
    }

    /// A 3-class, 2-d head: chair (1, 0), none (0, 1, bias 1), radiator (-1, 0).
    func head(policy: String? = nil) throws -> ObjectClassifierHead {
        let json = """
        {"dimension": 2, "logitScale": 10, "classes": [
          {"id": "chair", "category": "chair", "bias": 0},
          {"id": "wall", "category": "none", "bias": 1},
          {"id": "radiator", "category": "radiator", "bias": 0}]\(policy.map { ", \"policy\": \($0)" } ?? "")}
        """
        let halves: [UInt16] = [0x3C00, 0, 0, 0x3C00, 0xBC00, 0]
        var matrix = Data()
        for h in halves { matrix.append(UInt8(h & 0xFF)); matrix.append(UInt8(h >> 8)) }
        return try ObjectClassifierHead(json: Data(json.utf8), matrix: matrix)
    }

    /// The pre-policy formula, verbatim.
    func oldProbabilities(_ head: ObjectClassifierHead, _ embedding: [Float]) -> [Float] {
        let norm = max(embedding.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-12)
        var logits = head.classes.indices.map { c -> Float in
            var dot: Float = 0
            let row = c * head.dimension
            for i in 0..<head.dimension { dot += head.weights[row + i] * embedding[i] }
            return head.logitScale * dot / norm + head.classes[c].bias
        }
        let top = logits.max() ?? 0
        logits = logits.map { exp($0 - top) }
        let sum = logits.reduce(0, +)
        return logits.map { $0 / sum }
    }

    func softmax(_ l: [Float]) -> [Float] {
        let e = l.map { exp($0 - (l.max() ?? 0)) }
        let s = e.reduce(0, +)
        return e.map { $0 / s }
    }

    // MARK: Decoding

    @Test func absentPolicyIsShipped() throws {
        let h = try head()
        #expect(h.policy == .shipped)
        #expect(try policy("{}") == .shipped)
        #expect(try policy(#"{"recheck": null, "fit": {"anything": [1, 2]}}"#) == .shipped)
        let s = Policy.shipped
        #expect(s.detector == .init(mass: .top, reject: 0.6, doubt: nil))
        #expect(s.roomPlan == .init(mass: .sum, reject: 0.7, doubt: nil))
        #expect(s.relabelMargin == 0.2 && s.unknownCategoryThreshold == 0.5 && s.relabelMarginByDetector.isEmpty)
        #expect(s.temperature == 1 && s.categoryBias.isEmpty)
    }

    @Test func partialPolicyKeepsShippedValues() throws {
        let p = try policy(#"{"recheck": {"detector": {"doubt": 0.4}, "relabelMargin": 0.25}}"#)
        #expect(p.detector == .init(mass: .top, reject: 0.6, doubt: 0.4))
        #expect(p.roomPlan == Policy.shipped.roomPlan)
        #expect(p.relabelMargin == 0.25)
        #expect(p.unknownCategoryThreshold == 0.5)
        #expect(p.temperature == 1)
        // Unknown mass names fall back to that origin's shipped mode.
        let q = try policy(#"{"recheck": {"detector": {"mass": "median", "reject": 0.9}, "roomPlan": {"mass": "nope"}}}"#)
        #expect(q.detector == .init(mass: .top, reject: 0.9))
        #expect(q.roomPlan == Policy.shipped.roomPlan)
    }

    @Test func fullPolicyDecodes() throws {
        let json = """
        {"version": 1, "temperature": 1.5, "categoryBias": {"none": 0.3, "radiator": -0.2},
         "recheck": {
           "detector": {"mass": "nonePlusMaxFixture", "reject": 0.8, "doubt": 0.4},
           "roomPlan": {"mass": "sum", "reject": 0.85, "doubt": 0.5},
           "relabelMargin": 0.2, "relabelMarginByDetector": {"vacuum": 0.1, "bag": 0.3},
           "unknownCategoryThreshold": 0.55},
         "fit": {"anything": "free-form provenance"}}
        """
        let p = try policy(json)
        #expect(p == Policy(version: 1, temperature: 1.5, categoryBias: ["none": 0.3, "radiator": -0.2],
                            detector: .init(mass: .nonePlusMaxFixture, reject: 0.8, doubt: 0.4),
                            roomPlan: .init(mass: .sum, reject: 0.85, doubt: 0.5),
                            relabelMargin: 0.2, relabelMarginByDetector: ["vacuum": 0.1, "bag": 0.3],
                            unknownCategoryThreshold: 0.55))
        #expect(try head(policy: json).policy == p)
        // Today's numbers written out are the shipped policy.
        let explicit = try policy("""
        {"version": 1, "temperature": 1, "categoryBias": {},
         "recheck": {"detector": {"mass": "top", "reject": 0.6, "doubt": null}, "roomPlan": {"mass": "sum", "reject": 0.7},
                     "relabelMargin": 0.2, "relabelMarginByDetector": {}, "unknownCategoryThreshold": 0.5}}
        """)
        #expect(explicit == .shipped)
    }

    // MARK: Temperature and category bias

    @Test func noTemperatureOrBiasIsTodaysMath() throws {
        let plain = try head()
        let neutral = try head(policy: #"{"temperature": 1, "categoryBias": {"none": 0}}"#)
        for e: [Float] in [[1, 0], [0.3, 0.7], [-2, 0.5], [0.01, -0.02]] {
            #expect(plain.classProbabilities(e) == oldProbabilities(plain, e))
            #expect(neutral.classProbabilities(e) == oldProbabilities(plain, e))
        }
    }

    @Test func temperatureThenCategoryBias() throws {
        let h = try head(policy: #"{"temperature": 2, "categoryBias": {"none": 0.3, "radiator": -0.2}}"#)
        let e: [Float] = [0.6, 0.8]  // unit: cos = 0.6, 0.8, -0.6
        let want = softmax([(10 * 0.6 + 0) / 2, (10 * 0.8 + 1) / 2 + 0.3, (10 * -0.6 + 0) / 2 - 0.2])
        let got = h.classProbabilities(e)
        #expect(got.count == 3)
        for (g, w) in zip(got, want) { #expect(abs(g - w) < 1e-6) }
        // Temperature alone flattens the distribution.
        let t = try head(policy: #"{"temperature": 4}"#), plain = try head()
        #expect(t.classProbabilities(e).max()! < plain.classProbabilities(e).max()!)
        // Nonsense temperatures are ignored.
        #expect(try head(policy: #"{"temperature": 0}"#).classProbabilities(e) == oldProbabilities(h, e))
    }

    // MARK: Detector

    let fitted = Policy(detector: .init(mass: .nonePlusMaxFixture, reject: 0.8, doubt: 0.4))

    func check(_ det: String, _ scores: [String: Double], _ w: Double, _ h: Double, _ d: Double, _ p: Policy) -> ObjectRecheck.Verdict {
        ObjectRecheck.check(detectorCategory: det, scores: scores, width: w, height: h, depth: d, policy: p)
    }

    @Test func keepInTheDoubtBandIsADoubt() {
        let s = ["chair": 0.55, "none": 0.3, "towel rack": 0.15]
        #expect(check("chair", s, 0.5, 0.9, 0.5, .shipped) == .keep)
        guard case let .doubt(nil, why) = check("chair", s, 0.5, 0.9, 0.5, fitted) else {
            Issue.record("not doubted"); return
        }
        #expect(why.hasPrefix("maybe not an item (45% none + a fixture)"))
        // Under the doubt bar: a plain keep.
        #expect(check("chair", ["chair": 0.8, "none": 0.2], 0.5, 0.9, 0.5, fitted) == .keep)
    }

    @Test func relabelInTheDoubtBandCarriesTheTarget() {
        let s = ["scooter": 0.5, "none": 0.35, "radiator": 0.1, "vacuum": 0.05]
        guard case .relabel("scooter", _) = check("vacuum", s, 0.55, 1.1, 1.0, .shipped) else {
            Issue.record("shipped didn't relabel"); return
        }
        guard case let .doubt("scooter", why) = check("vacuum", s, 0.55, 1.1, 1.0, fitted) else {
            Issue.record("not doubted with the relabel"); return
        }
        #expect(why.contains("looks like a scooter"))
    }

    @Test func unknownInTheDoubtBandIsOther() {
        let s = ["none": 0.45, "ladder": 0.25, "radiator": 0.2, "vacuum": 0.1]
        guard case .unknown = check("vacuum", s, 1.07, 2.08, 0.77, .shipped) else {
            Issue.record("shipped not unknown"); return
        }
        #expect(check("vacuum", s, 1.07, 2.08, 0.77, fitted) == .doubt(ObjectSanity.relabelCategory, reason:
            "maybe not an item (65% none + a fixture), detector said vacuum; box can't be a vacuum"))
    }

    @Test func pooledMassRejectsWhatTheTopPickMisses() {
        let s = ["none": 0.5, "towel rack": 0.35, "bag": 0.15]
        #expect(check("bag", s, 0.5, 0.4, 0.3, .shipped) == .keep)  // top pick none 0.5 < 0.6
        guard case let .reject(why) = check("bag", s, 0.5, 0.4, 0.3, fitted) else {
            Issue.record("not rejected"); return
        }
        #expect(why == "not an object (85% none + a fixture), detector said bag")
        // Sum mode counts every fixture.
        let sum = Policy(detector: .init(mass: .sum, reject: 0.8))
        guard case .reject = check("bag", ["none": 0.4, "towel rack": 0.25, "radiator": 0.2, "bag": 0.15], 0.5, 0.4, 0.3, sum) else {
            Issue.record("sum didn't reject"); return
        }
        // A top-mode policy uses its own reject bar.
        let strict = Policy(detector: .init(mass: .top, reject: 0.9))
        #expect(check("refrigerator", ["none": 0.8, "refrigerator": 0.2], 1.0, 1.8, 0.7, strict) == .keep)
        guard case .reject = check("refrigerator", ["none": 0.8, "refrigerator": 0.2], 1.0, 1.8, 0.7, .shipped) else {
            Issue.record("shipped didn't reject"); return
        }
    }

    @Test func perDetectorMarginIsByGroup() {
        // A detector "backpack" (group "bag") the classifier leans suitcase on by 0.15.
        let s = ["suitcase": 0.5, "bag": 0.35, "backpack": 0, "none": 0.15]
        #expect(check("backpack", s, 0.45, 0.7, 0.25, .shipped) == .keep)
        guard case .relabel("suitcase", _) = check("backpack", s, 0.45, 0.7, 0.25, Policy(relabelMarginByDetector: ["bag": 0.1])) else {
            Issue.record("bag margin not used"); return
        }
        // Keyed by the raw category: not the group, so no effect.
        #expect(check("backpack", s, 0.45, 0.7, 0.25, Policy(relabelMarginByDetector: ["backpack": 0.1])) == .keep)
        // A stricter global margin wins where the table has no entry.
        let leans = ["sofa": 0.6, "chair": 0.35, "none": 0.05]
        guard case .relabel("sofa", _) = check("chair", leans, 0.8, 0.9, 0.8, .shipped) else {
            Issue.record("shipped didn't relabel"); return
        }
        #expect(check("chair", leans, 0.8, 0.9, 0.8, Policy(relabelMargin: 0.3)) == .keep)
    }

    // MARK: RoomPlan

    @Test func roomPlanDoubtBand() {
        let p = Policy(roomPlan: .init(mass: .sum, reject: 0.85, doubt: 0.5))
        guard case let .doubt(nil, why) = ObjectRecheck.checkRoomPlan(category: "storage", scores: ["none": 0.5, "towel rack": 0.1, "storage": 0.4], policy: p) else {
            Issue.record("not doubted"); return
        }
        #expect(why == "maybe not an item (60% none + fixtures), RoomPlan said storage")
        guard case .reject = ObjectRecheck.checkRoomPlan(category: "storage", scores: ["none": 0.9, "storage": 0.1], policy: p) else {
            Issue.record("not rejected"); return
        }
        #expect(ObjectRecheck.checkRoomPlan(category: "storage", scores: ["none": 0.3, "storage": 0.7], policy: p) == .keep)
        #expect(ObjectRecheck.checkRoomPlan(category: "storage", scores: ["none": 0.6, "storage": 0.4]) == .keep)
        #expect(ObjectRecheck.checkRoomPlan(category: "sink", scores: ["none": 0.6, "sink": 0.4], policy: p) == .keep)  // unchecked
    }

    // MARK: Shipped == before

    @Test func shippedPolicyMatchesTheBenchmarkCases() throws {
        struct Case: Decodable {
            var photo, detector: String
            var dimensions: [Double]
            var embedding: [Float]
        }
        let head = try #require(ObjectClassifierHead.bundled)
        #expect(head.policy == .shipped)  // the bundled json has no policy block yet
        let url = try #require(Bundle.module.url(forResource: "recheck-cases", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        let explicit = Policy(detector: .init(mass: .top, reject: 0.6), roomPlan: .init(mass: .sum, reject: 0.7))
        for c in cases {
            let s = head.scores([c.embedding])
            let (w, h, d) = (c.dimensions[0], c.dimensions[1], c.dimensions[2])
            let before = ObjectRecheck.check(detectorCategory: c.detector, scores: s, width: w, height: h, depth: d)
            #expect(ObjectRecheck.check(detectorCategory: c.detector, scores: s, width: w, height: h, depth: d, policy: explicit) == before, "\(c.photo)")
            #expect(ObjectRecheck.checkRoomPlan(category: c.detector, scores: s, policy: explicit) == ObjectRecheck.checkRoomPlan(category: c.detector, scores: s))
        }
    }

    @Test func recheckAttributesAreNotNamingWords() {
        #expect(ObjectRecheck.isRecheckAttribute(ObjectRecheck.suspectAttribute))
        #expect(ScanObject.isValidAttribute(ObjectRecheck.suspectAttribute))
        let o = RoomNames.Object(category: "chair", attributes: ["ChairType.dining", ObjectRecheck.suspectAttribute])
        #expect(RoomNames.words(of: o).contains("dining"))
        #expect(!RoomNames.words(of: o).contains("suspect"))
        #expect(!RoomNames.words(of: o).contains("recheck"))
        let item = Item(id: 1, owner: "me", roomId: 1, name: "Chair", category: "chair", widthM: 0.5, heightM: 0.9, depthM: 0.5, attributes: ["ChairType.dining", ObjectRecheck.suspectAttribute, "UserRotate.90"])
        #expect(item.modelAttributes == ["ChairType.dining"])
    }
}
