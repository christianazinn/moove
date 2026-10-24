import Foundation

// OWNER: mesher agent.

public enum VoxelMesher {
    /// Merges a grid into one mesh: only faces between a filled voxel and empty space,
    /// coplanar same-color faces merged (greedy meshing). `centered`: x/z centered on the
    /// grid (furniture); otherwise voxel (0,0,0)'s corner is the origin (the house).
    public static func mesh(_ grid: VoxelGrid, centered: Bool = true) -> VoxelMesh {
        VoxelMesh()
    }
}

extension IsoSprite {
    /// A dimetric thumbnail of the grid as seen from front-right and above, fitted to the unit square.
    public static func render(_ grid: VoxelGrid) -> IsoSprite {
        IsoSprite()
    }
}
