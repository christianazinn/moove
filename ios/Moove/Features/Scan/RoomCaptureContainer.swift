import SwiftUI
import RoomPlan

/// SwiftUI wrapper for Apple's RoomPlan capture UI. Calls `onFinished` with
/// the processed room once the user taps Done and RoomPlan finishes processing.
struct RoomCaptureContainer: UIViewRepresentable {
    @Binding var stopRequested: Bool
    var onFinished: (Result<CapturedRoom, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinished: onFinished) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if stopRequested && !context.coordinator.stopped {
            context.coordinator.stopped = true
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        if !coordinator.stopped { view.captureSession.stop() }
    }

    @objc(MooveRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        let onFinished: (Result<CapturedRoom, Error>) -> Void
        var stopped = false

        init(onFinished: @escaping (Result<CapturedRoom, Error>) -> Void) {
            self.onFinished = onFinished
        }

        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {}

        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

        func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            if let error { onFinished(.failure(error)) } else { onFinished(.success(processedResult)) }
        }
    }
}
