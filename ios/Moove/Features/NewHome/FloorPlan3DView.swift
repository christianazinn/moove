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
    /// Called once per fly-in after its finale: one slow turn around the furnished home that
    /// settles on the default 3/4 view (no turn with Reduce Motion; a touch stops it early).
    var onFlyInFinale: (@MainActor () -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Warm paper in light mode (Theme `surface`), deep walnut in dark mode (Theme `bg`).
    static var sceneBackground: UIColor { Theme.dynamicUIColor(0xEAE3D7, 0x1C1814) }

    /// Resolved for SwiftUI's color scheme rather than the ARView's trait collection, which is
    /// unset before the view is in a window and can lag an in-app Appearance change.
    static func sceneBackgroundColor(for scheme: ColorScheme) -> UIColor {
        sceneBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(Self.sceneBackgroundColor(for: context.environment.colorScheme))
        context.coordinator.attach(to: view, interactive: interactive)
        update(context.coordinator, animated: false)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        view.environment.background = .color(Self.sceneBackgroundColor(for: context.environment.colorScheme))
        update(context.coordinator, animated: true)
    }

    private func update(_ coordinator: Coordinator, animated: Bool) {
        coordinator.onFinale = onFlyInFinale
        coordinator.show(plan, focusRoom: focusRoom, animated: animated, wallColor: wallColor, floorColor: floorColor)
        coordinator.showFurniture(placements, items: items, plan: plan, flyInToken: flyInToken, starts: flyInStarts)
        coordinator.setAutoOrbit(autoOrbit)
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
        private var target: SIMD3<Float> = .zero
        private var yaw: Float = Coordinator.defaultYaw
        private var pitch: Float = Coordinator.defaultPitch
        private var distance: Float = 30
        private var shadowDistance: Float = 0
        private var shownFocus: String??
        /// Back to the house after a fly-in that framed the old room too.
        private var reframe: Task<Void, Never>?
        private var orbitLoop: Task<Void, Never>?
        /// The fly-in finale (wait for the last piece, then one slow turn); nil when not pending.
        private var finale: Task<Void, Never>?
        var onFinale: (@MainActor () -> Void)?
        private weak var touchDown: UIGestureRecognizer?
        private var fov: Float { Self.fieldOfView }

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

            guard interactive else { return }
            let orbit = UIPanGestureRecognizer(target: self, action: #selector(orbit(_:)))
            orbit.maximumNumberOfTouches = 1
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.minimumNumberOfTouches = 2
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            let reset = UITapGestureRecognizer(target: self, action: #selector(reset(_:)))
            reset.numberOfTapsRequired = 2
            // Any touch on the view stops the finale's turn at once (before a drag is recognized).
            let touch = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
            touch.minimumPressDuration = 0
            touch.cancelsTouchesInView = false
            touch.delaysTouchesEnded = false
            touchDown = touch
            for g in [orbit, pan, pinch, reset, touch] as [UIGestureRecognizer] {
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        func show(_ plan: FloorPlan, focusRoom: String?, animated: Bool, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) {
            let planChanged = plan != scene.plan
            scene.build(plan, wallColor: wallColor, floorColor: floorColor)
            guard planChanged || shownFocus != .some(focusRoom) else { return }
            reframe?.cancel()
            shownFocus = .some(focusRoom)
            frame(on: focusRoom.flatMap(plan.room(named:))?.bounds ?? plan.bounds, animated: animated && !planChanged)
        }

        func showFurniture(_ placements: [Placement], items: [LayoutItem], plan: FloorPlan, flyInToken: Int, starts: FlyInStarts? = nil) {
            guard placements != shownPlacements || flyInToken != shownFlyIn else { return }
            // Hold the fly-in until there's something to fly.
            let flyIn = flyInToken != shownFlyIn && !placements.isEmpty
            shownPlacements = placements
            if !placements.isEmpty { shownFlyIn = flyInToken }
            let duration = furniture.show(placements, items: items, plan: plan, flyIn: flyIn, starts: starts)
            // Flying from the old room: pull back so it's in view too, then settle on the house.
            reframe?.cancel()
            finale?.cancel()
            finale = nil
            if flyIn { scheduleFinale(after: duration + 0.4) }
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
            endFinale()
        }

        /// After the last piece lands: one slow turn (~7 s, at least 300°) easing onto the
        /// default 3/4 view, then `onFinale`. Reduce Motion skips the turn.
        private func scheduleFinale(after delay: Double) {
            finale = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                if UIAccessibility.isReduceMotionEnabled || self.orbitLoop != nil || self.view == nil {
                    self.endFinale()
                    return
                }
                let startYaw = self.yaw, startPitch = self.pitch
                let full = 2 * Float.pi
                var turn = (Self.defaultYaw - startYaw).truncatingRemainder(dividingBy: full)
                if turn < 0 { turn += full }
                if turn < full * 300 / 360 { turn += full }
                let seconds = 7.0, frameTime = 1.0 / 30
                let start = ContinuousClock.now
                while true {
                    try? await Task.sleep(for: .seconds(frameTime))
                    guard !Task.isCancelled else { return }
                    let t = Float(min((ContinuousClock.now - start) / .seconds(seconds), 1))
                    let eased = t * t * (3 - 2 * t)
                    self.yaw = startYaw + turn * eased
                    self.pitch = startPitch + (Self.defaultPitch - startPitch) * eased
                    self.updateCamera()
                    if t >= 1 { break }
                }
                self.yaw = Self.defaultYaw
                self.endFinale()
            }
        }

        /// Stops a running finale and reports it done (once); no-op if none is pending.
        private func endFinale() {
            guard let task = finale else { return }
            task.cancel()
            finale = nil
            onFinale?()
        }

        @objc private func touched(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { endFinale() }
        }

        private func frame(on bounds: PlanBounds, animated: Bool) {
            let f = NewHomeScene.focus(on: bounds)
            target = f.center
            // Fit the bounds' circle in the narrower of the two fields of view.
            let size = view?.bounds.size ?? .zero
            let aspect = size.width > 0 && size.height > 0 ? Float(size.width / size.height) : 0.8
            let halfV = fov / 2 * .pi / 180
            let halfH = atan(tan(halfV) * aspect)
            let radius = f.radius * 0.95
            distance = max(3, radius / sin(min(halfV, halfH)))
            pitch = Self.defaultPitch
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
            let d = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            yaw -= Float(d.x) * 0.008
            pitch += Float(d.y) * 0.006
            updateCamera()
        }

        @objc private func pan(_ g: UIPanGestureRecognizer) {
            reframe?.cancel()
            stopAutoOrbit()
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
            distance /= Float(g.scale)
            g.scale = 1
            updateCamera()
        }

        @objc private func reset(_ g: UITapGestureRecognizer) {
            guard let plan = scene.plan else { return }
            yaw = Self.defaultYaw
            shownFocus = .some(nil)
            frame(on: plan.bounds, animated: true)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if g === touchDown || other === touchDown { return true }
            return (g is UIPinchGestureRecognizer) != (other is UIPinchGestureRecognizer)
        }
    }
}

#Preview {
    FloorPlan3DView(plan: DemoHouse.floorPlan).ignoresSafeArea()
}
