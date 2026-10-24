import SwiftUI
import RealityKit
import MooveKit

/// Guided Object Capture for one item, then on-device reconstruction into a
/// USDZ: point at the item, adjust the box, walk around it (optionally a
/// second pass, e.g. after flipping something small), then wait a few minutes
/// while the phone builds the model.
struct ObjectCaptureFlowView: View {
    let objectId: String
    let title: String
    var onFinished: (URL) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var session: ObjectCaptureSession?
    /// Held so Cancel can stop a reconstruction that's already running.
    @State private var photogrammetry: PhotogrammetrySession?
    @State private var phase: Phase = .capturing
    @State private var progress: Double = 0
    @State private var stage: String = "Preparing"

    enum Phase: Equatable {
        case capturing, reconstructing, done, failed(String)
    }

    static var isSupported: Bool { ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch phase {
            case .capturing:
                if let session {
                    ObjectCaptureView(session: session)
                        .ignoresSafeArea()
                        .overlay(alignment: .bottom) { CaptureControls(session: session, title: title) }
                        .overlay(alignment: .top) { CaptureHint(session: session) }
                } else {
                    ProgressView().tint(.white)
                }
            case .reconstructing:
                reconstructing
            case .done:
                ContentUnavailableView {
                    Label("3D model ready", systemImage: "cube.fill")
                } description: {
                    Text("It's now placed in your room's 3D view.")
                } actions: {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            case .failed(let why):
                ContentUnavailableView {
                    Label("Couldn't build the model", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(why)
                } actions: {
                    Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            if phase == .capturing || phase == .reconstructing {
                Button("Cancel", systemImage: "xmark.circle.fill") { cancel() }
                    .labelStyle(.iconOnly).font(.title).foregroundStyle(.white, .black.opacity(0.4))
                    .padding()
            }
        }
        .task { await run() }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
    }

    private var reconstructing: some View {
        VStack(spacing: 18) {
            Image(systemName: "cube.transparent").font(.system(size: 56)).foregroundStyle(.white)
            Text("Building 3D model of \(title)").font(.headline).foregroundStyle(.white)
            ProgressView(value: progress).tint(.white).frame(maxWidth: 260)
            Text("\(stage) · \(Int(progress * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            Text("Keep Moove open. This takes a few minutes.").font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .padding()
    }

    // MARK: Pipeline

    private var folder: URL { ObjectModelStore.shared.folder(for: objectId) }
    private var imagesFolder: URL { folder.appending(path: "Images", directoryHint: .isDirectory) }
    private var checkpointFolder: URL { folder.appending(path: "Checkpoint", directoryHint: .isDirectory) }

    private func run() async {
        guard Self.isSupported else {
            phase = .failed("Object Capture needs an iPhone or iPad with LiDAR.")
            return
        }
        // Start from scratch: the session requires an empty images folder.
        try? FileManager.default.removeItem(at: imagesFolder)
        try? FileManager.default.removeItem(at: checkpointFolder)
        do {
            try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpointFolder, withIntermediateDirectories: true)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let session = ObjectCaptureSession()
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = checkpointFolder
        configuration.isOverCaptureEnabled = true
        session.start(imagesDirectory: imagesFolder, configuration: configuration)
        self.session = session

        for await state in session.stateUpdates {
            switch state {
            case .completed:
                // Release the camera session before reconstructing: both are memory hungry.
                self.session = nil
                await reconstruct()
                return
            case .failed(let error):
                self.session = nil
                if case ObjectCaptureSession.Error.cancelled = error { return }
                phase = .failed(error.localizedDescription)
                return
            default:
                continue
            }
        }
    }

    private func reconstruct() async {
        phase = .reconstructing
        // Build into a temp file and only replace the item's model once it succeeds,
        // so a failed or cancelled recapture keeps the previous good model.
        let final = ObjectModelStore.shared.modelFile(for: objectId)
        let output = folder.appending(path: "model-building.usdz")
        try? FileManager.default.removeItem(at: output)
        do {
            var configuration = PhotogrammetrySession.Configuration()
            configuration.checkpointDirectory = checkpointFolder
            configuration.isObjectMaskingEnabled = true
            let photogrammetry = try PhotogrammetrySession(input: imagesFolder, configuration: configuration)
            self.photogrammetry = photogrammetry
            defer { self.photogrammetry = nil }
            try photogrammetry.process(requests: [.modelFile(url: output)])
            for try await event in photogrammetry.outputs {
                switch event {
                case .requestProgress(_, let fraction):
                    progress = fraction
                case .requestProgressInfo(_, let info):
                    if let s = info.processingStage { stage = Self.label(s) }
                case .requestError(_, let error):
                    phase = .failed(error.localizedDescription)
                    return
                case .processingCancelled:
                    return
                case .processingComplete:
                    try? FileManager.default.removeItem(at: final)
                    do {
                        try FileManager.default.moveItem(at: output, to: final)
                    } catch {
                        phase = .failed("Couldn't save the model: \(error.localizedDescription)")
                        return
                    }
                    ObjectModelStore.shared.didSaveModel(for: objectId)
                    onFinished(final)
                    phase = .done
                    return
                default:
                    continue
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func cancel() {
        photogrammetry?.cancel()
        session?.cancel()
        try? FileManager.default.removeItem(at: folder.appending(path: "model-building.usdz"))
        try? FileManager.default.removeItem(at: imagesFolder)
        try? FileManager.default.removeItem(at: checkpointFolder)
        dismiss()
    }

    private static func label(_ stage: PhotogrammetrySession.Output.ProcessingStage) -> String {
        switch stage {
        case .preProcessing: "Preparing photos"
        case .imageAlignment: "Aligning photos"
        case .pointCloudGeneration: "Building point cloud"
        case .meshGeneration: "Building mesh"
        case .textureMapping: "Painting textures"
        case .optimization: "Optimizing"
        @unknown default: "Processing"
        }
    }
}

/// Buttons for each capture step, driven by the session's state.
private struct CaptureControls: View {
    let session: ObjectCaptureSession
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            switch session.state {
            case .ready:
                step("Point at the \(title.lowercased()) and tap Continue.") {
                    Button("Continue") { _ = session.startDetecting() }
                }
            case .detecting:
                step("Drag the box's edges so it just fits the item.") {
                    Button("Start capture") { session.startCapturing() }
                    Button("Reset box") { _ = session.resetDetection() }.tint(.white.opacity(0.3))
                }
            case .capturing:
                if session.userCompletedScanPass {
                    step("Pass complete. Another pass from higher or lower helps, or finish now.") {
                        Button("Finish") { session.finish() }
                        Button("Another pass") { session.beginNewScanPass() }.tint(.white.opacity(0.3))
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Walk slowly all the way around").font(.headline)
                        Text("\(session.numberOfShotsTaken) of \(session.maximumNumberOfInputImages) photos")
                            .font(.caption.monospacedDigit()).opacity(0.8)
                        Button("Finish early") { session.finish() }
                            .buttonStyle(.bordered).tint(.white)
                            .disabled(session.numberOfShotsTaken < 20)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.45), in: .rect(cornerRadius: 16))
                }
            case .finishing:
                ProgressView("Saving photos…").tint(.white).foregroundStyle(.white)
            default:
                EmptyView()
            }
        }
        .padding(.bottom, 30)
        .padding(.horizontal)
    }

    private func step(_ text: String, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(spacing: 12) {
            Text(text).multilineTextAlignment(.center).foregroundStyle(.white)
            HStack { buttons() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .background(.black.opacity(0.45), in: .rect(cornerRadius: 16))
    }
}

/// One-line guidance from the session ("Move closer", "More light", ...).
private struct CaptureHint: View {
    let session: ObjectCaptureSession

    var body: some View {
        if let message = Self.message(session.feedback) {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.5), in: .capsule)
                .padding(.top, 60)
        }
    }

    static func message(_ feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        if feedback.contains(.environmentTooDark) { return "Too dark: add more light" }
        if feedback.contains(.environmentLowLight) { return "More light would help" }
        if feedback.contains(.movingTooFast) { return "Slow down" }
        if feedback.contains(.objectTooClose) { return "Move back" }
        if feedback.contains(.objectTooFar) { return "Move closer" }
        if feedback.contains(.outOfFieldOfView) { return "Keep the item in view" }
        if #available(iOS 17.4, *), feedback.contains(.objectNotDetected) { return "Point at the item" }
        return nil
    }
}
