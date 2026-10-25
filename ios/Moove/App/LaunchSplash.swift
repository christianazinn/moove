import SwiftUI
import UIKit

/// A short launch moment laid over the app (never a gate in front of it, so
/// the store and backend start underneath): a tire rolls in from the left and
/// stops where the wordmark's first "o" sits, the wordmark inks in around it
/// and settles, then everything fades into the app. About 2.4 s in all.
///
/// Tap anywhere to skip. Reduce Motion gets a brief fade with no rolling.
/// Skipped entirely for UI tests, the screenshot harness and VoiceOver, and
/// hidden from accessibility.
struct LaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = !LaunchSplash.shouldSkip
    @State private var rolled = false
    @State private var showWordmark = false
    @State private var tireFaded = false

    /// Wordmark height; kept fixed (no iPad bump) so the tire lines up with the "o".
    private let markHeight: CGFloat = 64
    private var markWidth: CGFloat { markHeight * MooveWordmark.aspect }
    private var tireDiameter: CGFloat { markHeight * 0.66 }
    /// Center of the first "o" relative to the wordmark's center, from the artwork.
    private var tireTarget: CGSize { CGSize(width: (0.375 - 0.5) * markWidth, height: (0.55 - 0.5) * markHeight) }

    static var shouldSkip: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["MOOVE_UI_TEST_RESET"] != nil
            || env["MOOVE_ROOM_PREVIEW"] != nil
            || env["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-moove.skipSplash")
    }

    var body: some View {
        ZStack {
            if visible {
                GeometryReader { geo in
                    let startX = -(geo.size.width / 2 + tireDiameter)
                    let distance = tireTarget.width - startX
                    // Rolling without slipping: angle (radians) = distance / radius.
                    let spin = Angle.radians(Double(distance / (tireDiameter / 2)))
                    ZStack {
                        Theme.bg
                        if showWordmark {
                            MooveWordmark(height: markHeight, regularScale: 1)
                        }
                        if !reduceMotion {
                            LaunchTire(diameter: tireDiameter)
                                .rotationEffect(rolled ? spin : .zero)
                                .offset(x: rolled ? tireTarget.width : startX, y: tireTarget.height)
                                .opacity(tireFaded ? 0 : 1)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss(after: 0.2) }
                .transition(.opacity)
                .task { await play() }
            }
        }
        .accessibilityHidden(true)
    }

    private func play() async {
        if UIAccessibility.isVoiceOverRunning {
            visible = false
            return
        }
        if reduceMotion {
            showWordmark = true
            try? await Task.sleep(for: .milliseconds(600))
            dismiss(after: 0.3)
            return
        }
        withAnimation(.timingCurve(0.2, 0.6, 0.35, 1, duration: 0.85)) { rolled = true }
        try? await Task.sleep(for: .milliseconds(700))
        showWordmark = true
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeOut(duration: 0.4)) { tireFaded = true }
        try? await Task.sleep(for: .milliseconds(950))
        dismiss(after: 0.35)
    }

    private func dismiss(after duration: Double) {
        guard visible else { return }
        withAnimation(.easeOut(duration: duration)) { visible = false }
    }
}

/// A side-on tire: a thick ring with tread notches and a hub, so the roll reads.
private struct LaunchTire: View {
    var diameter: CGFloat

    var body: some View {
        let ring = diameter * 0.26
        ZStack {
            Circle().strokeBorder(Theme.text, lineWidth: ring)
            ForEach(0..<10, id: \.self) { i in
                Capsule()
                    .fill(Theme.bg)
                    .frame(width: max(1.5, diameter * 0.04), height: ring * 0.6)
                    .offset(y: -(diameter - ring) / 2)
                    .rotationEffect(.degrees(Double(i) * 36))
            }
            Circle().fill(Theme.text).frame(width: diameter * 0.18)
        }
        .frame(width: diameter, height: diameter)
    }
}

#Preview {
    Text("App underneath")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { LaunchSplash() }
}
