import AppFeature
import ComposableArchitecture
import DesignSystem
import SwiftUI

@main
struct NetxExplorerApp: App {
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    /// Mirrors the same keys `SettingsView`'s Dark Mode toggle writes. Until the user
    /// overrides it, no override is applied here and the app just follows the system.
    @AppStorage("hasSetAppearanceOverride") private var hasAppearanceOverride = false
    @AppStorage("prefersDarkMode") private var prefersDarkModeOverride = false

    init() {
        DesignSystemFonts.registerAll()
        DesignSystemFonts.applyGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
                .tint(Color.accent)
                .preferredColorScheme(hasAppearanceOverride ? (prefersDarkModeOverride ? .dark : .light) : nil)
        }
    }
}
