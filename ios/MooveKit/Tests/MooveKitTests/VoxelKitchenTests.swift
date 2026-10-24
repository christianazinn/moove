import Testing
@testable import MooveKit

/// Kitchen appliances: ranges / wall ovens, dishwashers, microwaves.
@Suite struct VoxelKitchenTests {
    func spec(_ category: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h)
    }

    func colors(_ g: VoxelGrid) -> Set<VoxelColor> {
        var out = Set<VoxelColor>()
        for y in 0..<g.ny { for z in 0..<g.nz { for x in 0..<g.nx { if let c = g[x, y, z] { out.insert(c) } } } }
        return out
    }

    /// Distinct colors seen looking at the piece from +z (front) or from -z (back).
    func faceColors(_ g: VoxelGrid, front: Bool) -> Set<VoxelColor> {
        var out = Set<VoxelColor>()
        for y in 0..<g.ny {
            for x in 0..<g.nx {
                let zs = front ? Array(stride(from: g.nz - 1, through: 0, by: -1)) : Array(0..<g.nz)
                for z in zs { if let c = g[x, y, z] { out.insert(c); break } }
            }
        }
        return out
    }

    /// Average color of the filled voxels, as (r, g, b).
    func meanColor(_ g: VoxelGrid) -> (Double, Double, Double) {
        var r = 0.0, gg = 0.0, b = 0.0, n = 0.0
        for c in g.cells where c != 0 {
            r += Double((c >> 16) & 255); gg += Double((c >> 8) & 255); b += Double(c & 255); n += 1
        }
        return (r / n, gg / n, b / n)
    }

    static let pieces: [(String, String, VoxelModels.Kind, (Double, Double, Double))] = [
        ("stove", "Stove", .stove, (0.4, 0.5, 0.5)),
        ("appliance", "GE gas range", .stove, (0.4, 0.5, 0.5)),
        ("appliance", "Electric range", .stove, (0.4, 0.5, 0.5)),
        ("oven", "Oven", .stove, (0.4, 0.5, 0.5)),
        ("dishwasher", "Dishwasher", .dishwasher, (0.4, 0.5, 0.5)),
        ("appliance", "Microwave", .microwave, (0.3, 0.2, 0.2)),
        ("appliance", "Over the range microwave", .microwave, (0.3, 0.2, 0.2)),
    ]

    @Test func buildWithinBoundsAtAllSizes() {
        for (cat, name, kind, _) in Self.pieces {
            #expect(VoxelModels.kind(spec(cat, name)) == kind, "\(name)")
            let sizes: [(Double, Double, Double)] = [(0, 0, 0), (0.05, 0.05, 0.05), (0.42, 0.41, 0.52), (3, 2.5, 3), (8, 8, 4)]
            for (w, d, h) in sizes {
                let s = spec(cat, name, w, d, h)
                let g = VoxelModels.build(s)
                if let m = kind.minDims { #expect(g.nx >= m.0 && g.ny >= m.1 && g.nz >= m.2, "\(name) \(w)x\(d)x\(h)") }
                #expect(g.nx <= 160 && g.ny <= 160 && g.nz <= 160)
                #expect(g.filledCount > g.nx * g.ny * g.nz / 3, "\(name) \(w)x\(d)x\(h) too sparse")
                #expect(colors(g).count >= 6, "\(name) \(w)x\(d)x\(h) too plain")
                #expect(g.cells.allSatisfy { $0 == 0 || $0 & 0x1000000 != 0 })
            }
        }
    }

    @Test func frontIsBusierThanTheBack() {
        for (cat, name, _, _) in Self.pieces {
            for (w, d, h) in [(0.0, 0.0, 0.0), (0.05, 0.05, 0.05), (1.2, 0.8, 1.2)] {
                let g = VoxelModels.build(spec(cat, name, w, d, h))
                let f = faceColors(g, front: true).count, b = faceColors(g, front: false).count
                #expect(f > b, "\(name) \(w)x\(d)x\(h): front \(f) vs back \(b)")
            }
        }
    }

    @Test func finishFollowsTheName() {
        for (cat, base) in [("stove", "range"), ("dishwasher", "dishwasher"), ("microwave", "microwave")] {
            let steel = VoxelModels.build(spec(cat, "Stainless \(base)"))
            let white = VoxelModels.build(spec(cat, "White \(base)"))
            let black = VoxelModels.build(spec(cat, "Black \(base)"))
            #expect(steel != white && white != black)
            let (sr, sg, sb) = meanColor(steel), (wr, wg, wb) = meanColor(white), (br, bg, bb) = meanColor(black)
            #expect(wr + wg + wb > sr + sg + sb, "\(base): white brighter than stainless")
            #expect(sr + sg + sb > br + bg + bb, "\(base): stainless brighter than black")
        }
    }

    @Test func gasAndElectricCooktopsDiffer() {
        let gas = VoxelModels.build(spec("stove", "Gas range"))
        let electric = VoxelModels.build(spec("stove", "Electric range"))
        #expect(gas.nx == electric.nx && gas.ny == electric.ny && gas.nz == electric.nz)
        // gas grates stand a layer above the cooktop; the glass top is flush
        #expect(gas.filledCount > electric.filledCount)
        #expect(VoxelModels.surfaces(spec("stove", "Gas range")).isEmpty)
    }

    @Test func deterministic() {
        for (cat, name, _, size) in Self.pieces {
            let s = spec(cat, name, size.0, size.1, size.2)
            #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(name)")
            let d = spec(cat, name)
            #expect(VoxelModels.build(d) == VoxelModels.build(d), "\(name) default")
        }
    }
}
