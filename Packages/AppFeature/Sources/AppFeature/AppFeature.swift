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
        /// Cleared on every sign out so a staged copy/move never carries across into a
        /// different account's session.
        @Shared(.inMemory(FileClipboard.sharedKey)) public var fileClipboard: FileClipboard?

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

                // Optimistic: trust the stored cookie and show the app straight away, with a
                // placeholder user filled in from the confirmed `me` response. The splash
                // covers this swap; a genuinely rejected session drops back to login through
                // `sessionValidationResponse(.failure)`.
                if case .authenticated = state.destination {} else {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(
                            serverURL: credentials.serverBaseURL,
                            user: User(id: "", username: credentials.username ?? "", email: nil)
                        )
                    )
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
                if case let .authenticated(current) = state.destination, current.user == user {
                    return .none
                }
                withAnimation {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: credentials.serverBaseURL, user: user)
                    )
                }
                return .none

            case let .sessionValidationResponse(.failure(error), _):
                // Only a real auth rejection tears down the optimistic session; a network
                // hiccup or a non-auth server error leaves it in place for the next request
                // to sort out.
                switch error {
                case .sessionExpired, .sessionCookieMissing, .invalidCredentials, .server(statusCode: 401):
                    break
                default:
                    return .none
                }
                withAnimation {
                    state.destination = .unauthenticated(.init())
                }
                let authClient = self.authClient
                return .run { _ in
                    await authClient.clearSession()
                }

            case .sessionExpiryDetected:
                if state.sessionDidExpire { state.$sessionDidExpire.withLock { $0 = false } }
                state.$fileClipboard.withLock { $0 = nil }
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
                state.$fileClipboard.withLock { $0 = nil }
                state.destination = .unauthenticated(.init())
                return .none

            case .destination:
                return .none
            }
        }
    }
}

extension AppFeature.Destination.State: Equatable {}
