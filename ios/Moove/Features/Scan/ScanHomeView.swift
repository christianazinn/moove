import SwiftUI
import MooveKit

/// Scan entry point. RoomPlan capture lands with #3/#4.
struct ScanHomeView: View {
    var body: some View {
        ContentUnavailableView("Scan a room", systemImage: "camera.viewfinder",
                               description: Text("RoomPlan capture is coming in #3 / #4."))
            .navigationTitle("Scan")
    }
}
