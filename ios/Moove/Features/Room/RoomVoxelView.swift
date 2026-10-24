import SwiftUI
import MooveKit

/// The room screen's Voxel style (#236): the same voxel dollhouse as the Scan page
/// (`ScanResultsView`), built from the scan's walls and openings with each item where it
/// stood. Items the photo sweep added get estimated spots (`EstimatedRoom.scanned`).
struct RoomVoxelView: View {
    let geometry: RoomGeometry
    let roomName: String
    /// Every item in the room, including ones without a scanned box.
    let items: [Item]

    @State private var model: EstimatedRoom?

    /// The demo bedroom has no camera frames to sample, so it uses its fixture colors
    /// (as `ScanFinishedResults` does); real scans carry measured colors on each item.
    private var colors: ScanColors? {
        items.contains(where: DemoFixtures.isDemoItem) ? DemoFixtures.scanColors() : nil
    }

    var body: some View {
        Group {
            if let model {
                FloorPlan3DView(plan: model.plan, focusRoom: nil, items: model.items, placements: model.placements,
                                wallColor: colors?.wallColor, floorColor: colors?.floorColor)
            } else {
                Theme.surface
            }
        }
        .onChange(of: Key(items: items.map { LayoutItem($0, colors: colors) }, geometry: geometry), initial: true) { _, key in
            model = EstimatedRoom.scanned(name: roomName, geometry: key.geometry, items: items, layoutItems: key.items)
        }
    }

    private struct Key: Equatable {
        var items: [LayoutItem]
        var geometry: RoomGeometry
    }
}
