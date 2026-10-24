import SwiftUI
import MooveKit

/// Keep / sell / donate / trash review. Built out in #9.
struct ReviewView: View {
    var body: some View {
        ContentUnavailableView("Review", systemImage: "checklist", description: Text("Coming in #9."))
            .navigationTitle("Review")
    }
}
