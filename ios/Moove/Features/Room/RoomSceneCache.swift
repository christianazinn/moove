import RealityKit
import UIKit

/// Caches for building the room scene. Label text meshes are the expensive
/// part (`MeshResource.generateText`), so they're kept by text and size.
@available(iOS 18.0, *)
@MainActor
enum RoomSceneCache {
    private struct LabelKey: Hashable {
        var text: String
        var fontSize: Float
    }

    private static var labelMeshes: [LabelKey: MeshResource] = [:]

    /// The cached text mesh for a label, built with `make` the first time.
    static func labelMesh(_ text: String, fontSize: Float, make: () -> MeshResource) -> MeshResource {
        let key = LabelKey(text: text, fontSize: fontSize)
        if let mesh = labelMeshes[key] { return mesh }
        if labelMeshes.count >= 256 { labelMeshes.removeAll() }  // names are few; just don't grow forever
        let mesh = make()
        labelMeshes[key] = mesh
        return mesh
    }
}
