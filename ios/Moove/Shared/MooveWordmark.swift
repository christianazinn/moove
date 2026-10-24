import SwiftUI

/// The hand-drawn "moove" wordmark (tires for the o's). Vector, tinted with
/// the theme ink so it works in light and dark mode. When `animated`, it is
/// written in left to right with a soft pen edge, then settles; Reduce Motion
/// shows it straight away.
struct MooveWordmark: View {
    var height: CGFloat = 36
    var animated = true
    var color: Color = Theme.text
    /// Extra scale on regular-width layouts (iPad), where the phone size looks lost.
    var regularScale: CGFloat = 1.35

    /// Width / height of the artwork (Brand.xcassets/MooveWordmark).
    static let aspect: CGFloat = 2597 / 538

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var revealed: CGFloat = 0
    @State private var settled = false

    /// The height actually drawn: `height`, scaled up on iPad.
    private var drawnHeight: CGFloat { sizeClass == .regular ? height * regularScale : height }

    var body: some View {
        Image("MooveWordmark")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(Self.aspect, contentMode: .fit)
            .frame(height: drawnHeight)
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
        let width = drawnHeight * Self.aspect
        let feather = drawnHeight * 0.9
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
        MooveWordmark(height: 64)
        MooveWordmark(height: 34, animated: false, color: Theme.accentStrong)
    }
    .padding()
    .background(Theme.bg)
}
