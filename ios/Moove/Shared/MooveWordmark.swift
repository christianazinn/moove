import SwiftUI

/// The hand-drawn "moove" wordmark (tires for the o's). Vector, tinted with
/// the theme ink so it works in light and dark mode. When `animated`, it is
/// written in left to right with a soft pen edge, then settles; Reduce Motion
/// shows it straight away.
struct MooveWordmark: View {
    var height: CGFloat = 36
    var animated = true
    var color: Color = Theme.text

    /// Width / height of the artwork (Brand.xcassets/MooveWordmark).
    static let aspect: CGFloat = 2597 / 538

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: CGFloat = 0
    @State private var settled = false

    var body: some View {
        Image("MooveWordmark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(Self.aspect, contentMode: .fit)
            .frame(height: height)
            .foregroundStyle(color)
            .mask(alignment: .leading) { pen }
            .scaleEffect(settled ? 1 : 0.97, anchor: .leading)
            .accessibilityElement()
            .accessibilityLabel("moove")
            .accessibilityAddTraits(.isHeader)
            .onAppear(perform: play)
    }

    /// Solid up to the pen position, then a short fade so the edge looks inked rather than cut.
    private var pen: some View {
        let width = height * Self.aspect
        let feather = height * 0.9
        return HStack(spacing: 0) {
            Rectangle().frame(width: max(0, (width + feather) * revealed - feather))
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: feather)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }

    private func play() {
        guard animated, !reduceMotion else {
            revealed = 1
            settled = true
            return
        }
        revealed = 0
        settled = false
        withAnimation(.timingCurve(0.45, 0.05, 0.25, 1, duration: 1.15)) { revealed = 1 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.95)) { settled = true }
    }
}

#Preview {
    VStack(spacing: 32) {
        MooveWordmark(height: 48)
        MooveWordmark(height: 24, animated: false, color: Theme.accentStrong)
    }
    .padding()
    .background(Theme.bg)
}
