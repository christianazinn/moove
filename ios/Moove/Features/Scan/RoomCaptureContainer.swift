import SwiftUI
import RoomPlan
import os
@preconcurrency import ARKit
import MooveKit

extension Logger {
    static let scan = Logger(subsystem: "app.moove", category: "scan")
}

/// SwiftUI wrapper for Apple's RoomPlan capture UI. Calls `onFinished` with the
/// processed room, plus any everyday objects RoomPlan doesn't recognize that the
/// extra detector (#73) found and measured in the same scan.
///
/// Each scan gets its own `RoomCaptureView` (made in `makeUIView`, never reused).
/// While it runs, the screen stays awake and a banner warns when the phone is
/// getting hot or the scan was interrupted by leaving the app.
struct RoomCaptureContainer: UIViewRepresentable {
    @Binding var stopRequested: Bool
    /// Where RoomPlan's raw capture data is saved before processing, so a room
    /// can be rebuilt (`ScanSession.rebuild`) if processing fails.
    var rawDataURL: URL?
    /// Live list of extra objects found so far (e.g. ["bicycle"]), for on-screen chips.
    var onFound: ([String]) -> Void = { _ in }
    var onFinished: (Result<CapturedRoom, Error>, [RoomGeometry.Object]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound, onFinished: onFinished) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        context.coordinator.rawDataURL = rawDataURL
        context.coordinator.start(on: view)
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        context.coordinator.startDetecting(on: view.captureSession.arSession)
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        context.coordinator.onFinished = onFinished
        context.coordinator.onFound = onFound
        context.coordinator.rawDataURL = rawDataURL
        if stopRequested && !context.coordinator.stopped {
            context.coordinator.stopped = true
            context.coordinator.stopDetecting()
            view.captureSession.stop()
        }
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        coordinator.stopDetecting()
        if !coordinator.stopped { view.captureSession.stop() }
        coordinator.end()
    }

    /// Main-actor only: RoomCaptureView calls its delegate on the main thread.
    @MainActor
    @objc(MooveRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        var onFound: ([String]) -> Void
        var onFinished: (Result<CapturedRoom, Error>, [RoomGeometry.Object]) -> Void
        var rawDataURL: URL?
        var stopped = false
        /// The data RoomPlan handed over for processing, kept to rebuild the room if processing fails.
        private var roomData: CapturedRoomData?
        private weak var view: RoomCaptureView?
        private var banner: UIView?
        private var observers: [any NSObjectProtocol] = []
        private var idleTimerWasDisabled: Bool?
        private var interrupted = false
        private let detector = ExtraObjectDetector()
        private var timer: Timer?
        private var lastFound: [String] = []

        init(onFound: @escaping ([String]) -> Void, onFinished: @escaping (Result<CapturedRoom, Error>, [RoomGeometry.Object]) -> Void) {
            self.onFound = onFound
            self.onFinished = onFinished
        }

        nonisolated required init?(coder: NSCoder) { nil }
        nonisolated func encode(with coder: NSCoder) {}

        // MARK: Lifecycle

        func start(on view: RoomCaptureView) {
            self.view = view
            idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateBanner() }
                },
                // Leaving the app pauses RoomPlan's ARKit session; tracking may not pick up again.
                center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        Logger.scan.notice("Scan interrupted: app went to the background")
                        self?.interrupted = true
                        self?.updateBanner()
                    }
                },
            ]
            updateBanner()
        }

        /// Restores the idle timer and stops observing. Safe to call more than once.
        func end() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            if let idleTimerWasDisabled {
                UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
                self.idleTimerWasDisabled = nil
            }
            banner?.removeFromSuperview()
            banner = nil
        }

        // MARK: Extra objects (#73)

        func startDetecting(on session: ARSession) {
            guard let detector, timer == nil else { return }  // model not bundled: RoomPlan only
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                // Scheduled on the main run loop, so this runs on the main actor.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    detector.offer(session)
                    let found = detector.foundSoFar
                    if found != self.lastFound {
                        self.lastFound = found
                        self.onFound(found)
                    }
                }
            }
        }

        func stopDetecting() {
            timer?.invalidate()
            timer = nil
        }

        /// The extra detector's objects for this room, minus anything RoomPlan already outlined.
        private func extras(for room: CapturedRoom) -> [RoomGeometry.Object] {
            guard let detector else { return [] }
            let roomPlan = RoomGeometry(room)
            let extras = detector.results(floorY: roomPlan.floorY, excluding: roomPlan.objects)
            Logger.scan.notice("Extra objects: \(extras.map(\.category), privacy: .public) (depth frames \(detector.usedDepth), raycast frames \(detector.usedRaycast))")
            return extras
        }

        // MARK: RoomCaptureViewDelegate

        nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
            MainActor.assumeIsolated { shouldPresent(roomDataForProcessing, error: error) }
        }

        nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            MainActor.assumeIsolated { didPresent(processedResult, error: error) }
        }

        private func shouldPresent(_ data: CapturedRoomData, error: Error?) -> Bool {
            stopped = true  // the session has ended, whether by Done or an error
            roomData = data
            if let rawDataURL { Self.save(data, to: rawDataURL) }
            if let error {
                Logger.scan.error("Scan ended with an error: \(Self.describe(error), privacy: .public)")
                end()
                stopDetecting()
                onFinished(.failure(CaptureFailure(error)), [])
                return false
            }
            return true
        }

        private func didPresent(_ room: CapturedRoom, error: Error?) {
            end()
            stopDetecting()
            guard let error else { return onFinished(.success(room), extras(for: room)) }
            Logger.scan.error("RoomPlan processing failed: \(Self.describe(error), privacy: .public)")
            guard let roomData else { return onFinished(.failure(CaptureFailure(error)), []) }
            // Processing failed; try once more from the raw data.
            Task {
                do {
                    let rebuilt = try await ScanSession.rebuild(roomData)
                    Logger.scan.notice("Rebuilt the room from the raw capture data")
                    onFinished(.success(rebuilt), extras(for: rebuilt))
                } catch let rebuildError {
                    Logger.scan.error("Rebuilding the room failed: \(String(describing: rebuildError), privacy: .public)")
                    onFinished(.failure(CaptureFailure(error)), [])
                }
            }
        }

        /// Writes RoomPlan's raw capture data off the main thread.
        private nonisolated static func save(_ data: CapturedRoomData, to url: URL) {
            Task.detached(priority: .userInitiated) {
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(data).write(to: url)
                } catch {
                    Logger.scan.error("Couldn't save the raw capture data: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // MARK: Errors

        private nonisolated static func describe(_ error: Error) -> String {
            guard let error = error as? RoomCaptureSession.CaptureError else { return String(describing: error) }
            switch error {
            case .exceedSceneSizeLimit: return "CaptureError.exceedSceneSizeLimit"
            case .worldTrackingFailure: return "CaptureError.worldTrackingFailure"
            case .invalidARConfiguration: return "CaptureError.invalidARConfiguration"
            case .deviceTooHot: return "CaptureError.deviceTooHot"
            case .deviceNotSupported: return "CaptureError.deviceNotSupported"
            case .internalError: return "CaptureError.internalError"
            @unknown default: return "CaptureError.\(error)"
            }
        }

        /// A RoomPlan error with a message that says what to do next.
        struct CaptureFailure: LocalizedError {
            let underlying: Error
            init(_ underlying: Error) { self.underlying = underlying }

            var errorDescription: String? {
                guard let error = underlying as? RoomCaptureSession.CaptureError else { return underlying.localizedDescription }
                switch error {
                case .exceedSceneSizeLimit:
                    return "This space is too big for one scan. Scan one room at a time."
                case .worldTrackingFailure:
                    return "RoomPlan lost track of where the phone is. Scan again with the lights on, moving slowly."
                case .invalidARConfiguration:
                    return "RoomPlan couldn't start the camera. Close and reopen Moove, then scan again."
                case .deviceTooHot:
                    return "Your iPhone got too hot to keep scanning. Let it cool down, then scan again."
                case .deviceNotSupported:
                    return "This device can't scan rooms. RoomPlan needs an iPhone or iPad with LiDAR."
                case .internalError:
                    return "RoomPlan hit an internal error. Try scanning again."
                @unknown default:
                    return error.localizedDescription
                }
            }
        }

        // MARK: Banner

        private var bannerText: String? {
            switch ProcessInfo.processInfo.thermalState {
            case .critical:
                return "Your iPhone is too hot to keep scanning. Tap Done now to keep what you have."
            case .serious:
                return "Your iPhone is getting hot. Finish soon, or RoomPlan may stop the scan."
            default:
                break
            }
            if interrupted {
                return "The scan was paused when you left Moove. Point at a part you already scanned to pick up again, or tap Done."
            }
            return nil
        }

        private func updateBanner() {
            if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
                Logger.scan.notice("Thermal state during scan: \(ProcessInfo.processInfo.thermalState.rawValue)")
            }
            guard let view, let text = bannerText else {
                banner?.removeFromSuperview()
                banner = nil
                return
            }
            if let label = banner?.subviews.first as? UILabel {
                label.text = text
                return
            }
            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .footnote)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .black
            label.translatesAutoresizingMaskIntoConstraints = false
            let box = UIView()
            box.backgroundColor = .systemYellow
            box.layer.cornerRadius = 12
            box.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
            view.addSubview(box)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
                label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
                box.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                box.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                box.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
            banner = box
        }
    }
}
