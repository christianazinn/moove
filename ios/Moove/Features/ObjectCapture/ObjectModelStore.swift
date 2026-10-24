import Foundation
import Observation
import MooveKit

/// Where captured 3D models live on this device, keyed by the item's RoomPlan
/// `scanObjectId`: Documents/models/<id>/model.usdz (plus the capture's images
/// and checkpoint while it's being built). Also remembers each model's
/// "rotate 90°" correction. Views read `revision` so they refresh when a model
/// is added or turned.
@MainActor
@Observable
final class ObjectModelStore {
    static let shared = ObjectModelStore()

    private(set) var revision = 0
    @ObservationIgnored private var remoteCache: [String: URL] = [:]
    @ObservationIgnored private var remoteSource: [String: URL] = [:]
    @ObservationIgnored private var failedAt: [URL: Date] = [:]

    private let root = URL.documentsDirectory.appending(path: "models", directoryHint: .isDirectory)
    private let turnsKey = "moove.modelTurns"

    func folder(for id: String) -> URL { root.appending(path: Self.safe(id), directoryHint: .isDirectory) }
    func modelFile(for id: String) -> URL { folder(for: id).appending(path: "model.usdz") }

    /// The model to show for an item: captured on this device, or downloaded
    /// from the item's `modelUrl` once that's synced.
    func modelURL(for id: String) -> URL? {
        _ = revision
        let local = modelFile(for: id)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return remoteCache[id]
    }

    func hasModel(_ id: String?) -> Bool { id.map { modelURL(for: $0) != nil } ?? false }

    /// Quick Look / AR only open USDZ; SAM 3D models are GLB.
    static func isQuickLookable(_ url: URL) -> Bool { url.pathExtension.lowercased() == "usdz" }

    /// Called when a capture finishes building.
    func didSaveModel(for id: String) {
        // The images and checkpoint are big; only the USDZ is needed now.
        let folder = folder(for: id)
        for sub in ["Images", "Checkpoint"] { try? FileManager.default.removeItem(at: folder.appending(path: sub)) }
        revision += 1
    }

    func deleteModel(for id: String) {
        try? FileManager.default.removeItem(at: folder(for: id))
        remoteCache[id] = nil
        remoteSource[id] = nil
        revision += 1
    }

    // MARK: Orientation correction

    func extraTurns(for id: String) -> Int {
        _ = revision
        return (UserDefaults.standard.dictionary(forKey: turnsKey)?[id] as? Int) ?? 0
    }

    func rotate(_ id: String) {
        var all = UserDefaults.standard.dictionary(forKey: turnsKey) ?? [:]
        all[id] = ((all[id] as? Int ?? 0) + 1) % 4
        UserDefaults.standard.set(all, forKey: turnsKey)
        revision += 1
    }

    // MARK: Synced models

    /// Downloads a synced model (item.modelUrl: another phone's capture, or SAM 3D) into the cache.
    /// Returns true if a new file was cached. A URL is only remembered once its
    /// download succeeds; a cancelled download (e.g. the view's task restarting) is
    /// simply retried next time, and a real failure is retried after 30 s.
    /// `notify: false` skips the revision bump for callers that load the result
    /// themselves (bumping restarts their `.task(id:)` and cancels the loop).
    @discardableResult
    func fetchRemote(_ url: URL, for id: String, notify: Bool = true) async -> Bool {
        if FileManager.default.fileExists(atPath: modelFile(for: id).path) { return false }
        if remoteSource[id] == url, remoteCache[id] != nil { return false }
        if let failed = failedAt[url], Date.now.timeIntervalSince(failed) < 30 { return false }
        if url.isFileURL {
            // Another device's file URL is useless here; only our own files are readable.
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return cache(url, from: url, for: id, notify: notify)
        }
        do {
            let (temp, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                failedAt[url] = .now
                return false
            }
            let ext = url.pathExtension.lowercased() == "glb" ? "glb" : "usdz"
            let dest = FileManager.default.temporaryDirectory.appending(path: "remote-\(Self.safe(id))-\(abs(url.lastPathComponent.hashValue)).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
            return cache(dest, from: url, for: id, notify: notify)
        } catch {
            let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            if !cancelled { failedAt[url] = .now }  // offline or the worker is down: keep the block for now
            return false
        }
    }

    private func cache(_ file: URL, from url: URL, for id: String, notify: Bool) -> Bool {
        remoteSource[id] = url
        remoteCache[id] = file
        failedAt[url] = nil
        if notify { revision += 1 }
        return true
    }

    /// True when the model was captured on this phone (not just downloaded).
    func hasLocalModel(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: modelFile(for: id).path)
    }

    private static func safe(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }
}
