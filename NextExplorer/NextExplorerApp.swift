import AppFeature
import AppStorageKeys
import ComposableArchitecture
import DesignSystem
import FilesFeature
import Localization
import SwiftUI
import UIKit

/// Every screen but the image/video viewers is portrait-only — `OrientationLock` is the only
/// way to plumb that per-screen override through, since `UIApplicationDelegate` (not the
/// SwiftUI `App`/`WindowGroup`) is what UIKit actually consults on every rotation attempt.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}

@main
struct NextExplorerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    /// Mirrors the same keys `SettingsView`'s Dark Mode toggle writes. Until the user
    /// overrides it, no override is applied here and the app just follows the system.
    @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
    @AppStorage(AppStorageKeys.prefersDarkMode) private var prefersDarkModeOverride = false

    init() {
        // Point localization at the saved language before the first view builds, so the splash and
        // login are already in the chosen language rather than flashing the system one first.
        let saved = UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage) ?? ""
        LocalizationOverride.apply(saved.isEmpty ? nil : saved)
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
