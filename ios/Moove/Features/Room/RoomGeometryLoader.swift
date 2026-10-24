import Foundation
import RoomPlan
import MooveKit

/// Finds the geometry for a room: the scan's `geometry.json` / `room.json` (this device's
/// copy, or the uploaded URL), or the built-in demo bedroom for rooms imported with
/// "Load demo scan".
///
/// Order: (1) this device's own copy of the scan (`ScanSession` keeps
/// `Documents/scans/<stamp>/geometry.json`; the folder is found by the room's item
/// `scanObjectId`s, which are the geometry's object ids), (2) the uploaded file on the
/// worker's *current* upload host (a quick tunnel gets a new host on every restart, so a
/// stored `…/files/<name>` URL is moved onto `AppConfig.effectiveUploadBaseURL`), (3) the
/// URL as stored. Throws only when all of them fail; callers then show an estimated room.
@MainActor
enum RoomGeometryLoader {
    private static var cache: [String: RoomGeometry] = [:]
    /// Object ids per local scan file, built on first use and rebuilt when nothing matches.
    private static var localIndex: [(file: URL, objectIds: Set<String>)]?

    static func load(room: Room, snapshot: SyncSnapshot) async throws -> RoomGeometry? {
        let scan = snapshot.scans.filter { $0.roomId == room.id }.max { $0.createdAt < $1.createdAt }
        if let urlString = scan?.capturedRoomJsonUrl {
            if let cached = cache[urlString] { return cached }
            let objectIds = Set(snapshot.items.filter { $0.roomId == room.id }.compactMap(\.scanObjectId))
            if let local = await localGeometry(urlString: urlString, objectIds: objectIds) {
                cache[urlString] = local
                return local
            }
            var lastError: Error = URLError(.badURL)
            for url in remoteURLs(urlString) {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    let geometry = try decode(data)
                    cache[urlString] = geometry
                    return geometry
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
        let isDemo = snapshot.items.contains { $0.roomId == room.id && ($0.scanObjectId?.hasPrefix("demo-") ?? false) }
        return isDemo ? DemoFixtures.roomGeometry() : nil
    }

    /// Accepts either RoomPlan's JSON or an already-converted `RoomGeometry`.
    nonisolated static func decode(_ data: Data) throws -> RoomGeometry {
        if let room = try? JSONDecoder().decode(CapturedRoom.self, from: data) { return RoomGeometry(room) }
        return try JSONDecoder().decode(RoomGeometry.self, from: data)
    }

    // MARK: This device's copy

    private static var scansFolder: URL { URL.documentsDirectory.appending(path: "scans", directoryHint: .isDirectory) }

    private static func localGeometry(urlString: String, objectIds: Set<String>) async -> RoomGeometry? {
        // A file URL (the upload failed at scan time): that file, or the same path under this
        // install's Documents (the container path changes on reinstall).
        if let url = URL(string: urlString), url.isFileURL {
            var files = [url]
            if let range = url.path.range(of: "/Documents/") {
                files.append(URL.documentsDirectory.appending(path: String(url.path[range.upperBound...])))
            }
            for file in files {
                if let g = await read(file) { return g }
            }
        }
        guard !objectIds.isEmpty else { return nil }
        for rebuild in [false, true] {
            if rebuild || localIndex == nil { localIndex = await indexLocalScans() }
            let best = (localIndex ?? [])
                .map { ($0.file, $0.objectIds.intersection(objectIds).count) }
                .filter { $0.1 > 0 }
                .max { $0.1 < $1.1 }
            if let best, let g = await read(best.0) { return g }
        }
        return nil
    }

    private static func read(_ file: URL) async -> RoomGeometry? {
        await Task.detached { () -> RoomGeometry? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decode(data)
        }.value
    }

    private static func indexLocalScans() async -> [(file: URL, objectIds: Set<String>)] {
        let folder = scansFolder
        return await Task.detached { () -> [(file: URL, objectIds: Set<String>)] in
            let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return dirs.compactMap { dir in
                let file = dir.appending(path: "geometry.json")
                guard let data = try? Data(contentsOf: file),
                      let g = try? JSONDecoder().decode(RoomGeometry.self, from: data) else { return nil }
                return (file, Set(g.objects.map(\.id)))
            }
        }.value
    }

    // MARK: The upload server

    /// The stored URL moved onto the current upload host (when it's an upload `/files/` path on
    /// another host), then the stored URL itself.
    private static func remoteURLs(_ urlString: String) -> [URL] {
        guard let stored = URL(string: urlString), !stored.isFileURL else { return [] }
        // A scan's geometry URL is always one of our uploads, so its host counts as a past upload base.
        let host = stored.host?.lowercased()
        let hostKey = host.map { h in stored.port.map { "\(h):\($0)" } ?? h }
        let current = ListingURL.resolve(urlString, simulated: false, uploadBase: AppConfig.effectiveUploadBaseURL,
                                         previousUploadHosts: Set([host, hostKey].compactMap { $0 }))
        return [current, stored].compactMap { $0 }.reduce(into: [URL]()) { out, url in
            if !out.contains(url) { out.append(url) }
        }
    }
}
