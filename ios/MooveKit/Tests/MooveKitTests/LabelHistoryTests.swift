import Foundation
import Testing
@testable import MooveKit

/// A flat-ish slab of LiDAR points (enough for `BoxFit`), centered at `center`.
private func slab(_ center: SIMD3<Float>, size: SIMD3<Float> = SIMD3(0.5, 1.0, 0.4), jitter: Float = 0) -> [SIMD3<Float>] {
    var pts: [SIMD3<Float>] = []
    for i in 0..<6 {
        for j in 0..<6 {
            for k in 0..<2 {
                let u = Float(i) / 5 - 0.5, v = Float(j) / 5 - 0.5, w = Float(k) - 0.5
                pts.append(center + SIMD3(u * size.x + jitter, v * size.y, w * size.z))
            }
        }
    }
    return pts
}

@Suite struct LabelHistoryTests {
    typealias History = SightingMerger.LabelHistory

    /// One physical object the detector calls "vacuum" 3x and "scooter" 2x (separate views),
    /// interleaved, plus a single "ladder" glimpse that never confirms on its own.
    private func flippingMerger() -> SightingMerger {
        var m = SightingMerger(floorY: 0)
        let c = SIMD3<Float>(1, 0.5, -1)
        let labels = ["vacuum", "scooter", "vacuum", "scooter", "vacuum", "ladder"]
        for (i, label) in labels.enumerated() {
            m.add(Sighting(label: label, confidence: label == "vacuum" ? 0.6 : 0.5, points: slab(c, jitter: Float(i) * 0.01),
                           camera: SIMD3(1, 1.4, 1), time: Double(i)))
        }
        return m
    }

    @Test func mergeKeepsTheLosingLabels() throws {
        let results = flippingMerger().results()
        #expect(results.count == 1)
        let t = try #require(results.first)
        #expect(t.label == "vacuum")
        let h = t.labelHistory
        #expect(h.labels["vacuum"]?.views == 3)
        #expect(h.labels["scooter"]?.views == 2)
        #expect(h.labels["vacuum"]?.totalConfidence ?? 0 > 1.79)
        // The unconfirmed one-off is history only: it doesn't count as a view of the object.
        #expect(h.labels["ladder"]?.views == 1)
        #expect(t.views == 5)
        #expect(h.views == 6)
        #expect(h.distinct == 3)
        // vacuum scooter vacuum scooter vacuum ladder: every sighting changed the label.
        #expect(h.flips == 5)
        #expect(h.top == "vacuum")
        #expect(abs(h.consensus - 0.5) < 1e-9)
    }

    @Test func steadyObjectHasFullConsensus() throws {
        var m = SightingMerger(floorY: 0)
        for i in 0..<4 {
            m.add(Sighting(label: "lamp", confidence: 0.7, points: slab(SIMD3(0, 0.8, 0), size: SIMD3(0.3, 1.6, 0.3)),
                           camera: SIMD3(0, 1.4, 2), time: Double(i)))
        }
        let h = try #require(m.results().first).labelHistory
        #expect(h.labels.keys.sorted() == ["lamp"])
        #expect(h.flips == 0)
        #expect(h.consensus == 1)
        #expect(h.views == 4)
    }

    @Test func historyIsStoredWithTheScanAndOldScansStillDecode() throws {
        let h = History(labels: ["vacuum": .init(views: 3, sightings: 4, totalConfidence: 2.1, bestConfidence: 0.8)], flips: 1)
        let o = RoomGeometry.Object(id: "A", category: "vacuum", dimensions: SIMD3(0.3, 1.1, 0.3), transform: .identity,
                                    measured: .init(depth: 0.12, camera: SIMD3(1, 1.4, 0), labelHistory: h))
        let back = try JSONDecoder().decode(RoomGeometry.Object.self, from: JSONEncoder().encode(o))
        #expect(back == o)
        #expect(back.measured?.labelHistory?.labels["vacuum"]?.views == 3)

        var plain = o
        plain.measured = nil
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("measured"))
        let old = try JSONDecoder().decode(RoomGeometry.Object.self, from: Data(json.utf8))
        #expect(old.measured == nil)
    }

    @Test func noHistoryIsTheShippedCheck() {
        let cases: [(String, [String: Double])] = [
            ("vacuum", ["scooter": 0.5, "vacuum": 0.25, "none": 0.25]),
            ("refrigerator", ["none": 0.7, "refrigerator": 0.3]),
            ("lamp", ["lamp": 0.8, "none": 0.2]),
        ]
        for (det, s) in cases {
            #expect(ObjectRecheck.check(detectorCategory: det, scores: s, width: 0.3, height: 1.1, depth: 0.3, history: nil)
                == ObjectRecheck.check(detectorCategory: det, scores: s, width: 0.3, height: 1.1, depth: 0.3))
        }
    }

    @Test func steadyDetectorLabelOutvotesAMarginalRelabel() {
        let s = ["scooter": 0.5, "vacuum": 0.25, "none": 0.25]
        // Without history the classifier's 0.25 margin relabels the vacuum as a scooter...
        if case .relabel("scooter", _) = ObjectRecheck.check(detectorCategory: "vacuum", scores: s, width: 0.3, height: 1.1, depth: 0.3) {} else {
            Issue.record("expected the shipped check to relabel")
        }
        // ...but five views all saying vacuum keep it.
        let h = History(labels: ["vacuum": .init(views: 5, sightings: 6, totalConfidence: 4, bestConfidence: 0.8)])
        #expect(ObjectRecheck.check(detectorCategory: "vacuum", scores: s, width: 0.3, height: 1.1, depth: 0.3, history: h) == .keep)
        // The pool never moves the non-item mass.
        let p = ObjectRecheck.pooled(s, with: h, beta: 1, alpha: 0.5)
        #expect(abs((p["none"] ?? 0) - 0.25) < 1e-12)
        #expect(abs(p.values.reduce(0, +) - 1) < 1e-9)
    }

    @Test func flippingLabelsPlusANonItemLeanRejects() {
        let s = ["none": 0.45, "refrigerator": 0.3, "mirror": 0.25]
        let steady = History(labels: ["refrigerator": .init(views: 4, sightings: 4, totalConfidence: 2.4, bestConfidence: 0.7)])
        let flipping = History(labels: [
            "refrigerator": .init(views: 2, sightings: 2, totalConfidence: 1.2, bestConfidence: 0.6),
            "mirror": .init(views: 1, sightings: 1, totalConfidence: 0.5, bestConfidence: 0.5),
            "storage": .init(views: 1, sightings: 1, totalConfidence: 0.5, bestConfidence: 0.5),
        ], flips: 3)
        // 45% none isn't enough on its own (the bar is 60%), nor with a detector that never wavered...
        #expect(ObjectRecheck.check(detectorCategory: "refrigerator", scores: s, width: 0.8, height: 1.8, depth: 0.7) == .keep)
        #expect(ObjectRecheck.check(detectorCategory: "refrigerator", scores: s, width: 0.8, height: 1.8, depth: 0.7, history: steady) == .keep)
        // ...but a "refrigerator" that was also a mirror and storage is a phantom (a window, a wall).
        if case .reject = ObjectRecheck.check(detectorCategory: "refrigerator", scores: s, width: 0.8, height: 1.8, depth: 0.7, history: flipping) {} else {
            Issue.record("expected a reject")
        }
        // A flipping detector alone never throws a real object away: the classifier must lean non-item.
        let sure = ["none": 0.1, "refrigerator": 0.6, "mirror": 0.3]
        if case .reject = ObjectRecheck.check(detectorCategory: "refrigerator", scores: sure, width: 0.8, height: 1.8, depth: 0.7, history: flipping) {
            Issue.record("rejected a real object")
        }
    }
}
