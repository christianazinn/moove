import Foundation
import Testing
@testable import MooveKit

@Suite struct FitToBoxTests {
    /// FitToBox for a model of `size` whose bounds start at the origin.
    func fit(_ model: SIMD3<Float>, _ box: SIMD3<Float>, turns: Int = 0) -> FitToBox {
        FitToBox.fit(modelMin: .zero, modelMax: model, box: box, extraQuarterTurns: turns)
    }

    // Vectors ported from ModelFitTests (PR #71): same turn/scale rule.

    @Test func alignsLongSidesAndScalesToFit() {
        let f = fit(SIMD3(0.35, 0.37, 0.7), SIMD3(1.4, 0.75, 0.7))
        #expect(f.quarterTurns == 1)
        #expect(abs(f.scale - 2) < 1e-4)
    }

    @Test func keepsOrientationWhenAlreadyAligned() {
        let f = fit(SIMD3(1.6, 0.4, 2.1), SIMD3(1.6, 0.4, 2.1))
        #expect(f.quarterTurns == 0)
        #expect(abs(f.scale - 1) < 1e-5)
    }

    @Test func limitedByTheTightestAxis() {
        #expect(abs(fit(SIMD3(0.3, 2.0, 0.3), SIMD3(0.3, 1.6, 0.3)).scale - 0.8) < 1e-5)
    }

    @Test func userTurnsAddUpAndWrap() {
        let m = SIMD3<Float>(1, 1, 0.5)
        #expect(fit(m, m).quarterTurns == 0)
        #expect(fit(m, m, turns: 2).quarterTurns == 2)
        #expect(fit(m, m, turns: 4).quarterTurns == 0)
        #expect(fit(m, m, turns: 1).scale < 1)
    }

    @Test func negativeTurnsWrap() {
        let m = SIMD3<Float>(1, 1, 0.5)
        #expect(fit(m, m, turns: -1).quarterTurns == 3)
        #expect(fit(m, m, turns: -2).quarterTurns == 2)
        #expect(fit(m, m, turns: -3).quarterTurns == 1)
        #expect(fit(m, m, turns: -5).quarterTurns == 3)
        #expect(abs(fit(m, m, turns: -1).yaw - 3 * .pi / 2) < 1e-5)
    }

    @Test func degenerateSizesDoNotProduceNaN() {
        let f = fit(.zero, SIMD3(1, 1, 1))
        #expect(f.scale.isFinite)
        let t = f.worldTransform(boxSize: SIMD3(1, 1, 1), object: .at(SIMD3(1, 0.5, 2), yaw: 0.3))
        #expect(t.columns.allSatisfy { [$0.x, $0.y, $0.z, $0.w].allSatisfy(\.isFinite) })
        #expect(FitToBox.fit(modelMin: .zero, modelMax: SIMD3(1, 1, 1), box: .zero).scale.isFinite)
    }

    // MARK: - Normalization and placement

    @Test func offCenterModelEndsUpCenteredOnTheBoxBottom() {
        let lo = SIMD3<Float>(3, -2, 5), hi = SIMD3<Float>(4, -1, 5.5), box = SIMD3<Float>(2, 2, 1)
        let f = FitToBox.fit(modelMin: lo, modelMax: hi, box: box)
        #expect(f.offset == SIMD3(-3.5, 2, -5.25))
        let local = f.localTransform(boxSize: box)
        let pts = corners(lo, hi).map(local.apply)
        let pmin = pts.reduce(pts[0]) { pointwiseMin($0, $1) }, pmax = pts.reduce(pts[0]) { pointwiseMax($0, $1) }
        #expect(abs(pmin.y + box.y / 2) < 1e-4)  // bottom on box bottom
        #expect(abs(pmin.x + pmax.x) < 1e-4 && abs(pmin.z + pmax.z) < 1e-4)  // centered
        #expect(abs((pmax.x - pmin.x) - box.x) < 1e-4)  // scaled to the tightest axis (x, 1 m -> 2 m)
    }

    @Test func worldTransformKeepsModelInsideTheBox() {
        let lo = SIMD3<Float>(-0.1, 0.2, -0.3), hi = SIMD3<Float>(0.3, 0.6, 1.1)
        let box = SIMD3<Float>(1.8, 0.8, 0.9), object = RoomTransform.at(SIMD3(2, 0.4, -1), yaw: 0.6)
        for turns in -2...3 {
            let f = FitToBox.fit(modelMin: lo, modelMax: hi, box: box, extraQuarterTurns: turns)
            let world = f.worldTransform(boxSize: box, object: object)
            let inverse = RoomTransform.at(.zero, yaw: -0.6)
            for p in corners(lo, hi).map(world.apply) {
                let q = inverse.apply(p - object.position)  // back to box-local
                #expect(abs(q.x) <= box.x / 2 + 1e-4 && abs(q.y) <= box.y / 2 + 1e-4 && abs(q.z) <= box.z / 2 + 1e-4)
            }
            #expect(abs(world.yaw - remainder(0.6 + f.yaw, 2 * .pi)) < 1e-4)
        }
    }

    func corners(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] { out.append(SIMD3(x, y, z)) } } }
        return out
    }
}
