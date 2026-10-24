import Foundation
import Testing
@testable import MooveKit

@Suite struct RoomDisplayGeometryTests {
    @Test func matchesDirectComputation() {
        let g = DemoFixtures.roomGeometry()
        let cache = RoomDisplayGeometry()
        #expect(cache.centered(g) == g.centered())
        #expect(cache.cutaway(g, at: 1.2) == g.centered().cutaway(at: 1.2))
    }

    @Test func computesOncePerGeometry() {
        let g = DemoFixtures.roomGeometry()
        let cache = RoomDisplayGeometry()
        for _ in 0..<5 {
            _ = cache.centered(g)
            _ = cache.cutaway(g, at: 1.2)
        }
        #expect(cache.computations == 2)
        _ = cache.cutaway(g, at: 0.5)  // new height: only the cutaway is redone
        #expect(cache.computations == 3)
    }

    @Test func recomputesWhenGeometryChanges() {
        var g = DemoFixtures.roomGeometry()
        let cache = RoomDisplayGeometry()
        _ = cache.cutaway(g, at: 1.2)
        g.objects.removeLast()
        #expect(cache.centered(g) == g.centered())
        #expect(cache.cutaway(g, at: 1.2) == g.centered().cutaway(at: 1.2))
        #expect(cache.computations == 4)
    }
}
