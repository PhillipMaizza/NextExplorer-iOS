import AuthClient
import ComposableArchitecture
import Foundation

@Reducer
public struct AuthenticatedFeature {
    @ObservableState
    public struct State: Equatable {
        public var serverURL: URL
        public var username: String
        public var isSigningOut = false

        public init(serverURL: URL, username: String) {
            self.serverURL = serverURL
            self.username = username
        }
    }

    public enum Action: Sendable {
        case signOutButtonTapped
        case signOutResponse
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case loggedOut
        }
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .signOutButtonTapped:
                state.isSigningOut = true
                let serverURL = state.serverURL
                let authClient = self.authClient
                return .run { send in
                    try? await authClient.logout(serverURL)
                    await authClient.clearSession()
                    await send(.signOutResponse)
                }

            case .signOutResponse:
                state.isSigningOut = false
                return .send(.delegate(.loggedOut))

            case .delegate:
                return .none
            }
        }
    }
}
