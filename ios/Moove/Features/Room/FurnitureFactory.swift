import RealityKit
import UIKit
/// Builds a stand-in furniture entity for a RoomPlan category. Team D fills this in.
/// Contract: the returned entity's origin is the CENTER of the measured box, its local axes are
/// the box's (x = width, y = height, z = depth), and all geometry fits within ±size/2.
/// Return nil to fall back to the colored box. The caller keeps selection/collision on the parent.
@MainActor
enum FurnitureFactory {
    static func makeEntity(category: String, size: SIMD3<Float>, tint: UIColor) -> Entity? { nil }
}
