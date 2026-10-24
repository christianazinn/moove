import Testing
@testable import MooveKit

/// Dividers, screens and curtains draw as thin panels, not the 1.4 m bookshelf the size
/// fallback picked for a detector "room divider" (a shower curtain in Rio's room, Oct 24).
@Suite struct VoxelScreenTests {
    func spec(_ category: String, _ name: String) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: 0.53, depthM: 0.5, heightM: 1.43)
    }

    @Test func dividersAndCurtainsAreScreens() {
        for (c, n) in [("room divider", "Room divider"), ("other", "Shower curtain"), ("decor", "White linen curtains"),
                       ("furniture", "Rattan folding screen"), ("other", "Wooden room divider")] {
            #expect(VoxelModels.kind(spec(c, n)) == .screen, "\(c) / \(n)")
        }
        // "screen" alone stays a TV / monitor word, and a real shelf stays a shelf
        #expect(VoxelModels.kind(spec("electronics", "Projector screen")) != .screen)
        #expect(VoxelModels.kind(spec("storage", "Bookshelf")) == .bookshelf)
    }

    @Test func screensBuild() {
        for n in ["Room divider", "Shower curtain"] {
            let g = VoxelModels.build(spec("room divider", n))
            #expect(g.filledCount > 0, "\(n)")
        }
    }
}
