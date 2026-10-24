import Foundation
import MooveKit

/// Looks up where each kept piece stood in its scanned old room, for the new-home fly-in:
/// loads each old room's geometry (`RoomGeometryLoader`; the built-in demo bedroom for demo
/// items), turns it into the dollhouse plan + placements (`RoomGeometry.dollhouse`), and lays
/// those rooms out beside the new house (`FlyInStarts`). Items with no scanned spot are left
/// out, and the fly-in piles them as before.
@MainActor
enum OldRoomStarts {
    /// A geometry that takes longer than this (a slow upload server) is skipped: pile instead.
    nonisolated static let timeout: Duration = .seconds(3)

    /// nil when no item has a scanned spot (no geometry loaded, items added by photo).
    static func load(_ items: [Item], snapshot: SyncSnapshot, beside: PlanBounds) async -> FlyInStarts? {
        let scanned = items.filter { $0.scanObjectId != nil }
        guard !scanned.isEmpty else { return nil }
        var rooms: [FlyInStarts.OldRoom] = []
        for (roomId, group) in Dictionary(grouping: scanned, by: \.roomId).sorted(by: { $0.key < $1.key }) {
            let room = snapshot.rooms.first { $0.id == roomId }
            guard let geometry = await geometry(for: room, items: group, snapshot: snapshot) else { continue }
            let name = room?.name ?? "Old room"
            let dollhouse = geometry.dollhouse(roomName: name, items: group)
            rooms.append(FlyInStarts.OldRoom(plan: dollhouse.plan, placements: dollhouse.placements))
        }
        let starts = FlyInStarts.layout(oldRooms: rooms, beside: beside)
        return starts.placements.isEmpty ? nil : starts
    }

    private static func geometry(for room: Room?, items: [Item], snapshot: SyncSnapshot) async -> RoomGeometry? {
        // Demo bedroom items ("Load demo scan", or the New Home's demo keeps, which aren't in the
        // store at all): the built-in demo geometry, no loading.
        if items.allSatisfy(DemoFixtures.isDemoItem) { return DemoFixtures.roomGeometry() }
        guard let room else { return nil }
        // Cancelling the load after `timeout` stops a slow download (URLSession honors cancellation).
        let load = Task { @MainActor in try? await RoomGeometryLoader.load(room: room, snapshot: snapshot) }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            load.cancel()
        }
        let geometry = await load.value ?? nil
        timer.cancel()
        return geometry
    }
}
