import SwiftUI
import RoomPlan
@preconcurrency import ARKit
import MooveKit

/// SwiftUI wrapper for Apple's RoomPlan capture UI. Calls `onFinished` with the
/// processed room, plus any everyday objects RoomPlan doesn't recognize that the
/// extra detector (#73) found and measured in the same scan.
struct RoomCaptureContainer: UIViewRepresentable {
    @Binding var stopRequested: Bool
    /// Polls the capture's ARSession for color-sampling keyframes while it runs.
    var recorder: ScanFrameRecorder? = nil
    /// Live list of extra objects found so far (e.g. ["bicycle"]), for on-screen chips.
    var onFound: ([String]) -> Void = { _ in }
    var onFinished: (Result<CapturedRoom, Error>, [RoomGeometry.Object]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound, onFinished: onFinished) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        recorder?.start(view.captureSession.arSession)
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
        let onFinished: (Result<CapturedRoom, Error>, [RoomGeometry.Object]) -> Void
        var stopped = false
        private let detector = ExtraObjectDetector()
        private var timer: Timer?
        private var lastFound: [String] = []

        init(onFound: @escaping ([String]) -> Void, onFinished: @escaping (Result<CapturedRoom, Error>, [RoomGeometry.Object]) -> Void) {
            self.onFound = onFound
            self.onFinished = onFinished
        }

        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {}

        func startDetecting(on session: ARSession) {
            guard let detector else { return }  // model not bundled: RoomPlan only
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
            if let error { return onFinished(.failure(error), []) }
            let roomPlan = RoomGeometry(processedResult)
            let extras = detector?.results(floorY: roomPlan.floorY, excluding: roomPlan.objects) ?? []
            if let detector {
                print("[extra-objects] \(extras.map(\.category)) (depth frames \(detector.usedDepth), raycast frames \(detector.usedRaycast))")
            }
            onFinished(.success(processedResult), extras)
        }
    }
}
