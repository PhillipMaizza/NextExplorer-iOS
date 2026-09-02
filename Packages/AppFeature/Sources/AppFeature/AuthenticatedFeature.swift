import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation

@Reducer
public struct AuthenticatedFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var user: User
        public var mainTab: MainTabFeature.State

        public init(serverURL: URL, user: User) {
            self.serverURL = serverURL
            self.user = user
            self.mainTab = MainTabFeature.State(serverURL: serverURL, user: user)
        }
    }

    public enum Action: Sendable {
        case mainTab(MainTabFeature.Action)
        case signOutResponse
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case loggedOut
        }
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.mainTab, action: \.mainTab) {
            MainTabFeature()
        }
        Reduce { state, action in
            switch action {
            case .mainTab(.delegate(.signOutButtonTapped)):
                state.mainTab.settings.isSigningOut = true
                let serverURL = state.serverURL
                let authClient = self.authClient
                let directoryCacheStore = self.directoryCacheStore
                let jsonCacheStore = self.jsonCacheStore
                return .run { send in
                    try? await authClient.logout(serverURL)
                    await authClient.clearSession()
                    directoryCacheStore.clearAll()
                    jsonCacheStore.clearAll()
                    await send(.signOutResponse)
                }

            case .signOutResponse:
                state.mainTab.settings.isSigningOut = false
                return .send(.delegate(.loggedOut))

            case .mainTab, .delegate:
                return .none
            }
        }
    }
}
