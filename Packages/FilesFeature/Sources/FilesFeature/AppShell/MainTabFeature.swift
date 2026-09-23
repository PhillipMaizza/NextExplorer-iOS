import ComposableArchitecture
import CoreModels
import Foundation
import Localization
import NetworkClient

@Reducer
public struct MainTabFeature {
    public enum Tab: Equatable, Hashable, Sendable {
        case browse, favorites, shared, downloads, settings
    }

    /// The "Upload complete" toast shown app-wide once the queue drains. `openDestination` is
    /// the folder to jump to when the user taps "Open" — `nil` hides that button (they're
    /// already looking at it, or nothing succeeded).
    public struct UploadToast: Equatable, Sendable {
        public var message: String
        public var openDestination: String?
    }

    @ObservableState
    public struct State: Equatable {
        public var selectedTab: Tab = .browse
        public var browse: BrowseTabFeature.State
        public var favorites: FavoritesFeature.State
        public var shared: SharedFeature.State
        public var downloads = DownloadsFeature.State()
        public var settings: SettingsFeature.State
        public var uploads: UploadsFeature.State
        /// The offline download engine, a session lifetime sibling so its long running download
        /// effect survives the user leaving the Settings screen that started it.
        public var offline: OfflineDownloadsFeature.State
        /// Shared offline progress, reset when a fresh session mounts so a previous account's
        /// finished run never lingers on the new account's Settings screen.
        @Shared(.inMemory(OfflineDownloadProgress.sharedKey)) public var offlineProgress = OfflineDownloadProgress()
        public var uploadToast: UploadToast?

        public init(serverURL: URL, user: User) {
            browse = BrowseTabFeature.State(serverURL: serverURL)
            favorites = FavoritesFeature.State(serverURL: serverURL)
            shared = SharedFeature.State(serverURL: serverURL)
            settings = SettingsFeature.State(serverURL: serverURL, user: user)
            uploads = UploadsFeature.State(serverURL: serverURL)
            offline = OfflineDownloadsFeature.State(serverURL: serverURL)
        }

        /// The folder currently on screen in the Browse tab (root or the deepest pushed
        /// subfolder).
        var currentBrowseDirectory: String {
            browse.path.last?.directoryPath ?? browse.root.directoryPath
        }
    }

    public enum Action: Sendable {
        case tabSelected(Tab)
        /// Mac menu bar commands: refresh whatever the selected tab shows, and create a folder
        /// in the visible Browse folder (only while Browse is the selected tab).
        case refreshSelectedTab
        case newFolderRequested
        case enclosingFolderRequested
        /// Sent when the scene becomes active again after being backgrounded — `BrowseTabFeature`
        /// re-fetches the current folder and every pushed subfolder, since `BrowseFeature.onAppear`
        /// deliberately no-ops once a folder already has items loaded.
        case appBecameActive
        /// Long-lived subscription to reachability, started once from the view's `.task`.
        case observeConnectivity
        /// The connection came back — refresh the list tabs so their offline "saved copy"
        /// banners clear and they show live data without a manual pull.
        case connectivityRestored
        case browse(BrowseTabFeature.Action)
        case favorites(FavoritesFeature.Action)
        case shared(SharedFeature.Action)
        case downloads(DownloadsFeature.Action)
        case settings(SettingsFeature.Action)
        case uploads(UploadsFeature.Action)
        case offline(OfflineDownloadsFeature.Action)
        case openUploadedLocation(String)
        case dismissUploadToast
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case signOutButtonTapped
            /// Multi-server account switcher (Settings): activate, remove, or add another account.
            case switchAccount(String)
            case removeAccount(String)
            case addAccountRequested
        }
    }

    @Dependency(\.connectivity) var connectivity

    private enum CancelID { case connectivity }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.browse, action: \.browse) {
            BrowseTabFeature()
        }
        Scope(state: \.favorites, action: \.favorites) {
            FavoritesFeature()
        }
        Scope(state: \.shared, action: \.shared) {
            SharedFeature()
        }
        Scope(state: \.downloads, action: \.downloads) {
            DownloadsFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Scope(state: \.uploads, action: \.uploads) {
            UploadsFeature()
        }
        Scope(state: \.offline, action: \.offline) {
            OfflineDownloadsFeature()
        }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none

            case .refreshSelectedTab:
                switch state.selectedTab {
                case .browse: return .send(.browse(.refreshVisibleFolder))
                case .favorites: return .send(.favorites(.refreshButtonTapped))
                case .shared: return .send(.shared(.refreshRequested))
                case .downloads: return .send(.downloads(.refreshButtonTapped))
                case .settings: return .none
                }

            case .newFolderRequested:
                guard state.selectedTab == .browse else { return .none }
                return .send(.browse(.newFolderInVisibleFolder))

            case .enclosingFolderRequested:
                switch state.selectedTab {
                case .browse: return .send(.browse(.goToEnclosingFolder))
                case .favorites: return .send(.favorites(.goToEnclosingFolder))
                case .shared, .downloads, .settings: return .none
                }

            case let .browse(.delegate(.uploadRequested(files))),
                 let .favorites(.delegate(.uploadRequested(files))):
                return .send(.uploads(.enqueue(files)))

            case let .uploads(.delegate(.queueFinished(summary))):
                // Refetch only the folders an upload actually landed in, and only where they
                // are on screen — `refreshDirectory` does nothing for a path nothing is showing.
                var effects: [Effect<Action>] = []
                for path in summary.changedPaths {
                    effects.append(.send(.browse(.refreshDirectory(path: path))))
                    effects.append(.send(.favorites(.refreshDirectory(path: path))))
                }
                // Failures are surfaced by the persistent failed bar (with its own Retry), so
                // the toast is only the all-succeeded confirmation.
                if summary.failedCount == 0, summary.uploadedCount > 0 {
                    let message = summary.uploadedCount == 1
                        ? L10n.Uploads.complete
                        : L10n.Uploads.completeMany(summary.uploadedCount)
                    let alreadyThere = state.selectedTab == .browse
                        && summary.lastDestination == state.currentBrowseDirectory
                    state.uploadToast = UploadToast(
                        message: message,
                        openDestination: alreadyThere ? nil : summary.lastDestination
                    )
                }
                return .merge(effects)

            case let .openUploadedLocation(destination):
                state.uploadToast = nil
                state.selectedTab = .browse
                let title = destination.isEmpty
                    ? L10n.Browse.navigationTitle
                    : (destination as NSString).lastPathComponent
                return .send(.browse(.navigateToDirectory(path: destination, title: title)))

            case .dismissUploadToast:
                state.uploadToast = nil
                return .none

            case .appBecameActive:
                return .merge(
                    .send(.browse(.syncPathStack)),
                    .send(.favorites(.syncPathStack)),
                    .send(.uploads(.appResumed)),
                    // Check the pinned folders for new files each time the app comes forward.
                    .send(.offline(.autoSync(force: false)))
                )

            case .observeConnectivity:
                // Runs once when this session's shell mounts: clear any offline progress left over
                // from a previous account (unless a download is somehow already running), then check
                // the pinned folders for new files to pull down.
                state.$offlineProgress.withLock {
                    if !$0.isActive {
                        $0 = OfflineDownloadProgress()
                    }
                }
                // First value is the current state (ignored); refresh only on a real
                // offline -> online transition.
                let connectivity = connectivity
                return .merge(
                    .send(.offline(.autoSync(force: false))),
                    .run { send in
                        var wasOnline = true
                        for await online in connectivity.events() {
                            defer { wasOnline = online }
                            if online, !wasOnline {
                                await send(.connectivityRestored)
                            }
                        }
                    }
                    .cancellable(id: CancelID.connectivity, cancelInFlight: true)
                )

            case .connectivityRestored:
                // Refresh every list tab (each is cancel-in-flight, so this is cheap) so no tab
                // is left showing a stale offline copy after the connection returns. Both tabs
                // that own a browse stack refresh their root and every pushed subfolder, matching
                // `appBecameActive`; Favorites needs `syncPathStack` too or a folder pushed inside
                // the Favorites tab keeps its "saved copy" banner after the connection is back.
                return .merge(
                    .send(.browse(.syncPathStack)),
                    .send(.favorites(.refreshButtonTapped)),
                    .send(.favorites(.syncPathStack)),
                    .send(.shared(.refreshRequested)),
                    // Back online: pull any files added to pinned folders while offline.
                    .send(.offline(.autoSync(force: true)))
                )

            case .browse(.delegate(.favoritesChanged)), .favorites(.delegate(.favoritesChanged)):
                return .send(.favorites(.refreshButtonTapped))

            case .browse(.delegate(.openDownloadsTapped)), .favorites(.delegate(.openDownloadsTapped)):
                state.selectedTab = .downloads
                return .send(.downloads(.refreshButtonTapped))

            case .browse(.delegate(.goToSharedTab)), .favorites(.delegate(.goToSharedTab)):
                state.selectedTab = .shared
                return .send(.shared(.refreshRequested))

            case .settings(.delegate(.signOutButtonTapped)):
                return .send(.delegate(.signOutButtonTapped))

            case let .settings(.delegate(.switchAccount(id))):
                return .send(.delegate(.switchAccount(id)))

            case let .settings(.delegate(.removeAccount(id))):
                return .send(.delegate(.removeAccount(id)))

            case .settings(.delegate(.addAccountRequested)):
                return .send(.delegate(.addAccountRequested))

            case .settings(.delegate(.allDownloadsRemoved)):
                state.downloads.downloads = []
                return .none

            case let .settings(.delegate(.startOfflineDownload(items))):
                return .send(.offline(.startDownload(items)))

            case .settings(.delegate(.cancelOfflineDownload)):
                return .send(.offline(.cancelTapped))

            case .settings(.delegate(.resyncOffline)):
                return .send(.offline(.resyncTapped))

            case .settings(.delegate(.removeOfflineFiles)):
                return .send(.offline(.removeAllOfflineTapped))

            case .browse, .favorites, .shared, .downloads, .settings, .uploads, .offline, .delegate:
                return .none
            }
        }
    }
}
