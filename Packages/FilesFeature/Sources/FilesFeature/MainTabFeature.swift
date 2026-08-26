import ComposableArchitecture
import CoreModels
import Foundation

@Reducer
public struct MainTabFeature {
    public enum Tab: Equatable, Sendable {
        case browse, favorites, settings
    }

    @ObservableState
    public struct State: Equatable {
        public var selectedTab: Tab = .browse
        public var browse: BrowseTabFeature.State
        public var favorites: FavoritesFeature.State
        public var settings: SettingsFeature.State

        public init(serverURL: URL, user: User) {
            self.browse = BrowseTabFeature.State(serverURL: serverURL)
            self.favorites = FavoritesFeature.State(serverURL: serverURL)
            self.settings = SettingsFeature.State(serverURL: serverURL, user: user)
        }
    }

    public enum Action: Sendable {
        case tabSelected(Tab)
        case browse(BrowseTabFeature.Action)
        case favorites(FavoritesFeature.Action)
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
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none

            case let .favorites(.delegate(.didSelectDirectory(path, title))):
                state.selectedTab = .browse
                return .send(.browse(.navigateToDirectory(path: path, title: title)))

            case .browse(.delegate(.favoritesChanged)):
                return .send(.favorites(.refreshButtonTapped))

            case .settings(.delegate(.signOutButtonTapped)):
                return .send(.delegate(.signOutButtonTapped))

            case .browse, .favorites, .settings, .delegate:
                return .none
            }
        }
    }
}
