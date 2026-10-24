import Foundation

/// Places an arbitrary 3D model (stock or captured) inside a RoomPlan object box.
///
/// RoomPlan's object transform is the box **center**, so the model is
/// normalized first (`offset`: center its X/Z, put its lowest point at y = 0),
/// then scaled, turned `yaw` about +Y, and dropped by `boxSize.y / 2` so it
/// stands on the box bottom, centered in X/Z.
///
/// The turn/scale rule is behaviorally identical to `ModelFit.fit` (PR #71):
/// align the model's long side with the box's long side, add the user's
/// quarter turns, then scale uniformly by the tightest axis. After rebasing
/// onto #71 the turn/scale part can delegate to `ModelFit`.
public struct FitToBox: Equatable, Sendable {
    /// Quarter turns about +Y, 0...3.
    public var quarterTurns: Int
    /// Uniform scale, model meters to box meters.
    public var scale: Float
    /// Translation applied before scale and rotation: minus the model's bottom-center.
    public var offset: SIMD3<Float>

    public init(quarterTurns: Int, scale: Float, offset: SIMD3<Float>) {
        self.quarterTurns = quarterTurns
        self.scale = scale
        self.offset = offset
    }

    /// Rotation about +Y in radians.
    public var yaw: Float { Float(quarterTurns) * .pi / 2 }

    /// Fits a model with bounds `modelMin...modelMax` (its own space) into a box of size `box`.
    public static func fit(modelMin: SIMD3<Float>, modelMax: SIMD3<Float>, box: SIMD3<Float>, extraQuarterTurns: Int = 0) -> FitToBox {
        let model = modelMax - modelMin
        let boxWide = box.x >= box.z, modelWide = model.x >= model.z
        let turns = ((boxWide == modelWide ? 0 : 1) + extraQuarterTurns) % 4
        let turned = turns % 2 == 0 ? model : SIMD3(model.z, model.y, model.x)
        let ratios = [box.x / turned.x, box.y / turned.y, box.z / turned.z].filter { $0.isFinite && $0 > 0 }
        let offset = -SIMD3((modelMin.x + modelMax.x) / 2, modelMin.y, (modelMin.z + modelMax.z) / 2)
        return FitToBox(quarterTurns: (turns + 4) % 4, scale: ratios.min() ?? 1, offset: offset)
    }

    /// Model space to box-local space (origin at the box center): translate by
    /// `offset`, scale, rotate `yaw`, then drop to the box bottom (-boxSize.y / 2).
    public func localTransform(boxSize: SIMD3<Float>) -> RoomTransform {
        let r = RoomTransform.at(.zero, yaw: yaw)
        let o = r.apply(offset * scale) + SIMD3(0, -boxSize.y / 2, 0)
        return RoomTransform(columns: [r.columns[0] * scale, r.columns[1] * scale, r.columns[2] * scale, SIMD4(o.x, o.y, o.z, 1)])
    }

    /// Model space to world space: `object * localTransform(boxSize:)`.
    public func worldTransform(boxSize: SIMD3<Float>, object: RoomTransform) -> RoomTransform {
        let local = localTransform(boxSize: boxSize)
        return RoomTransform(columns: local.columns.map { c in
            object.columns[0] * c.x + object.columns[1] * c.y + object.columns[2] * c.z + object.columns[3] * c.w
        })
    }
}
