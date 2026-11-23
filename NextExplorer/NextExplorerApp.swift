import AppFeature
import AppStorageKeys
import ComposableArchitecture
import DesignSystem
import FilesFeature
import Localization
import SwiftUI
#if os(iOS)
    import TipKit
    import UIKit
#endif

#if os(iOS)
    /// Every screen but the image/video viewers is portrait only; `OrientationLock` is the only
    /// way to plumb that per screen override through, since `UIApplicationDelegate` (not the
    /// SwiftUI `App`/`WindowGroup`) is what UIKit actually consults on every rotation attempt.
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _: UIApplication,
            supportedInterfaceOrientationsFor _: UIWindow?
        ) -> UIInterfaceOrientationMask {
            OrientationLock.shared.mask
        }

        /// Uploads started from the Share Extension finish here when the extension is long gone.
        func application(
            _: UIApplication,
            handleEventsForBackgroundURLSession identifier: String,
            completionHandler: @escaping () -> Void
        ) {
            let completion = UncheckedCompletion(completionHandler)
            if !BackgroundUploadEvents.handle(sessionIdentifier: identifier, completion: { completion.run() }) {
                completionHandler()
            }
        }
    }

    /// UIKit calls the background session completion handler on the main thread; it is not
    /// marked `Sendable`, so it travels in this box.
    private nonisolated struct UncheckedCompletion: @unchecked Sendable {
        let run: () -> Void

        init(_ run: @escaping () -> Void) {
            self.run = run
        }
    }
#endif

#if os(macOS)
    private enum MacAppDefaults {
        static let ignorePersistenceKey = "ApplePersistenceIgnoreState"
        static let tooltipDelayKey = "NSInitialToolTipDelay"
        static let tooltipDelayMilliseconds = 250
    }
#endif

@main
struct NextExplorerApp: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
        @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    /// Mirrors the same keys `SettingsView`'s Dark Mode toggle writes. Until the user
    /// overrides it, no override is applied here and the app just follows the system.
    @AppStorage(AppStorageKeys.appearanceOverrideSet) private var hasAppearanceOverride = false
    @AppStorage(AppStorageKeys.prefersDarkMode) private var isDarkAppearanceOverride = false

    private var appearanceMode: AppearanceMode {
        AppearanceMode(hasOverride: hasAppearanceOverride, isDark: isDarkAppearanceOverride)
    }

    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
            // Swap in the fully mocked, backend free dependency graph when launched by XCUITest.
            // A no op in every normal launch. Must run first: the launch migrations start a task that
            // reads dependencies, and one read before this freezes the live value for the whole run.
            AppFeature.prepareUITestDependencies()
        #endif
        LaunchMigrations.start()
        #if os(iOS)
            // The tips that teach a hidden gesture once (slide to select); never over a UI test's screens.
            if UITestEnvironment.isActive {
                Tips.hideAllTipsForTesting()
            }
            try? Tips.configure()
        #endif
        #if os(macOS)
            // No window restores (each scene opts out), and leftover saved state from a crash,
            // Force Quit or test run made AppKit restore nothing, so no window opened at all.
            UserDefaults.standard.register(defaults: [
                MacAppDefaults.ignorePersistenceKey: true,
                MacAppDefaults.tooltipDelayKey: MacAppDefaults.tooltipDelayMilliseconds,
            ])
        #endif
        // Point localization at the saved language before the first view builds, so the splash and
        // login are already in the chosen language rather than flashing the system one first.
        let saved = UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage) ?? ""
        LocalizationOverride.apply(saved.isEmpty ? nil : saved)
        DesignSystemFonts.registerAll()
        DesignSystemFonts.applyGlobalAppearance()
        BackgroundUploadEvents.installNotificationHandling()
        Task.detached { await BackgroundUploadEvents.reconnectPending() }
    }

    #if os(macOS)
        /// The About window's coffee link: the tip jar sheet belongs to the main window, so that
        /// window comes forward and presents it. Signed out, there is no session and nothing opens.
        private static func openTipJar() {
            guard case .authenticated = store.destination else { return }
            store.send(.destination(.authenticated(.mainTab(.settings(.tipJarButtonTapped)))))
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0.title != L10n.Menu.about }?
                .makeKeyAndOrderFront(nil)
        }
    #endif

    var body: some Scene {
        WindowGroup {
            AppView(store: Self.store)
                // Share uploads that ran or finished while the app was closed or in the background
                // get cleaned up and reported each time the app comes to the front.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    guard phase == .active else { return }
                    BackgroundUploadEvents.startPeriodicReconnect()
                    Task.detached { await BackgroundUploadEvents.sceneDidBecomeActive() }
                }
                .tint(Color.accent)
                .appAppearance(appearanceMode)
                .observesFoldableHinge()
            #if os(macOS)
                // A Mac window always gets the regular width sidebar layout, never the phone tab bar.
                .environment(\.horizontalSizeClass, .regular)
                .frame(minWidth: MacWindow.minWidth, minHeight: MacWindow.minHeight)
                .macFrostedWindow()
            #endif
            #if DEBUG
            .disablesAnimationsUnderUITest()
            .onAppear {
                // Under XCUITest, collapse animation durations once the window is attached.
                DispatchQueue.main.async {
                    UITestSupport.applyAnimationSpeedIfNeeded()
                    UITestSupport.applyOrientationIfNeeded()
                }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: MacWindow.defaultWidth, height: MacWindow.defaultHeight)
        // The session comes from the store, so the main window always opens fresh.
        .restorationBehavior(.disabled)
        .commands { NextExplorerCommands(store: Self.store) }
        #elseif os(iOS)
        .commands { IOSKeyboardCommands(store: Self.store) }
        #endif
        #if os(macOS)
            WindowGroup(id: FolderWindowRoute.windowID, for: FolderWindowRoute.self) { $route in
                if let route {
                    MacFolderWindow(route: route, mainStore: Self.store)
                        .macFrostedWindow()
                        .appAppearance(appearanceMode)
                }
            }
            .defaultSize(width: MacWindow.folderWindowWidth, height: MacWindow.folderWindowHeight)
            // Never reopened at launch: a restored window would come back empty (or under
            // another account) instead of from the live session.
            .restorationBehavior(.disabled)

            Window(L10n.Menu.about, id: MacAboutView.windowID) {
                MacAboutView(onTip: { Self.openTipJar() })
                    .containerBackground(Color.macCard, for: .window)
                    .followsAppLanguage()
                    .appAppearance(appearanceMode)
            }
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)

            // The native Settings window; SwiftUI adds NextExplorer > Settings… (⌘,) for it.
            Settings {
                MacSettingsWindow(mainStore: Self.store)
                    .followsAppLanguage()
                    .appAppearance(appearanceMode)
            }
        #endif
    }
}

#if os(macOS)
    private enum MacWindow {
        static let minWidth: CGFloat = 800
        static let minHeight: CGFloat = 520
        static let defaultWidth: CGFloat = 1180
        static let defaultHeight: CGFloat = 780
        static let folderWindowWidth: CGFloat = 960
        static let folderWindowHeight: CGFloat = 640
    }
#endif

private extension View {
    /// The Light, Dark or System choice from Settings. The Mac sets it app wide through AppKit:
    /// SwiftUI's `preferredColorScheme(nil)` never returns an open window to the system look,
    /// which left parts of a window stuck on the previous one.
    func appAppearance(_ mode: AppearanceMode) -> some View {
        #if os(macOS)
            onChange(of: mode, initial: true) { _, mode in
                NSApp.appearance = switch mode {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
        #else
            preferredColorScheme(mode.colorScheme)
        #endif
    }
}
