import Foundation
import RoomPlan
import simd
import MooveKit

extension RoomTransform {
    init(_ m: simd_float4x4) {
        self.init(columns: [m.columns.0, m.columns.1, m.columns.2, m.columns.3])
    }

    var matrix: simd_float4x4 { simd_float4x4(columns[0], columns[1], columns[2], columns[3]) }
}

extension RoomGeometry {
    /// Converts RoomPlan's result, keeping real sizes and positions.
    init(_ room: CapturedRoom) {
        func surface(_ s: CapturedRoom.Surface, _ kind: SurfaceKind) -> Surface {
            Surface(id: s.identifier.uuidString, kind: kind, parentId: s.parentIdentifier?.uuidString,
                    dimensions: s.dimensions, transform: RoomTransform(s.transform))
        }
        let floors: [Floor] = room.floors.map { f in
            // Corners are in the floor's local space; fall back to its rectangle.
            var corners = f.polygonCorners
            if corners.count < 3 {
                let w = f.dimensions.x / 2, d = f.dimensions.y / 2
                corners = [SIMD3(-w, -d, 0), SIMD3(w, -d, 0), SIMD3(w, d, 0), SIMD3(-w, d, 0)]
            }
            let world = corners.map { c in (f.transform * SIMD4(c.x, c.y, c.z, 1)) }
            let elevation = world.map(\.y).reduce(0, +) / Float(world.count)
            return Floor(id: f.identifier.uuidString, outline: world.map { SIMD2($0.x, $0.z) }, elevation: elevation)
        }
        self.init(
            walls: room.walls.map { surface($0, .wall) },
            openings: room.doors.map { surface($0, .door) } + room.windows.map { surface($0, .window) } + room.openings.map { surface($0, .opening) },
            floors: floors,
            objects: room.objects.map { o in
                Object(id: o.identifier.uuidString, category: String(describing: o.category),
                       dimensions: o.dimensions, transform: RoomTransform(o.transform))
            }
        )
    }
}
