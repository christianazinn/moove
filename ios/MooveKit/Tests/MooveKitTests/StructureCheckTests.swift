import Foundation
import Testing
@testable import MooveKit

/// A real iPad Pro scan (bedroom, 2026-10-24) with RoomPlan's 2 objects plus 14
/// detector finds. Ground truth comes from looking at each find's auto photo.
@Suite struct StructureCheckTests {
    let room: RoomGeometry

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "ipad-bedroom-geometry", withExtension: "json", subdirectory: "Fixtures"))
        room = try JSONDecoder().decode(RoomGeometry.self, from: Data(contentsOf: url))
    }

    private func verdict(_ idPrefix: String) throws -> StructureCheck.Verdict {
        let o = try #require(room.objects.first { $0.id.hasPrefix(idPrefix) }, "no object \(idPrefix)")
        return StructureCheck.verdict(for: o, in: room)
    }

    @Test func keepsRealObjects() throws {
        #expect(try verdict("59B5") == .keep)  // sink (RoomPlan)
        #expect(try verdict("8E36") == .keep)  // cabinet (RoomPlan)
        #expect(try verdict("C4FB") == .keep)  // laptop
        #expect(try verdict("4389") == .keep)  // broom + dustpan, labeled vacuum
    }

    @Test func renamesRealThingsWithImpossibleLabels() throws {
        // Photo light stands, ~2.1-2.3 m tall, labeled "vacuum".
        guard case .unknown = try verdict("ECF2") else { Issue.record("ECF2 stand should be unknown"); return }
        guard case .unknown = try verdict("CC2F") else { Issue.record("CC2F stand should be unknown"); return }
    }

    @Test func dropsRoomStructure() throws {
        let falsePositives: [(String, String)] = [
            ("52CF", "interior window labeled mirror"),
            ("88AB", "view through the window labeled mirror"),
            ("3DD1", "baseboard labeled vacuum"),
            ("637B", "wall with a sign labeled mirror"),
            ("7030", "door frame labeled basket"),
            ("9A87", "backdrop on a wall labeled refrigerator"),
            ("997D", "wall panel labeled room divider"),
            ("DD44", "high on a far wall labeled mirror"),
            ("05F7", "wall above the counter labeled refrigerator"),
            // Pink bean bag ~0.5 m beyond the scanned walls (a gap in RoomPlan's walls);
            // its photo shows it half-hidden behind a wall edge, i.e. in the next space.
            ("B19E", "bean bag outside the scanned room"),
        ]
        for (id, what) in falsePositives {
            guard case .drop = try verdict(id) else { Issue.record("should drop \(id): \(what)"); continue }
        }
    }

    @Test func applyKeepsSixAndRenamesTwo() {
        let (kept, dropped) = StructureCheck.apply(room.objects, in: room)
        #expect(kept.count == 6)
        #expect(dropped.count == 10)
        #expect(kept.filter { $0.category == StructureCheck.unknownCategory }.count == 2)
    }

    @Test func wallMountedArtSurvives() {
        // A painting flat on a wall is legitimate.
        let wall = room.walls[0]
        let p = wall.transform.apply(SIMD3(0, 0.2, 0.03))
        let yaw = wall.transform.yaw
        let art = RoomGeometry.Object(id: "art", category: "art", dimensions: SIMD3(0.6, 0.5, 0.03), transform: .at(p, yaw: yaw))
        #expect(StructureCheck.verdict(for: art, in: room) == .keep)
    }
}
