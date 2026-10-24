import SwiftUI
import RealityKit
import MooveKit

/// Pack > See it in 3D: the plan's truck as a voxel box truck (roof and near side cut away)
/// with every piece of furniture and every box where `TruckLoader` puts it. "Load the truck"
/// replays them flying in, in load order. Tap a piece to see what it is.
struct TruckView: View {
    let plan: PackingPlan
    let items: [Item]
    /// The Pack card's load when it has one, so both screens show the same truck.
    @State var load: TruckLoad? = nil
    @State private var flyInToken = 0
    @State private var selected: TruckPlacement?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if let load {
                TruckSceneView(load: load, items: items, flyInToken: flyInToken, selected: $selected)
                    .ignoresSafeArea(edges: .bottom)
                // VoiceOver reads this summary; the ARView itself stays out of the tree (see ios/CLAUDE.md).
                Color.clear
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(Self.summary(load))
                    .accessibilityAddTraits(.isImage)
                VStack(spacing: 0) {
                    legend(load)
                    Spacer(minLength: 0)
                    controls(load)
                }
            } else {
                ProgressView("Loading the truck…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: FloorPlan3DView.sceneBackground))
        .navigationTitle("Truck in 3D")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: plan) {
            guard load == nil else { return }
            let plan = plan, items = items
            load = await Task.detached(priority: .userInitiated) { TruckLoader.load(plan: plan, items: items) }.value
        }
    }

    // MARK: Legend

    private func legend(_ load: TruckLoad) -> some View {
        let note = load.sizeNote(planned: plan.truck.truck)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Load plan").eyebrow()
                Spacer(minLength: 8)
                MonoTag(text: "\(Int((load.fill * 100).rounded()))% full", tone: Theme.accentStrong)
            }
            Text(load.truck.label).blockTitle()
            Text("\(load.furnitureCount) furniture · \(load.boxCount) boxes · loaded cab first, open-first box by the door")
                .monoMeta()
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .monoMeta()
                    .foregroundStyle(Theme.ochreInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !load.unloaded.isEmpty {
                Text("\(load.unloaded.count) more \(load.unloaded.count == 1 ? "piece needs" : "pieces need") a second trip.")
                    .monoMeta()
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            roomKey(load)
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.bg.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Box tape colors per destination room (the same `PackingPalette` the box cards use).
    private func roomKey(_ load: TruckLoad) -> some View {
        var rooms: [String] = []
        for p in load.placements where p.item.isBox && !rooms.contains(p.item.room) { rooms.append(p.item.room) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(rooms, id: \.self) { room in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.color(PackingPalette.color(forRoom: room)))
                            .frame(width: 14, height: 9)
                        Text(room).monoText(12).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Controls

    private func controls(_ load: TruckLoad) -> some View {
        VStack(spacing: 10) {
            if let s = selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.item.name).sansText(15, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    Text(detail(s, of: load)).monoMeta()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Theme.bg.opacity(0.94), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
            Button {
                selected = nil
                flyInToken += 1
            } label: {
                Label("Load the truck", systemImage: "shippingbox")
            }
            .buttonStyle(.pill)
            .disabled(load.placements.isEmpty)
            .accessibilityHint(reduceMotion ? "Shows the pieces in load order" : "Plays every piece going onto the truck, in load order")
            Text("Drag to turn · pinch to zoom · tap a piece")
                .monoText(12)
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.2), value: selected?.id)
    }

    private func detail(_ p: TruckPlacement, of load: TruckLoad) -> String {
        var parts = ["#\(p.order) of \(load.placements.count) on", p.item.room]
        if p.item.fragile { parts.append("fragile") }
        if p.tilt != .none { parts.append("on its side") }
        if p.y > 0.01 { parts.append("stacked") }
        return parts.joined(separator: " · ")
    }

    static func summary(_ load: TruckLoad) -> String {
        var s = "3D view of a \(load.truck.label), \(Int((load.fill * 100).rounded())) percent full, with \(load.furnitureCount) pieces of furniture and \(load.boxCount) boxes loaded."
        if let first = load.placements.first { s += " \(first.item.name) goes on first, against the cab." }
        if !load.unloaded.isEmpty { s += " \(load.unloaded.count) pieces don't fit." }
        return s
    }
}

/// The truck and its load in a non-AR ARView, lit and framed like `FloorPlan3DView`:
/// front-right at ~35°, narrow FOV, warm sun plus fill. Drag to orbit, pinch to zoom,
/// double-tap to reset, tap a piece to select it.
struct TruckSceneView: UIViewRepresentable {
    let load: TruckLoad
    let items: [Item]
    var flyInToken: Int
    @Binding var selected: TruckPlacement?
    /// False on Pack's inline card: no gestures, so the page still scrolls over it.
    var interactive = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(FloorPlan3DView.sceneBackground.resolvedColor(with: view.traitCollection))
        let c = context.coordinator
        c.onSelect = { selected = $0 }
        c.attach(to: view, interactive: interactive)
        c.show(load, items: items)
        c.shownFlyIn = flyInToken
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        view.environment.background = .color(FloorPlan3DView.sceneBackground.resolvedColor(with: view.traitCollection))
        let c = context.coordinator
        c.onSelect = { selected = $0 }
        c.show(load, items: items)
        if flyInToken != c.shownFlyIn {
            c.shownFlyIn = flyInToken
            c.flyIn()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSelect: ((TruckPlacement?) -> Void)?
        var shownFlyIn = 0
        private weak var view: ARView?
        private let anchor = AnchorEntity(world: .zero)
        /// Truck grid space, shifted so the cargo's center is the world origin.
        private let root = Entity()
        private let camera = PerspectiveCamera()
        private let sun = DirectionalLight()
        private var shownLoad: TruckLoad?
        private var pieces: [String: Entity] = [:]
        private var placements: [String: TruckPlacement] = [:]
        private var flight: Task<Void, Never>?
        private var shellTask: Task<Void, Never>?
        private var boxCache: [String: ModelEntity] = [:]
        /// Same angle as the dollhouse (`FloorPlan3DView.Coordinator.defaultYaw` / `defaultPitch`):
        /// front-right, so the cab is on the right and the open side faces the camera.
        private var yaw: Float = 40 * .pi / 180
        private var pitch: Float = 35 * .pi / 180
        private var distance: Float = 14
        private var fitDistance: Float = 14
        private var target: SIMD3<Float> = .zero

        func attach(to view: ARView, interactive: Bool = true) {
            self.view = view
            camera.camera.fieldOfViewInDegrees = FloorPlan3DView.Coordinator.fieldOfView
            anchor.addChild(camera)
            anchor.addChild(root)
            sun.light.color = Theme.uiColor(0xFFE4C2)
            sun.light.intensity = 2800
            sun.look(at: .zero, from: [2.2, 5.5, 3.4], relativeTo: nil)
            sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2)
            anchor.addChild(sun)
            let fill = DirectionalLight()
            fill.light.color = Theme.uiColor(0xFFF1E0)
            fill.light.intensity = 700
            fill.look(at: .zero, from: [-3, 4, -1], relativeTo: nil)
            anchor.addChild(fill)
            view.scene.addAnchor(anchor)

            guard interactive else { return }
            let orbit = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
            orbit.maximumNumberOfTouches = 1
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            let reset = UITapGestureRecognizer(target: self, action: #selector(reset(_:)))
            reset.numberOfTapsRequired = 2
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            tap.require(toFail: reset)
            for g in [orbit, pinch, reset, tap] as [UIGestureRecognizer] {
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        func show(_ load: TruckLoad, items: [Item]) {
            guard load != shownLoad else { return }
            let truckChanged = load.truck != shownLoad?.truck
            shownLoad = load
            flight?.cancel()
            if truckChanged { buildShell(load.truck) }
            for e in pieces.values { e.removeFromParent() }
            pieces = [:]
            placements = [:]
            let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for p in load.placements {
                guard let model = model(for: p, items: byId) else { continue }
                let pivot = Entity()
                pivot.name = p.id
                pivot.addChild(model)
                pivot.transform = transform(for: p, truck: load.truck)
                root.addChild(pivot)
                pieces[p.id] = pivot
                placements[p.id] = p
            }
        }

        private func buildShell(_ truck: TruckSize) {
            shellTask?.cancel()
            root.children.first { $0.name == "truck-shell" }?.removeFromParent()
            let c = VoxelTruck.cargoCenter(truck)
            root.position = -SIMD3(Float(c.x), Float(c.y), Float(c.z))
            let f = VoxelTruck.frame(truck)
            let s = Float(VoxelGrid.voxelSize)
            // Frame the whole truck: half its diagonal in the narrower field of view.
            let radius = 0.5 * simd_length(SIMD3(Float(f.nx), Float(f.ny), Float(f.nz)) * s)
            let size = view?.bounds.size ?? .zero
            let aspect = size.width > 0 && size.height > 0 ? Float(size.width / size.height) : 0.7
            let halfV = FloorPlan3DView.Coordinator.fieldOfView / 2 * .pi / 180
            let halfH = atan(tan(halfV) * aspect)
            fitDistance = max(4, radius * 1.05 / sin(min(halfV, halfH)))
            distance = fitDistance
            yaw = FloorPlan3DView.Coordinator.defaultYaw
            pitch = FloorPlan3DView.Coordinator.defaultPitch
            updateCamera()
            shellTask = Task { [weak self] in
                let mesh = await Task.detached(priority: .userInitiated) {
                    VoxelMesher.mesh(VoxelTruck.build(truck), centered: false)
                }.value
                guard let self, !Task.isCancelled, let shell = VoxelEntity.entity(mesh, name: "truck-shell") else { return }
                self.root.addChild(shell)
            }
        }

        /// A furniture voxel model or a voxel moving box, centered on its pivot.
        private func model(for p: TruckPlacement, items: [UInt64: Item]) -> ModelEntity? {
            let e: ModelEntity
            switch p.item.kind {
            case let .box(size):
                let key = "\(size.rawValue)|\(PackingPalette.color(forRoom: p.item.room))|\(p.item.fragile)"
                if let cached = boxCache[key] {
                    e = cached.clone(recursive: true)
                } else {
                    let mesh = VoxelMesher.mesh(VoxelMovingBox.build(size, room: p.item.room, fragile: p.item.fragile))
                    guard let made = VoxelEntity.entity(mesh, name: p.item.name) else { return nil }
                    boxCache[key] = made
                    e = made.clone(recursive: true)
                }
            case .furniture:
                guard let id = p.item.itemId, let item = items[id] else { return nil }
                e = VoxelEntity.furniture(LayoutItem(item))
            }
            // Voxel models stand on their origin; lift the center onto the pivot.
            e.position = [0, -Float(p.item.heightM) / 2, 0]
            e.generateCollisionShapes(recursive: true)
            return e
        }

        private func transform(for p: TruckPlacement, truck: TruckSize) -> Transform {
            let c = VoxelTruck.center(of: p, in: truck)
            let tilt: simd_quatf
            switch p.tilt {
            case .none: tilt = simd_quatf(angle: 0, axis: [0, 1, 0])
            case .depthUp: tilt = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            case .widthUp: tilt = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            }
            let yaw = simd_quatf(angle: Float(p.yawDeg) * .pi / 180, axis: [0, 1, 0])
            return Transform(scale: .one, rotation: yaw * tilt, translation: [Float(c.x), Float(c.y), Float(c.z)])
        }

        // MARK: Fly-in

        /// Everything back out behind the ramp in a loose pile, then onto the truck one at a
        /// time in load order. With Reduce Motion, pieces appear in order without flying.
        func flyIn() {
            guard let load = shownLoad else { return }
            flight?.cancel()
            let f = VoxelTruck.frame(load.truck), s = Double(VoxelGrid.voxelSize)
            let ordered = load.placements.compactMap { p in pieces[p.id].map { (p, $0) } }
            let reduce = UIAccessibility.isReduceMotionEnabled
            for (i, (p, e)) in ordered.enumerated() {
                e.stopAllAnimations()
                if reduce {
                    e.isEnabled = false
                    e.transform = transform(for: p, truck: load.truck)
                    continue
                }
                // Pile: rows behind the truck, upright, on the ground.
                let row = i / 4, col = i % 4
                var start = Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                                      translation: [Float(-1.2 - Double(row) * 0.9), Float(p.item.heightM / 2),
                                                    Float(Double(f.farZ) * s + 0.3 + Double(col) * 0.6)])
                start.rotation = simd_quatf(angle: Float(i % 3) * 0.3, axis: [0, 1, 0])
                e.transform = start
            }
            flight = Task { [weak self] in
                for (i, (p, e)) in ordered.enumerated() {
                    if i > 0 { try? await Task.sleep(for: .milliseconds(reduce ? 90 : 160)) }
                    guard let self, !Task.isCancelled else { return }
                    let target = self.transform(for: p, truck: load.truck)
                    if reduce { e.isEnabled = true } else { self.launch(e, to: target) }
                }
            }
        }

        /// Up over the tailgate, then down into its spot: the new-home fly-in's two-segment arc.
        private func launch(_ e: Entity, to target: Transform) {
            let start = e.transform
            let d = simd_distance(start.translation, target.translation)
            var apex = target
            apex.translation = (start.translation + target.translation) / 2
            apex.translation.y = max(start.translation.y, target.translation.y) + 1.2 + d * 0.1
            apex.rotation = simd_slerp(start.rotation, target.rotation, 0.5)
            let up = 0.45 + Double(d) * 0.02, down = 0.4 + Double(d) * 0.015
            _ = e.move(to: apex, relativeTo: root, duration: up, timingFunction: .easeOut)
            Task { [weak e, weak self] in
                try? await Task.sleep(for: .seconds(up))
                guard let e, let self, !Task.isCancelled else { return }
                _ = e.move(to: target, relativeTo: self.root, duration: down, timingFunction: .easeIn)
            }
        }

        // MARK: Camera

        private func updateCamera() {
            pitch = min(max(pitch, 0.15), 1.5)
            distance = min(max(distance, 2), fitDistance * 3)
            let eye = target + SIMD3(distance * cos(pitch) * sin(yaw), distance * sin(pitch), distance * cos(pitch) * cos(yaw))
            camera.look(at: target, from: eye, relativeTo: nil)
        }

        @objc private func orbit(_ g: UIPanGestureRecognizer) {
            let d = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            yaw -= Float(d.x) * 0.008
            pitch += Float(d.y) * 0.006
            updateCamera()
        }

        @objc private func pinch(_ g: UIPinchGestureRecognizer) {
            distance /= Float(g.scale)
            g.scale = 1
            updateCamera()
        }

        @objc private func reset(_ g: UITapGestureRecognizer) {
            yaw = FloorPlan3DView.Coordinator.defaultYaw
            pitch = FloorPlan3DView.Coordinator.defaultPitch
            distance = fitDistance
            updateCamera()
        }

        @objc private func tap(_ g: UITapGestureRecognizer) {
            guard let view = g.view as? ARView else { return }
            var hit = view.entity(at: g.location(in: view))
            while let e = hit, placements[e.name] == nil { hit = e.parent }
            onSelect?(hit.flatMap { placements[$0.name] })
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer) != (other is UIPinchGestureRecognizer)
        }
    }
}

#Preview {
    let items = DemoFixtures.inventory(owner: "me").items
    return NavigationStack { TruckView(plan: PackingPlanner.plan(items: items), items: items) }
}
