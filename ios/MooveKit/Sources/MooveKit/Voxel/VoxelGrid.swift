import Foundation

// Shared contract for the voxel dollhouse (#76). Owned by the integrator; builders,
// mesher and renderers code against these types and must not change their shape.
//
// Axes (all voxel code): x = width, y = up, z = depth. A piece's FRONT faces +z,
// matching LayoutSolver / Placement (rotationDeg 0 = front toward plan +y = world +z).
// One voxel is `VoxelGrid.voxelSize` meters (5 cm).

/// A packed 0xRRGGBB color. 0 is never a color (it means empty in `VoxelGrid`).
public typealias VoxelColor = UInt32

/// A dense box of voxels. Index `(x, y, z)` with 0 ≤ x < nx etc.; y = 0 is the floor layer.
public struct VoxelGrid: Sendable, Hashable {
    public static let voxelSize = 0.05

    public let nx: Int
    public let ny: Int
    public let nz: Int
    /// nx * ny * nz cells, x fastest then z then y. 0 = empty, else color | 0x1000000.
    public private(set) var cells: [UInt32]

    public init(nx: Int, ny: Int, nz: Int) {
        self.nx = max(1, nx)
        self.ny = max(1, ny)
        self.nz = max(1, nz)
        cells = Array(repeating: 0, count: self.nx * self.ny * self.nz)
    }

    @inline(__always) func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * nz + z) * nx + x }

    public func contains(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= 0 && y >= 0 && z >= 0 && x < nx && y < ny && z < nz
    }

    /// The color at a cell, or nil when empty or out of bounds.
    public subscript(x: Int, y: Int, z: Int) -> VoxelColor? {
        get {
            guard contains(x, y, z) else { return nil }
            let c = cells[index(x, y, z)]
            return c == 0 ? nil : c & 0xFFFFFF
        }
        set {
            guard contains(x, y, z) else { return }
            cells[index(x, y, z)] = newValue.map { ($0 & 0xFFFFFF) | 0x1000000 } ?? 0
        }
    }

    /// Fills the inclusive box [x0...x1] × [y0...y1] × [z0...z1], clipped to the grid. Empty ranges are a no-op.
    public mutating func fill(x: ClosedRange<Int>, y: ClosedRange<Int>, z: ClosedRange<Int>, _ color: VoxelColor?) {
        let xs = max(0, x.lowerBound), xe = min(nx - 1, x.upperBound)
        let ys = max(0, y.lowerBound), ye = min(ny - 1, y.upperBound)
        let zs = max(0, z.lowerBound), ze = min(nz - 1, z.upperBound)
        guard xs <= xe, ys <= ye, zs <= ze else { return }
        for yy in ys...ye {
            for zz in zs...ze {
                for xx in xs...xe { self[xx, yy, zz] = color }
            }
        }
    }

    public var filledCount: Int { cells.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }

    /// Size in meters (width, height, depth).
    public var sizeM: (width: Double, height: Double, depth: Double) {
        (Double(nx) * Self.voxelSize, Double(ny) * Self.voxelSize, Double(nz) * Self.voxelSize)
    }

    /// Number of voxels for a length in meters (at least 1).
    public static func count(_ meters: Double) -> Int { max(1, Int((meters / voxelSize).rounded())) }
}

/// A triangle mesh for one voxel grid, ready for RealityKit's MeshDescriptor.
/// Coordinates in meters: centered on x and z, y = 0 at the grid's floor.
public struct VoxelMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>] = []
    public var normals: [SIMD3<Float>] = []
    /// Three indices per triangle, wound counterclockwise seen from outside (RealityKit front faces).
    public var indices: [UInt32] = []
    /// Per triangle: an index into `palette`.
    public var triangleColors: [UInt32] = []
    /// Distinct colors used, 0xRRGGBB.
    public var palette: [VoxelColor] = []

    public init() {}

    public var triangleCount: Int { indices.count / 3 }
}

/// What a piece of furniture is, for picking a voxel builder.
public struct VoxelItemSpec: Sendable, Hashable {
    public var category: String
    public var name: String
    public var widthM: Double
    public var depthM: Double
    public var heightM: Double
    // Added by the voxel-models agent (optional, defaulted so existing callers compile):
    /// Stable per-item identity (scanObjectId or item id). Seeds the small details, so two
    /// scanned tables differ while the same item always looks the same.
    public var id: String?
    /// Vision-agent material ("oak", "mesh", "laminate", ...): palette and style hints.
    public var material: String?
    /// Brand ("IKEA", "Herman Miller", ...): style hints.
    public var brand: String?
    /// 1 (broken) to 5 (like new): wear (fading, scuffs, stains, a missing knob or slat).
    public var condition: Int?
    /// RoomPlan (iOS 17) object attributes as type-prefixed raw values, e.g. "ChairType.stool",
    /// "ChairLegType.star", "SofaType.lShaped", "TableShapeType.circularElliptic", "StorageType.shelf".
    /// They win over name keywords, which win over size heuristics.
    public var attributes: [String]
    /// Measured from scan photos: overrides the keyword palette for the main material / accent.
    public var primaryColor: VoxelColor?
    public var secondaryColor: VoxelColor?

    public init(category: String, name: String, widthM: Double, depthM: Double, heightM: Double,
                id: String? = nil, material: String? = nil, brand: String? = nil, condition: Int? = nil,
                attributes: [String] = [], primaryColor: VoxelColor? = nil, secondaryColor: VoxelColor? = nil) {
        self.category = category
        self.name = name
        self.widthM = widthM
        self.depthM = depthM
        self.heightM = heightM
        self.id = id
        self.material = material
        self.brand = brand
        self.condition = condition
        self.attributes = attributes
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }

    public init(_ item: LayoutItem) {
        self.init(category: item.category, name: item.name, widthM: item.widthM, depthM: item.depthM, heightM: item.heightM,
                  id: String(item.id))
    }

    public init(_ item: Item) {
        self.init(category: item.category, name: item.name, widthM: item.widthM, depthM: item.depthM, heightM: item.heightM,
                  id: item.scanObjectId ?? String(item.id), material: item.material, brand: item.brand, condition: item.condition)
    }
}

/// A flat 2.5D drawing of a grid for list thumbnails: polygons in drawing order
/// (back to front), coordinates in a unit square (0...1, y down).
public struct IsoSprite: Sendable, Equatable {
    public struct Face: Sendable, Equatable {
        public var points: [SIMD2<Float>]
        public var color: VoxelColor
    }
    public var faces: [Face] = []
    public init() {}
}
