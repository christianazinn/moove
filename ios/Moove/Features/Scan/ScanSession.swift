import Foundation
import Observation
import RoomPlan
import MooveKit

/// One scan, from RoomPlan result to `importScan`. Everything is also written
/// to Documents/scans/<id>/ in the #3 fixture layout (room.json, room.usdz,
/// geometry.json, photos/<object uuid>.jpg, frames/, colors.json) so a good scan can be copied off the device
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
        /// RoomPlan attributes as type-prefixed raw values ("ChairLegType.star"), #110.
        var attributes: [String] = []
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
    /// Wall, floor and per-object colors sampled from the capture's camera frames. Nil until
    /// the analysis finishes (a second or two after capture), or if no frames were kept.
    private(set) var colors: ScanColors?
    /// Keeps camera keyframes during capture for `colors`.
    let frameRecorder = ScanFrameRecorder()
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

    func captured(_ room: CapturedRoom) {
        frameRecorder.stop()
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
                depthM: Double(object.dimensions.z),
                attributes: Self.attributeStrings(object)
            )
        }
        phase = .reviewing
        analyzeColors()
    }

    /// Samples real colors from the kept frames off the main actor. The raw geometry is in
    /// the same ARSession world space as the frames (don't use a `centered()` copy here).
    private func analyzeColors() {
        guard let geometry, !frameRecorder.frames.isEmpty else { return }
        let frames = frameRecorder.frames, folder = folder
        Task { [weak self] in
            let colors = await ScanColorAnalysis.run(geometry: geometry, frames: frames, saveTo: folder)
            try? JSONEncoder().encode(colors).write(to: folder.appending(path: "colors.json"))
            self?.colors = colors
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
            try jpeg.write(to: url)
            photos[object.id] = url
        } catch {
            phase = .failed("Couldn't save the photo: \(error.localizedDescription)")
        }
    }

    /// Uploads the room files and photos, then creates the room, scan and
    /// items in one reducer call.
    func submit(to store: MooveStore, uploader: Uploader) async {
        // A double tap on "Add N items" must not import the scan twice.
        if case .uploading = phase { return }
        if phase == .finished { return }
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
        let jsonUrl = await send(roomJSON, "application/json") ?? roomJSON.absoluteString
        var photoUrls: [UUID: String] = [:]
        for (id, file) in photos { photoUrls[id] = await send(file, "image/jpeg") }

        let imported = await store.importScan(ScanImport(
            roomName: roomName,
            usdzUrl: usdzUrl,
            capturedRoomJsonUrl: jsonUrl,
            objects: objects.map {
                ScanObject(scanObjectId: $0.id.uuidString, category: $0.category,
                           widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM,
                           photoUrl: photoUrls[$0.id], attributes: $0.attributes)
            }
        ))
        phase = imported ? .finished : .failed(store.lastError ?? "Couldn't save the scan")
    }
}

// MARK: - RoomPlan attributes (#110)

extension ScanSession {
    /// RoomPlan's iOS 17 object attributes as type-prefixed values ("ChairType.swivel",
    /// "ChairLegType.star", "TableShapeType.circularElliptic") for `import_scan_v2`, which
    /// the voxel builders read. Spelled out per case rather than via reflection so the
    /// strings can't drift; `unidentified` says nothing, so it's left out.
    nonisolated static func attributeStrings(_ object: CapturedRoom.Object) -> [String] {
        object.attributes.compactMap { attribute -> String? in
            switch attribute {
            case let a as ChairType: value(a).map { "ChairType.\($0)" }
            case let a as ChairArmType: value(a).map { "ChairArmType.\($0)" }
            case let a as ChairBackType: value(a).map { "ChairBackType.\($0)" }
            case let a as ChairLegType: value(a).map { "ChairLegType.\($0)" }
            case let a as SofaType: value(a).map { "SofaType.\($0)" }
            case let a as TableType: value(a).map { "TableType.\($0)" }
            case let a as TableShapeType: value(a).map { "TableShapeType.\($0)" }
            case let a as StorageType: value(a).map { "StorageType.\($0)" }
            default: nil
            }
        }
    }

    private nonisolated static func value(_ a: ChairType) -> String? {
        switch a {
        case .dining: "dining"
        case .stool: "stool"
        case .swivel: "swivel"
        case .unidentified: nil
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: ChairArmType) -> String? {
        switch a {
        case .existing: "existing"
        case .missing: "missing"
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: ChairBackType) -> String? {
        switch a {
        case .existing: "existing"
        case .missing: "missing"
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: ChairLegType) -> String? {
        switch a {
        case .four: "four"
        case .star: "star"
        case .unidentified: nil
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: SofaType) -> String? {
        switch a {
        case .lShaped: "lShaped"
        case .lShapedExtension: "lShapedExtension"
        case .rectangular: "rectangular"
        case .singleSeat: "singleSeat"
        case .unidentified: nil
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: TableType) -> String? {
        switch a {
        case .coffee: "coffee"
        case .dining: "dining"
        case .unidentified: nil
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: TableShapeType) -> String? {
        switch a {
        case .circularElliptic: "circularElliptic"
        case .lShaped: "lShaped"
        case .rectangular: "rectangular"
        case .unidentified: nil
        @unknown default: nil
        }
    }

    private nonisolated static func value(_ a: StorageType) -> String? {
        switch a {
        case .cabinet: "cabinet"
        case .shelf: "shelf"
        @unknown default: nil
        }
    }
}
