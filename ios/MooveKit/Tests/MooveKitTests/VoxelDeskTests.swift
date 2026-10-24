import Testing
@testable import MooveKit

/// Desk types picked from name words (gaming, writing, hutch, pedestal, computer, vanity).
@Suite struct VoxelDeskTests {
    static let variants: [(name: String, style: Canvas.DeskStyle)] = [
        ("Black RGB gaming desk", .gaming),
        ("Walnut writing desk", .writing),
        ("Mid-century console desk", .writing),
        ("Oak secretary desk with hutch", .hutch),
        ("Roll top desk", .hutch),
        ("Executive double pedestal desk", .pedestal),
        ("Computer desk with keyboard tray", .computer),
        ("White vanity", .vanity),
    ]
    static let defaultSize = (1.2, 0.6, 0.75)
    static let tallSize = (1.2, 0.6, 1.8)
    static let minSize = (0.01, 0.01, 0.01)
    static let largeSize = (3.0, 1.6, 2.2)

    func spec(_ name: String, _ s: (Double, Double, Double), condition: Int? = nil) -> VoxelItemSpec {
        VoxelItemSpec(category: "desk", name: name, widthM: s.0, depthM: s.1, heightM: s.2, condition: condition)
    }

    /// Which cells are filled (shape only: colors depend on the name-seeded grain and jitter).
    func mask(_ g: VoxelGrid) -> [Bool] { g.cells.map { $0 != 0 } }

    /// Size that shows the variant's defining part (the hutch and the vanity mirror need height).
    func showSize(_ style: Canvas.DeskStyle) -> (Double, Double, Double) {
        style == .hutch || style == .vanity ? Self.tallSize : Self.defaultSize
    }

    @Test func routesAndPicksStyle() {
        for v in Self.variants {
            let s = spec(v.name, showSize(v.style))
            #expect(VoxelModels.kind(s) == .desk, "\(v.name)")
            let (X, Y, Z) = VoxelModels.dims(s, .desk)
            let g = Canvas(X, Y, Z, seed: 1)
            #expect(g.deskStyle(X, Y, Z, VName(v.name.lowercased())) == v.style, "\(v.name)")
        }
        // the original styles keep precedence
        let g = Canvas(24, 15, 12, seed: 1)
        #expect(g.deskStyle(24, 15, 12, VName("office desk")) == .plain, "narrow office desk")
        #expect(g.deskStyle(30, 15, 12, VName("office desk")) == .pedestal, "wide office desk")
        #expect(g.deskStyle(24, 15, 12, VName("secretary desk")) == .plain, "short secretary is the plain desk")
    }

    @Test func buildsWithinBoundsAtAllSizes() {
        for v in Self.variants {
            for size in [Self.defaultSize, Self.tallSize, Self.minSize, Self.largeSize, (0.15, 0.15, 1.2), (4.0, 0.3, 0.4)] {
                for c in [nil, 1] as [Int?] {
                    let s = spec(v.name, size, condition: c)
                    let r = VoxelModels.buildWithSurfaces(s)
                    let g = r.grid
                    #expect(g.filledCount > 0, "\(v.name) \(size) empty")
                    #expect(g.nx >= 3 && g.ny >= 3 && g.nz >= 3)
                    #expect(g.nx <= 160 && g.ny <= 160 && g.nz <= 160)
                    #expect(g.cells.count == g.nx * g.ny * g.nz)
                    #expect(g.cells.allSatisfy { $0 == 0 || $0 & 0x1000000 != 0 })
                    // a size no desk has (15 cm wide, 1.2 m tall) is drawn by its shape (a lamp, #shape sanity)
                    if VoxelModels.kind(s) == .desk { #expect(!r.surfaces.isEmpty, "\(v.name) \(size) has no surfaces") }
                    for f in r.surfaces {
                        #expect(f.x0 >= 0 && f.z0 >= 0 && f.x1 <= g.nx && f.z1 <= g.nz && f.width > 0 && f.depth > 0, "\(v.name) \(size) surface \(f)")
                        #expect(f.y >= 0 && f.y <= g.ny, "\(v.name) \(size) surface y \(f.y)")
                        if let cl = f.clearance { #expect(cl > 0 && f.y + cl <= g.ny) }
                    }
                }
            }
        }
    }

    @Test func eachVariantDiffersFromThePlainDesk() {
        for v in Self.variants {
            for size in [showSize(v.style), Self.largeSize] {
                let plain = mask(VoxelModels.build(spec("Desk", size)))
                let g = mask(VoxelModels.build(spec(v.name, size)))
                #expect(g.count == plain.count)
                #expect(g != plain ? true : false, "\(v.name) at \(size) looks like the plain desk")
            }
        }
    }

    @Test func hutchOnlyWhenTall() {
        for name in ["Oak secretary desk with hutch", "Roll top desk", "Computer armoire desk"] {
            let tall = VoxelModels.buildWithSurfaces(spec(name, Self.tallSize))
            let g = tall.grid
            // something stands at the back near the top of a tall secretary
            var top = 0
            for z in 0..<2 { for x in 0..<g.nx where g[x, g.ny - 1, z] != nil { top += 1 } }
            #expect(top > 0, "\(name): no hutch")
            #expect(tall.surfaces.contains { $0.clearance != nil }, "\(name): hutch shelves have clearance")
            let work = tall.surfaces.filter { $0.clearance == nil && $0.y < g.ny }
            #expect(work.contains { $0.z1 == g.nz && $0.z0 > 0 }, "\(name): work surface in front of the hutch")

            // short: just the desk (same shape as the plain one)
            let short = VoxelModels.buildWithSurfaces(spec(name, Self.defaultSize))
            #expect(mask(short.grid) == mask(VoxelModels.build(spec("Desk", Self.defaultSize))) ? true : false, "\(name): short build grew a hutch")
            #expect(short.surfaces.allSatisfy { $0.clearance == nil })
        }
    }

    @Test func vanityMirrorOnlyWhenTall() {
        let tall = VoxelModels.build(spec("White vanity", Self.tallSize))
        let short = VoxelModels.build(spec("White vanity", Self.defaultSize))
        func backHigh(_ g: VoxelGrid) -> Int {
            var n = 0
            for y in (g.ny * 2 / 3)..<g.ny { for x in 0..<g.nx where g[x, y, 0] != nil { n += 1 } }
            return n
        }
        #expect(backHigh(tall) > 0, "mirror on the back edge")
        // the mirror glass is light blue and flat
        #expect(tall.cells.contains { $0 & 0xFFFFFF == 0xBFDCEB })
        #expect(!short.cells.contains { $0 & 0xFFFFFF == 0xBFDCEB }, "short vanity is a plain dressing table")
    }

    @Test func deterministic() {
        for v in Self.variants {
            for size in [Self.defaultSize, Self.tallSize, Self.largeSize] {
                let s = spec(v.name, size, condition: 2)
                let a = VoxelModels.buildWithSurfaces(s), b = VoxelModels.buildWithSurfaces(s)
                #expect(a.grid == b.grid, "\(v.name)")
                #expect(a.surfaces == b.surfaces, "\(v.name)")
            }
        }
    }
}
