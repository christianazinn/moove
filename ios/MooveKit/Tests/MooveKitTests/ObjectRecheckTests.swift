import Foundation
import Testing
@testable import MooveKit

@Suite struct ObjectRecheckTests {
    func check(_ det: String, _ scores: [String: Double], _ w: Double, _ h: Double, _ d: Double) -> ObjectRecheck.Verdict {
        ObjectRecheck.check(detectorCategory: det, scores: scores, width: w, height: h, depth: d)
    }

    /// Every category at 0 except the ones given, like the head's output.
    func scores(_ given: [String: Double]) -> [String: Double] {
        var s = Dictionary(uniqueKeysWithValues: (ObjectClassifierHead.bundled?.categories ?? []).map { ($0, 0.0) })
        for (k, v) in given { s[k] = v }
        return s
    }

    @Test func bundledHeadLoads() throws {
        let head = try #require(ObjectClassifierHead.bundled)
        #expect(head.classes.count == 62)
        #expect(head.dimension == 512)
        #expect(head.logitScale == 100)
        for c in ["none", "scooter", "vacuum", "box", "radiator", "shower curtain", "towel rack", "storage"] {
            #expect(head.categories.contains(c))
        }
        // Rows are unit vectors, so a class's own row scores highest for itself.
        let row = Array(head.weights[0..<512])
        #expect(abs(row.reduce(0) { $0 + $1 * $1 } - 1) < 0.01)
        let p = head.classProbabilities(row)
        #expect(p.count == 62)
        #expect(abs(p.reduce(0, +) - 1) < 1e-4)
        #expect(head.classProbabilities([1, 2, 3]).isEmpty)
    }

    @Test func decodesHalfFloats() {
        #expect(ObjectClassifierHead.float(fromHalf: 0x3C00) == 1)
        #expect(ObjectClassifierHead.float(fromHalf: 0xC000) == -2)
        #expect(ObjectClassifierHead.float(fromHalf: 0x3555) == Float(0.333251953125))
        #expect(ObjectClassifierHead.float(fromHalf: 0x0000) == 0)
        #expect(ObjectClassifierHead.float(fromHalf: 0x0001) == Float(pow(2.0, -24.0)))
        #expect(ObjectClassifierHead.float(fromHalf: 0x7C00) == .infinity)
    }

    /// Real iPad scan objects (Core ML embeddings of their auto photos, LiDAR boxes), with what
    /// the benchmark script decided for them: the Swift head + fusion must agree.
    @Test func matchesTheBenchmarkScript() throws {
        struct Case: Decodable {
            var photo, truth, detector, action, category, top: String
            var dimensions: [Double]
            var embedding: [Float]
            var topProbability: Double
        }
        let head = try #require(ObjectClassifierHead.bundled)
        let url = try #require(Bundle.module.url(forResource: "recheck-cases", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        #expect(cases.count >= 10)
        for c in cases {
            let s = head.scores([c.embedding])
            var groups: [String: Double] = [:]
            for (k, v) in s { groups[ObjectRecheck.group(k), default: 0] += v }
            #expect(abs((groups[c.top] ?? 0) - c.topProbability) < 0.01, "\(c.photo) \(c.top)")
            let v = check(c.detector, s, c.dimensions[0], c.dimensions[1], c.dimensions[2])
            switch v {
            case .keep: #expect(c.action == "keep", "\(c.photo): kept, expected \(c.action)")
            case let .relabel(cat, _): #expect(c.action == "relabel" && c.category == cat, "\(c.photo): relabel \(cat), expected \(c.action) \(c.category)")
            case .reject: #expect(c.action == "reject", "\(c.photo): rejected, expected \(c.action)")
            case .unknown: #expect(c.action == "unknown", "\(c.photo): unknown, expected \(c.action)")
            }
        }
        // The headline cases.
        let byPhoto = Dictionary(uniqueKeysWithValues: cases.map { ($0.photo, $0) })
        #expect(byPhoto["2026-10-25T02-05-43_AC5DB808"]?.category == "scooter")  // e-scooter the detector called "vacuum"
        #expect(byPhoto["2026-10-25T02-01-29_644162E4"]?.category == "box")      // cardboard box called "bin"
        #expect(byPhoto["2026-10-24T19-43-54_1162E1D1"]?.action == "reject")     // radiator called "heater"
    }

    @Test func rejectsWallsAndFixtures() {
        guard case let .reject(why) = check("refrigerator", scores(["none": 0.8, "refrigerator": 0.1]), 1.0, 1.8, 0.4) else {
            Issue.record("kept a wall"); return
        }
        #expect(why.contains("not an object"))
        guard case let .reject(why2) = check("heater", scores(["radiator": 0.86, "heater": 0.05]), 0.3, 0.64, 0.2) else {
            Issue.record("kept a radiator"); return
        }
        #expect(why2.contains("radiator"))
        // Not sure enough: keep.
        #expect(check("bag", scores(["none": 0.45, "bag": 0.4]), 0.5, 0.4, 0.3) == .keep)
    }

    @Test func relabelsWhenTheClassifierIsClearlyRight() {
        // e-scooter the detector called a vacuum, box seen whole.
        guard case .relabel("scooter", _) = check("vacuum", scores(["scooter": 0.99]), 0.55, 1.1, 1.0) else {
            Issue.record("not relabeled"); return
        }
        // Too close to call: keep the detector's.
        #expect(check("chair", scores(["chair": 0.4, "sofa": 0.55]), 0.8, 0.9, 0.8) == .keep)
        // A category the classifier doesn't know ("bin") needs ≥ 0.5.
        guard case .relabel("box", _) = check("bin", scores(["box": 0.7]), 0.45, 0.4, 0.45) else {
            Issue.record("bin not relabeled"); return
        }
        #expect(check("bin", scores(["box": 0.45, "trash can": 0.4]), 0.45, 0.4, 0.45) == .keep)
    }

    @Test func sameThingsDontRelabelEachOther() {
        #expect(check("monitor", scores(["television": 0.9]), 0.6, 0.4, 0.2) == .keep)
        #expect(check("backpack", scores(["bag": 0.8]), 0.3, 0.45, 0.2) == .keep)
        // But a detector "bag" the classifier sees as a backpack stays a bag (same group).
        #expect(check("bag", scores(["backpack": 0.8]), 0.3, 0.45, 0.2) == .keep)
    }

    @Test func heightSettlesTableVersusStorage() {
        guard case .relabel("storage", _) = check("lamp", scores(["table": 0.45, "storage": 0.4]), 0.8, 1.2, 0.4) else {
            Issue.record("tall box not storage"); return
        }
        guard case .relabel("table", _) = check("lamp", scores(["table": 0.4, "storage": 0.45]), 0.8, 0.75, 0.6) else {
            Issue.record("low box not table"); return
        }
    }

    @Test func sizeVetoesOnlyClearMismatches() {
        // A "bicycle" relabel on a 30 cm box: far outside 1.5-1.9 m long, and not sure enough.
        #expect(check("toy", scores(["bicycle": 0.8]), 0.3, 0.3, 0.3) == .keep)
        // So sure it wins anyway (partial LiDAR boxes: a side-on scooter measured 26 cm tall).
        guard case .relabel("scooter", _) = check("shoe rack", scores(["scooter": 0.99]), 0.7, 0.26, 0.33) else {
            Issue.record("sure scooter vetoed"); return
        }
        // A bit off isn't clearly off (box measured 0.88 m with a neighbor merged in).
        guard case .relabel("box", _) = check("bin", scores(["box": 0.8]), 0.88, 0.22, 0.27) else {
            Issue.record("box vetoed"); return
        }
        // A 2 m tall "vacuum" nobody backs: unknown, for vision to name.
        guard case .unknown = check("vacuum", scores(["ladder": 0.25, "vacuum": 0.1]), 1.07, 2.08, 0.77) else {
            Issue.record("tall vacuum kept"); return
        }
    }

    @Test func roomPlanObjectsAreOnlyRejectedWhenVerySure() {
        #expect(ObjectRecheck.checkRoomPlan(category: "storage", scores: scores(["chair": 0.9])) == .keep)   // never relabels
        #expect(ObjectRecheck.checkRoomPlan(category: "storage", scores: scores(["none": 0.65, "storage": 0.35])) == .keep)
        guard case .reject = ObjectRecheck.checkRoomPlan(category: "storage", scores: scores(["none": 0.5, "towel rack": 0.25])) else {
            Issue.record("door kept"); return
        }
        #expect(ObjectRecheck.checkRoomPlan(category: "sink", scores: scores(["none": 0.95])) == .keep)      // not rechecked
        #expect(ObjectRecheck.checkRoomPlan(category: "stove", scores: scores(["none": 0.95])) == .keep)
    }

    @Test func emptyScoresKeep() {
        #expect(check("vacuum", [:], 0.3, 1.1, 0.3) == .keep)
    }

    @Test func footprintPriors() {
        #expect(ObjectSanity.fitsFootprint("scooter", width: 0.5, height: 1.15, depth: 1.1) == true)     // e-scooter
        #expect(ObjectSanity.fitsFootprint("scooter", width: 0.3, height: 0.85, depth: 0.75) == true)    // kick scooter
        #expect(ObjectSanity.fitsFootprint("vacuum", width: 0.32, height: 0.09, depth: 0.32) == true)    // robot
        #expect(ObjectSanity.fitsFootprint("vacuum", width: 0.3, height: 2.08, depth: 0.3) == false)
        #expect(ObjectSanity.fitsFootprint("box", width: 0.46, height: 0.4, depth: 0.46) == true)
        #expect(ObjectSanity.fitsFootprint("box", width: 0.95, height: 0.43, depth: 0.54) == false)
        #expect(ObjectSanity.fitsFootprint("box", width: 0.95, height: 0.43, depth: 0.54, factor: 2) == true)
        #expect(ObjectSanity.fitsFootprint("guitar", width: 0.4, height: 1, depth: 0.1) == nil)
        // check() doesn't enforce them (detector boxes are noisy).
        #expect(ObjectSanity.check(category: "box", width: 0.95, height: 0.43, depth: 0.54) == .ok)
    }

    @Test func localSkipsJoinTheNotice() {
        let local = [ScanSkips.Entry(id: "A", why: "not an object (80% sure), detector said vacuum")]
        let only = ScanSkips.combined(nil, local: local)
        #expect(only?.count == 1)
        #expect(only?.summary == "1 object looked wrong and was skipped")
        #expect(ScanSkips.combined(nil, local: []) == nil)
        let event = AgentEvent(id: 9, owner: "me", agent: "scan", kind: .error, message: "Skipped 2 scanned object(s)",
                               refTable: "scan", refId: 4, dataJson: #"[{"id":"B","why":"width_m=NaN"},{"id":"C","why":"x"}]"#)
        let both = ScanSkips.combined(ScanSkips(event), local: local)
        #expect(both?.count == 3)
        #expect(both?.entries.map(\.id) == ["A", "B", "C"])
    }
}
