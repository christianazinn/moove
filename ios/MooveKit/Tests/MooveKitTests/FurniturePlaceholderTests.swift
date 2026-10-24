import Testing
@testable import MooveKit

@Suite struct FurniturePlaceholderTests {
    static let cases: [(String, SIMD3<Float>)] = [
        ("table", SIMD3(1.4, 0.75, 0.7)), ("chair", SIMD3(0.6, 1.0, 0.6)), ("sofa", SIMD3(2.0, 0.85, 0.9)),
        ("bed", SIMD3(1.5, 1.0, 2.0)), ("storage", SIMD3(0.8, 1.8, 0.4)), ("television", SIMD3(1.2, 0.7, 0.1)),
        ("Table", SIMD3(0.5, 0.45, 0.5)), ("chair", SIMD3(0.1, 0.1, 0.1)),
    ]

    @Test(arguments: cases)
    func staysInsideTheBoxAndStandsOnTheFloor(category: String, size: SIMD3<Float>) {
        let parts = FurniturePlaceholder.parts(category: category, size: size)
        #expect(!parts.isEmpty)
        let eps: Float = 1e-4
        for p in parts {
            let lo = p.center - p.size / 2, hi = p.center + p.size / 2
            #expect(lo.x >= -size.x / 2 - eps && hi.x <= size.x / 2 + eps)
            #expect(lo.y >= -size.y / 2 - eps && hi.y <= size.y / 2 + eps)
            #expect(lo.z >= -size.z / 2 - eps && hi.z <= size.z / 2 + eps)
            #expect(p.size.x > 0 && p.size.y > 0 && p.size.z > 0)
            #expect(p.cornerRadius <= min(p.size.x, p.size.y, p.size.z) / 2 + eps)
        }
        // Something touches the floor (no floating furniture) and something reaches the top.
        #expect(parts.contains { abs($0.center.y - $0.size.y / 2 + size.y / 2) < eps })
        #expect(parts.contains { abs($0.center.y + $0.size.y / 2 - size.y / 2) < 1e-3 })
    }

    @Test func shapes() {
        #expect(FurniturePlaceholder.parts(category: "table", size: SIMD3(1.4, 0.75, 0.7)).count == 5)  // top + 4 legs
        #expect(FurniturePlaceholder.parts(category: "chair", size: SIMD3(0.6, 1.0, 0.6)).count == 6)   // seat, back, 4 legs
        #expect(FurniturePlaceholder.parts(category: "sofa", size: SIMD3(2, 0.85, 0.9)).count == 4)
        #expect(FurniturePlaceholder.parts(category: "lamp", size: SIMD3(0.4, 1.6, 0.4)).count == 1)    // plain block
        #expect(FurniturePlaceholder.parts(category: "chair", size: SIMD3(0.1, 0.1, 0.1)).count == 1)   // too small
    }
}
