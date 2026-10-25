import Foundation
import Testing
@testable import MooveKit

/// Thumbnail cost: building + projecting the iso sprite for every demo inventory item, the way
/// `VoxelThumbnail` does. Lists (Review deck, Inventory binder) build one per item, so a mesher
/// or builder change that makes this slow shows up as scroll hitches. Budgets are loose
/// (debug build, shared runner); they only trip on a real blow-up. Today (Oct 24, Linux): 12
/// items, 4.7k faces (bed frame 1.7k); build + project 33 ms debug, 4 ms release.
@Suite struct VoxelSpriteBudgetTests {
    static var demoSpecs: [VoxelItemSpec] {
        let colors = DemoFixtures.scanColors()
        return DemoFixtures.inventory(owner: "sprite-budget").items.map { item in
            var spec = VoxelItemSpec(item)
            if item.colors == nil, DemoFixtures.isDemoItem(item), let c = colors.colors(for: item) {
                spec.primaryColor = c.primary
                spec.secondaryColor = c.secondary
            }
            return spec
        }
    }

    @Test func demoInventorySpritesAreCheap() {
        let specs = Self.demoSpecs
        #expect(!specs.isEmpty)
        let clock = ContinuousClock()
        var build = Duration.zero, render = Duration.zero
        var faces = 0, worst = (0, "")
        for spec in specs {
            var grid = VoxelGrid(nx: 1, ny: 1, nz: 1)
            build += clock.measure { grid = VoxelModels.build(spec) }
            var sprite = IsoSprite()
            render += clock.measure { sprite = IsoSprite.render(grid) }
            faces += sprite.faces.count
            if sprite.faces.count > worst.0 { worst = (sprite.faces.count, spec.name) }
        }
        print("sprite budget: \(specs.count) demo items, build \(build), render \(render), \(faces) faces, worst \(worst.1) \(worst.0)")
        #expect(build + render < .seconds(3))
        #expect(worst.0 < 4_000)
    }
}
