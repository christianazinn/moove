import Foundation

// OWNER: voxel-models agent. Moove pieces in the house style (palette, jitter, front at +z):
// benches and ottomans. Placeholders until the real builders land.

extension Canvas {
    func bench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }

    func ottoman(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }
}
