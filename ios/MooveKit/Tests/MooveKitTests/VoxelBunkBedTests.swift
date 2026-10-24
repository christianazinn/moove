import Testing
@testable import MooveKit

/// RoomPlan calls a bunk bed a "bed" with a tall box (Rio's room, Oct 24: 1.08 × 2.06 × 1.47 m).
@Suite struct VoxelBunkBedTests {
    func spec(_ name: String, _ w: Double, _ d: Double, _ h: Double) -> VoxelItemSpec {
        VoxelItemSpec(category: "bed", name: name, widthM: w, depthM: d, heightM: h)
    }

    /// Heights (voxel layers) filled in the middle of the bed, away from the head and foot panels.
    func filledLayersMidBed(_ g: VoxelGrid) -> [Int] {
        let x = g.nx / 2, z = g.nz / 2
        return (0..<g.ny).filter { g[x, $0, z] != nil }
    }

    @Test func aTallBedHasTwoDecks() {
        let g = VoxelModels.build(spec("Bed", 1.08, 2.06, 1.47))
        let layers = filledLayersMidBed(g)
        #expect(layers.contains { $0 < g.ny / 3 }, "lower bunk")
        #expect(layers.contains { $0 > g.ny / 2 }, "upper bunk")
        // open space between the decks
        #expect(Set(layers).count < g.ny / 2)
    }

    @Test func aNormalBedHasOneDeck() {
        let g = VoxelModels.build(spec("Bed", 1.56, 2.08, 0.57))
        #expect(!filledLayersMidBed(g).contains { $0 > vox(0.7) })
    }

    @Test func aNamedBunkIsTallEvenWithAShortBox() {
        let g = VoxelModels.build(spec("Metal bunk bed", 1.0, 2.0, 0.5))
        #expect(g.ny >= vox(1.4))
        #expect(filledLayersMidBed(g).contains { $0 > g.ny / 2 })
    }
}
