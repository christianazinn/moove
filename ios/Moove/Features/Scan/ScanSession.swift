import Foundation
import Observation
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
        folder = URL.documentsDirectory.appending(path: "scans/\(stamp)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder.appending(path: "photos"), withIntermediateDirectories: true)
    }

    var roomJSON: URL { folder.appending(path: "room.json") }
    var roomUSDZ: URL { folder.appending(path: "room.usdz") }
    /// Moove's own geometry: RoomPlan's room plus the extra detected objects.
    var geometryJSON: URL { folder.appending(path: "geometry.json") }

    /// `extras` are objects RoomPlan doesn't recognize, found by the extra detector (#73).
    func captured(_ room: CapturedRoom, extras: [RoomGeometry.Object] = []) {
        do {
            try JSONEncoder().encode(room).write(to: roomJSON)
            try room.export(to: roomUSDZ, exportOptions: .model)
            var geometry = RoomGeometry(room)
            geometry.objects += extras
            self.geometry = geometry
            try JSONEncoder().encode(geometry).write(to: geometryJSON)
        } catch {
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
        } + extras.compactMap { extra in
            UUID(uuidString: extra.id).map {
                DetectedObject(id: $0, category: extra.category, widthM: Double(extra.dimensions.x),
                               heightM: Double(extra.dimensions.y), depthM: Double(extra.dimensions.z))
            }
        }
        phase = .reviewing
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
            try jpeg.write(to: url)
            photos[object.id] = url
        } catch {
            phase = .failed("Couldn't save the photo: \(error.localizedDescription)")
        }
    }

    /// Uploads the room files and photos, then creates the room, scan and
    /// items in one reducer call.
    func submit(to store: MooveStore, uploader: Uploader) async {
        let total = 2 + photos.count
        var done = 0
        phase = .uploading(done: 0, total: total)
        uploadProblem = nil
        func send(_ file: URL, _ type: String) async -> String? {
            defer {
                done += 1
                phase = .uploading(done: done, total: total)
            }
            guard uploadProblem == nil else { return nil }  // server is down; don't wait out each timeout
            do {
                return try await uploader.upload(file, contentType: type)
            } catch {
                uploadProblem = error.localizedDescription
                return nil
            }
        }
        // If the worker's upload server is unreachable, still import the scan:
        // room files fall back to this device's copies (only the app reads them),
        // and photos are left off so the vision agent never gets a URL it can't fetch.
        let usdzUrl = await send(roomUSDZ, "model/vnd.usdz+zip") ?? roomUSDZ.absoluteString
        // Upload Moove's geometry (it includes objects RoomPlan doesn't know); RoomPlan's
        // raw room.json stays in the on-device fixture folder.
        let jsonUrl = await send(geometryJSON, "application/json") ?? geometryJSON.absoluteString
        var photoUrls: [UUID: String] = [:]
        for (id, file) in photos { photoUrls[id] = await send(file, "image/jpeg") }

        await store.importScan(ScanImport(
            roomName: roomName,
            usdzUrl: usdzUrl,
            capturedRoomJsonUrl: jsonUrl,
            objects: objects.map {
                ScanObject(scanObjectId: $0.id.uuidString, category: $0.category,
                           widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM,
                           photoUrl: photoUrls[$0.id])
            }
        ))
        if let error = store.lastError {
            phase = .failed(error)
        } else {
            phase = .finished
        }
    }
}
