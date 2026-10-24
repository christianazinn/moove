import Foundation
import Testing
@testable import MooveKit

struct VoxelMesherTests {
    private func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private func checkWellFormed(_ m: VoxelMesh) {
        #expect(m.positions.count == m.normals.count)
        #expect(m.positions.count % 4 == 0)
        #expect(m.indices.count % 3 == 0)
        #expect(m.triangleColors.count == m.triangleCount)
        #expect(m.triangleColors.allSatisfy { Int($0) < m.palette.count })
        #expect(m.indices.allSatisfy { Int($0) < m.positions.count })
        // Winding: (b - a) × (c - a) points along the face normal.
        var bad = 0
        for t in 0..<m.triangleCount {
            let ia = Int(m.indices[3 * t]), ib = Int(m.indices[3 * t + 1]), ic = Int(m.indices[3 * t + 2])
            let a = m.positions[ia], b = m.positions[ib], c = m.positions[ic]
            let n = cross(b - a, c - a)
            let dot = (n * m.normals[ia]).sum()
            if !(dot > 0) { bad += 1 }
        }
        #expect(bad == 0)
    }

    @Test func singleVoxel() {
        var g = VoxelGrid(nx: 1, ny: 1, nz: 1)
        g[0, 0, 0] = 0xFF0000
        let m = VoxelMesher.mesh(g)
        #expect(m.triangleCount == 12)
        #expect(m.positions.count == 24)
        #expect(Set(m.normals.map { "\($0)" }).count == 6)
        #expect(m.palette == [0xFF0000])
        let xs = m.positions.map(\.x), ys = m.positions.map(\.y), zs = m.positions.map(\.z)
        #expect(abs(xs.min()! + 0.025) < 1e-6 && abs(xs.max()! - 0.025) < 1e-6)
        #expect(abs(zs.min()! + 0.025) < 1e-6 && abs(zs.max()! - 0.025) < 1e-6)
        #expect(abs(ys.min()!) < 1e-6 && abs(ys.max()! - 0.05) < 1e-6)
        checkWellFormed(m)
    }

    @Test func uncenteredStartsAtOrigin() {
        var g = VoxelGrid(nx: 4, ny: 2, nz: 3)
        g[3, 1, 2] = 0x00FF00
        let m = VoxelMesher.mesh(g, centered: false)
        let lo = m.positions.reduce(SIMD3<Float>(repeating: 9)) { pointwiseMin($0, $1) }
        let hi = m.positions.reduce(SIMD3<Float>(repeating: -9)) { pointwiseMax($0, $1) }
        #expect(abs(lo.x - 0.15) < 1e-5 && abs(lo.y - 0.05) < 1e-5 && abs(lo.z - 0.10) < 1e-5)
        #expect(abs(hi.x - 0.20) < 1e-5 && abs(hi.y - 0.10) < 1e-5 && abs(hi.z - 0.15) < 1e-5)
    }

    @Test func solidCubeMergesToTwelveTriangles() {
        var g = VoxelGrid(nx: 3, ny: 3, nz: 3)
        g.fill(x: 0...2, y: 0...2, z: 0...2, 0x123456)
        let m = VoxelMesher.mesh(g)
        #expect(m.triangleCount == 12)
        #expect(m.palette == [0x123456])
        checkWellFormed(m)
    }

    @Test func adjacentColorsHaveNoInternalFaces() {
        var g = VoxelGrid(nx: 2, ny: 1, nz: 1)
        g[0, 0, 0] = 0xFF0000
        g[1, 0, 0] = 0x0000FF
        let m = VoxelMesher.mesh(g)
        // 10 exposed unit faces, none merge across colors.
        #expect(m.triangleCount == 20)
        #expect(m.palette.count == 2)
        // No face lies on the shared plane x = 0.
        for t in 0..<m.triangleCount {
            let pts = (0..<3).map { m.positions[Int(m.indices[3 * t + $0])] }
            #expect(!pts.allSatisfy { abs($0.x) < 1e-6 })
        }
        checkWellFormed(m)
    }

    @Test func hollowShellHasNoFacesBetweenFilledNeighbors() {
        var g = VoxelGrid(nx: 5, ny: 5, nz: 5)
        g.fill(x: 0...4, y: 0...4, z: 0...4, 0xAAAAAA)
        g.fill(x: 1...3, y: 1...3, z: 1...3, nil)
        let m = VoxelMesher.mesh(g, centered: false)
        // 6 outer faces + 6 inner cavity faces, each one merged quad.
        #expect(m.triangleCount == 24)
        // Every quad's center, nudged against its normal, is inside a filled voxel; nudged
        // along it, it is empty or outside.
        let s = Float(VoxelGrid.voxelSize)
        for q in 0..<(m.positions.count / 4) {
            let c = (m.positions[4 * q] + m.positions[4 * q + 2]) / 2
            let n = m.normals[4 * q]
            func cell(_ p: SIMD3<Float>) -> VoxelColor? {
                let v = (p / s).rounded(.down)
                return g[Int(v.x), Int(v.y), Int(v.z)]
            }
            #expect(cell(c - n * s / 2) != nil)
            #expect(cell(c + n * s / 2) == nil)
        }
        checkWellFormed(m)
    }

    @Test func paletteInFirstSeenOrderAndExactColors() {
        var g = VoxelGrid(nx: 3, ny: 1, nz: 1)
        g[0, 0, 0] = 0x010203
        g[1, 0, 0] = 0xFFFFFF
        g[2, 0, 0] = 0x010203
        let m = VoxelMesher.mesh(g)
        #expect(Set(m.palette) == [0x010203, 0xFFFFFF])
        #expect(m.palette.count == 2)
    }

    @Test func boxGridCounts() {
        // 1.6 × 0.5 × 2.1 m solid box.
        var g = VoxelGrid(nx: VoxelGrid.count(1.6), ny: VoxelGrid.count(0.5), nz: VoxelGrid.count(2.1))
        g.fill(x: 0...(g.nx - 1), y: 0...(g.ny - 1), z: 0...(g.nz - 1), 0xB98D5E)
        let t0 = Date()
        let m = VoxelMesher.mesh(g)
        let dt = Date().timeIntervalSince(t0)
        print("VoxelMesher box \(g.nx)x\(g.ny)x\(g.nz): \(m.triangleCount) triangles in \(String(format: "%.2f", dt * 1000)) ms")
        #expect(m.triangleCount == 12)
        checkWellFormed(m)
    }

    /// A house-sized grid: plank floor of alternating colors, thin walls, scattered furniture.
    static func sparseHouse() -> VoxelGrid {
        var g = VoxelGrid(nx: 220, ny: 26, nz: 210)
        for z in 0..<210 {
            g.fill(x: 0...219, y: 0...0, z: z...z, z % 4 < 2 ? 0xC8A27A : 0xB8926A)
        }
        g.fill(x: 0...0, y: 1...25, z: 0...209, 0xEEE6DA)
        g.fill(x: 219...219, y: 1...25, z: 0...209, 0xEEE6DA)
        g.fill(x: 0...219, y: 1...25, z: 0...0, 0xEEE6DA)
        g.fill(x: 0...219, y: 1...25, z: 209...209, 0xEEE6DA)
        g.fill(x: 110...110, y: 1...25, z: 0...209, 0xE0D8CC)
        g.fill(x: 110...110, y: 1...16, z: 100...117, nil) // a door
        var seed: UInt32 = 12345
        func next() -> Int { seed = seed &* 1_103_515_245 &+ 12345; return Int((seed >> 8) % 10_000) }
        for _ in 0..<300 {
            let x = 2 + next() % 200, z = 2 + next() % 190, w = 2 + next() % 15, d = 2 + next() % 15, h = 1 + next() % 15
            g.fill(x: x...(x + w), y: 1...h, z: z...(z + d), UInt32(0x302010 + (next() % 8) * 0x111111))
        }
        return g
    }

    @Test func largeSparseGridIsFast() {
        let g = Self.sparseHouse()
        let t0 = Date()
        let m = VoxelMesher.mesh(g, centered: false)
        let dt = Date().timeIntervalSince(t0)
        print("VoxelMesher sparse 220x26x210 (\(g.filledCount) filled): \(m.triangleCount) triangles in \(String(format: "%.1f", dt * 1000)) ms")
        #expect(m.triangleCount > 0)
        #expect(dt < 5) // debug builds are slow; release is well under a second
        checkWellFormed(m)
    }

    // MARK: IsoSprite

    private func inUnitSquare(_ s: IsoSprite) -> Bool {
        for f in s.faces { for p in f.points where p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1 { return false } }
        return true
    }

    @Test func isoFullyHiddenVoxelDrawsNothing() {
        // (1,1,1) projects exactly over (0,0,0) on the view ray, hiding it.
        var g = VoxelGrid(nx: 2, ny: 2, nz: 2)
        g[0, 0, 0] = 0x0000FF
        g[1, 1, 1] = 0xFF0000
        let s = IsoSprite.render(g)
        #expect(s.faces.count == 3)
        #expect(Set(s.faces.map(\.color)) == [0xFF0000, IsoSprite.shaded(0xFF0000, 0.82), IsoSprite.shaded(0xFF0000, 0.68)])
    }

    @Test func isoHalfHiddenFacesBecomeTriangles() {
        var g = VoxelGrid(nx: 2, ny: 2, nz: 1)
        g[0, 0, 0] = 0x0000FF
        g[1, 1, 0] = 0xFF0000
        let s = IsoSprite.render(g)
        // Back cube: half its top, half its right, all its front. Front cube: 3 quads.
        #expect(s.faces.filter { $0.points.count == 3 }.count == 2)
        #expect(s.faces.filter { $0.points.count == 4 }.count == 4)
        #expect(inUnitSquare(s))
    }

    @Test func isoEmptyGrid() {
        #expect(IsoSprite.render(VoxelGrid(nx: 3, ny: 3, nz: 3)).faces.isEmpty)
    }

    @Test func isoSingleVoxel() {
        var g = VoxelGrid(nx: 1, ny: 1, nz: 1)
        g[0, 0, 0] = 0x808080
        let s = IsoSprite.render(g)
        #expect(s.faces.count == 3)
        #expect(Set(s.faces.map(\.color)) == [0x808080, IsoSprite.shaded(0x808080, 0.82), IsoSprite.shaded(0x808080, 0.68)])
        let pts = s.faces.flatMap(\.points)
        #expect(inUnitSquare(s))
        // Fitted and centered: touches both sides of its longer axis.
        let xs = pts.map(\.x), ys = pts.map(\.y)
        #expect(abs(xs.min()! + xs.max()! - 1) < 1e-5 && abs(ys.min()! + ys.max()! - 1) < 1e-5)
        #expect(max(xs.max()! - xs.min()!, ys.max()! - ys.min()!) > 0.999)
    }

    @Test func isoPartialOcclusionAndBounds() {
        // An L: a tall column behind a low block hides part of it.
        var g = VoxelGrid(nx: 3, ny: 3, nz: 3)
        g.fill(x: 0...2, y: 0...0, z: 0...2, 0x996633)
        g.fill(x: 0...0, y: 0...2, z: 0...0, 0x336699)
        let s = IsoSprite.render(g)
        #expect(!s.faces.isEmpty)
        #expect(s.faces.allSatisfy { $0.points.count == 3 || $0.points.count == 4 })
        #expect(inUnitSquare(s))
    }

    @Test func isoBedSizedFaceCount() {
        var g = VoxelGrid(nx: 32, ny: 12, nz: 42)
        g.fill(x: 0...31, y: 0...3, z: 0...41, 0x7A5230)
        g.fill(x: 1...30, y: 4...7, z: 1...40, 0xF2EEE6)
        g.fill(x: 0...31, y: 4...11, z: 0...1, 0x7A5230)
        g.fill(x: 3...12, y: 8...9, z: 3...8, 0xFFFFFF)
        g.fill(x: 19...28, y: 8...9, z: 3...8, 0xFFFFFF)
        for z in stride(from: 12, to: 41, by: 2) { g.fill(x: 1...30, y: 8...8, z: z...z, 0x5B7DB1) }
        let s = IsoSprite.render(g)
        #expect(!s.faces.isEmpty && s.faces.count < 3000)
    }

    @Test func isoDownsamplesLargeGrids() {
        let s = IsoSprite.render(Self.sparseHouse())
        #expect(!s.faces.isEmpty && s.faces.count < 20_000)
        #expect(inUnitSquare(s))
    }
}
