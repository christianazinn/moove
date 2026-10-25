import SwiftUI
import UIKit

/// The app's light/dark setting (Settings > Appearance, decision 0050 addendum).
/// Stored in `@AppStorage(Appearance.storageKey)`; `.system` follows iOS.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    static let storageKey = "moove.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// For `.preferredColorScheme`; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Sets every window's `overrideUserInterfaceStyle`, so UIKit views (ARView, share sheets,
    /// alerts) and every sheet / full-screen cover follow an in-app choice, and going back to
    /// System really goes back (`.preferredColorScheme(nil)` alone can leave the last override).
    @MainActor static func applyToWindows(_ appearance: Appearance) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = appearance.interfaceStyle }
        }
    }
}

/// Applied once at the app's root (`MooveApp`).
struct AppearanceRoot: ViewModifier {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .onAppear { Appearance.applyToWindows(appearance) }
            .onChange(of: appearance) { _, new in Appearance.applyToWindows(new) }
    }
}

extension View {
    /// Follow the app's Appearance setting (System / Light / Dark).
    func followsAppAppearance() -> some View { modifier(AppearanceRoot()) }
}
