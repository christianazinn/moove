import Foundation

/// A simple, recognizable stand-in for furniture that has no 3D model yet: a few
/// rounded boxes (a table's top and legs, a sofa's seat, back and arms) instead
/// of one plain block. Everything stays inside RoomPlan's measured box and stands
/// on its floor. Coordinates are in the object's local frame: centered on the box,
/// y up. RoomPlan doesn't say which way a chair faces, so backs go on the -z side.
public enum FurniturePlaceholder {
    public struct Part: Equatable, Sendable {
        public var center: SIMD3<Float>
        public var size: SIMD3<Float>
        public var cornerRadius: Float
    }

    public static func parts(category: String, size d: SIMD3<Float>) -> [Part] {
        let bottom = -d.y / 2
        // Part spanning y0...y1 (from the floor) over the given x/z extent and offset.
        func part(x: Float, z: Float, y0: Float, y1: Float, w: Float, depth: Float, r: Float? = nil) -> Part {
            let h = max(0.005, y1 - y0)
            let radius = r ?? min(0.03, min(w, h, depth) / 4)
            return Part(center: SIMD3(x, bottom + y0 + h / 2, z), size: SIMD3(w, h, depth), cornerRadius: radius)
        }
        let full = [part(x: 0, z: 0, y0: 0, y1: d.y, w: d.x, depth: d.z)]
        // Too small to read as anything but a block.
        guard min(d.x, d.z) > 0.15, d.y > 0.2 else { return full }

        let leg = min(0.06, min(d.x, d.z) * 0.12)
        func legs(height: Float) -> [Part] {
            let lx = d.x / 2 - leg / 2 - 0.01, lz = d.z / 2 - leg / 2 - 0.01
            return [(-lx, -lz), (lx, -lz), (-lx, lz), (lx, lz)].map { part(x: $0.0, z: $0.1, y0: 0, y1: height, w: leg, depth: leg, r: leg / 3) }
        }

        switch category.lowercased() {
        case "table":
            let top = min(0.05, d.y * 0.12)
            return [part(x: 0, z: 0, y0: d.y - top, y1: d.y, w: d.x, depth: d.z)] + legs(height: d.y - top)

        case "chair":
            let seatTop = min(d.y * 0.5, 0.5)
            let seat = min(0.07, seatTop * 0.2)
            let back = min(0.07, d.z * 0.15)
            return [
                part(x: 0, z: 0, y0: seatTop - seat, y1: seatTop, w: d.x, depth: d.z),
                part(x: 0, z: -d.z / 2 + back / 2, y0: seatTop, y1: d.y, w: d.x * 0.92, depth: back),
            ] + legs(height: seatTop - seat)

        case "sofa":
            let seatTop = min(d.y * 0.55, 0.48)
            let back = min(0.25, d.z * 0.28)
            let arm = min(0.22, d.x * 0.12)
            let armTop = min(d.y, seatTop + (d.y - seatTop) * 0.45)
            return [
                part(x: 0, z: back / 2, y0: 0, y1: seatTop, w: d.x - 2 * arm, depth: d.z - back),
                part(x: 0, z: -d.z / 2 + back / 2, y0: 0, y1: d.y, w: d.x, depth: back),
                part(x: -d.x / 2 + arm / 2, z: back / 2, y0: 0, y1: armTop, w: arm, depth: d.z - back),
                part(x: d.x / 2 - arm / 2, z: back / 2, y0: 0, y1: armTop, w: arm, depth: d.z - back),
            ]

        case "bed":
            let head = min(0.08, d.z * 0.06)
            let frameTop = min(d.y * 0.3, 0.3)
            let mattressTop = min(d.y, frameTop + min(0.25, d.y * 0.3))
            let inset: Float = 0.03
            return [
                part(x: 0, z: head / 2, y0: 0, y1: frameTop, w: d.x, depth: d.z - head),
                part(x: 0, z: head / 2, y0: frameTop, y1: mattressTop, w: d.x - 2 * inset, depth: d.z - head - 2 * inset, r: 0.05),
                part(x: 0, z: -d.z / 2 + head / 2, y0: 0, y1: d.y, w: d.x, depth: head),
            ]

        case "storage":
            // Cabinet body on a recessed plinth, with a slightly overhanging top.
            let plinth = min(0.08, d.y * 0.1)
            let top = min(0.03, d.y * 0.06)
            return [
                part(x: 0, z: 0, y0: 0, y1: plinth, w: d.x - 0.04, depth: d.z - 0.04),
                part(x: 0, z: 0, y0: plinth, y1: d.y - top, w: d.x - 0.01, depth: d.z - 0.01),
                part(x: 0, z: 0, y0: d.y - top, y1: d.y, w: d.x, depth: d.z),
            ]

        default:
            return full
        }
    }
}
