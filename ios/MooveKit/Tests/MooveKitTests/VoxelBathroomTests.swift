import Testing
@testable import MooveKit

/// RoomPlan's bathroom fixtures have their own shapes: by size alone a toilet drew as a
/// dresser and a sink or bathtub as a plain box (Rio's bathroom scan, Oct 24).
@Suite struct VoxelBathroomTests {
    func spec(_ c: String, _ w: Double, _ d: Double, _ h: Double, name: String? = nil) -> VoxelItemSpec {
        VoxelItemSpec(category: c, name: name ?? c.capitalized, widthM: w, depthM: d, heightM: h)
    }

    @Test func fixturesRouteToTheirOwnKinds() {
        #expect(VoxelModels.kind(spec("toilet", 0.45, 0.71, 0.82)) == .toilet)
        #expect(VoxelModels.kind(spec("sink", 0.55, 0.44, 0.3)) == .sink)
        #expect(VoxelModels.kind(spec("bathtub", 1.4, 0.77, 0.45)) == .bathtub)
    }

    @Test func toiletHasATankBehindALowerBowl() {
        let g = VoxelModels.build(spec("toilet", 0.45, 0.71, 0.82))
        func top(_ z: Int) -> Int { (0..<g.ny).last { y in (0..<g.nx).contains { g[$0, y, z] != nil } } ?? -1 }
        let back = top(1), front = top(g.nz - 2)
        #expect(back == g.ny - 1, "tank reaches the top")
        #expect(front < g.ny * 2 / 3, "bowl is lower than the tank (\(front) of \(g.ny))")
        // the bowl is open: the middle of the bowl at rim height is empty or water
        let mid = g.nz * 2 / 3
        #expect((0..<g.ny).contains { g[g.nx / 2, $0, mid] == nil })
    }

    @Test func tubAndSinkAreHollow() {
        for s in [spec("bathtub", 1.4, 0.77, 0.45), spec("sink", 0.55, 0.44, 0.3)] {
            let g = VoxelModels.build(s)
            #expect(g[g.nx / 2, g.ny - 1, g.nz / 2] == nil, "\(s.category) open in the middle")
            #expect(g[0, g.ny - 1, g.nz / 2] != nil, "\(s.category) has a rim")
        }
    }
}
