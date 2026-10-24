/// How to place a captured 3D model (Object Capture) inside the box RoomPlan
/// measured for the same item. Captured models are upright but face an
/// arbitrary direction, so line their longer horizontal side up with the
/// box's, then scale uniformly to fit. `extraQuarterTurns` is the user's
/// "rotate 90°" correction, since there's no way to know which side is the front.
public struct ModelFit: Equatable, Sendable {
    /// Rotation about +Y, in multiples of 90°.
    public var quarterTurns: Int
    public var scale: Float

    public var yaw: Float { Float(quarterTurns) * .pi / 2 }

    public static func fit(model: SIMD3<Float>, box: SIMD3<Float>, extraQuarterTurns: Int = 0) -> ModelFit {
        let boxWide = box.x >= box.z, modelWide = model.x >= model.z
        let turns = ((boxWide == modelWide ? 0 : 1) + extraQuarterTurns) % 4
        let turned = turns % 2 == 0 ? model : SIMD3(model.z, model.y, model.x)
        let ratios = [box.x / turned.x, box.y / turned.y, box.z / turned.z].filter { $0.isFinite && $0 > 0 }
        return ModelFit(quarterTurns: (turns + 4) % 4, scale: ratios.min() ?? 1)
    }
}
