import Foundation
import RoomPlan
import MooveKit

/// Finds the geometry for a room: the scan's `room.json` (a RoomPlan
/// `CapturedRoom`, local file or uploaded URL), or the built-in demo bedroom
/// for rooms imported with "Load demo scan".
@MainActor
enum RoomGeometryLoader {
    private static var cache: [String: RoomGeometry] = [:]

    static func load(room: Room, snapshot: SyncSnapshot) async throws -> RoomGeometry? {
        let scan = snapshot.scans.filter { $0.roomId == room.id }.max { $0.createdAt < $1.createdAt }
        if let urlString = scan?.capturedRoomJsonUrl, let url = URL(string: urlString) {
            if let cached = cache[urlString] { return cached }
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                data = try await URLSession.shared.data(from: url).0
            }
            let geometry = try decode(data)
            cache[urlString] = geometry
            return geometry
        }
        let isDemo = snapshot.items.contains { $0.roomId == room.id && ($0.scanObjectId?.hasPrefix("demo-") ?? false) }
        return isDemo ? DemoFixtures.roomGeometry() : nil
    }

    /// Accepts either RoomPlan's JSON or an already-converted `RoomGeometry`.
    static func decode(_ data: Data) throws -> RoomGeometry {
        if let room = try? JSONDecoder().decode(CapturedRoom.self, from: data) { return RoomGeometry(room) }
        return try JSONDecoder().decode(RoomGeometry.self, from: data)
    }
}
