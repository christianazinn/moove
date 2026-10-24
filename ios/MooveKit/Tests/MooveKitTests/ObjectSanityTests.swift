import Foundation
import Testing
@testable import MooveKit

@Suite struct ObjectSanityTests {
    func check(_ c: String, _ w: Double, _ h: Double, _ d: Double) -> ObjectSanity.Result {
        ObjectSanity.check(category: c, width: w, height: h, depth: d)
    }

    @Test func keepsNormalFurniture() {
        #expect(check("table", 1.4, 0.75, 0.7) == .ok)
        #expect(check("chair", 0.55, 0.9, 0.55) == .ok)
        #expect(check("sofa", 2.1, 0.85, 0.95) == .ok)
        #expect(check("bed", 1.6, 0.5, 2.05) == .ok)
        #expect(check("storage", 0.8, 1.9, 0.4) == .ok)
        #expect(check("refrigerator", 0.7, 1.8, 0.7) == .ok)
        #expect(check("television", 1.2, 0.7, 0.08) == .ok)
        // Detector classes with only a height range, and "other".
        #expect(check("bicycle", 1.7, 1.0, 0.6) == .ok)
        #expect(check("other", 0.3, 2.4, 0.3) == .ok)
    }

    @Test func relabelsLastNightsBadBoxes() {
        // 2.08 m tall "vacuum" and a 6 cm deep "refrigerator" (maincloud scan, Oct 24).
        guard case .relabel("other", _) = check("vacuum", 0.4, 2.08, 0.3) else { Issue.record("vacuum kept"); return }
        guard case .relabel("other", let why) = check("refrigerator", 0.9, 1.8, 0.06) else { Issue.record("fridge kept"); return }
        #expect(why.contains("6 cm"))
    }

    @Test func relabelsWrongSizeForTheCategory() {
        guard case .relabel = check("chair", 0.5, 2.4, 0.5) else { Issue.record("2.4 m chair"); return }
        guard case .relabel = check("toilet", 1.8, 0.4, 1.8) else { Issue.record("1.8 m toilet"); return }
    }

    @Test func toleratesSlightlyLooseBoxes() {
        // 10% over a bound is within the 15% slack.
        #expect(check("dishwasher", 0.6, 1.0, 0.6) == .ok)
    }

    @Test func dropsAbsurdBoxes() {
        guard case .drop = check("table", .nan, 0.7, 0.6) else { Issue.record("NaN"); return }
        guard case .drop = check("storage", 40, 2.4, 0.3) else { Issue.record("40 m"); return }
        guard case .drop = check("other", 1.0, 0.01, 1.0) else { Issue.record("1 cm"); return }
    }
}

/// The real iPad bedroom scan (see StructureCheckTests): what survives the structure
/// check must also pass the size check, so ObjectSanity never renames real finds there.
@Suite struct ObjectSanityRealScanTests {
    @Test func keepsWhatTheStructureCheckKept() throws {
        let url = try #require(Bundle.module.url(forResource: "ipad-bedroom-geometry", withExtension: "json", subdirectory: "Fixtures"))
        let room = try JSONDecoder().decode(RoomGeometry.self, from: Data(contentsOf: url))
        let kept = StructureCheck.apply(room.objects, in: room).kept
        #expect(!kept.isEmpty)
        for o in kept {
            let d = o.dimensions
            let r = ObjectSanity.check(category: o.category, width: Double(d.x), height: Double(d.y), depth: Double(d.z))
            #expect(r == .ok, "\(o.category) \(d): \(r)")
        }
    }
}
