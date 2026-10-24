import Testing
@testable import MooveKit

@Suite struct ModelFitTests {
    @Test func alignsLongSidesAndScalesToFit() {
        // Captured desk is long along z; RoomPlan's desk box is long along x.
        let fit = ModelFit.fit(model: SIMD3(0.35, 0.37, 0.7), box: SIMD3(1.4, 0.75, 0.7))
        #expect(fit.quarterTurns == 1)
        #expect(abs(fit.scale - 2) < 1e-4)  // 0.7 → 1.4, 0.35 → 0.7, 0.37 → 0.74 all fit
    }

    @Test func keepsOrientationWhenAlreadyAligned() {
        let fit = ModelFit.fit(model: SIMD3(1.6, 0.4, 2.1), box: SIMD3(1.6, 0.4, 2.1))
        #expect(fit.quarterTurns == 0)
        #expect(abs(fit.scale - 1) < 1e-5)
    }

    @Test func limitedByTheTightestAxis() {
        // A tall lamp model in a short box: height decides the scale.
        let fit = ModelFit.fit(model: SIMD3(0.3, 2.0, 0.3), box: SIMD3(0.3, 1.6, 0.3))
        #expect(abs(fit.scale - 0.8) < 1e-5)
    }

    @Test func userTurnsAddUpAndWrap() {
        let base = ModelFit.fit(model: SIMD3(1, 1, 0.5), box: SIMD3(1, 1, 0.5))
        #expect(base.quarterTurns == 0)
        #expect(ModelFit.fit(model: SIMD3(1, 1, 0.5), box: SIMD3(1, 1, 0.5), extraQuarterTurns: 2).quarterTurns == 2)
        #expect(ModelFit.fit(model: SIMD3(1, 1, 0.5), box: SIMD3(1, 1, 0.5), extraQuarterTurns: 4).quarterTurns == 0)
        // An odd user turn on a non-square item swaps the sides, so it gets smaller to fit.
        #expect(ModelFit.fit(model: SIMD3(1, 1, 0.5), box: SIMD3(1, 1, 0.5), extraQuarterTurns: 1).scale < 1)
    }

    @Test func degenerateSizesDoNotProduceNaN() {
        let fit = ModelFit.fit(model: SIMD3(0, 0, 0), box: SIMD3(1, 1, 1))
        #expect(fit.scale.isFinite)
    }
}
