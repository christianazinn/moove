import Foundation
import Testing
@testable import MooveKit

@Suite struct RoomGeometryTests {
    @Test func triangulatesLShapedFloor() {
        let l: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 2), SIMD2(2, 2), SIMD2(2, 4), SIMD2(0, 4)]
        let tris = Triangulation.triangulate(l)
        #expect(tris.count == 12)  // n - 2 triangles
        var area: Float = 0
        for t in stride(from: 0, to: tris.count, by: 3) {
            area += Triangulation.signedArea([l[Int(tris[t])], l[Int(tris[t + 1])], l[Int(tris[t + 2])]])
        }
        #expect(abs(area - 12) < 1e-4)  // every triangle CCW, total = polygon area
    }

    @Test func triangulatesClockwiseInput() {
        let square: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0)]
        #expect(Triangulation.triangulate(square).count == 6)
    }

    @Test func transformYawRoundTrips() {
        let t = Transform.at(SIMD3(1, 2, 3), yaw: 0.7)
        #expect(abs(t.yaw - 0.7) < 1e-5)
        #expect(t.position == SIMD3(1, 2, 3))
        let p = t.apply(SIMD3(1, 0, 0))
        #expect(abs(p.y - 2) < 1e-5)
    }

    @Test func centeredPutsFloorAtZeroAndRoomAtOrigin() {
        var g = DemoFixtures.roomGeometry()
        g.walls = g.walls.map { var w = $0; w.transform = w.transform.translated(by: SIMD3(5, -1, 7)); return w }
        g.floors = g.floors.map { .init(id: $0.id, outline: $0.outline.map { $0 + SIMD2(5, 7) }, elevation: -1) }
        g.objects = g.objects.map { var o = $0; o.transform = o.transform.translated(by: SIMD3(5, -1, 7)); return o }
        g.openings = g.openings.map { var o = $0; o.transform = o.transform.translated(by: SIMD3(5, -1, 7)); return o }
        let c = g.centered()
        #expect(abs(c.floorY) < 1e-5)
        let b = c.bounds!
        #expect(abs(b.min.x + b.max.x) < 1e-4)
        #expect(abs(b.min.z + b.max.z) < 1e-4)
    }

    @Test func demoRoomHasOneObjectPerDemoItem() {
        let ids = Set(DemoFixtures.roomGeometry().objects.map(\.id))
        let items = DemoFixtures.inventory(owner: "me").items.compactMap(\.scanObjectId)
        #expect(ids == Set(items))
    }

    @Test func demoObjectsSitInsideTheRoomWithoutOverlapping() {
        let g = DemoFixtures.roomGeometry()
        let rects = g.objects.filter { $0.transform.position.y - $0.dimensions.y / 2 < 0.01 }.map { o -> (String, SIMD2<Float>, SIMD2<Float>) in
            let pts = RoomGeometry.footprint(width: o.dimensions.x, depth: o.dimensions.z, o.transform)
            let lo = pts.reduce(pts[0]) { pointwiseMin($0, $1) }, hi = pts.reduce(pts[0]) { pointwiseMax($0, $1) }
            return (o.id, lo, hi)
        }
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

    @Test func roundTripsThroughJSON() throws {
        let g = DemoFixtures.roomGeometry()
        let decoded = try JSONDecoder().decode(RoomGeometry.self, from: JSONEncoder().encode(g))
        #expect(decoded == g)
    }
}

@Suite struct WallPiecesTests {
    @Test func doorLeavesSidesAndLintel() {
        let door = WallHole(id: "d", kind: .door, center: SIMD2(0, -0.2), size: SIMD2(1, 2))  // wall 4 × 2.4, door to the floor
        let pieces = RoomGeometry.pieces(wallSize: SIMD2(4, 2.4), holes: [door])
        #expect(pieces.count == 3)  // left, right, above; nothing below a door
        let area = pieces.map { $0.size.x * $0.size.y }.reduce(0, +)
        #expect(abs(area - (4 * 2.4 - 1 * 2)) < 1e-4)
    }

    @Test func windowLeavesSillAndLintel() {
        let window = WallHole(id: "w", kind: .window, center: SIMD2(0.5, 0.2), size: SIMD2(1.2, 1))
        let pieces = RoomGeometry.pieces(wallSize: SIMD2(4, 2.4), holes: [window])
        #expect(pieces.count == 4)
        let area = pieces.map { $0.size.x * $0.size.y }.reduce(0, +)
        #expect(abs(area - (4 * 2.4 - 1.2)) < 1e-4)
    }

    @Test func demoRoomOpeningsResolveToTheirWalls() {
        let g = DemoFixtures.roomGeometry()
        let south = g.walls.first { $0.id == "wall-s" }!
        let east = g.walls.first { $0.id == "wall-e" }!
        #expect(g.holes(in: south).map(\.kind) == [.door])
        #expect(g.holes(in: east).map(\.kind) == [.window])
        #expect(g.holes(in: g.walls.first { $0.id == "wall-n" }!).isEmpty)
    }

    @Test func openingWithoutParentIsMatchedByPosition() {
        var g = DemoFixtures.roomGeometry()
        g.openings = g.openings.map { var o = $0; o.parentId = nil; return o }
        let east = g.walls.first { $0.id == "wall-e" }!
        let hole = g.holes(in: east).first
        #expect(hole?.kind == .window)
        #expect(abs((hole?.center.x ?? 99) - 0.8) < 1e-4)  // z = -0.8 is local +0.8 on a wall facing -x
    }
}

@Suite struct CutawayTests {
    @Test func cutsWallsAndOpeningsKeepingTheirBottoms() {
        let g = DemoFixtures.roomGeometry().centered().cutaway(at: 1.2)
        for wall in g.walls {
            #expect(abs(wall.dimensions.y - 1.2) < 1e-4)
            #expect(abs(wall.transform.position.y - 0.6) < 1e-4)
        }
        let door = g.openings.first { $0.kind == .door }!
        #expect(abs(door.dimensions.y - 1.2) < 1e-4)  // door ran 0 to 2.05 m
        let window = g.openings.first { $0.kind == .window }!
        #expect(abs(window.dimensions.y - 0.4) < 1e-4)  // window ran 0.8 to 2.0 m
        #expect(g.objects == DemoFixtures.roomGeometry().centered().objects)
    }

    @Test func dropsOpeningsEntirelyAboveTheCut() {
        let g = DemoFixtures.roomGeometry().centered().cutaway(at: 0.5)
        #expect(!g.openings.contains { $0.kind == .window })
    }
}
