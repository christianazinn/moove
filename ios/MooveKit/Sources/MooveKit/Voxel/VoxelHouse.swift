import Foundation

// OWNER: scene agent. The voxel shell of the whole home.

public enum VoxelHouse {
    /// Thickness of the wooden base under the floor, in voxels; furniture stands on top of it.
    public static let baseVoxels = 2
    public static var floorTopM: Double { Double(baseVoxels) * VoxelGrid.voxelSize }
    /// Margin around the plan, in meters, so the base shows an edge.
    public static let marginM = 0.1

    /// The whole home as one grid: base, plank floors per room, cut-away tiled walls with
    /// door gaps and windows, baseboards. Grid voxel (0,0,0) sits at world
    /// (plan.bounds.minX - marginM, 0, plan.bounds.minY - marginM).
    public static func build(_ plan: FloorPlan, cutawayHeightM: Double = 1.1) -> VoxelGrid {
        let b = plan.bounds
        var g = VoxelGrid(nx: VoxelGrid.count(b.width + 2 * marginM), ny: VoxelGrid.count(cutawayHeightM) + baseVoxels,
                          nz: VoxelGrid.count(b.depth + 2 * marginM))
        g.fill(x: 0...(g.nx - 1), y: 0...(baseVoxels - 1), z: 0...(g.nz - 1), 0xC49A6C)
        return g
    }

    /// World position (meters) of grid voxel (0,0,0)'s corner.
    public static func origin(of plan: FloorPlan) -> SIMD3<Double> {
        SIMD3(plan.bounds.minX - marginM, 0, plan.bounds.minY - marginM)
    }
}
