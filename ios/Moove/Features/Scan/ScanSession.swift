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
    }

    var phase: Phase = .capturing
    var roomName = "Bedroom"
    private(set) var objects: [DetectedObject] = []
    private(set) var photos: [UUID: URL] = [:]
    private(set) var geometry: RoomGeometry?
    let folder: URL

    init() {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        folder = URL.documentsDirectory.appending(path: "scans/\(stamp)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder.appending(path: "photos"), withIntermediateDirectories: true)
    }

    var roomJSON: URL { folder.appending(path: "room.json") }
    var roomUSDZ: URL { folder.appending(path: "room.usdz") }

    func captured(_ room: CapturedRoom) {
        do {
            try JSONEncoder().encode(room).write(to: roomJSON)
            try room.export(to: roomUSDZ, exportOptions: .model)
            let geometry = RoomGeometry(room)
            self.geometry = geometry
            try JSONEncoder().encode(geometry).write(to: folder.appending(path: "geometry.json"))
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
        }
        phase = .reviewing
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
        do {
            func send(_ file: URL, _ type: String) async throws -> String {
                let url = try await uploader.upload(file, contentType: type)
                done += 1
                phase = .uploading(done: done, total: total)
                return url
            }
            let usdzUrl = try await send(roomUSDZ, "model/vnd.usdz+zip")
            let jsonUrl = try await send(roomJSON, "application/json")
            var photoUrls: [UUID: String] = [:]
            for (id, file) in photos { photoUrls[id] = try await send(file, "image/jpeg") }

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
        } catch {
            phase = .failed("Upload failed: \(error.localizedDescription). The scan is saved on this device.")
        }
    }
}
