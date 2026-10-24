import SwiftUI
import RealityKit
import GLTFKit2
import MooveKit

/// Orbitable 3D model of a scanned room (iOS 18+). Drag to orbit, pinch to
/// zoom, tap furniture to select it.
@available(iOS 18.0, *)
struct RoomModelView: View {
    let geometry: RoomGeometry
    let items: [String: Item]
    let mode: RoomPalette.Mode
    let showLabels: Bool
    @Binding var selection: String?

    @State private var models = ObjectModelStore.shared
    /// Loaded Object Capture models by object id (prototypes; the scene holds clones).
    @State private var prototypes: [String: Entity] = [:]

    var body: some View {
        RealityView { content in
            ModelSourceComponent.registerComponent()
            let room = RoomScene.make(geometry)
            content.add(stage(holding: room))
            apply(to: room)
        } update: { content in
            guard let room = content.entities.first?.findEntity(named: "room") else { return }
            apply(to: room)
        }
        .realityViewCameraControls(.orbit)
        .task(id: TaskKey(revision: models.revision, urls: items.values.compactMap(\.modelUrl).sorted())) { await loadModels() }
        .gesture(
            SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                var entity: Entity? = value.entity
                while let e = entity, !e.name.hasPrefix(RoomScene.objectPrefix) { entity = e.parent }
                let id = entity.map { String($0.name.dropFirst(RoomScene.objectPrefix.count)) }
                selection = (id == selection) ? nil : id
            }
        )
    }

    /// RealityView's virtual camera can't be repositioned, so fit the room to it
    /// instead: scale it to a fixed size and tip it toward the viewer for a
    /// three-quarter "dollhouse" view. Orbit rotates around the result.
    private func stage(holding room: Entity) -> Entity {
        let b = geometry.bounds ?? (SIMD3(-2, 0, -2), SIMD3(2, 2.5, 2))
        let extent = max(b.max.x - b.min.x, b.max.z - b.min.z, 1)
        let stage = Entity()
        stage.name = "stage"
        let scale = Self.fittedSize / extent
        room.scale = SIMD3(repeating: scale)
        room.position = SIMD3(0, -(b.max.y + b.min.y) / 2 * scale, 0)  // pivot on the room's middle
        stage.addChild(room)
        stage.position = SIMD3(0, Self.lift, 0)
        stage.orientation = simd_quatf(angle: Self.tilt, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: -.pi / 9, axis: SIMD3(0, 1, 0))
        return stage
    }

    static var fittedSize: Float {
        Float(ProcessInfo.processInfo.environment["MOOVE_ROOM_SIZE"].flatMap(Double.init) ?? 0.95)
    }
    static var lift: Float {
        Float(ProcessInfo.processInfo.environment["MOOVE_ROOM_LIFT"].flatMap(Double.init) ?? 0.22)
    }
    static var tilt: Float {
        Float(ProcessInfo.processInfo.environment["MOOVE_ROOM_TILT"].flatMap(Double.init) ?? 1.0)
    }

    private var labelSize: Float {
        let b = geometry.bounds ?? (SIMD3(-2, 0, -2), SIMD3(2, 2.5, 2))
        return max(b.max.x - b.min.x, b.max.z - b.min.z, 1) * 0.04
    }

    /// Loads every object's model: captured on this phone first, else the synced
    /// `modelUrl` (another phone's capture, or SAM 3D from the worker).
    private func loadModels() async {
        for object in geometry.objects {
            if models.modelURL(for: object.id) == nil, let remote = items[object.id]?.modelUrl.flatMap(URL.init(string:)) {
                await models.fetchRemote(remote, for: object.id)  // bumps revision, which re-runs this task
            }
            guard let url = models.modelURL(for: object.id) else {
                prototypes[object.id] = nil
                continue
            }
            if prototypes[object.id]?.name == url.absoluteString { continue }
            guard let entity = await Self.load(url) else { continue }
            entity.name = url.absoluteString  // remembers which file it came from
            prototypes[object.id] = entity
        }
    }

    /// RealityKit reads USDZ (Object Capture); SAM 3D models are GLB, loaded with GLTFKit2.
    private static func load(_ url: URL) async -> Entity? {
        if url.pathExtension.lowercased() == "glb" {
            return try? await GLTFRealityKitLoader.load(from: url)
        }
        return try? await Entity(contentsOf: url)
    }

    /// Recolors furniture for the current mode and selection, swaps in captured
    /// models, and shows labels.
    private func apply(to room: Entity) {
        guard let objects = room.children.first(where: { $0.name == "objects" }) else { return }
        for container in objects.children {
            let id = String(container.name.dropFirst(RoomScene.objectPrefix.count))
            guard let object = geometry.objects.first(where: { $0.id == id }),
                  let block = container.findEntity(named: "block") as? ModelEntity,
                  let base = container.findEntity(named: "base") as? ModelEntity else { continue }
            let item = items[id]
            let selected = id == selection
            let color = RoomPalette.color(for: object, item: item, mode: mode)

            if let prototype = prototypes[id] {
                // Captured model: show it on a colored base; the block becomes a
                // translucent highlight when selected.
                let turns = models.extraTurns(for: id)
                let current = container.findEntity(named: "model")
                if current?.components[ModelSourceComponent.self] != ModelSourceComponent(source: prototype.name, turns: turns) {
                    RoomScene.attachModel(prototype, to: container, object: object, extraQuarterTurns: turns)
                    container.findEntity(named: "model")?.components.set(ModelSourceComponent(source: prototype.name, turns: turns))
                }
                base.isEnabled = true
                base.model?.materials = [RoomScene.material(color, roughness: 0.6, glow: selected)]
                block.isEnabled = selected
                var highlight = RoomScene.material(color, roughness: 0.4, glow: true)
                highlight.blending = .transparent(opacity: .init(floatLiteral: 0.22))
                block.model?.materials = [highlight]
                block.scale = .one
            } else {
                container.children.filter { $0.name == "model" }.forEach { $0.removeFromParent() }
                base.isEnabled = false
                block.isEnabled = true
                block.model?.materials = [RoomScene.material(color, roughness: 0.5, glow: selected)]
                block.scale = selected ? SIMD3(repeating: 1.06) : .one
            }

            container.children.filter { $0.name == "label" }.forEach { $0.removeFromParent() }
            if showLabels || selected {
                var text = item?.name ?? object.category.capitalized
                if item?.maybeSentimental == true { text += " ♥" }
                container.addChild(RoomScene.label(text, above: object, fontSize: labelSize))
            }
        }
    }
}

/// Tags a placed model with the file and rotation it was built from, so
/// updates only rebuild it when one of those changes.
private struct ModelSourceComponent: Component, Equatable {
    var source: String
    var turns: Int
}

private struct TaskKey: Equatable {
    var revision: Int
    var urls: [String]
}
