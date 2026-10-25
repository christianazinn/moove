import Foundation
import Testing
@testable import MooveKit

/// The recheck pieces together: clutter prototypes (R5-2), the fitted policy's doubt band (R9),
/// the relabel guardrails (R5-1) and the detector's label history (R6B).
@Suite struct ObjectRecheckCombinedTests {
    typealias Policy = ObjectRecheck.Policy

    /// Every bundled category at 0 except the ones given.
    func scores(_ given: [String: Double]) -> [String: Double] {
        var s = Dictionary(uniqueKeysWithValues: (ObjectClassifierHead.bundled?.categories ?? []).map { ($0, 0.0) })
        for (k, v) in given { s[k] = v }
        return s
    }

    let fitted = Policy(detector: .init(mass: .nonePlusMaxFixture, reject: 0.74, doubt: 0.3),
                        roomPlan: .init(mass: .sum, reject: 0.78, doubt: 0.3), relabelMargin: 0.3)

    func history(_ labels: [String: Int], flips: Int = 0) -> SightingMerger.LabelHistory {
        SightingMerger.LabelHistory(labels: labels.mapValues { .init(views: $0, sightings: $0, totalConfidence: Float($0) * 0.6, bestConfidence: 0.6) },
                                    flips: flips)
    }

    // MARK: Clutter

    @Test func sureClutterIsRejected() {
        let v = ObjectRecheck.check(detectorCategory: "vacuum", scores: scores(["clutter": 0.85, "vacuum": 0.005, "none": 0.08, "lamp": 0.065]),
                                    width: 0.3, height: 1.2, depth: 0.3)
        guard case let .reject(why) = v else { Issue.record("kept a mop: \(v)"); return }
        #expect(why.contains("clutter"))
    }

    @Test func clutterNeverRejectsARealVacuumOrWhatTheDetectorSaid() {
        // Vacuum mass >= 0.1 keeps it out of the reject; clutter on top still hands it to vision.
        let v = ObjectRecheck.check(detectorCategory: "vacuum", scores: scores(["clutter": 0.7, "vacuum": 0.12, "chair": 0.18]),
                                    width: 0.3, height: 1.1, depth: 0.3)
        #expect(v == .unknown(reason: "looks like clutter (70%), detector said vacuum"))
        // The classifier backs the detector's category (>= 0.5 once clutter is set aside): kept.
        #expect(ObjectRecheck.check(detectorCategory: "lamp", scores: scores(["clutter": 0.55, "lamp": 0.4, "none": 0.05]),
                                    width: 0.3, height: 1.5, depth: 0.3) == .keep)
    }

    @Test func clutterOnTopGoesToVisionAsOther() {
        let v = ObjectRecheck.check(detectorCategory: "vacuum", scores: scores(["clutter": 0.6, "chair": 0.3, "none": 0.1]),
                                    width: 0.3, height: 1.2, depth: 0.3)
        guard case .unknown = v else { Issue.record("expected other: \(v)"); return }
    }

    @Test func clutterIsSetAsideForTheOtherRules() {
        // Without clutter, chair 0.75 / none 0.25: chair is kept, not doubted at none 0.25.
        let s = scores(["clutter": 0.2, "chair": 0.6, "none": 0.2])
        #expect(ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.5, height: 0.9, depth: 0.5, policy: fitted) == .keep)
        // RoomPlan objects ignore clutter: none 0.35 -> 0.7 of the rest is doubt, not reject.
        let r = ObjectRecheck.checkRoomPlan(category: "storage", scores: scores(["clutter": 0.5, "none": 0.35, "storage": 0.15]), policy: fitted)
        guard case .doubt(nil, _) = r else { Issue.record("expected doubt: \(r)"); return }
        #expect(ObjectRecheck.withoutClutter(["a": 0.5, "b": 0.5]) == ["a": 0.5, "b": 0.5])
    }

    // MARK: Doubt band through the other overloads

    @Test func doubtFlowsThroughTheHistoryCheck() {
        let s = scores(["chair": 0.55, "none": 0.4, "table": 0.05])
        let steady = history(["chair": 4])
        let v = ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.5, height: 0.9, depth: 0.5, policy: fitted, history: steady)
        guard case .doubt(nil, _) = v else { Issue.record("expected doubt: \(v)"); return }
        // No history: the same as the plain check.
        #expect(ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.5, height: 0.9, depth: 0.5, policy: fitted, history: nil)
            == ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.5, height: 0.9, depth: 0.5, policy: fitted))
        // A flipping detector plus non-item >= 0.4 still rejects (it overrides the doubt).
        let flipping = history(["chair": 1, "table": 1, "bin": 1], flips: 2)
        guard case .reject = ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.5, height: 0.9, depth: 0.5,
                                                 policy: fitted, history: flipping) else {
            Issue.record("flip reject lost"); return
        }
    }

    @Test func historyPoolingLeavesClutterAlone() {
        let s = scores(["clutter": 0.3, "chair": 0.35, "table": 0.35])
        let p = ObjectRecheck.pooled(s, with: history(["chair": 3]), beta: 1, alpha: 0.5)
        #expect(abs((p["clutter"] ?? 0) - 0.3) < 1e-9)
        #expect((p["chair"] ?? 0) > (p["table"] ?? 0))
        #expect(abs(p.values.reduce(0, +) - 1) < 1e-9)
    }

    // MARK: Guardrails under the fitted margin

    @Test func relabelNeedsMarginAndFloor() {
        // 0.25 ahead: enough for the shipped 0.2, not for the fitted 0.3.
        let s = scores(["sofa": 0.6, "chair": 0.35, "table": 0.05])
        guard case .relabel("sofa", _) = ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.9, height: 0.9, depth: 0.9) else {
            Issue.record("shipped margin should relabel"); return
        }
        #expect(ObjectRecheck.check(detectorCategory: "chair", scores: s, width: 0.9, height: 0.9, depth: 0.9, policy: fitted) == .keep)
        // 0.35 ahead but under the 0.4 floor: kept.
        let low = scores(["storage": 0.37, "lamp": 0.02, "none": 0.2, "box": 0.2, "chair": 0.21])
        #expect(ObjectRecheck.check(detectorCategory: "lamp", scores: low, width: 0.4, height: 1.6, depth: 0.4, policy: fitted) == .keep)
    }
}
