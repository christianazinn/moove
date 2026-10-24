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
        var category: String
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
    /// Objects whose photo was cut from a scan keyframe (#82), not taken by the user.
    private(set) var autoPhotos: Set<UUID> = []
    /// Wide room photos for the worker's photo sweep (#92), sent after the import.
    private(set) var roomPhotos: [URL] = []
    /// True while auto photos are being cut after the scan.
    private(set) var autoPhotosPending = false
    private(set) var geometry: RoomGeometry?
    /// Wall, floor and per-object colors sampled from the capture's camera frames. Nil until
    /// the analysis finishes (a second or two after capture), or if no frames were kept.
    private(set) var colors: ScanColors?
    /// Keeps camera keyframes during capture for `colors`.
    let frameRecorder = ScanFrameRecorder()
    /// Where the scan was imported, so colors that finish sampling after the import still get saved.
    @ObservationIgnored private weak var store: MooveStore?
    @ObservationIgnored private var colorsSaved = false
    /// Set when some files couldn't reach the worker's upload server.
    private(set) var uploadProblem: String?
    /// Item photos that didn't reach the worker yet (#222), keyed by object. After the
    /// import they keep retrying in the background and are attached with `add_item_photo`.
    private(set) var pendingPhotos: [UUID: URL] = [:]
    let folder: URL

    init() {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        folder = URL.documentsDirectory.appending(path: "scans/\(stamp)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder.appending(path: "photos"), withIntermediateDirectories: true)
    }

    var roomJSON: URL { folder.appending(path: "room.json") }
    /// Moove's own geometry: RoomPlan's room plus the extra detected objects (#73).
    var geometryJSON: URL { folder.appending(path: "geometry.json") }
    var roomUSDZ: URL { folder.appending(path: "room.usdz") }

    /// `extras` are objects RoomPlan doesn't recognize, found by the extra detector (#73).
    /// `photographer` holds the scan's keyframes; every object gets its best view as a
    /// photo, so the checklist starts mostly filled in (#82).
    func captured(_ room: CapturedRoom, extras: [RoomGeometry.Object] = [], photographer: AutoPhotographer? = nil) {
        frameRecorder.stop()
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
                depthM: Double(object.dimensions.z),
                attributes: Self.attributeStrings(object)
            )
        } + extras.compactMap { extra in
            // Detector finds have no RoomPlan attributes (#110: send []).
            UUID(uuidString: extra.id).map {
                DetectedObject(id: $0, category: extra.category, widthM: Double(extra.dimensions.x),
                               heightM: Double(extra.dimensions.y), depthM: Double(extra.dimensions.z))
            }
        }
        objects = Self.sanitized(objects)
        phase = .reviewing
        analyzeColors()
        if let photographer, let geometry = self.geometry { takeAutoPhotos(of: geometry.objects, with: photographer) }
    }

    private func takeAutoPhotos(of objects: [RoomGeometry.Object], with photographer: AutoPhotographer) {
        autoPhotosPending = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let started = Date()
            let jpegs = photographer.photos(for: objects)
            let room = photographer.roomPhotos()
            print("[auto-photos] \(jpegs.count) of \(objects.count) objects + \(room.count) room photos in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            await self?.applyAutoPhotos(jpegs)
            await self?.saveRoomPhotos(room)
        }
    }

    private func applyAutoPhotos(_ jpegs: [String: Data]) {
        autoPhotosPending = false
        for object in objects {
            // Never replace a photo the user took meanwhile.
            guard photos[object.id] == nil, let jpeg = jpegs[object.id.uuidString] else { continue }
            setPhoto(jpeg, for: object)
            autoPhotos.insert(object.id)
        }
    }

    private func saveRoomPhotos(_ jpegs: [Data]) {
        let dir = folder.appending(path: "room-photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        roomPhotos = jpegs.enumerated().compactMap { i, jpeg in
            let url = dir.appending(path: "\(i).jpg")
            return (try? jpeg.write(to: url)) != nil ? url : nil
        }
    }

    /// Samples real colors from the kept frames off the main actor. The raw geometry is in
    /// the same ARSession world space as the frames (don't use a `centered()` copy here).
    private func analyzeColors() {
        guard let geometry, !frameRecorder.frames.isEmpty else { return }
        let frames = frameRecorder.frames, folder = folder
        Task { [weak self] in
            let colors = await ScanColorAnalysis.run(geometry: geometry, frames: frames, saveTo: folder)
            try? JSONEncoder().encode(colors).write(to: folder.appending(path: "colors.json"))
            guard let self else { return }
            self.colors = colors
            // Finished after the items were imported: save them now.
            if self.phase == .finished { await self.persistColors() }
        }
    }

    /// Writes the sampled per-object colors onto the imported items (`set_item_colors`), so the
    /// new home, summary and thumbnails show the real colors too. Once per scan; a sampling
    /// failure (no colors) or a failed write just leaves the keyword palette.
    private func persistColors() async {
        guard !colorsSaved, let store, let colors, !colors.objectColors.isEmpty else { return }
        colorsSaved = true
        await store.saveScanColors(colors, roomName: roomName)
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
        autoPhotos.remove(object.id)
    }

    func setPhoto(_ jpeg: Data, for object: DetectedObject) {
        let url = folder.appending(path: "photos/\(object.id.uuidString).jpg")
        do {
            try jpeg.write(to: url)
            photos[object.id] = url
            autoPhotos.remove(object.id)  // a user photo replaces an auto one; applyAutoPhotos re-marks its own
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
                uploadProblem = (error as? UploadFailure)?.message ?? error.localizedDescription
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
        for (id, file) in photos {
            if let url = await send(file, "image/jpeg") { photoUrls[id] = url } else { pendingPhotos[id] = file }
        }

        let imported = await store.importScan(ScanImport(
            roomName: roomName,
            usdzUrl: usdzUrl,
            capturedRoomJsonUrl: jsonUrl,
            objects: Self.sanitized(objects).map {
                ScanObject(scanObjectId: $0.id.uuidString, category: $0.category,
                           widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM,
                           photoUrl: photoUrls[$0.id], attributes: $0.attributes)
            }
        ))
        phase = imported ? .finished : .failed(store.lastError ?? "Couldn't save the scan")
        if imported {
            self.store = store
            await persistColors()
            await sendRoomPhotos(to: store, uploader: uploader)
            if !pendingPhotos.isEmpty, !(uploader is LocalUploader) {
                Task { await self.drainPendingPhotos(to: store, uploader: uploader) }
            }
        }
    }
}

// MARK: - Size sanity (#182)

extension ScanSession {
    /// `ObjectSanity` on every scanned box: drops impossible ones, renames ones that are
    /// the wrong size for their label to "other" (vision then names them from the photo).
    /// Items added by photo have no size and pass through. Idempotent.
    nonisolated static func sanitized(_ objects: [DetectedObject]) -> [DetectedObject] {
        objects.compactMap { object in
            guard !object.manual else { return object }
            switch ObjectSanity.check(category: object.category, width: object.widthM, height: object.heightM, depth: object.depthM) {
            case .ok:
                return object
            case let .relabel(category, reason):
                print("[sanity] \(object.category) → \(category): \(reason)")
                var renamed = object
                renamed.category = category
                return renamed
            case let .drop(reason):
                print("[sanity] dropped \(object.category): \(reason)")
                return nil
            }
        }
    }
}

// MARK: - Queued photo uploads (#222)

extension ScanSession {
    /// Keeps trying photos that didn't upload during `submit` (server down, rate limited,
    /// tunnel restarting) for up to 15 minutes, then attaches each to its imported item.
    /// Each attempt already backs off (`UploadRetry`); this outer loop rides out longer outages.
    fileprivate func drainPendingPhotos(to store: MooveStore, uploader: Uploader) async {
        let deadline = Date.now.addingTimeInterval(15 * 60)
        while !pendingPhotos.isEmpty, Date.now < deadline, !Task.isCancelled {
            guard let room = store.newestRoom(named: roomName) else { break }
            for (id, file) in pendingPhotos {
                guard let url = try? await uploader.upload(file, contentType: "image/jpeg") else { break }
                if let item = store.items.first(where: { $0.roomId == room.id && $0.scanObjectId == id.uuidString }),
                   await store.addItemPhoto(itemId: item.id, url: url) {
                    pendingPhotos[id] = nil
                }
            }
            if pendingPhotos.isEmpty { uploadProblem = nil; break }
            try? await Task.sleep(for: .seconds(20))
        }
        if !pendingPhotos.isEmpty { print("[uploads] \(pendingPhotos.count) photos still waiting after the retry window") }
    }
}

// MARK: - Room photo sweep (#92)

extension ScanSession {
    /// Attaches the wide room photos to the scan just imported (`add_scan_photo`); the
    /// worker then names "other" items and adds ones RoomPlan missed. Skipped offline
    /// (no sweep agent) and when uploads failed: the worker can't fetch a device URL.
    /// Runs after `.finished` shows, so it doesn't touch `phase`.
    fileprivate func sendRoomPhotos(to store: MooveStore, uploader: Uploader) async {
        guard !roomPhotos.isEmpty, store.uploadBaseURL != nil, uploadProblem == nil,
              let scan = await store.newestScan(inRoomNamed: roomName) else { return }
        var sent = 0
        for file in roomPhotos {
            guard let url = try? await uploader.upload(file, contentType: "image/jpeg") else { break }
            if await store.addScanPhoto(scanId: scan.id, url: url) { sent += 1 }
        }
        print("[sweep] sent \(sent) of \(roomPhotos.count) room photos for scan \(scan.id)")
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
