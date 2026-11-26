#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesFeature
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 1200
        static let minHeight: CGFloat = 620
    }

    /// Content of the Mac's Settings window: the signed in session's settings, or only this Mac's
    /// own settings while the account is locked or nobody is signed in.
    public struct MacSettingsWindow: View {
        let mainStore: StoreOf<AppFeature>
        let onTip: @MainActor () -> Void
        @Environment(\.dismiss) private var dismiss

        public init(mainStore: StoreOf<AppFeature>, onTip: @escaping @MainActor () -> Void) {
            self.mainStore = mainStore
            self.onTip = onTip
        }

        public var body: some View {
            content
                .environment(\.horizontalSizeClass, .regular)
                .modifier(AddAccountSheet(store: mainStore))
                .frame(width: Metrics.width)
                .frame(minHeight: Metrics.minHeight)
        }

        @ViewBuilder
        private var content: some View {
            switch mainStore.destination {
            case .authenticated:
                if let session = mainStore.scope(
                    state: \.destination.authenticated,
                    action: \.destination.authenticated
                ) {
                    MacSettingsContent(store: session.scope(state: \.mainTab, action: \.mainTab))
                        .id(mainStore.state.currentAccountID)
                }
            case .locked:
                if let lock = mainStore.scope(state: \.destination.locked, action: \.destination.locked) {
                    MacLocalSettingsRoot(
                        lockedAccount: lock.account,
                        onShowLockScreen: { dismiss() },
                        onSignOut: {
                            lock.send(.signOutButtonTapped)
                            dismiss()
                        },
                        onTip: onTip
                    )
                }
            case .loading, .unauthenticated:
                MacLocalSettingsRoot(
                    lockedAccount: nil,
                    onShowLockScreen: {},
                    onSignOut: {},
                    onTip: onTip
                )
            }
        }
    }

    #Preview("Signed in") {
        MacSettingsWindow(mainStore: .previewSignedIn()) {}
    }

    #Preview("Locked") {
        MacSettingsWindow(mainStore: .previewLocked()) {}
    }

    #Preview("Signed out") {
        MacSettingsWindow(mainStore: Store(initialState: AppFeature.State()) { AppFeature() }) {}
    }
#endif
