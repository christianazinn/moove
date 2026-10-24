import SwiftUI
import RealityKit
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

    var body: some View {
        RealityView { content in
            AppliedLookComponent.registerComponent()
            await RoomScene.prepareLook()
            let room = RoomScene.make(geometry)
            RoomScene.addEnvironmentLight(to: room)
            let staged = stage(holding: room)
            content.add(staged)
            if Self.orbitsRoom { content.cameraTarget = staged }  // orbit pivots on (and frames) the room
            apply(to: room)
        } update: { content in
            guard let room = content.entities.first?.findEntity(named: "room") else { return }
            apply(to: room)
        }
        .realityViewCameraControls(.orbit)
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
    /// Point the orbit camera at the room. MOOVE_ROOM_ORBIT_TARGET=0 falls back to orbiting the world origin.
    static var orbitsRoom: Bool {
        ProcessInfo.processInfo.environment["MOOVE_ROOM_ORBIT_TARGET"] != "0"
    }
    static var tilt: Float {
        Float(ProcessInfo.processInfo.environment["MOOVE_ROOM_TILT"].flatMap(Double.init) ?? 1.0)
    }

    private var labelSize: Float {
        let b = geometry.bounds ?? (SIMD3(-2, 0, -2), SIMD3(2, 2.5, 2))
        return max(b.max.x - b.min.x, b.max.z - b.min.z, 1) * 0.04
    }

    /// Recolors furniture for the current mode and selection, and shows labels.
    /// Incremental: each container remembers the look it last got, so SwiftUI
    /// updates only rebuild materials or labels whose inputs changed.
    private func apply(to room: Entity) {
        guard let objects = room.children.first(where: { $0.name == "objects" }) else { return }
        let byId = Dictionary(geometry.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fontSize = labelSize
        for container in objects.children {
            let id = String(container.name.dropFirst(RoomScene.objectPrefix.count))
            guard let object = byId[id],
                  let body = RoomScene.body(of: container) else { continue }
            let item = items[id]
            let selected = id == selection
            let color = RoomPalette.color(for: object, item: item, mode: mode)
            let look = RoomObjectLook(color: RoomSceneCache.rgba(color), selected: selected,
                                      label: showLabels || selected ? RoomObjectLook.labelText(for: object, item: item) : nil,
                                      labelSize: fontSize)
            let changes = look.changes(since: container.components[AppliedLookComponent.self]?.look)
            guard !changes.isEmpty else { continue }

            if changes.contains(.color) { RoomScene.recolor(body, color, roughness: 0.5, glow: selected) }
            if changes.contains(.selection) { RoomScene.setSelected(body, selected: selected) }
            if changes.contains(.label) {
                container.children.filter { $0.name == "label" }.forEach { $0.removeFromParent() }
                if let text = look.label { container.addChild(RoomScene.label(text, above: object, fontSize: fontSize)) }
            }
            container.components.set(AppliedLookComponent(look: look))
        }
    }
}
