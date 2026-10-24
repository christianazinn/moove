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

/// The names vision actually wrote for Rio's rooms (Oct 24): it files fixtures under "appliance",
/// and a bunk bed's name mentions its ladder.
@Suite struct VoxelVisionNameTests {
    func kind(_ name: String, _ c: String, _ w: Double, _ d: Double, _ h: Double) -> VoxelModels.Kind {
        VoxelModels.kind(VoxelItemSpec(category: c, name: name, widthM: w, depthM: d, heightM: h))
    }

    @Test func visionNamedFixtures() {
        #expect(kind("white two-piece elongated toilet", "appliance", 0.45, 0.71, 0.82) == .toilet)
        #expect(kind("white wall-mounted porcelain bathroom sink with chrome faucet", "appliance", 0.55, 0.44, 0.3) == .sink)
        #expect(kind("white alcove bathtub with apron front", "appliance", 1.4, 0.77, 0.45) == .bathtub)
        #expect(kind("cream fabric shower curtain with rod", "decor", 0.53, 0.5, 1.43) == .screen)
    }

    @Test func accessoriesAreNotFixtures() {
        #expect(kind("toilet paper rolls", "decor", 0.3, 0.2, 0.2) != .toilet)
        #expect(kind("bath mat", "decor", 0.8, 0.5, 0.02) != .bathtub)
        #expect(kind("sink strainer", "kitchenware", 0.1, 0.1, 0.05) != .sink)
        #expect(kind("plastic storage tub", "storage", 0.6, 0.4, 0.35) != .bathtub)
    }

    @Test func aBunkBedWithALadderIsABed() {
        #expect(kind("gray metal twin bunk bed with ladder", "bed", 1.08, 2.06, 1.47) == .bed)
        #expect(kind("white loft bed with ladder", "bed", 1.0, 2.0, 1.6) == .bed)
        #expect(kind("aluminum step ladder", "other", 0.5, 0.1, 1.5) == .ladder)
    }
}
