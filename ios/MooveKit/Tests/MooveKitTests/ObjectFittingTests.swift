import Foundation
import Testing
@testable import MooveKit

/// Points on the faces and top of an upright box, plus a little noise.
private func surfacePoints(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float, count: Int = 800, seed: UInt64 = 1) -> [SIMD3<Float>] {
    var rng = Rng(seed: seed)
    let t = RoomTransform.at(center, yaw: yaw)
    return (0..<count).map { _ in
        var p = SIMD3<Float>(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * size
        switch rng.next() % 5 {
        case 0: p.x = -size.x / 2
        case 1: p.x = size.x / 2
        case 2: p.z = -size.z / 2
        case 3: p.z = size.z / 2
        default: p.y = size.y / 2
        }
        return t.apply(p) + SIMD3(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * 0.01
    }
}

private struct Rng {
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

private let deg = Float.pi / 180

@Suite struct MADTests {
    @Test func dropsFarPointsAndKeepsTheObject() {
        let obj = surfacePoints(center: SIMD3(1, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0)
        let strays: [SIMD3<Float>] = [SIMD3(6, 0.5, 0), SIMD3(1, 4, 0), SIMD3(1, 0.5, -5), SIMD3(-4, 3, 4)]
        let kept = ObjectFitting.rejectOutliers(obj + strays)
        #expect(kept.count == obj.count)
        #expect(!strays.contains { s in kept.contains(s) })
    }

    @Test func rangeTestKeepsTheNearSurfaceBand() {
        let camera = SIMD3<Float>(0, 1.4, 0)
        // Object 2 m away, a few hits on the wall 5 m away.
        let obj = surfacePoints(center: SIMD3(0, 0.5, -2), size: SIMD3(0.5, 0.6, 0.3), yaw: 0, count: 200)
        let wall = (0..<12).map { SIMD3<Float>(Float($0) * 0.05, 1, -5) }
        let kept = ObjectFitting.rejectRangeOutliers(obj + wall, from: camera)
        #expect(kept.count == obj.count)
    }

    @Test func identicalValuesDoNotDivideByZero() {
        let pts = Array(repeating: SIMD3<Float>(1, 1, 1), count: 10) + [SIMD3(1, 1, 1.01)]
        #expect(ObjectFitting.rejectOutliers(pts).count >= 10)
        #expect(ObjectFitting.median([3, 1, 2, 4]) == 2.5)
    }
}

@Suite struct PCAYawTests {
    @Test func findsTheLongAxis() throws {
        for yawDeg: Float in [0, 17, 30, 62, 135] {
            let pts = surfacePoints(center: SIMD3(0.4, 0.5, 1), size: SIMD3(1.7, 1, 0.4), yaw: yawDeg * deg)
            let pca = try #require(ObjectFitting.principalYaw(pts))
            #expect(abs(remainder(pca.yaw - yawDeg * deg, .pi)) < 3 * deg, "yaw \(yawDeg)")
            #expect(pca.anisotropy > 0.5)
        }
    }

    @Test func squareFootprintIsNotElongated() throws {
        let pca = try #require(ObjectFitting.principalYaw(surfacePoints(center: .zero, size: SIMD3(0.5, 1, 0.5), yaw: 0.3)))
        #expect(pca.anisotropy < 0.2)
    }

    @Test func yawDifferenceIsModNinety() {
        #expect(abs(ObjectFitting.yawDifference(0, .pi / 2)) < 1e-5)
        #expect(abs(ObjectFitting.yawDifference(10 * deg, 95 * deg) - 5 * deg) < 1e-5)
    }
}

@Suite struct ObjectFittingFitTests {
    @Test func recoversOffGridYawBetterThanTheSweep() throws {
        // 31.4° sits between the 3° sweep's steps; the PCA seed refines it.
        let yaw = 31.4 * deg
        let pts = surfacePoints(center: SIMD3(1.2, 0.5, -0.8), size: SIMD3(1.7, 1, 0.5), yaw: yaw)
        let fit = try #require(ObjectFitting.fit(pts, floorY: 0))
        #expect(ObjectFitting.yawDifference(fit.yaw, yaw) < 1 * deg)
        #expect(abs(fit.size.x - 1.7) < 0.15 && abs(fit.size.z - 0.5) < 0.1 && abs(fit.size.y - 1) < 0.1)
        #expect(abs(fit.center.x - 1.2) < 0.08 && abs(fit.center.z + 0.8) < 0.08)
    }

    @Test func madRejectionShrinksAGrossOutlierCluster() throws {
        // 8% of points are background 3 m behind: past BoxFit's 5% trim.
        let obj = surfacePoints(center: SIMD3(0, 0.3, 0), size: SIMD3(0.5, 0.6, 0.3), yaw: 0, count: 300)
        let bg = (0..<26).map { SIMD3<Float>(Float($0 % 5) * 0.02, 0.3, -3 - Float($0) * 0.01) }
        let plain = try #require(BoxFit.fit(obj + bg, floorY: 0))
        let robust = try #require(ObjectFitting.fit(obj + bg, floorY: 0))
        #expect(max(plain.size.x, plain.size.z) > 1)
        #expect(abs(robust.size.x - 0.5) < 0.1 && abs(robust.size.z - 0.3) < 0.1)
    }

    @Test func needsEnoughPoints() {
        #expect(ObjectFitting.fit([SIMD3(0, 0, 0), SIMD3(1, 1, 1)]) == nil)
    }
}

@Suite struct IoUTests {
    let unit = SIMD3<Float>(1, 1, 1)

    @Test func identicalBoxesAreOne() {
        #expect(abs(ObjectFitting.iou(center: .zero, size: unit, yaw: 0.4, center: .zero, size: unit, yaw: 0.4) - 1) < 1e-4)
    }

    @Test func halfShiftedBoxesAreAThird() {
        let v = ObjectFitting.iou(center: .zero, size: unit, yaw: 0, center: SIMD3(0.5, 0, 0), size: unit, yaw: 0)
        #expect(abs(v - 1.0 / 3) < 1e-4)
        // Shifted vertically instead: same answer.
        let h = ObjectFitting.iou(center: .zero, size: unit, yaw: 0, center: SIMD3(0, 0.5, 0), size: unit, yaw: 0)
        #expect(abs(h - 1.0 / 3) < 1e-4)
    }

    @Test func rotatedSquareOverlap() {
        // A unit square and the same square turned 45° overlap in a regular octagon:
        // area 2(√2 − 1) ≈ 0.8284, so IoU = 0.8284 / (2 − 0.8284).
        let v = ObjectFitting.iou(center: .zero, size: unit, yaw: 0, center: .zero, size: unit, yaw: .pi / 4)
        let oct: Float = 2 * (Float(2).squareRoot() - 1)
        #expect(abs(v - oct / (2 - oct)) < 1e-3)
    }

    @Test func disjointAndStackedAreZero() {
        #expect(ObjectFitting.iou(center: .zero, size: unit, yaw: 0, center: SIMD3(3, 0, 0), size: unit, yaw: 0) == 0)
        #expect(ObjectFitting.iou(center: .zero, size: unit, yaw: 0, center: SIMD3(0, 1.5, 0), size: unit, yaw: 0) == 0)
    }

    @Test func smallThingOnABigTableIsNotADuplicate() {
        let table = RoomGeometry.Object(id: "t", category: "table", dimensions: SIMD3(1.6, 0.75, 0.9), transform: .at(SIMD3(0, 0.375, 0), yaw: 0.3))
        let laptop = FittedBox(center: SIMD3(0.1, 0.77, 0), size: SIMD3(0.35, 0.03, 0.25), yaw: 0.3)
        let bench = FittedBox(center: SIMD3(0, 0.35, 0), size: SIMD3(1.5, 0.7, 0.8), yaw: 0.35)
        #expect(!ObjectFitting.isDuplicate(laptop, of: [table]))
        #expect(ObjectFitting.isDuplicate(bench, of: [table]))
    }
}

@Suite struct TrackFuserTests {
    let bike = (center: SIMD3<Float>(1, 0.5, 0), size: SIMD3<Float>(1.7, 1, 0.6))

    func bikeSighting(_ seed: UInt64, confidence: Float = 0.7, at center: SIMD3<Float>? = nil) -> Sighting {
        Sighting(label: "bicycle", confidence: confidence,
                 points: surfacePoints(center: center ?? bike.center, size: bike.size, yaw: 0, count: 300, seed: seed))
    }

    @Test func confirmsAfterThreeFramesOverTwoSeconds() throws {
        var fuser = TrackFuser(floorY: 0)
        fuser.add(bikeSighting(1), at: 0)
        fuser.add(bikeSighting(2), at: 0.5)
        #expect(fuser.confirmed().isEmpty)  // two frames
        fuser.add(bikeSighting(3, confidence: 0.9), at: 1.0)
        #expect(fuser.confirmed().isEmpty)  // three frames but only 1 s
        fuser.add(bikeSighting(4), at: 2.5)
        let t = try #require(fuser.confirmed().first)
        #expect(t.sightings == 4 && t.duration == 2.5)
        #expect(abs(t.bestConfidence - 0.9) < 1e-6)
        #expect(t.mergerTrack.sightings == 4)
    }

    @Test func sameFrameCountsOnce() {
        var fuser = TrackFuser(floorY: 0)
        for (i, time) in [0, 0, 0, 2.5].enumerated() { fuser.add(bikeSighting(UInt64(i + 1)), at: time) }
        #expect(fuser.tracks.count == 1)
        #expect(fuser.tracks[0].sightings == 2)
        #expect(fuser.confirmed().isEmpty)
    }

    @Test func farSightingsStartANewTrack() {
        var fuser = TrackFuser(floorY: 0)
        fuser.add(bikeSighting(1), at: 0)
        fuser.add(bikeSighting(2, at: bike.center + SIMD3(0.8, 0, 0)), at: 1)  // > 0.5 m off
        fuser.add(Sighting(label: "suitcase", confidence: 0.6,
                           points: surfacePoints(center: bike.center, size: SIMD3(0.5, 0.6, 0.3), yaw: 0, seed: 7)), at: 2)
        #expect(fuser.tracks.count == 3)
    }

    @Test func dropsWhatRoomPlanFoundBy3DIoU() {
        var fuser = TrackFuser(floorY: 0)
        for (i, time) in [0.0, 1, 2, 3].enumerated() {
            fuser.add(Sighting(label: "bench", confidence: 0.7,
                               points: surfacePoints(center: SIMD3(0, 0.25, 0), size: SIMD3(1.2, 0.5, 0.4), yaw: 0, seed: UInt64(i + 1))), at: time)
        }
        let table = RoomGeometry.Object(id: "t", category: "table", dimensions: SIMD3(1.3, 0.75, 0.6), transform: .at(SIMD3(0, 0.375, 0)))
        #expect(fuser.confirmed().count == 1)
        #expect(fuser.confirmed(excluding: [table]).isEmpty)
    }
}
