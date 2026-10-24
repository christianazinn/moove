import Foundation

// OWNER: voxel-models agent. Moove pieces in the house style (palette, jitter, front at +z):
// bikes and suitcases. Placeholders until the real builders land.

extension Canvas {
    func bike(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }

    func suitcase(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }
}
