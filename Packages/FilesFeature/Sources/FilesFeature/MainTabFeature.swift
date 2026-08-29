import ComposableArchitecture
import CoreModels
import Foundation
import Localization

@Reducer
public struct MainTabFeature {
    public enum Tab: Equatable, Sendable {
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
        public var uploadToast: UploadToast?

        public init(serverURL: URL, user: User) {
            self.browse = BrowseTabFeature.State(serverURL: serverURL)
            self.favorites = FavoritesFeature.State(serverURL: serverURL)
            self.shared = SharedFeature.State(serverURL: serverURL)
            self.settings = SettingsFeature.State(serverURL: serverURL, user: user)
            self.uploads = UploadsFeature.State(serverURL: serverURL)
        }

        /// The folder currently on screen in the Browse tab (root or the deepest pushed
        /// subfolder).
        var currentBrowseDirectory: String {
            browse.path.last?.directoryPath ?? browse.root.directoryPath
        }
    }

    public enum Action: Sendable {
        case tabSelected(Tab)
        /// Sent when the scene becomes active again after being backgrounded — `BrowseTabFeature`
        /// re-fetches the current folder and every pushed subfolder, since `BrowseFeature.onAppear`
        /// deliberately no-ops once a folder already has items loaded.
        case appBecameActive
        case browse(BrowseTabFeature.Action)
        case favorites(FavoritesFeature.Action)
        case shared(SharedFeature.Action)
        case downloads(DownloadsFeature.Action)
        case settings(SettingsFeature.Action)
        case uploads(UploadsFeature.Action)
        case openUploadedLocation(String)
        case dismissUploadToast
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case signOutButtonTapped
        }
    }

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
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none

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
                    .send(.uploads(.appResumed))
                )

            case .browse(.delegate(.favoritesChanged)), .favorites(.delegate(.favoritesChanged)):
                return .send(.favorites(.refreshButtonTapped))

            case let .shared(.delegate(.openSharedLink(path, title))):
                state.selectedTab = .browse
                return .send(.browse(.navigateToDirectory(path: path, title: title)))

            case .browse(.delegate(.openDownloadsTapped)), .favorites(.delegate(.openDownloadsTapped)):
                state.selectedTab = .downloads
                return .send(.downloads(.refreshButtonTapped))

            case .settings(.delegate(.signOutButtonTapped)):
                return .send(.delegate(.signOutButtonTapped))

            case .settings(.delegate(.allDownloadsRemoved)):
                state.downloads.downloads = []
                return .none

            case .browse, .favorites, .shared, .downloads, .settings, .uploads, .delegate:
                return .none
            }
        }
    }
}
