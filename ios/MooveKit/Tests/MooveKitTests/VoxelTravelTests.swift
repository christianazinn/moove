import Testing
@testable import MooveKit

@Suite struct VoxelTravelTests {
    func spec(_ category: String, _ name: String, _ w: Double, _ d: Double, _ h: Double) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h)
    }

    /// Which cells are filled, ignoring color.
    func mask(_ g: VoxelGrid) -> [Bool] { g.cells.map { $0 != 0 } }

    static let bikeNames = ["Bike", "Kids BMX bike", "Electric e-bike", "Road bike", "Beach cruiser bike", "Red mountain bike"]
    static let suitcaseNames = ["Suitcase", "Navy hard-shell suitcase", "Soft-side luggage", "Duffel bag", "Carry-on suitcase"]
    /// (w, d, h) in meters: defaults (0 = missing), tiny (clamped up to minDims), large, tall and odd.
    static let sizes: [(Double, Double, Double)] = [(0, 0, 0), (0.05, 0.05, 0.05), (3.0, 1.5, 2.5), (0.8, 0.2, 2.0), (8, 8, 4), (1.7, 0.6, 1.0)]

    func checkBounds(_ s: VoxelItemSpec, _ kind: VoxelModels.Kind) {
        #expect(VoxelModels.kind(s) == kind, "\(s.name)")
        let g = VoxelModels.build(s)
        let (X, Y, Z) = VoxelModels.dims(s, kind)
        let m = kind.minDims!
        #expect(g.nx == min(160, max(X, m.0)) && g.ny == min(160, max(Y, m.1)) && g.nz == min(160, max(Z, m.2)), "\(s.name) dims")
        #expect(g.filledCount > 0, "\(s.name) empty")
        #expect(g.cells.allSatisfy { $0 == 0 || $0 & 0x1000000 != 0 })
        #expect(VoxelModels.surfaces(s).isEmpty, "\(s.name) is not a surface piece")
    }

    @Test func bikesBuildWithinBounds() {
        for n in Self.bikeNames { for (w, d, h) in Self.sizes { checkBounds(spec("bike", n, w, d, h), .bike) } }
    }

    @Test func suitcasesBuildWithinBounds() {
        for n in Self.suitcaseNames { for (w, d, h) in Self.sizes { checkBounds(spec("luggage", n, w, d, h), .suitcase) } }
    }

    @Test func bikeIsMostlyAir() {
        for (w, d, h) in [(0.0, 0.0, 0.0), (0.05, 0.05, 0.05), (3.0, 1.5, 2.5)] {
            let g = VoxelModels.build(spec("bike", "Bike", w, d, h))
            #expect(g.filledCount < g.nx * g.ny * g.nz / 4, "\(g.nx)x\(g.ny)x\(g.nz): \(g.filledCount)")
        }
    }

    @Test func bikeHasTwoWheelsOnEitherHalf() {
        for (w, d, h) in [(0.0, 0.0, 0.0), (0.05, 0.05, 0.05), (3.0, 1.5, 2.5)] {
            let g = VoxelModels.build(spec("bike", "Bike", w, d, h))
            // tires touch the ground on both halves, with nothing on the ground between them
            var left = 0, right = 0
            for z in 0..<g.nz { for x in 0..<g.nx where g[x, 0, z] != nil { if x < g.nx / 2 { left += 1 } else { right += 1 } } }
            #expect(left > 0 && right > 0)
            for z in 0..<g.nz { #expect(g[g.nx / 2, 0, z] == nil) }
            // wheels are rings: the tire band at the top of the rear wheel has air below it
            #expect(left <= 3 * g.nz && right <= 3 * g.nz)
        }
    }

    @Test func bikeIsCenteredInZWithWideBars() {
        let g = VoxelModels.build(spec("bike", "Bike", 0, 0, 0))
        let zc = g.nz / 2
        func zs(_ y: ClosedRange<Int>) -> Set<Int> {
            var out = Set<Int>()
            for yy in y { for z in 0..<g.nz { for x in 0..<g.nx where g[x, yy, z] != nil { out.insert(z) } } }
            return out
        }
        // wheels sit in the middle plane
        #expect(zs(0...0) == [zc])
        // the handlebar spans much more of z than the wheels
        #expect(zs(0...(g.ny - 1)).count >= g.nz * 2 / 3)
    }

    @Test func bikeVariantsDiffer() {
        let names = ["Bike", "Kids bike", "E-bike", "Road bike", "Cruiser bike"]
        let masks = names.map { mask(VoxelModels.build(spec("bike", $0, 1.7, 0.6, 1.0))) }
        for i in masks.indices { for j in masks.indices where j > i { #expect(masks[i] != masks[j], "\(names[i]) vs \(names[j])") } }
        let plain = VoxelModels.build(spec("bike", "Bike", 1.7, 0.6, 1.0))
        let ebike = VoxelModels.build(spec("bike", "E-bike", 1.7, 0.6, 1.0))
        #expect(ebike.filledCount > plain.filledCount) // battery + hub motor
        let kids = VoxelModels.build(spec("bike", "Kids bike", 1.7, 0.6, 1.0))
        // smaller wheels: the rear tire's ground contact sits further left
        func firstGroundX(_ g: VoxelGrid) -> Int { (0..<g.nx).first { x in (0..<g.nz).contains { g[x, 0, $0] != nil } } ?? -1 }
        #expect(firstGroundX(kids) < firstGroundX(plain))
        // frame color follows the name
        #expect(VoxelModels.build(spec("bike", "Red bike", 1.7, 0.6, 1.0)) != VoxelModels.build(spec("bike", "Blue bike", 1.7, 0.6, 1.0)))
    }

    @Test func suitcaseHasWheelsAndAHandleAtTheBack() {
        let g = VoxelModels.build(spec("luggage", "Suitcase", 0, 0, 0))
        // wheels at the corners of the bottom layer, nothing under the middle
        #expect(g[0, 0, 0] != nil && g[0, 0, g.nz - 1] != nil)
        #expect(g[g.nx / 2, 0, g.nz / 2] == nil)
        // top layer: only the telescoping handle grip, at the back (low z)
        var top = 0
        for z in 0..<g.nz { for x in 0..<g.nx where g[x, g.ny - 1, z] != nil { top += 1; #expect(z <= 1) } }
        #expect(top > 0)
        // side carry handle sticks out on +x
        var side = 0
        for y in 0..<g.ny { for z in 0..<g.nz where g[g.nx - 1, y, z] != nil { side += 1 } }
        #expect(side > 0 && side < g.ny * g.nz / 3)
    }

    @Test func suitcaseVariantsDiffer() {
        let names = ["Suitcase", "Soft-side suitcase", "Duffel bag"]
        let masks = names.map { mask(VoxelModels.build(spec("luggage", $0, 0.7, 0.35, 0.4))) }
        for i in masks.indices { for j in masks.indices where j > i { #expect(masks[i] != masks[j], "\(names[i]) vs \(names[j])") } }
        // duffel is rounded: its bottom edges along x are empty
        let d = VoxelModels.build(spec("luggage", "Duffel bag", 0.7, 0.35, 0.4))
        #expect(d[d.nx / 2, 0, 0] == nil && d[d.nx / 2, 0, d.nz - 1] == nil)
        #expect(d[d.nx / 2, 0, d.nz / 2] != nil)
        // carry-on is the same builder, just smaller
        let carry = VoxelModels.build(spec("luggage", "Carry-on", 0.35, 0.2, 0.55))
        let big = VoxelModels.build(spec("luggage", "Suitcase", 0.5, 0.3, 0.75))
        #expect(carry.filledCount < big.filledCount)
    }

    @Test func deterministic() {
        for n in Self.bikeNames { let s = spec("bike", n, 1.7, 0.6, 1.0); #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(n)") }
        for n in Self.suitcaseNames { let s = spec("luggage", n, 0.45, 0.28, 0.7); #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(n)") }
    }
}
