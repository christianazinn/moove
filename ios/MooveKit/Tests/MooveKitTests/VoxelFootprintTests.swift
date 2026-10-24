import Testing
@testable import MooveKit

/// Lisa's iPad scan (Oct 24): "size a bit off". Every builder fills the scanned footprint and
/// height: the filled voxels' bounding box matches the spec's (w, h, d) within one voxel.
struct VoxelFootprintTests {
    /// The filled voxels' extent (x, y, z), in voxels.
    static func extent(_ g: VoxelGrid) -> (Int, Int, Int) {
        var lo = (Int.max, Int.max, Int.max), hi = (-1, -1, -1)
        for y in 0..<g.ny {
            for z in 0..<g.nz {
                for x in 0..<g.nx where g[x, y, z] != nil {
                    lo = (min(lo.0, x), min(lo.1, y), min(lo.2, z))
                    hi = (max(hi.0, x), max(hi.1, y), max(hi.2, z))
                }
            }
        }
        return hi.0 < 0 ? (0, 0, 0) : (hi.0 - lo.0 + 1, hi.1 - lo.1 + 1, hi.2 - lo.2 + 1)
    }

    /// Style variants of the common pieces (each builder branch), on top of one sample per kind.
    static let variants: [(String, String)] = [
        ("table", "Round walnut dining table"), ("table", "Glass coffee table"), ("table", "Farmhouse trestle table"),
        ("table", "Mid-century side table"), ("table", "Oak coffee table with shelf"), ("table", "Bar table"),
        ("dresser", "Walnut sideboard"), ("dresser", "Nightstand"), ("dresser", "White wardrobe"), ("dresser", "TV stand"),
        ("lamp", "Arc floor lamp"), ("lamp", "Tripod floor lamp"), ("lamp", "Torchiere"), ("lamp", "Brass desk lamp"),
        ("lamp", "Ceramic table lamp"), ("chair", "Office chair"), ("chair", "Windsor chair"), ("chair", "Bar stool"),
        ("chair", "Velvet dining chair"), ("sofa", "Leather sofa"), ("sofa", "Sectional"), ("sofa", "Armchair"),
        ("ottoman", "Round tufted ottoman"), ("ottoman", "Storage ottoman"), ("decor", "Throw pillow"),
        ("decor", "Candle"), ("storage", "Kallax cube shelf"), ("storage", "Ladder shelf"),
    ]

    static func samples() -> [(String, String)] {
        VoxelModels.Kind.allCases.map { RenderBudgetTests.kindSamples[$0] ?? ($0.rawValue, $0.rawValue) } + variants
    }

    @Test func everyKindFillsItsScannedSize() {
        var bad: [String] = []
        for (cat, name) in Self.samples() {
            let k0 = VoxelModels.kind(VoxelItemSpec(category: cat, name: name, widthM: 0, depthM: 0, heightM: 0))
            let def = k0.defaultSize
            for f in [0.8, 1.0, 1.3] {
                let spec = VoxelItemSpec(category: cat, name: name, widthM: def.0 * f, depthM: def.1 * f, heightM: def.2 * f)
                let k = VoxelModels.kind(spec)
                // a drum kit and a bike are loose arrangements of parts with set sizes (a snare,
                // handlebars), not one body filling a box
                if k == .drums || k == .bike { continue }
                let g = VoxelModels.build(spec)
                let e = Self.extent(g)
                let m = k.minDims ?? (1, 1, 1)
                let want = (max(vox(spec.widthM), m.0), max(vox(spec.heightM), m.1), max(vox(spec.depthM), m.2))
                // a bed's headboard rises above a low (mattress-top) height; a rug is one layer thick
                let checkH = k != .bed && k != .rug
                if abs(e.0 - want.0) > 1 || abs(e.2 - want.2) > 1 || (checkH && abs(e.1 - want.1) > 1) {
                    bad.append("\(cat)/\(name) [\(k)] x\(f): want \(want) filled \(e)")
                }
            }
        }
        #expect(bad.isEmpty, "\(bad.count) pieces don't fill their scanned size:\n\(bad.joined(separator: "\n"))")
    }
}
