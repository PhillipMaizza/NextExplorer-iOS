import AppStorageKeys
import AuthClient
import AuthFeature
import ComposableArchitecture
import DesignSystem
import FilesFeature
import Localization
import SwiftUI

private enum Constants {
    static let destinationCrossFadeDuration: Double = 0.35
    /// After the login button's accent circle has flooded the screen, `AppView` holds that
    /// same accent fill and fades it out, uncovering the app that cross-faded in behind it.
    static let authFillFadeDuration: Double = 0.4
}

/// Identity for the authenticated subtree: it remounts when the splash finishes (to relayout nav
/// bars) and when the active account changes (to play the switch transition).
private struct AuthenticatedIdentity: Hashable {
    let splashPresented: Bool
    let accountID: String?
}

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    /// The launch splash sits on top of `destinationContent` and removes itself once its own
    /// animation has cleared — the reducer flips `destination` the moment auth resolves, the
    /// splash just holds the frame until then.
    @State private var isSplashPresented = true
    /// Flipped the moment the splash commits to its exit, while it still covers the screen —
    /// the authenticated tree mounts then (not after the splash is gone) so its wing-opening
    /// reveal uncovers the real Browse screen with its skeleton, not a blank frame.
    @State private var splashIsExiting = false
    /// Opacity of the full-screen accent layer that takes over from `LoginFormView`'s
    /// expanding button circle, then fades to reveal the authenticated app.
    @State private var authFillOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Chosen UI language ("" = follow system). Drives `LocalizationOverride`, the SwiftUI locale,
    /// and a full rebuild of the content on change so every `L10n` string re-resolves live.
    @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    private var selectedLanguage: String? {
        appLanguage.isEmpty ? nil : appLanguage
    }

    private var appLocale: Locale {
        selectedLanguage.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    private var layoutDirection: LayoutDirection {
        if let language = selectedLanguage, LocalizationOverride.isRTL(language) {
            return .rightToLeft
        }
        return .leftToRight
    }

    /// A gentle zoom-and-fade used when the whole content is swapped out from under the user: an
    /// account switch (the authenticated tree remounts for the new account) and a language change
    /// (the tree remounts so every string re-resolves). New content scales up as the old fades,
    /// so the change reads as a deliberate reveal rather than a hard cut. Flattened to a plain
    /// fade under Reduce Motion.
    private var contentSwapTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .scale(scale: 0.94).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var contentSwapAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.45)
    }

    public var body: some View {
        ZStack {
            destinationContent

            if authFillOpacity > 0 {
                Color.accent
                    .ignoresSafeArea()
                    .opacity(authFillOpacity)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }

            if isSplashPresented {
                SplashView(
                    isReady: store.destination != .loading,
                    onExitStarted: { splashIsExiting = true }
                ) {
                    isSplashPresented = false
                }
                .transition(.identity)
                .zIndex(3)
            }
        }
        // Full Dynamic Type support (see Typography.font). Capped at accessibility3 (~235%,
        // comfortably above the 200% Apple asks for the Larger Text nutrition label) rather than
        // accessibility5,
        // whose extreme sizes shatter the app's fixed height chrome; buttons/rows grow with the
        // text up to that point.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .environment(\.locale, appLocale)
        .environment(\.layoutDirection, layoutDirection)
        .onChange(of: appLanguage, initial: true) { _, _ in
            LocalizationOverride.apply(selectedLanguage)
        }
        .onChange(of: store.didAuthenticateFromLogin) { _, fromLogin in
            guard fromLogin, !reduceMotion else {
                authFillOpacity = 0
                return
            }
            // The login button's circle has just filled the screen with accent; pick that up
            // seamlessly, then fade it out over the app.
            authFillOpacity = 1
            withAnimation(.easeOut(duration: Constants.authFillFadeDuration)) {
                authFillOpacity = 0
            }
        }
        .task {
            store.send(.onAppear)
        }
        // Finish tip transactions that resolve outside the inline purchase (Ask to Buy approvals,
        // interrupted purchases). Started once for the app's lifetime; without it StoreKit
        // redelivers the same unfinished transaction on every launch.
        .task {
            await TipTransactionObserver.run()
        }
        .onChange(of: store.sessionDidExpire) { _, didExpire in
            guard didExpire else { return }
            store.send(.sessionExpiryDetected)
        }
        .sheet(item: $store.scope(state: \.addAccount, action: \.addAccount)) { addAccountStore in
            LoginFormView(store: addAccountStore, autoFocus: true)
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        Group {
            switch store.destination {
            case .loading:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .backgroundGradient()
                    .ignoresSafeArea()

            case .unauthenticated:
                if let scopedStore = store.scope(state: \.destination.unauthenticated, action: \.destination.unauthenticated) {
                    LoginFormView(store: scopedStore, autoFocus: !isSplashPresented)
                        .transition(.opacity)
                }

            case .authenticated:
                // Mount as the splash starts to leave (still covering the screen) so the
                // wing-opening reveal uncovers the real Browse skeleton, not a blank frame.
                // But a `NavigationStack` that does its first layout under the splash has its
                // large titles sized collapsed by UIKit and never revisited (every tab stuck
                // inline until a manual tab switch). `.id(isSplashPresented)` re-establishes
                // each nav bar's layout on screen the moment the splash is gone; the TCA store
                // state survives the identity change, so the content stays put and only the
                // nav bars relayout, no reload flash.
                if !isSplashPresented || splashIsExiting,
                   let scopedStore = store.scope(state: \.destination.authenticated, action: \.destination.authenticated)
                {
                    AuthenticatedView(store: scopedStore)
                        // Keying on the active account too means switching accounts remounts the
                        // authenticated tree, so the swap cross-fades instead of updating in place.
                        // A plain quick fade (not the zoom reveal) — the switch should feel light.
                        // The TCA store state survives the identity change.
                        .id(AuthenticatedIdentity(splashPresented: isSplashPresented, accountID: store.currentAccountID))
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: Constants.destinationCrossFadeDuration), value: store.destination)
        // Remount when the language changes so every cached string and UIKit-backed title
        // (nav bars, tab bar) re-resolves through the new `LocalizationOverride` bundle. The TCA
        // store state lives outside the view tree, so navigation and data survive the swap.
        .id(appLanguage)
        .transition(contentSwapTransition)
        .animation(contentSwapAnimation, value: appLanguage)
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}
