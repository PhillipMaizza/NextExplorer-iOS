import AppFeature
import AppStorageKeys
import ComposableArchitecture
import DesignSystem
import FilesFeature
import Localization
import SwiftUI
#if os(iOS)
    import UIKit
#endif

#if os(iOS)
    /// Every screen but the image/video viewers is portrait-only — `OrientationLock` is the only
    /// way to plumb that per-screen override through, since `UIApplicationDelegate` (not the
    /// SwiftUI `App`/`WindowGroup`) is what UIKit actually consults on every rotation attempt.
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
            OrientationLock.shared.mask
        }
    }
#endif

@main
struct NextExplorerApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    /// Mirrors the same keys `SettingsView`'s Dark Mode toggle writes. Until the user
    /// overrides it, no override is applied here and the app just follows the system.
    @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
    @AppStorage(AppStorageKeys.prefersDarkMode) private var prefersDarkModeOverride = false

    init() {
        #if DEBUG
            // Swap in the fully mocked, backend free dependency graph when launched by XCUITest.
            // A no op in every normal launch. Runs before the root store is first built in `body`.
            AppFeature.prepareUITestDependencies()
        #endif
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
                .preferredColorScheme(AppearanceMode(hasOverride: hasAppearanceOverride, prefersDark: prefersDarkModeOverride).colorScheme)
            #if os(macOS)
                // A Mac window always gets the regular width sidebar layout, never the phone tab bar.
                .environment(\.horizontalSizeClass, .regular)
                .frame(minWidth: MacWindow.minWidth, minHeight: MacWindow.minHeight)
            #endif
            #if DEBUG
            .onAppear {
                // Under XCUITest, collapse animation durations once the window is attached.
                DispatchQueue.main.async { UITestSupport.applyAnimationSpeedIfNeeded() }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: MacWindow.defaultWidth, height: MacWindow.defaultHeight)
        .commands { NextExplorerCommands(store: Self.store) }
        #endif
        #if os(macOS)
            WindowGroup(id: FolderWindowRoute.windowID, for: FolderWindowRoute.self) { $route in
                if let route {
                    MacFolderWindow(route: route, mainStore: Self.store)
                        .tint(Color.accent)
                        .preferredColorScheme(AppearanceMode(hasOverride: hasAppearanceOverride, prefersDark: prefersDarkModeOverride).colorScheme)
                }
            }
            .defaultSize(width: MacWindow.folderWindowWidth, height: MacWindow.folderWindowHeight)
            // Never reopened at launch: a restored window would come back empty (or under
            // another account) instead of from the live session.
            .restorationBehavior(.disabled)
        #endif
    }
}

#if os(macOS)
    private enum MacWindow {
        static let minWidth: CGFloat = 760
        static let minHeight: CGFloat = 520
        static let defaultWidth: CGFloat = 1180
        static let defaultHeight: CGFloat = 780
        static let folderWindowWidth: CGFloat = 960
        static let folderWindowHeight: CGFloat = 640
    }
#endif
