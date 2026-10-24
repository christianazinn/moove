import Foundation
import Observation
import os
import RoomPlan
import MooveKit

/// One scan, from RoomPlan result to `importScan`. Everything is also written
/// to Documents/scans/<id>/ in the #3 fixture layout (room.json, room.usdz,
/// geometry.json, photos/<object uuid>.jpg) so a good scan can be copied off the device
/// (Files app or `xcrun devicectl device copy from`) and committed as a fixture.
@MainActor
@Observable
final class ScanSession {
    enum Phase: Equatable {
        case capturing
        /// Showing the 3D result before photos.
        case reviewing
        case photos
        case uploading(done: Int, total: Int)
        case finished
        case failed(String)
    }

    struct DetectedObject: Identifiable, Hashable {
        let id: UUID
        let category: String
        let widthM: Double
        let heightM: Double
        let depthM: Double
        /// Added by photo because RoomPlan didn't detect it: no size or position,
        /// so it's in the inventory but not in the 3D room.
        var manual = false

        static func manual() -> DetectedObject {
            DetectedObject(id: UUID(), category: "other", widthM: 0, heightM: 0, depthM: 0, manual: true)
        }
    }

    var phase: Phase = .capturing
    var roomName = "Bedroom"
    private(set) var objects: [DetectedObject] = []
    private(set) var photos: [UUID: URL] = [:]
    private(set) var geometry: RoomGeometry?
    /// Set when some files couldn't reach the worker's upload server.
    private(set) var uploadProblem: String?
    let folder: URL

    init() {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        // Created on first write, so opening and cancelling a scan leaves no empty folder.
        folder = URL.documentsDirectory.appending(path: "scans/\(stamp)", directoryHint: .isDirectory)
    }

    var roomJSON: URL { folder.appending(path: "room.json") }
    var roomUSDZ: URL { folder.appending(path: "room.usdz") }

    /// RoomPlan's raw capture data, saved before processing so the room can be rebuilt.
    var capturedRoomDataJSON: URL { folder.appending(path: "captured-room-data.json") }

    func captured(_ room: CapturedRoom) {
        Task { await save(room) }
    }

    /// Writes the room files off the main thread, then shows the review.
    private func save(_ room: CapturedRoom) async {
        let folder = folder, roomJSON = roomJSON, roomUSDZ = roomUSDZ
        do {
            geometry = try await Task.detached(priority: .userInitiated) {
                try Self.write(room, folder: folder, roomJSON: roomJSON, roomUSDZ: roomUSDZ)
            }.value
        } catch {
            Logger.scan.error("Couldn't save the scan: \(error.localizedDescription, privacy: .public)")
            phase = .failed("Couldn't save the scan: \(error.localizedDescription)")
            return
        }
        // RoomPlan dimensions are (width, height, depth) in meters.
        objects = room.objects.map { object in
            DetectedObject(
                id: object.identifier,
                category: String(describing: object.category),
                widthM: Double(object.dimensions.x),
                heightM: Double(object.dimensions.y),
                depthM: Double(object.dimensions.z)
            )
        }
        phase = .reviewing
    }

    /// JSON encoding and USDZ export are slow for big rooms, so they run off the main actor.
    private nonisolated static func write(_ room: CapturedRoom, folder: URL, roomJSON: URL, roomUSDZ: URL) throws -> RoomGeometry {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(room).write(to: roomJSON)
        try room.export(to: roomUSDZ, exportOptions: .model)
        let geometry = RoomGeometry(room)
        try JSONEncoder().encode(geometry).write(to: folder.appending(path: "geometry.json"))
        return geometry
    }

    /// Runs RoomPlan's processing again on raw capture data, e.g. after the
    /// capture view's own processing failed.
    nonisolated static func rebuild(_ data: CapturedRoomData) async throws -> CapturedRoom {
        try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
    }

    /// Rebuilds the room from `capturedRoomDataJSON`, for retrying a scan whose processing failed.
    func rebuildFromSavedData() async {
        do {
            let data = try JSONDecoder().decode(CapturedRoomData.self, from: Data(contentsOf: capturedRoomDataJSON))
            let room = try await Self.rebuild(data)
            captured(room)
        } catch {
            Logger.scan.error("Couldn't rebuild the scan: \(String(describing: error), privacy: .public)")
            phase = .failed("Couldn't rebuild the scan: \(error.localizedDescription)")
        }
    }

    /// An item RoomPlan missed, added by its photo. The vision agent names and
    /// categorizes it from the photo.
    func addManual(_ object: DetectedObject, photo jpeg: Data) {
        guard object.manual, !objects.contains(where: { $0.id == object.id }) else { return }
        objects.append(object)
        setPhoto(jpeg, for: object)
    }

    func remove(_ object: DetectedObject) {
        objects.removeAll { $0.id == object.id }
        if let file = photos.removeValue(forKey: object.id) { try? FileManager.default.removeItem(at: file) }
    }

    func setPhoto(_ jpeg: Data, for object: DetectedObject) {
        let url = folder.appending(path: "photos/\(object.id.uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: url)
            photos[object.id] = url
        } catch {
            phase = .failed("Couldn't save the photo: \(error.localizedDescription)")
        }
    }

    /// Upload and import progress, kept across retries (see `ScanSubmission`).
    private(set) var submission = ScanSubmission()
    /// True when the room files were imported without a public URL: they're only
    /// in this device's scan folder, and SpacetimeDB has '' for them.
    private(set) var roomFilesLocalOnly = false

    /// Call after a photo is (re)taken: its file is overwritten in place, so an
    /// upload from an earlier failed attempt is stale.
    func photoChanged(for object: DetectedObject) {
        if let file = photos[object.id] { submission.forgetUpload(file) }
    }

    /// Uploads the room files and photos, then creates the room, scan and
    /// items in one reducer call. Safe to call again after a failure: files
    /// already uploaded aren't re-sent, and an imported scan isn't imported twice.
    func submit(to store: MooveStore, uploader: Uploader) async {
        guard submission.begin() else {
            if submission.isImported { phase = .finished }
            return
        }
        let total = 2 + photos.count
        var done = 0
        phase = .uploading(done: 0, total: total)
        uploadProblem = nil
        func send(_ file: URL, _ type: String) async -> String? {
            defer {
                done += 1
                phase = .uploading(done: done, total: total)
            }
            if let url = submission.uploaded[file] { return url }  // uploaded on an earlier attempt
            guard uploadProblem == nil else { return nil }  // server is down; don't wait out each timeout
            do {
                let url = try await uploader.upload(file, contentType: type)
                submission.recordUpload(file, url: url)
                return url
            } catch {
                uploadProblem = error.localizedDescription
                return nil
            }
        }
        // If the worker's upload server is unreachable, still import the scan:
        // room files stay local-only in this device's scan folder, and photos are
        // left off so the vision agent never gets a URL it can't fetch.
        let usdzUrl = await send(roomUSDZ, "model/vnd.usdz+zip")
        let jsonUrl = await send(roomJSON, "application/json")
        var photoUrls: [UUID: String] = [:]
        for (id, file) in photos { photoUrls[id] = await send(file, "image/jpeg") }

        var scan = ScanImport(
            roomName: roomName,
            usdzUrl: usdzUrl,
            capturedRoomJsonUrl: jsonUrl,
            objects: objects.map {
                ScanObject(scanObjectId: $0.id.uuidString, category: $0.category,
                           widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM,
                           photoUrl: photoUrls[$0.id])
            }
        )
        // Never sync a file:// URL (LocalUploader's) to SpacetimeDB. The offline
        // fixture backend lives on this device, so it keeps them.
        if store.backendKind != .fixture { scan = scan.syncable() }
        roomFilesLocalOnly = scan.hasLocalOnlyRoomFiles && store.backendKind != .fixture

        let imported = await store.importScan(scan)
        submission.finish(error: imported ? nil : (store.lastError ?? "The import failed"))
        if case .failed(let error) = submission.state {
            phase = .failed(error)
        } else {
            phase = .finished
        }
    }
}
