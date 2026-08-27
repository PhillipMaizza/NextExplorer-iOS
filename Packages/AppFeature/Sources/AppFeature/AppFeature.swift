import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesFeature
import Foundation
import SwiftUI

@Reducer
public struct AppFeature {
    @Reducer
    public enum Destination {
        case loading
        case unauthenticated(LoginFormFeature)
        case authenticated(AuthenticatedFeature)
    }

    @ObservableState
    public struct State: Equatable {
        public var destination: Destination.State
        /// Tripped by `apiResult` (in FilesFeature) the moment any authenticated request
        /// answers 401. Watched by `AppView`, which sends `sessionExpiryDetected`.
        @Shared(.inMemory(SessionExpiry.sharedKey)) public var sessionDidExpire = false

        public init(destination: Destination.State = .loading) {
            self.destination = destination
        }
    }

    public enum Action {
        case onAppear
        case sessionRestoreResponse(SessionCredentials?)
        case sessionValidationResponse(Result<User, AuthClientError>, SessionCredentials)
        case sessionExpiryDetected
        case destination(Destination.Action)
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.destination, action: \.destination) {
            Destination.body
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
                    withAnimation {
                        state.destination = .unauthenticated(.init())
                    }
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
                if state.sessionDidExpire { state.$sessionDidExpire.withLock { $0 = false } }
                withAnimation {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: credentials.serverBaseURL, user: user)
                    )
                }
                return .none

            case .sessionValidationResponse(.failure, _):
                withAnimation {
                    state.destination = .unauthenticated(.init())
                }
                let authClient = self.authClient
                return .run { _ in
                    await authClient.clearSession()
                }

            case .sessionExpiryDetected:
                if state.sessionDidExpire { state.$sessionDidExpire.withLock { $0 = false } }
                guard case .authenticated = state.destination else { return .none }
                withAnimation {
                    state.destination = .unauthenticated(.init())
                }
                let authClient = self.authClient
                return .run { _ in await authClient.clearSession() }

            case let .destination(.unauthenticated(.delegate(.authenticated(user, serverURL)))):
                if state.sessionDidExpire { state.$sessionDidExpire.withLock { $0 = false } }
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: serverURL, user: user)
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
