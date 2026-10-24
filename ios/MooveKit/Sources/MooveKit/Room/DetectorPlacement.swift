import Foundation

/// Final placement of a detector find (#267): its depth and center, and which way
/// its front faces. LiDAR only sees the side facing the camera, so a measured box is
/// the object's front slab, and `BoxFit` only knows the box's axes, not its front.
public enum DetectorPlacement {
    /// A box within this gap (m) of a roughly parallel wall stands against it.
    public static let wallGap: Float = 0.3
    /// Ignore room-center / camera directions closer than this (m): too unstable.
    static let minDirection: Float = 0.3

    /// Pads the box's depth up to `minDepth`. The seen face stays where it was seen:
    /// the center moves away from `camera` by half the added depth. Without a
    /// camera, or when the camera saw the box side-on, it grows evenly.
    public static func padDepth(_ box: FittedBox, to minDepth: Float, camera: SIMD3<Float>?) -> FittedBox {
        guard box.size.z < minDepth else { return box }
        let added = minDepth - box.size.z
        var out = box
        out.size.z = minDepth
        guard let camera else { return out }
        let away = SIMD2(box.center.x - camera.x, box.center.z - camera.z)
        let length = (away * away).sum().squareRoot()
        guard length > minDirection else { return out }
        let z = depthAxis(box.yaw)
        let cosine = (z * away).sum() / length
        guard abs(cosine) > 0.25 else { return out }  // seen from the side: its depth faces weren't the near ones
        let shift = z * (added / 2) * (cosine > 0 ? 1 : -1)
        out.center += SIMD3(shift.x, 0, shift.y)
        return out
    }

    /// Turns the box (by 0 or 180°, size unchanged) so its front (+z, the voxel and
    /// layout convention) faces the room: back to the wall when it stands against one
    /// within `wallGap`, otherwise toward the room's center, else toward `camera`.
    public static func faced(_ box: FittedBox, in room: RoomGeometry, camera: SIMD3<Float>?) -> FittedBox {
        guard let want = frontDirection(box, in: room, camera: camera) else { return box }
        var out = box
        if (depthAxis(box.yaw) * want).sum() < 0 { out.yaw = normalized(box.yaw + .pi) }
        return out
    }

    /// Pads to the category's minimum depth (re-centered away from the camera), then faces it.
    public static func place(_ o: RoomGeometry.Object, in room: RoomGeometry, camera: SIMD3<Float>?) -> RoomGeometry.Object {
        var box = FittedBox(center: o.transform.position, size: o.dimensions, yaw: o.transform.yaw)
        box = padDepth(box, to: ObjectVocabulary.minimumDepth[o.category] ?? 0.05, camera: camera)
        box = faced(box, in: room, camera: camera)
        var out = o
        out.dimensions = box.size
        out.transform = box.transform
        return out
    }

    /// Unit direction (x, z) the front should face, or nil when nothing says.
    static func frontDirection(_ box: FittedBox, in room: RoomGeometry, camera: SIMD3<Float>?) -> SIMD2<Float>? {
        let x = SIMD2(cos(box.yaw), -sin(box.yaw))  // the box's width axis in (x, z)
        var nearest: (gap: Float, away: SIMD2<Float>)?
        for w in room.walls {
            let wx = unit(SIMD2(w.transform.columns[0].x, w.transform.columns[0].z))
            let wz = unit(SIMD2(w.transform.columns[2].x, w.transform.columns[2].z))
            guard let wx, let wz, abs((wx * x).sum()) > 0.7 else { continue }  // back roughly along the wall
            let l = w.transform.inverseApply(box.center)
            guard abs(l.x) <= w.dimensions.x / 2 + 0.2, abs(l.z) > 0.01 else { continue }
            let gap = abs(l.z) - box.size.z / 2
            guard gap <= wallGap, gap < (nearest?.gap ?? .infinity) else { continue }
            nearest = (gap, wz * (l.z > 0 ? 1 : -1))
        }
        if let nearest { return nearest.away }
        let here = SIMD2(box.center.x, box.center.z)
        let hull = StructureCheck.roomFootprint(room)
        if !hull.isEmpty {
            let center = hull.reduce(SIMD2<Float>(0, 0), +) / Float(hull.count)
            if let d = unit(center - here, min: minDirection) { return d }
        }
        if let camera, let d = unit(SIMD2(camera.x, camera.z) - here, min: minDirection) { return d }
        return nil
    }

    /// The box's local +z (its front) in world (x, z), for `RoomTransform.at(_:yaw:)`.
    static func depthAxis(_ yaw: Float) -> SIMD2<Float> { SIMD2(sin(yaw), cos(yaw)) }

    static func unit(_ v: SIMD2<Float>, min: Float = 1e-4) -> SIMD2<Float>? {
        let l = (v * v).sum().squareRoot()
        return l > min ? v / l : nil
    }

    static func normalized(_ a: Float) -> Float {
        var a = a.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a <= -.pi { a += 2 * .pi }
        return a
    }
}
