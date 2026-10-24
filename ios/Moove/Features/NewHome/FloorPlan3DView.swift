import SwiftUI
import RealityKit
import MooveKit

/// Non-AR RealityKit view of a floor plan. Drag to orbit, pinch to zoom,
/// two-finger drag to pan, double-tap to reset. Setting `focusRoom` flies the camera to that room.
struct FloorPlan3DView: UIViewRepresentable {
    var plan: FloorPlan
    var focusRoom: String? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        context.coordinator.attach(to: view)
        context.coordinator.show(plan, focusRoom: focusRoom, animated: false)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.show(plan, focusRoom: focusRoom, animated: true)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene = NewHomeScene()
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private var target: SIMD3<Float> = .zero
        private var yaw: Float = 0
        private var pitch: Float = 0.95
        private var distance: Float = 14
        private var shownFocus: String??

        func attach(to view: ARView) {
            camera.camera.fieldOfViewInDegrees = 50
            anchor.addChild(camera)
            anchor.addChild(scene.root)
            let sun = DirectionalLight()
            sun.light.intensity = 2500
            sun.look(at: .zero, from: [4, 10, 6], relativeTo: nil)
            anchor.addChild(sun)
            view.scene.addAnchor(anchor)

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

        func show(_ plan: FloorPlan, focusRoom: String?, animated: Bool) {
            let planChanged = plan != scene.plan
            scene.build(plan)
            guard planChanged || shownFocus != .some(focusRoom) else { return }
            shownFocus = .some(focusRoom)
            frame(on: focusRoom.flatMap(plan.room(named:))?.bounds ?? plan.bounds, animated: animated && !planChanged)
        }

        private func frame(on bounds: PlanBounds, animated: Bool) {
            let f = NewHomeScene.focus(on: bounds)
            target = f.center
            distance = max(4, f.radius * 2.6)
            pitch = 0.95
            updateCamera(duration: animated ? 0.6 : 0)
        }

        private func updateCamera(duration: TimeInterval = 0) {
            pitch = min(max(pitch, 0.2), 1.5)
            distance = min(max(distance, 2), 60)
            let eye = target + SIMD3(
                distance * cos(pitch) * sin(yaw),
                distance * sin(pitch),
                distance * cos(pitch) * cos(yaw)
            )
            if duration > 0 {
                let probe = Entity()
                probe.look(at: target, from: eye, relativeTo: nil)
                _ = camera.move(to: probe.transform, relativeTo: nil, duration: duration, timingFunction: .easeInOut)
            } else {
                camera.look(at: target, from: eye, relativeTo: nil)
            }
        }

        // MARK: Gestures

        @objc private func orbit(_ g: UIPanGestureRecognizer) {
            let d = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            yaw -= Float(d.x) * 0.008
            pitch += Float(d.y) * 0.006
            updateCamera()
        }

        @objc private func pan(_ g: UIPanGestureRecognizer) {
            let d = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            // Move the target in the ground plane, relative to where the camera faces.
            let scale = distance * 0.0016
            let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
            target += right * Float(-d.x) * scale + forward * Float(d.y) * scale
            updateCamera()
        }

        @objc private func pinch(_ g: UIPinchGestureRecognizer) {
            distance /= Float(g.scale)
            g.scale = 1
            updateCamera()
        }

        @objc private func reset(_ g: UITapGestureRecognizer) {
            guard let plan = scene.plan else { return }
            yaw = 0
            shownFocus = .some(nil)
            frame(on: plan.bounds, animated: true)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer) != (other is UIPinchGestureRecognizer)
        }
    }
}

#Preview {
    FloorPlan3DView(plan: DemoHouse.floorPlan).ignoresSafeArea()
}
