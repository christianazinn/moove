import SwiftUI
import RoomPlan
@preconcurrency import ARKit
import MooveKit

/// SwiftUI wrapper for Apple's RoomPlan capture UI. Calls `onFinished` with the
/// processed room, plus any everyday objects RoomPlan doesn't recognize that the
/// extra detector (#73, #82) found and measured in the same scan, and the auto
/// photographer holding keyframes to photograph every object from (#82).
struct RoomCaptureContainer: UIViewRepresentable {
    @Binding var stopRequested: Bool
    /// Live list of extra objects found so far (e.g. ["bicycle"]), for on-screen chips.
    var onFound: ([String]) -> Void = { _ in }
    var onFinished: (Result<CapturedRoom, Error>, [RoomGeometry.Object], AutoPhotographer) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound, onFinished: onFinished) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        context.coordinator.startDetecting(on: view.captureSession.arSession)
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if stopRequested && !context.coordinator.stopped {
            context.coordinator.stopped = true
            context.coordinator.stopDetecting()
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        coordinator.stopDetecting()
        if !coordinator.stopped { view.captureSession.stop() }
    }

    @objc(MooveRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        let onFound: ([String]) -> Void
        let onFinished: (Result<CapturedRoom, Error>, [RoomGeometry.Object], AutoPhotographer) -> Void
        var stopped = false
        private let detector = ExtraObjectDetector()
        private let photographer = AutoPhotographer()
        private var timer: Timer?
        private var lastFound: [String] = []

        init(onFound: @escaping ([String]) -> Void, onFinished: @escaping (Result<CapturedRoom, Error>, [RoomGeometry.Object], AutoPhotographer) -> Void) {
            self.onFound = onFound
            self.onFinished = onFinished
        }

        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {}

        func startDetecting(on session: ARSession) {
            let photographer = photographer, detector = detector
            // ~3 frames a second: the detector takes ~12 ms per frame on an M5's Neural
            // Engine, and busy frames are skipped, so this leaves RoomPlan room to work.
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 3, repeats: true) { [weak self] _ in
                photographer.offer(session)
                guard let detector else { return }  // model not bundled: RoomPlan only (photos still work)
                detector.offer(session)
                let found = detector.foundSoFar
                if found != self?.lastFound {
                    self?.lastFound = found
                    self?.onFound(found)
                }
            }
        }

        func stopDetecting() {
            timer?.invalidate()
            timer = nil
        }

        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

        func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            if let error { return onFinished(.failure(error), [], photographer) }
            let roomPlan = RoomGeometry(processedResult)
            let extras = detector?.results(floorY: roomPlan.floorY, excluding: roomPlan.objects) ?? []
            if let detector {
                print("[extra-objects] \(extras.map(\.category)) (frames \(detector.framesRun), depth \(detector.usedDepth), raycast \(detector.usedRaycast))")
            }
            print("[auto-photos] \(photographer.keyframeCount) keyframes")
            onFinished(.success(processedResult), extras, photographer)
        }
    }
}
