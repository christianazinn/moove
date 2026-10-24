import Testing
@testable import MooveKit

@Suite struct VoxelSeatingTests {
    static let benchNames = ["Bench", "Storage bench", "Storage bench with cubbies", "Upholstered bench", "Tufted bed bench",
                             "Shoe bench", "Picnic bench", "Garden bench", "Metal bench", "Oak slab bench", "Grey bench"]
    static let ottomanNames = ["Ottoman", "Tufted ottoman", "Round ottoman", "Drum ottoman", "Storage ottoman",
                               "Leather ottoman", "Footstool"]

    func spec(_ category: String, _ name: String, _ w: Double, _ d: Double, _ h: Double) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h)
    }

    /// Occupancy only (ignores per-voxel jitter, which differs with every name).
    func mask(_ g: VoxelGrid) -> [Bool] {
        var out: [Bool] = []
        for y in 0..<g.ny { for z in 0..<g.nz { for x in 0..<g.nx { out.append(g[x, y, z] != nil) } } }
        return out
    }

    func colors(_ g: VoxelGrid) -> Set<VoxelColor> {
        var out = Set<VoxelColor>()
        for y in 0..<g.ny { for z in 0..<g.nz { for x in 0..<g.nx { if let c = g[x, y, z] { out.insert(c) } } } }
        return out
    }

    func checkBuild(_ s: VoxelItemSpec, _ dims: (Int, Int, Int)) {
        let (g, surfaces) = VoxelModels.buildWithSurfaces(s)
        #expect(g.nx == dims.0 && g.ny == dims.1 && g.nz == dims.2, "\(s.name) dims \(g.nx)x\(g.ny)x\(g.nz)")
        #expect(g.filledCount > 0, "\(s.name) empty")
        #expect(g.cells.allSatisfy { $0 == 0 || $0 & 0x1000000 != 0 })
        #expect(!surfaces.isEmpty, "\(s.name) has no surface")
        for f in surfaces {
            #expect(f.x0 >= 0 && f.z0 >= 0 && f.x1 <= g.nx && f.z1 <= g.nz && f.width > 0 && f.depth > 0 && f.y <= g.ny, "\(s.name) surface \(f)")
        }
    }

    @Test func routesToSeatingKinds() {
        for n in Self.benchNames { #expect(VoxelModels.kind(spec("furniture", n, 1.2, 0.4, 0.45)) == .bench, "\(n)") }
        for n in Self.ottomanNames { #expect(VoxelModels.kind(spec("furniture", n, 0.6, 0.6, 0.42)) == .ottoman, "\(n)") }
    }

    @Test func benchesBuildWithinBoundsAtAnySize() {
        for n in Self.benchNames {
            checkBuild(spec("bench", n, 0, 0, 0), (24, 9, 8)) // default 1.2 x 0.4 x 0.45 m
            checkBuild(spec("bench", n, 0.05, 0.05, 0.05), (8, 4, 4)) // min dims
            checkBuild(spec("bench", n, 3.0, 1.0, 1.0), (60, 20, 20))
            checkBuild(spec("bench", n, 8.0, 0.3, 0.2), (160, 4, 6))
        }
    }

    @Test func ottomansBuildWithinBoundsAtAnySize() {
        for n in Self.ottomanNames {
            checkBuild(spec("ottoman", n, 0, 0, 0), (12, 8, 12))
            checkBuild(spec("ottoman", n, 0.05, 0.05, 0.05), (5, 4, 5))
            checkBuild(spec("ottoman", n, 1.6, 1.2, 0.6), (32, 12, 24))
        }
    }

    @Test func benchVariantsDiffer() {
        let names = ["Bench", "Storage bench", "Storage bench with cubbies", "Upholstered bench", "Tufted bench",
                     "Shoe bench", "Picnic bench", "Garden bench", "Metal bench", "Oak slab bench"]
        for size in [(1.2, 0.4, 0.45), (1.6, 0.6, 0.85)] {
            let masks = names.map { mask(VoxelModels.build(spec("bench", $0, size.0, size.1, size.2))) }
            for i in masks.indices { for j in masks.indices where j > i { #expect(masks[i] != masks[j], "\(names[i]) vs \(names[j]) at \(size)") } }
        }
        // the plank bench is not a solid block (open under the seat)
        let g = VoxelModels.build(spec("bench", "Bench", 1.2, 0.4, 0.45))
        #expect(g.filledCount < g.nx * g.ny * g.nz / 2)
        // a tall garden bench grows a back at z = 0 above the seat
        let garden = VoxelModels.build(spec("bench", "Garden bench", 1.4, 0.6, 0.85))
        #expect(garden[garden.nx / 2, garden.ny - 1, 0] != nil)
        #expect(garden[garden.nx / 2, garden.ny - 1, garden.nz - 1] == nil)
    }

    @Test func ottomanVariantsDiffer() {
        let names = ["Ottoman", "Tufted ottoman", "Round ottoman", "Storage ottoman"]
        let masks = names.map { mask(VoxelModels.build(spec("ottoman", $0, 0.6, 0.6, 0.42))) }
        for i in masks.indices { for j in masks.indices where j > i { #expect(masks[i] != masks[j], "\(names[i]) vs \(names[j])") } }
        // leather: same shape, a different palette
        let plain = VoxelModels.build(spec("ottoman", "Ottoman", 0.6, 0.6, 0.42))
        let leather = VoxelModels.build(spec("ottoman", "Leather ottoman", 0.6, 0.6, 0.42))
        #expect(mask(plain) == mask(leather))
        let top = { (g: VoxelGrid) in g[g.nx / 2, g.ny - 1, g.nz / 2] }
        #expect(top(plain) != nil && top(leather) != nil && top(plain) != top(leather))
        #expect(colors(plain).count > 1 && colors(plain) != colors(leather))
    }

    @Test func roundOttomanHasEmptyCorners() {
        for n in ["Round ottoman", "Drum ottoman", "Round tufted storage ottoman"] {
            for (w, d, h) in [(0.6, 0.6, 0.42), (0.05, 0.05, 0.05), (1.0, 0.7, 0.45)] {
                let g = VoxelModels.build(spec("ottoman", n, w, d, h))
                for y in 0..<g.ny {
                    for (x, z) in [(0, 0), (g.nx - 1, 0), (0, g.nz - 1), (g.nx - 1, g.nz - 1)] {
                        #expect(g[x, y, z] == nil, "\(n) corner \(x),\(y),\(z) filled")
                    }
                }
                // but the middle is solid up to the top
                #expect(g[g.nx / 2, g.ny - 1, g.nz / 2] != nil || n.contains("tufted"))
            }
        }
        // a square ottoman fills its corners below the rounded top
        let sq = VoxelModels.build(spec("ottoman", "Ottoman", 0.6, 0.6, 0.42))
        #expect(sq[0, sq.ny - 2, 0] != nil)
    }

    @Test func seatTopsAreSurfaces() {
        for n in Self.benchNames where !n.contains("Garden") {
            let s = spec("bench", n, 1.2, 0.4, 0.45)
            let f = VoxelModels.surfaces(s)
            #expect(f.contains { $0.y == 9 && $0.width == 24 }, "\(n): \(f)")
        }
        let garden = VoxelModels.surfaces(spec("bench", "Garden bench", 1.4, 0.6, 0.85))
        #expect(garden.count == 1 && garden[0].y < 17 && garden[0].z0 >= 1)
        for n in Self.ottomanNames {
            let f = VoxelModels.surfaces(spec("ottoman", n, 0.6, 0.6, 0.42))
            #expect(f.count == 1 && f[0].y == 8, "\(n): \(f)")
        }
        let round = VoxelModels.surfaces(spec("ottoman", "Round ottoman", 0.6, 0.6, 0.42))[0]
        #expect(round.width < 12 && round.depth < 12)
    }

    @Test func deterministic() {
        for n in Self.benchNames {
            let s = spec("bench", n, 1.2, 0.4, 0.45)
            #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(n)")
            #expect(VoxelModels.surfaces(s) == VoxelModels.surfaces(s))
        }
        for n in Self.ottomanNames {
            let s = spec("ottoman", n, 0.6, 0.6, 0.42)
            #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(n)")
        }
    }
}
