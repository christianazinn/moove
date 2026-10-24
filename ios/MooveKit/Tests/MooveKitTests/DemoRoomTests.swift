import Foundation
import Testing
@testable import MooveKit

@Suite struct DemoRoomTests {
    /// The objects `npm run seed:demo` puts on maincloud. Keep in sync with
    /// DEMO_OBJECTS in agents/scripts/demo-room.ts (width, height, depth in meters).
    static let seeded: [(id: String, category: String, dims: SIMD3<Float>)] = [
        ("demo-bedroom-bed", "bed", SIMD3(1.4, 0.36, 1.95)),
        ("demo-bedroom-desk", "table", SIMD3(1.05, 0.75, 0.5)),
        ("demo-bedroom-chair", "chair", SIMD3(0.64, 1.02, 0.62)),
        ("demo-bedroom-shelf", "storage", SIMD3(0.77, 1.47, 0.39)),
        ("demo-bedroom-fridge", "refrigerator", SIMD3(0.48, 0.85, 0.5)),
        ("demo-bedroom-tv", "television", SIMD3(0.73, 0.48, 0.18)),
        ("demo-bedroom-monitor", "electronics", SIMD3(0.61, 0.45, 0.18)),
        ("demo-bedroom-lamp", "lamp", SIMD3(0.3, 1.7, 0.3)),
        ("demo-bedroom-guitar", "instrument", SIMD3(0.38, 1.02, 0.12)),
    ]

    @Test func seededBedroomHasExactlyOneObjectPerSeededItem() {
        let objects = DemoFixtures.seededBedroomGeometry().objects
        #expect(objects.count == Self.seeded.count)
        for s in Self.seeded {
            let matches = objects.filter { $0.id == s.id }
            #expect(matches.count == 1, "\(s.id)")
            #expect(matches.first?.category == s.category, "\(s.id)")
            #expect(matches.first?.dimensions == s.dims, "\(s.id)")
        }
    }

    @Test func selectorPicksTheSeededLayoutForSeededIds() {
        let g = DemoFixtures.roomGeometry(forScanObjectIds: Self.seeded.map(\.id))
        #expect(g == DemoFixtures.seededBedroomGeometry())
    }

    @Test func selectorPicksTheFixtureLayoutForFixtureItems() {
        let ids = DemoFixtures.inventory(owner: "me").items.compactMap(\.scanObjectId)
        let g = DemoFixtures.roomGeometry(forScanObjectIds: ids)
        #expect(g == DemoFixtures.roomGeometry())
        #expect(Set(g?.objects.map(\.id) ?? []) == Set(ids))  // every offline fixture item still has a box
    }

    @Test func selectorReturnsNilForRealScans() {
        #expect(DemoFixtures.roomGeometry(forScanObjectIds: ["5B1C0A2E-9F3D-4C1B-8E7A-2D6F4A9B1C3E"]) == nil)
        #expect(DemoFixtures.roomGeometry(forScanObjectIds: [String]()) == nil)
    }

    @Test func seededObjectsSitInsideTheRoomWithoutOverlapping() {
        let g = DemoFixtures.seededBedroomGeometry()
        let rects = g.objects.filter { $0.transform.position.y - $0.dimensions.y / 2 < 0.01 }.map { Self.rect($0) }
        #expect(rects.count == 7)  // all but the TV and monitor stand on the floor
        for (id, lo, hi) in rects {
            #expect(lo.x >= -2.001 && hi.x <= 2.001 && lo.y >= -1.751 && hi.y <= 1.751, "\(id) outside room")
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let a = rects[i], b = rects[j]
                let overlap = a.1.x < b.2.x - 0.001 && b.1.x < a.2.x - 0.001 && a.1.y < b.2.y - 0.001 && b.1.y < a.2.y - 0.001
                #expect(!overlap, "\(a.0) overlaps \(b.0)")
            }
        }
    }

    @Test func tvSitsOnTheShelfAndMonitorOnTheDesk() {
        let byId = Dictionary(uniqueKeysWithValues: DemoFixtures.seededBedroomGeometry().objects.map { ($0.id, $0) })
        for (top, base) in [("demo-bedroom-tv", "demo-bedroom-shelf"), ("demo-bedroom-monitor", "demo-bedroom-desk")] {
            let t = byId[top]!, b = byId[base]!
            #expect(abs((t.transform.position.y - t.dimensions.y / 2) - (b.transform.position.y + b.dimensions.y / 2)) < 1e-4, "\(top) floats")
            let (_, tlo, thi) = Self.rect(t), (_, blo, bhi) = Self.rect(b)
            #expect(tlo.x >= blo.x - 0.001 && thi.x <= bhi.x + 0.001 && tlo.y >= blo.y - 0.001 && thi.y <= bhi.y + 0.001, "\(top) overhangs \(base)")
        }
    }

    private static func rect(_ o: RoomGeometry.Object) -> (String, SIMD2<Float>, SIMD2<Float>) {
        let pts = RoomGeometry.footprint(width: o.dimensions.x, depth: o.dimensions.z, o.transform)
        return (o.id, pts.reduce(pts[0]) { pointwiseMin($0, $1) }, pts.reduce(pts[0]) { pointwiseMax($0, $1) })
    }
}
