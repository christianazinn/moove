import Testing
@testable import MooveKit

/// Shape sanity after routing (Lisa's iPad scan, Oct 24): "the cabinet was too big where there
/// should've been a table ... a weird vertical thing it called pillow that was a lamp".
/// The name picks the builder unless the scanned size clearly says it is something else.
struct VoxelShapeSanityTests {
    func kind(_ cat: String, _ name: String, _ w: Double, _ d: Double, _ h: Double, attrs: [String] = []) -> VoxelModels.Kind {
        VoxelModels.kind(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, attributes: attrs))
    }

    @Test func tallThinPillowIsALamp() {
        #expect(kind("decor", "Pillow", 0.3, 0.3, 1.5) == .lamp)
        #expect(kind("other", "Pillow", 0.3, 0.3, 1.5) == .lamp)
        #expect(kind("furniture", "Throw pillow", 0.35, 0.3, 1.6) == .lamp)
    }

    @Test func pillowSizedPillowStaysAPillow() {
        #expect(kind("decor", "Pillow", 0.5, 0.4, 0.15) == .decor)
        #expect(kind("other", "Pillow", 0.5, 0.4, 0.15) == .decor)
        #expect(kind("decor", "Pillow", 0.5, 0.15, 0.5) == .decor) // standing against a sofa back
        #expect(kind("furniture", "Velvet cushion", 0.45, 0.45, 0.12) == .decor)
        #expect(kind("decor", "Chair cushion", 0.4, 0.4, 0.05) == .decor)
    }

    @Test func tableShapedStorageIsATable() {
        #expect(kind("storage", "Storage", 1.2, 0.7, 0.75) == .table)
        #expect(kind("storage", "Storage", 1.0, 0.6, 0.45) == .table) // a coffee table
        // RoomPlan's cabinet reading of a top deeper than any cabinet
        #expect(kind("storage", "Storage", 1.4, 0.8, 0.75, attrs: ["StorageType.cabinet"]) == .table)
        // real storage keeps its kind
        #expect(kind("storage", "Storage", 1.0, 0.4, 1.8) == .bookshelf)
        #expect(kind("storage", "Storage", 1.6, 0.45, 0.55) == .bookshelf) // shallow: a TV stand / low shelf
        #expect(kind("storage", "Storage", 1.2, 0.5, 0.8, attrs: ["StorageType.cabinet"]) == .dresser)
        #expect(kind("storage", "Storage", 1.2, 0.7, 0.75, attrs: ["StorageType.shelf"]) == .bookshelf)
        // the name says cabinet: a case piece whatever the depth
        #expect(kind("storage", "Storage cabinet", 1.2, 0.7, 0.75) == .dresser)
        #expect(kind("storage", "Chest of drawers", 1.2, 0.7, 0.75) == .dresser)
    }

    @Test func plausibleNameWins() {
        #expect(kind("furniture", "Dresser", 1.2, 0.5, 0.8) == .dresser)
        #expect(kind("dresser", "Dresser", 1.2, 0.5, 0.8) == .dresser)
        #expect(kind("table", "Side table", 0.45, 0.45, 0.6) == .table)
        #expect(kind("lamp", "Floor lamp", 0.4, 0.4, 1.6) == .lamp)
        #expect(kind("lamp", "Table lamp", 0.3, 0.3, 0.5) == .lamp)
        #expect(kind("sofa", "Sofa", 2.0, 0.9, 0.85) == .sofa)
        #expect(kind("chair", "Chair", 0.5, 0.5, 0.9) == .chair)
        #expect(kind("bed", "Bed", 1.6, 2.1, 0.5) == .bed)
        #expect(kind("ottoman", "Ottoman", 0.6, 0.6, 0.42) == .ottoman)
    }

    @Test func implausibleNameFollowsTheShape() {
        #expect(kind("table", "Olive tree", 0.4, 0.4, 1.8) == .plant) // a "table" that is a potted tree
        #expect(kind("table", "Table", 0.3, 0.3, 1.6) == .lamp)
        #expect(kind("lamp", "Lamp", 1.4, 0.8, 0.75) == .table) // a lamp box swallowed the table under it
        #expect(kind("furniture", "Chair", 1.5, 0.35, 1.8) == .bookshelf)
        #expect(kind("ottoman", "Ottoman", 1.2, 0.7, 0.75) == .table)
        // no clear alternative: keep the name's kind
        #expect(kind("chair", "Chair", 0.2, 0.2, 0.2) == .chair)
        #expect(kind("decor", "Pillow", 0.4, 0.4, 0.8) == .decor)
    }

    @Test func scanAttributesAndSmallCategoriesStayAuthoritative() {
        #expect(kind("chair", "Pillow", 0.3, 0.3, 1.5, attrs: ["ChairType.stool"]) == .chair)
        #expect(kind("sofa", "Sofa", 0.3, 0.3, 1.5, attrs: ["SofaType.singleSeat"]) == .sofa)
        #expect(kind("books", "Coffee table book", 0.3, 0.3, 1.5) == .books)
        #expect(kind("electronics", "TV remote", 0.3, 0.3, 1.5) == .electronics)
        #expect(kind("decor", "Floor vase", 0.3, 0.3, 1.2) == .decor)
        #expect(kind("rug", "Rolled-up rug", 0.3, 0.3, 1.8) == .rug) // rolled for the move
        #expect(kind("mattress", "Mattress", 1.5, 0.3, 2.0) == .mattress) // on its side
    }

    @Test func pillowDrawsAsAPillow() {
        // lying: one thin layer at the seams, puffed in the middle, no vase stems
        let g = VoxelModels.build(VoxelItemSpec(category: "decor", name: "Pillow", widthM: 0.5, depthM: 0.4, heightM: 0.15))
        #expect((g.nx, g.ny, g.nz) == (10, 3, 8))
        #expect(g[g.nx / 2, g.ny - 1, g.nz / 2] != nil && g[g.nx / 2, 0, g.nz / 2] != nil)
        #expect(g[0, 0, g.nz / 2] == nil && g[0, g.ny - 1, g.nz / 2] == nil) // pinched edge
        #expect(g[0, 0, 0] == nil && g[0, g.ny - 1, 0] == nil) // tucked corner
        // standing up against a sofa back: the face is in x-y
        let s = VoxelModels.build(VoxelItemSpec(category: "decor", name: "Pillow", widthM: 0.5, depthM: 0.15, heightM: 0.5))
        #expect(s[s.nx / 2, s.ny - 1, s.nz / 2] != nil && s[s.nx / 2, s.ny / 2, 0] != nil && s[s.nx / 2, s.ny / 2, s.nz - 1] != nil)
    }
}
