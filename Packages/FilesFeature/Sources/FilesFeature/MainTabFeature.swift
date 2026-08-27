import ComposableArchitecture
import CoreModels
import Foundation

@Reducer
public struct MainTabFeature {
    public enum Tab: Equatable, Sendable {
        case browse, favorites, downloads, settings
    }

    @ObservableState
    public struct State: Equatable {
        public var selectedTab: Tab = .browse
        public var browse: BrowseTabFeature.State
        public var favorites: FavoritesFeature.State
        public var downloads = DownloadsFeature.State()
        public var settings: SettingsFeature.State

        public init(serverURL: URL, user: User) {
            self.browse = BrowseTabFeature.State(serverURL: serverURL)
            self.favorites = FavoritesFeature.State(serverURL: serverURL)
            self.settings = SettingsFeature.State(serverURL: serverURL, user: user)
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
        case downloads(DownloadsFeature.Action)
        case settings(SettingsFeature.Action)
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
        Scope(state: \.downloads, action: \.downloads) {
            DownloadsFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none

            case .appBecameActive:
                return .merge(
                    .send(.browse(.syncPathStack)),
                    .send(.favorites(.syncPathStack))
                )

            case .browse(.delegate(.favoritesChanged)):
                return .send(.favorites(.refreshButtonTapped))

            case .favorites(.delegate(.favoritesChanged)):
                return .send(.favorites(.refreshButtonTapped))

            case .browse(.delegate(.openDownloadsTapped)):
                state.selectedTab = .downloads
                return .send(.downloads(.refreshButtonTapped))

            case .favorites(.delegate(.openDownloadsTapped)):
                state.selectedTab = .downloads
                return .send(.downloads(.refreshButtonTapped))

            case .settings(.delegate(.signOutButtonTapped)):
                return .send(.delegate(.signOutButtonTapped))

            case .settings(.delegate(.allDownloadsRemoved)):
                state.downloads.downloads = []
                return .none

            case .browse, .favorites, .downloads, .settings, .delegate:
                return .none
            }
        }
    }
}
