import Foundation

// OWNER: voxel-models agent. Moove pieces in the house style (palette, jitter, front at +z):
// ranges / ovens, dishwashers and microwaves. Placeholders until the real builders land.

extension Canvas {
    func stove(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }

    func dishwasher(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }

    func microwave(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) { kraftBox(X, Y, Z, name) }
}
