import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import Foundation

@Reducer
public struct AppFeature {
    @Reducer
    public enum Destination {
        case unauthenticated(LoginFormFeature)
        case authenticated(AuthenticatedFeature)
    }

    @ObservableState
    public struct State: Equatable {
        public var destination: Destination.State

        public init(destination: Destination.State = .unauthenticated(.init())) {
            self.destination = destination
        }
    }

    public enum Action {
        case onAppear
        case sessionRestoreResponse(SessionCredentials?)
        case sessionValidationResponse(Result<User, AuthClientError>, SessionCredentials)
        case destination(Destination.Action)
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.destination, action: \.destination) {
            EmptyReducer()
                .ifCaseLet(\.unauthenticated, action: \.unauthenticated) {
                    LoginFormFeature()
                }
                .ifCaseLet(\.authenticated, action: \.authenticated) {
                    AuthenticatedFeature()
                }
        }
        Reduce { state, action in
            switch action {
            case .onAppear:
                let authClient = self.authClient
                return .run { send in
                    let credentials = await authClient.restoreSession()
                    await send(.sessionRestoreResponse(credentials))
                }

            case let .sessionRestoreResponse(credentials):
                guard let credentials else {
                    state.destination = .unauthenticated(.init())
                    return .none
                }
                
                let authClient = self.authClient
                return .run { send in
                    do {
                        let user = try await authClient.me(credentials.serverBaseURL)
                        await send(.sessionValidationResponse(.success(user), credentials))
                    } catch {
                        let authError = (error as? AuthClientError) ?? .network(String(describing: error))
                        await send(.sessionValidationResponse(.failure(authError), credentials))
                    }
                }

            case let .sessionValidationResponse(.success(user), credentials):
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: credentials.serverBaseURL, username: user.username)
                )
                return .none

            case .sessionValidationResponse(.failure, _):
                state.destination = .unauthenticated(.init())
                let authClient = self.authClient
                return .run { _ in
                    await authClient.clearSession()
                }

            case let .destination(.unauthenticated(.delegate(.authenticated(user, serverURL)))):
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: serverURL, username: user.username)
                )
                return .none

            case .destination(.authenticated(.delegate(.loggedOut))):
                state.destination = .unauthenticated(.init())
                return .none

            case .destination:
                return .none
            }
        }
    }
}

extension AppFeature.Destination.State: Equatable {}
