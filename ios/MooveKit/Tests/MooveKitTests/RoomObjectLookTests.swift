import Foundation
import Testing
@testable import MooveKit

@Suite struct RoomObjectLookTests {
    private let red = SIMD4<Float>(1, 0, 0, 1)
    private let blue = SIMD4<Float>(0, 0, 1, 1)

    private func look(_ color: SIMD4<Float>? = nil, selected: Bool = false, label: String? = "Bed", size: Float = 0.2) -> RoomObjectLook {
        RoomObjectLook(color: color ?? red, selected: selected, label: label, labelSize: size)
    }

    @Test func firstApplyDoesEverything() {
        #expect(look().changes(since: nil) == .all)
    }

    @Test func unchangedDoesNothing() {
        #expect(look().changes(since: look()).isEmpty)
        #expect(look(label: nil).changes(since: look(label: nil, size: 0.5)).isEmpty)  // hidden label ignores size
    }

    @Test func capturedModelArrivingRebuildsEverything() {
        let plain = look()
        var captured = look()
        captured.model = "file:///models/demo-11/model.usdz#0"
        #expect(captured.changes(since: plain) == .all)
        var turned = captured
        turned.model = "file:///models/demo-11/model.usdz#1"
        #expect(turned.changes(since: captured) == .all)  // "Rotate 90°" rebuilds too
        #expect(plain.changes(since: captured) == .all)   // removed model
        #expect(captured.changes(since: captured).isEmpty)
    }

    @Test func colorChangeOnlyRecolors() {
        #expect(look(blue).changes(since: look()) == .color)
    }

    @Test func selectionRecolorsAndPops() {
        #expect(look(selected: true).changes(since: look()) == [.color, .selection])
        #expect(look().changes(since: look(selected: true)) == [.color, .selection])
    }

    @Test func labelChangesOnlyRebuildLabel() {
        #expect(look(label: "Sofa").changes(since: look()) == .label)
        #expect(look(label: nil).changes(since: look()) == .label)
        #expect(look().changes(since: look(label: nil)) == .label)
        #expect(look(size: 0.3).changes(since: look()) == .label)
    }

    @Test func labelText() {
        let object = RoomGeometry.Object(id: "a", category: "bed", dimensions: SIMD3(1, 1, 1), transform: .identity)
        #expect(RoomObjectLook.labelText(for: object, item: nil) == "Bed")
        var item = Item(id: 1, owner: "", roomId: 0, name: "Grandma's bed", category: "bed", widthM: 1, heightM: 1, depthM: 1)
        #expect(RoomObjectLook.labelText(for: object, item: item) == "Grandma's bed")
        item.maybeSentimental = true
        #expect(RoomObjectLook.labelText(for: object, item: item) == "Grandma's bed ♥")
    }
}

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
