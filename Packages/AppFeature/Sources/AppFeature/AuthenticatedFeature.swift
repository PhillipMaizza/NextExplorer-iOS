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
            mainTab = MainTabFeature.State(serverURL: serverURL, user: user)
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
                let authClient = authClient
                // Cache teardown (directory, JSON, preview, in-memory thumbnails) is done once,
                // authoritatively, by `AppFeature`'s `.loggedOut` handler after the delegate
                // below fires. Keeping it there avoids two features clearing the same caches and
                // a future edit dropping one path silently.
                return .run { send in
                    try? await authClient.logout(serverURL)
                    await authClient.clearSession()
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
