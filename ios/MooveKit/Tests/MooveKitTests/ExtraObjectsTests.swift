import Foundation
import Testing
@testable import MooveKit

/// Points sampled on the surface of an upright box (what LiDAR sees), plus noise.
private func boxPoints(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float, count: Int = 800,
                       seed: UInt64 = 1, outliers: Int = 0) -> [SIMD3<Float>] {
    var rng = SplitMix(seed: seed)
    let t = RoomTransform.at(center, yaw: yaw)
    var pts: [SIMD3<Float>] = (0..<count).map { _ in
        // Random point on one of the four vertical faces or the top.
        let face = Int(rng.next() % 5)
        var p = SIMD3<Float>(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * size
        switch face {
        case 0: p.x = -size.x / 2
        case 1: p.x = size.x / 2
        case 2: p.z = -size.z / 2
        case 3: p.z = size.z / 2
        default: p.y = size.y / 2
        }
        return t.apply(p) + SIMD3(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * 0.01
    }
    for _ in 0..<outliers { pts.append(center + SIMD3(rng.unit() * 6 - 3, rng.unit() * 2, rng.unit() * 6 - 3)) }
    return pts
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() % 1_000_000) / 1_000_000 }
}

@Suite struct BoxFitTests {
    // A bike: 1.7 m long, 1.0 m tall, 0.6 m wide (handlebars), turned 30°, standing on the floor.
    let bike = (center: SIMD3<Float>(1.2, 0.5, -0.8), size: SIMD3<Float>(1.7, 1.0, 0.6), yaw: Float(30 * Double.pi / 180))

    @Test func recoversSizePositionAndYaw() throws {
        let fit = try #require(BoxFit.fit(boxPoints(center: bike.center, size: bike.size, yaw: bike.yaw), floorY: 0))
        #expect(abs(fit.size.x - 1.7) < 0.15)
        #expect(abs(fit.size.y - 1.0) < 0.1)
        #expect(abs(fit.size.z - 0.6) < 0.12)
        #expect(abs(fit.center.x - 1.2) < 0.08 && abs(fit.center.z + 0.8) < 0.08)
        #expect(abs(fit.center.y - 0.5) < 0.06)
        // Yaw is only defined mod 180° for a box.
        let dyaw = abs(remainder(fit.yaw - bike.yaw, .pi))
        #expect(dyaw < 0.1)
    }

    @Test func ignoresStrayDepthSamples() throws {
        let fit = try #require(BoxFit.fit(boxPoints(center: bike.center, size: bike.size, yaw: bike.yaw, outliers: 20), floorY: 0))
        #expect(abs(fit.size.x - 1.7) < 0.25)
    }

    @Test func extendsToTheFloorOnlyWhenClose() throws {
        // A plant whose LiDAR points start 10 cm up (pot rim occluded) still stands on the floor...
        var pts = boxPoints(center: SIMD3(0, 0.6, 0), size: SIMD3(0.4, 1.0, 0.4), yaw: 0)
        let low = try #require(BoxFit.fit(pts, floorY: 0))
        #expect(abs((low.center.y - low.size.y / 2)) < 0.02)
        // ...but a suitcase on top of a 0.9 m dresser does not.
        pts = boxPoints(center: SIMD3(0, 1.2, 0), size: SIMD3(0.5, 0.6, 0.3), yaw: 0)
        let high = try #require(BoxFit.fit(pts, floorY: 0))
        #expect(high.center.y - high.size.y / 2 > 0.8)
    }

    @Test func needsEnoughPoints() {
        #expect(BoxFit.fit([SIMD3(0, 0, 0), SIMD3(1, 1, 1)]) == nil)
    }
}

@Suite struct SightingMergerTests {
    @Test func mergesRepeatedSightingsAndDropsOneOffs() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...4 {
            merger.add(Sighting(label: "bicycle", confidence: 0.6 + Float(seed) * 0.05,
                                points: boxPoints(center: SIMD3(1, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0, count: 300, seed: UInt64(seed))))
        }
        // A one-off phantom across the room.
        merger.add(Sighting(label: "suitcase", confidence: 0.5, points: boxPoints(center: SIMD3(-2, 0.3, 2), size: SIMD3(0.5, 0.6, 0.3), yaw: 0, seed: 9)))
        let results = merger.results()
        #expect(results.count == 1)
        #expect(results.first?.label == "bicycle")
        #expect(results.first?.sightings == 4)
        #expect(abs((results.first?.bestConfidence ?? 0) - 0.8) < 1e-5)
    }

    @Test func keepsTwoBikesApart() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "bicycle", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0, seed: UInt64(seed))))
            merger.add(Sighting(label: "bicycle", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.5, 2.5), size: SIMD3(1.7, 1, 0.6), yaw: 0, seed: UInt64(seed + 10))))
        }
        #expect(merger.results().count == 2)
    }

    @Test func dropsThingsRoomPlanAlreadyFound() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...3 {
            merger.add(Sighting(label: "bench", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.25, 0), size: SIMD3(1.2, 0.5, 0.4), yaw: 0, seed: UInt64(seed))))
        }
        let roomPlanTable = RoomGeometry.Object(id: "t", category: "table", dimensions: SIMD3(1.3, 0.75, 0.6), transform: .at(SIMD3(0, 0.375, 0)))
        #expect(merger.results(excluding: [roomPlanTable]).isEmpty)
        #expect(merger.results().count == 1)
    }

    @Test func capsPointsPerObject() {
        var merger = SightingMerger(floorY: 0)
        merger.maxPointsPerTrack = 500
        for seed in 1...5 {
            merger.add(Sighting(label: "bicycle", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0, seed: UInt64(seed))))
        }
        #expect(merger.tracks.first!.points.count <= 500)
    }
}

/// Recall tuning (#82).
@Suite struct SightingMergerRecallTests {
    let scooter = (center: SIMD3<Float>(1, 0.575, 0), size: SIMD3<Float>(1.1, 1.15, 0.45))

    @Test func keepsABigObjectSeenOnceWithConfidence() {
        var merger = SightingMerger(floorY: 0)
        merger.add(Sighting(label: "scooter", confidence: 0.74, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0)))
        #expect(merger.results().map(\.label) == ["scooter"])
    }

    @Test func dropsSmallOrUnsureOneOffs() {
        var merger = SightingMerger(floorY: 0)
        // Big but unsure.
        merger.add(Sighting(label: "scooter", confidence: 0.45, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0)))
        // Sure but small (a 30 cm vase).
        merger.add(Sighting(label: "vase", confidence: 0.9, points: boxPoints(center: SIMD3(-2, 0.15, 1), size: SIMD3(0.2, 0.3, 0.2), yaw: 0, seed: 3)))
        #expect(merger.results().isEmpty)
    }

    @Test func oneObjectWithTwoLabelsGetsTheStrongerPlausibleOne() {
        // An e-scooter that also scores as a motorcycle in every frame (real: 0.88 vs 0.82).
        var merger = SightingMerger(floorY: 0)
        for seed in 1...3 {
            let pts = boxPoints(center: scooter.center, size: scooter.size, yaw: 0, count: 300, seed: UInt64(seed))
            merger.add(Sighting(label: "motorcycle", confidence: 0.88, points: pts))
            merger.add(Sighting(label: "scooter", confidence: 0.82, points: pts))
        }
        let out = merger.results()
        #expect(out.count == 1)
        // A 1.1 m "motorcycle" is implausible, so the scooter wins despite lower scores.
        #expect(out.first?.label == "scooter")
        #expect(out.first?.sightings == 6)
    }

    @Test func moreEvidenceWinsBetweenPlausibleLabels() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...4 {
            merger.add(Sighting(label: "bicycle", confidence: 0.6, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0, count: 300, seed: UInt64(seed))))
        }
        merger.add(Sighting(label: "scooter", confidence: 0.8, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0, count: 300, seed: 9)))
        #expect(merger.results().map(\.label) == ["bicycle"])
    }

    @Test func keepsThingsStandingOnRoomPlanFurniture() {
        // A monitor on a RoomPlan desk: on top of it, not inside it.
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "monitor", confidence: 0.8, points: boxPoints(center: SIMD3(0, 1.0, 0), size: SIMD3(0.6, 0.45, 0.2), yaw: 0, seed: UInt64(seed))))
        }
        let desk = RoomGeometry.Object(id: "d", category: "table", dimensions: SIMD3(1.4, 0.75, 0.7), transform: .at(SIMD3(0, 0.375, 0)))
        #expect(merger.results(excluding: [desk]).map(\.label) == ["monitor"])
    }

    @Test func roomPlanCategoriesOnlyFillGaps() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            // A chair RoomPlan also found (boxes overlap partly)...
            merger.add(Sighting(label: "chair", confidence: 0.8, points: boxPoints(center: SIMD3(0.25, 0.45, 0), size: SIMD3(0.5, 0.9, 0.5), yaw: 0, seed: UInt64(seed))))
            // ...and one it missed.
            merger.add(Sighting(label: "chair", confidence: 0.8, points: boxPoints(center: SIMD3(3, 0.45, 2), size: SIMD3(0.5, 0.9, 0.5), yaw: 0, seed: UInt64(seed + 5))))
        }
        let roomPlanChair = RoomGeometry.Object(id: "c", category: "chair", dimensions: SIMD3(0.55, 0.9, 0.55), transform: .at(SIMD3(0, 0.45, 0)))
        let out = merger.results(excluding: [roomPlanChair])
        #expect(out.count == 1)
        #expect(abs((out.first?.box.center.x ?? 0) - 3) < 0.2)
    }

    @Test func trackIDsAreStable() {
        var merger = SightingMerger(floorY: 0)
        let a = merger.add(Sighting(label: "scooter", confidence: 0.7, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0)))
        let b = merger.add(Sighting(label: "guitar", confidence: 0.7, points: boxPoints(center: SIMD3(-2, 0.5, 0), size: SIMD3(0.4, 1.0, 0.12), yaw: 0, seed: 4)))
        let a2 = merger.add(Sighting(label: "scooter", confidence: 0.7, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0, seed: 7)))
        #expect(a == 0 && b == 1 && a2 == 0)
    }
}

private let deg = Float.pi / 180

/// Box-fit robustness folded in from #88: MAD outlier rejection before the percentile
/// trim, and a PCA-seeded fine yaw search next to the 3° sweep.
@Suite struct BoxFitRobustnessTests {
    // A carry-on suitcase, plus 26 depth samples (8%) on the wall 3 m behind it:
    // more than the 5% trim can absorb.
    func suitcaseWithBackground() -> [SIMD3<Float>] {
        let obj = boxPoints(center: SIMD3(0, 0.3, 0), size: SIMD3(0.5, 0.6, 0.3), yaw: 0, count: 300)
        let wall = (0..<26).map { SIMD3<Float>(Float($0 % 5) * 0.02, 0.3, -3 - Float($0) * 0.01) }
        return obj + wall
    }

    @Test func madRejectsABackgroundClusterThePercentileTrimKeeps() throws {
        let robust = try #require(BoxFit.fit(suitcaseWithBackground(), floorY: 0))
        #expect(abs(robust.size.x - 0.5) < 0.1 && abs(robust.size.z - 0.3) < 0.1)
        #expect(abs(robust.center.z) < 0.08)
        // Trim only (the pre-#88 fit): the box stretches to the wall.
        let trimOnly = try #require(BoxFit.fit(suitcaseWithBackground(), floorY: 0, madThreshold: nil))
        #expect(max(trimOnly.size.x, trimOnly.size.z) > 1)
    }

    @Test func madKeepsEveryPointOfACleanObject() {
        let pts = boxPoints(center: SIMD3(1, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0.4)
        #expect(BoxFit.rejectOutliers(pts).count == pts.count)
        let strays: [SIMD3<Float>] = [SIMD3(6, 0.5, 0), SIMD3(1, 4, 0), SIMD3(1, 0.5, -5), SIMD3(-4, 3, 4)]
        #expect(BoxFit.rejectOutliers(pts + strays).count == pts.count)
    }

    @Test func madSurvivesIdenticalValues() {
        let pts = Array(repeating: SIMD3<Float>(1, 1, 1), count: 10) + [SIMD3(1, 1, 1.01)]
        #expect(BoxFit.rejectOutliers(pts).count >= 10)
        #expect(BoxFit.median([3, 1, 2, 4]) == 2.5)
    }

    @Test func pcaFindsTheLongAxis() throws {
        for yawDeg: Float in [0, 17, 30, 62, 135] {
            let pts = boxPoints(center: SIMD3(0.4, 0.5, 1), size: SIMD3(1.7, 1, 0.4), yaw: yawDeg * deg)
            let pca = try #require(BoxFit.principalYaw(pts))
            #expect(abs(remainder(pca.yaw - yawDeg * deg, .pi)) < 3 * deg, "yaw \(yawDeg)")
            #expect(pca.anisotropy > 0.5)
        }
        let square = try #require(BoxFit.principalYaw(boxPoints(center: .zero, size: SIMD3(0.5, 1, 0.5), yaw: 0.3)))
        #expect(square.anisotropy < 0.2)
    }

    @Test func refinesAYawBetweenTheSweepSteps() throws {
        // 31.4° sits between the 3° sweep's 30° and 33°.
        let yaw = 31.4 * deg
        let pts = boxPoints(center: SIMD3(1.2, 0.5, -0.8), size: SIMD3(1.7, 1, 0.5), yaw: yaw)
        let refined = try #require(BoxFit.fit(pts, floorY: 0))
        let sweepOnly = try #require(BoxFit.fit(pts, floorY: 0, refineYaw: false))
        let errRefined = abs(remainder(refined.yaw - yaw, .pi / 2))
        let errSweep = abs(remainder(sweepOnly.yaw - yaw, .pi / 2))
        #expect(errRefined < 0.5 * deg)
        #expect(errSweep > 1 * deg)
        // A tighter yaw is a tighter box: the thin side stops absorbing the misalignment.
        #expect(abs(refined.size.z - 0.5) < abs(sweepOnly.size.z - 0.5))
        #expect(abs(refined.size.x - 1.7) < 0.15 && abs(refined.center.x - 1.2) < 0.08 && abs(refined.center.z + 0.8) < 0.08)
    }
}

/// Overlap with exact rotated footprints (from #88's 3D IoU), instead of axis-aligned bounds.
@Suite struct OverlapTests {
    let unit = SIMD3<Float>(1, 1, 1)
    func box(_ c: SIMD3<Float>, _ s: SIMD3<Float>, _ yaw: Float = 0) -> FittedBox { FittedBox(center: c, size: s, yaw: yaw) }

    @Test func exactValues() {
        #expect(abs(SightingMerger.overlap(box(.zero, unit, 0.4), box(.zero, unit, 0.4)) - 1) < 1e-4)
        #expect(abs(SightingMerger.overlap(box(.zero, unit), box(SIMD3(0.5, 0, 0), unit)) - 0.5) < 1e-4)
        #expect(abs(SightingMerger.overlap(box(.zero, unit), box(SIMD3(0, 0.5, 0), unit)) - 0.5) < 1e-4)
        // A unit square and the same square turned 45° share a regular octagon, 2(√2 − 1).
        let oct: Float = 2 * (Float(2).squareRoot() - 1)
        #expect(abs(SightingMerger.overlap(box(.zero, unit), box(.zero, unit, .pi / 4)) - oct) < 1e-3)
        #expect(SightingMerger.overlap(box(.zero, unit), box(SIMD3(3, 0, 0), unit)) == 0)
        #expect(SightingMerger.overlap(box(.zero, unit), box(SIMD3(0, 1.5, 0), unit)) == 0)
    }

    @Test func diagonalNeighboursDoNotOverlap() {
        // Two long boxes side by side at 45°: their axis-aligned bounds overlap by ~60%.
        let sofa = box(SIMD3(0, 0.45, 0), SIMD3(2, 0.9, 0.9), .pi / 4)
        let bike = box(SIMD3(0.53, 0.5, 0.53), SIMD3(1.7, 1, 0.4), .pi / 4)
        #expect(SightingMerger.overlap(bike, sofa, relativeTo: .first) < 0.01)
    }

    @Test func keepsABikeParkedAlongADiagonalSofa() {
        // RoomPlan found the sofa; the bike stands 5 cm from it, both at 45°. With
        // axis-aligned bounds this bike was dropped as a duplicate of the sofa.
        var merger = SightingMerger(floorY: 0)
        for seed in 1...3 {
            merger.add(Sighting(label: "bicycle", confidence: 0.8,
                                points: boxPoints(center: SIMD3(0.53, 0.5, 0.53), size: SIMD3(1.7, 1, 0.4), yaw: .pi / 4, seed: UInt64(seed))))
        }
        let sofa = RoomGeometry.Object(id: "s", category: "sofa", dimensions: SIMD3(2, 0.9, 0.9), transform: .at(SIMD3(0, 0.45, 0), yaw: .pi / 4))
        #expect(merger.results(excluding: [sofa]).map(\.label) == ["bicycle"])
    }
}
