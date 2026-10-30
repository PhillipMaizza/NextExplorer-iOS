#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// Everything the main Mac window adds around the app shell: its title, the Dock upload
    /// status, the account and tip jar prompts it shares with the Settings window, Go to
    /// Folder, and the transfer notifications.
    struct MacMainWindowChrome: ViewModifier {
        let store: StoreOf<MainTabFeature>

        /// The window (and tab) title: the folder on screen in Browse or a pushed Favorites
        /// folder, otherwise the section's name.
        private var windowTitle: String {
            switch store.selectedTab {
            case .browse: store.browse.path.last?.title ?? store.browse.root.title
            case .favorites: store.favorites.path.last?.title ?? L10n.Tab.favorites
            case .shared: L10n.Tab.shared
            case .downloads: L10n.Tab.downloads
            case .settings: L10n.Tab.settings
            }
        }

        private var isGoToFolderPresented: Binding<Bool> {
            Binding(get: { store.isGoToFolderPresented }, set: {
                if !$0 {
                    store.send(.goToFolderDismissed)
                }
            })
        }

        func body(content: Content) -> some View {
            content
                .modifier(MacDockUploadStatus(remaining: store.uploads.remainingCount, progress: store.uploads.overallProgress))
                .windowTitle(windowTitle)
                .modifier(AccountConfirmations(store: store.scope(state: \.settings, action: \.settings)))
                .modifier(TipJarPresentation(store: store.scope(state: \.settings, action: \.settings)))
                .sheet(isPresented: isGoToFolderPresented) {
                    MacGoToFolderSheet(
                        onGo: { store.send(.goToFolderRequested($0)) },
                        onCancel: { store.send(.goToFolderDismissed) }
                    )
                }
                .modifier(MacTransferNotifications(
                    uploadsRemaining: store.uploads.remainingCount,
                    uploadsFailed: store.uploads.failedCount,
                    downloadsRemaining: store.downloadQueue.remainingCount,
                    downloadsFailed: store.downloadQueue.failedCount
                ))
        }
    }

    #Preview {
        Text(verbatim: "Browse")
            .frame(width: 600, height: 400)
            .modifier(MacMainWindowChrome(store: Store(initialState: MainTabFeature.State(
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com")
            )) { MainTabFeature() } withDependencies: { $0.filesClient = .previewValue }))
    }
#endif
