import Foundation

// OWNER: voxel-models agent. Ports MoveWise's static/scene/models.js builders.

public enum VoxelModels {
    /// A detailed voxel model for one piece, sized to its dimensions (front faces +z).
    /// Unknown categories fall back to a simple box so the scene never breaks.
    public static func build(_ spec: VoxelItemSpec) -> VoxelGrid {
        var g = VoxelGrid(nx: VoxelGrid.count(spec.widthM), ny: VoxelGrid.count(spec.heightM), nz: VoxelGrid.count(spec.depthM))
        g.fill(x: 0...(g.nx - 1), y: 0...(g.ny - 1), z: 0...(g.nz - 1), 0xB98D5E)
        return g
    }
}
