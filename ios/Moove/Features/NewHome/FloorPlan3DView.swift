import SwiftUI
import RealityKit
import MooveKit

/// Non-AR RealityKit view of a floor plan. Drag to orbit, pinch to zoom,
/// two-finger drag to pan, double-tap to reset. Setting `focusRoom` flies the camera to that room.
/// The home is a voxel dollhouse seen from front-right at an isometric-feeling angle
/// (narrow FOV), lit by a warm sun with shadows. Its back walls stand full height and the
/// walls nearest the camera are cut low; which is which follows the camera's yaw. Items in `placements` are voxel models;
/// bumping `flyInToken` replays the fly-in.
struct FloorPlan3DView: UIViewRepresentable {
    var plan: FloorPlan
    var focusRoom: String? = nil
    var items: [LayoutItem] = []
    var placements: [Placement] = []
    var flyInToken = 0
    /// Where the fly-in starts pieces (their scanned spots in the old room); nil: the pile.
    var flyInStarts: FlyInStarts? = nil
    /// Measured from the scan's photos (scan results); nil keeps the default palette.
    var wallColor: VoxelColor? = nil
    var floorColor: VoxelColor? = nil
    /// Turn slowly around the home (Scan home hero). Off with Reduce Motion.
    var autoOrbit = false
    /// False: no gestures, so a scroll view around it still scrolls (taps pass through).
    var interactive = true
    /// Room shot: just this room (its own one-room plan with its doors and windows, and the
    /// pieces placed in it), framed tight from a cozy 3/4 interior angle whose two back walls are
    /// the room's most solid ones (`RoomShot`), warmer light, no room labels and no fly-in.
    var isolatedRoom: String? = nil
    /// Called with a snapshot of the view once the scene is ready (and again when the scene
    /// changes or `snapshotToken` changes). Nil: no snapshots.
    var onSnapshot: ((UIImage) -> Void)? = nil
    var snapshotToken = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Warm paper in light mode (Theme `surface`), deep walnut in dark mode (Theme `bg`).
    static var sceneBackground: UIColor { Theme.dynamicUIColor(0xEAE3D7, 0x1C1814) }

    /// The isolated room's own plan, its pieces and the shot's camera yaw.
    private var shot: (plan: FloorPlan, placements: [Placement], yaw: Float)? {
        guard let isolatedRoom, let room = plan.room(named: isolatedRoom), let one = plan.isolating(isolatedRoom) else { return nil }
        return (one, RoomShot.placements(placements, in: isolatedRoom), Float(RoomShot.yaw(for: room, in: plan)))
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(Self.sceneBackground.resolvedColor(with: view.traitCollection))
        context.coordinator.attach(to: view, interactive: interactive)
        update(context.coordinator, animated: false)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        view.environment.background = .color(Self.sceneBackground.resolvedColor(with: view.traitCollection))
        update(context.coordinator, animated: true)
    }

    private func update(_ coordinator: Coordinator, animated: Bool) {
        let shot = self.shot
        let shownPlan = shot?.plan ?? plan
        coordinator.configureShot(yaw: shot?.yaw)
        coordinator.show(shownPlan, focusRoom: shot == nil ? focusRoom : nil, animated: animated, wallColor: wallColor, floorColor: floorColor)
        coordinator.showFurniture(shot?.placements ?? placements, items: items, plan: shownPlan, flyInToken: flyInToken,
                                  starts: shot == nil ? flyInStarts : nil)
        coordinator.setAutoOrbit(autoOrbit)
        coordinator.requestSnapshot(token: snapshotToken, handler: onSnapshot)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene = NewHomeScene()
        let furniture = FurnitureLayer()
        private var shownPlacements: [Placement]?
        private var shownFlyIn: Int?
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private let sun = DirectionalLight()
        private weak var view: ARView?
        /// Front-right of the house (camera on +x, +z), ~35° up: MoveWise's dollhouse angle.
        static let defaultYaw: Float = 40 * .pi / 180
        static let defaultPitch: Float = 35 * .pi / 180
        static let fieldOfView: Float = 26
        /// Room shots: lower and a touch wider, like standing in the doorway.
        static let shotPitch: Float = 27 * .pi / 180
        static let shotFieldOfView: Float = 32
        private var target: SIMD3<Float> = .zero
        private var yaw: Float = Coordinator.defaultYaw
        private var pitch: Float = Coordinator.defaultPitch
        private var distance: Float = 30
        private var shadowDistance: Float = 0
        private var shownFocus: String??
        /// Back to the house after a fly-in that framed the old room too.
        private var reframe: Task<Void, Never>?
        private var orbitLoop: Task<Void, Never>?
        /// Room shot camera yaw (nil: the normal dollhouse view).
        private var shotYaw: Float?
        private var isShot: Bool { shotYaw != nil }
        private var basePitch: Float { isShot ? Self.shotPitch : Self.defaultPitch }
        private var fov: Float { isShot ? Self.shotFieldOfView : Self.fieldOfView }
        /// Set by gestures, so a snapshot of "this angle" doesn't snap the camera back.
        private var userMoved = false
        // Snapshots (room shots).
        private var snapshotHandler: ((UIImage) -> Void)?
        private var shownSnapshotToken: Int?
        private var snapshotPending = false
        /// Bumped whenever the plan or the placements change, so a stale snapshot is retaken.
        private var sceneGeneration = 0
        private var capture: Task<Void, Never>?

        func attach(to view: ARView, interactive: Bool = true) {
            self.view = view
            camera.camera.fieldOfViewInDegrees = fov
            anchor.addChild(camera)
            anchor.addChild(scene.root)
            anchor.addChild(furniture.root)

            // Warm key light from front-right and above, casting soft shadows into the rooms.
            sun.light.color = Theme.uiColor(0xFFE4C2)
            sun.light.intensity = 2800
            sun.look(at: .zero, from: [2.2, 5.5, 3.4], relativeTo: nil)
            anchor.addChild(sun)
            // Soft warm fill from back-left so shadowed sides aren't black.
            let fill = DirectionalLight()
            fill.light.color = Theme.uiColor(0xFFF1E0)
            fill.light.intensity = 700
            fill.look(at: .zero, from: [-3, 4, -1], relativeTo: nil)
            anchor.addChild(fill)
            view.scene.addAnchor(anchor)
            scene.onBuilt = { [weak self] in self?.tryCapture() }

            guard interactive else { return }
            let orbit = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
            orbit.maximumNumberOfTouches = 1
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.minimumNumberOfTouches = 2
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            let reset = UITapGestureRecognizer(target: self, action: #selector(reset(_:)))
            reset.numberOfTapsRequired = 2
            for g in [orbit, pan, pinch, reset] as [UIGestureRecognizer] {
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        /// Switches between the normal view and a room shot's camera and light.
        func configureShot(yaw newYaw: Float?) {
            guard newYaw != shotYaw else { return }
            shotYaw = newYaw
            scene.showsLabels = newYaw == nil
            camera.camera.fieldOfViewInDegrees = fov
            sun.light.color = Theme.uiColor(newYaw == nil ? 0xFFE4C2 : 0xFFD7A8)
            sun.light.intensity = newYaw == nil ? 2800 : 3300
            if newYaw == nil {
                sun.look(at: .zero, from: [2.2, 5.5, 3.4], relativeTo: nil)
            } else {
                yaw = newYaw ?? yaw
                userMoved = false
            }
            shownFocus = nil // reframe on the next show
        }

        func show(_ plan: FloorPlan, focusRoom: String?, animated: Bool, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) {
            let planChanged = plan != scene.plan
            if planChanged { sceneChanged() }
            scene.build(plan, wallColor: wallColor, floorColor: floorColor)
            guard planChanged || shownFocus != .some(focusRoom) else { return }
            reframe?.cancel()
            shownFocus = .some(focusRoom)
            frame(on: focusRoom.flatMap(plan.room(named:))?.bounds ?? plan.bounds, animated: animated && !planChanged)
        }

        func showFurniture(_ placements: [Placement], items: [LayoutItem], plan: FloorPlan, flyInToken: Int, starts: FlyInStarts? = nil) {
            guard placements != shownPlacements || flyInToken != shownFlyIn else { return }
            let changed = placements != shownPlacements
            if changed { sceneChanged() }
            defer { if changed { tryCapture() } }
            // Hold the fly-in until there's something to fly. Room shots never fly in.
            let flyIn = !isShot && flyInToken != shownFlyIn && !placements.isEmpty
            shownPlacements = placements
            if !placements.isEmpty { shownFlyIn = flyInToken }
            let duration = furniture.show(placements, items: items, plan: plan, flyIn: flyIn, starts: starts)
            // Flying from the old room: pull back so it's in view too, then settle on the house.
            reframe?.cancel()
            guard flyIn, shownFocus == .some(nil), let old = starts?.bounds,
                  starts?.placements.keys.contains(where: { id in placements.contains { $0.itemId == id } }) == true else { return }
            let b = plan.bounds
            frame(on: PlanBounds([PlanPoint(min(b.minX, old.minX), min(b.minY, old.minY)), PlanPoint(max(b.maxX, old.maxX), max(b.maxY, old.maxY))]),
                  animated: true)
            reframe = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, duration - 0.6)))
                guard let self, !Task.isCancelled, self.shownFocus == .some(nil), let plan = self.scene.plan else { return }
                self.frame(on: plan.bounds, animated: true)
            }
        }

        /// About one turn a minute. Stops for good once the user drags the view.
        func setAutoOrbit(_ on: Bool) {
            let on = on && !UIAccessibility.isReduceMotionEnabled
            guard on != (orbitLoop != nil) else { return }
            orbitLoop?.cancel()
            orbitLoop = nil
            guard on else { return }
            orbitLoop = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    guard let self, !Task.isCancelled else { return }
                    self.yaw += 2 * .pi / (60 * 30)
                    self.updateCamera()
                }
            }
        }

        private func stopAutoOrbit() {
            orbitLoop?.cancel()
        }

        private func frame(on bounds: PlanBounds, animated: Bool) {
            let f = NewHomeScene.focus(on: bounds)
            target = f.center
            // Room shots aim a little higher, so the tall back walls fit above the floor.
            if isShot { target.y = Float(VoxelHouse.floorTopM) + 0.9 }
            // Fit the bounds' circle in the narrower of the two fields of view.
            let size = view?.bounds.size ?? .zero
            let aspect = size.width > 0 && size.height > 0 ? Float(size.width / size.height) : 0.8
            let halfV = fov / 2 * .pi / 180
            let halfH = atan(tan(halfV) * aspect)
            let radius = isShot ? max(f.radius, 1.6) * 1.02 : f.radius * 0.95
            distance = max(isShot ? 2 : 3, radius / sin(min(halfV, halfH)))
            pitch = basePitch
            updateCamera(duration: animated ? 0.6 : 0)
        }

        private func updateCamera(duration: TimeInterval = 0) {
            pitch = min(max(pitch, 0.2), 1.5)
            distance = min(max(distance, 2), 150)
            updateShadow()
            let eye = target + SIMD3(
                distance * cos(pitch) * sin(yaw),
                distance * sin(pitch),
                distance * cos(pitch) * cos(yaw)
            )
            // Dollhouse walls: back walls full height, the ones facing the camera low.
            scene.setViewDirection(SIMD2(Double(sin(yaw)), Double(cos(yaw))))
            if isShot {
                // Warm key over the camera's left shoulder, high enough to pool light on the floor.
                let a = yaw - 0.6
                sun.look(at: target, from: target + SIMD3(3.5 * sin(a), 6, 3.5 * cos(a)), relativeTo: nil)
            }
            if duration > 0 {
                let probe = Entity()
                probe.look(at: target, from: eye, relativeTo: nil)
                _ = camera.move(to: probe.transform, relativeTo: nil, duration: duration, timingFunction: .easeInOut)
            } else {
                camera.look(at: target, from: eye, relativeTo: nil)
            }
        }

        /// Shadows reach from the camera to just past the house; refreshed only on big zoom changes.
        private func updateShadow() {
            let wanted = distance + 2 * scene.focus.radius + 2
            guard shadowDistance == 0 || abs(wanted - shadowDistance) / shadowDistance > 0.2 else { return }
            shadowDistance = wanted
            sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: wanted, depthBias: 2)
        }

        // MARK: Gestures

        @objc private func orbit(_ g: UIPanGestureRecognizer) {
            reframe?.cancel()
            stopAutoOrbit()
            userMoved = true
            let d = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            yaw -= Float(d.x) * 0.008
            pitch += Float(d.y) * 0.006
            updateCamera()
        }

        @objc private func pan(_ g: UIPanGestureRecognizer) {
            reframe?.cancel()
            stopAutoOrbit()
            userMoved = true
            let d = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            // Move the target in the ground plane, relative to where the camera faces.
            let scale = distance * 0.0009
            let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
            target += right * Float(-d.x) * scale + forward * Float(d.y) * scale
            updateCamera()
        }

        @objc private func pinch(_ g: UIPinchGestureRecognizer) {
            reframe?.cancel()
            stopAutoOrbit()
            userMoved = true
            distance /= Float(g.scale)
            g.scale = 1
            updateCamera()
        }

        @objc private func reset(_ g: UITapGestureRecognizer) {
            guard let plan = scene.plan else { return }
            yaw = shotYaw ?? Self.defaultYaw
            userMoved = false
            shownFocus = .some(nil)
            frame(on: plan.bounds, animated: true)
        }

        // MARK: Snapshots

        /// Takes a snapshot for `handler` once the scene is ready, and again whenever `token` changes.
        func requestSnapshot(token: Int, handler: ((UIImage) -> Void)?) {
            snapshotHandler = handler
            guard handler != nil, token != shownSnapshotToken else { return }
            shownSnapshotToken = token
            snapshotPending = true
            tryCapture()
        }

        /// The plan or the placements changed: anything captured (or capturing) is stale.
        private func sceneChanged() {
            sceneGeneration += 1
            if snapshotHandler != nil, shownSnapshotToken != nil { snapshotPending = true }
        }

        private func tryCapture() {
            guard snapshotPending, snapshotHandler != nil, scene.isBuilt, view != nil else { return }
            snapshotPending = false
            let generation = sceneGeneration
            capture?.cancel()
            capture = Task { [weak self] in
                // Wait for SwiftUI to size the view, refit to it, then give a few frames to draw.
                for _ in 0..<40 {
                    guard let self, let view = self.view, view.bounds.width < 1 else { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard let self, !Task.isCancelled else { return }
                if !self.userMoved, let plan = self.scene.plan { self.frame(on: plan.bounds, animated: false) }
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, generation == self.sceneGeneration, let view = self.view else { return }
                view.snapshot(saveToHDR: false) { @Sendable [weak self] image in
                    Task { @MainActor in self?.deliver(image, generation: generation) }
                }
            }
        }

        private func deliver(_ image: UIImage?, generation: Int) {
            guard generation == sceneGeneration else {
                snapshotPending = true
                tryCapture()
                return
            }
            if let image { snapshotHandler?(image) }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer) != (other is UIPinchGestureRecognizer)
        }
    }
}

#Preview {
    FloorPlan3DView(plan: DemoHouse.floorPlan).ignoresSafeArea()
}
