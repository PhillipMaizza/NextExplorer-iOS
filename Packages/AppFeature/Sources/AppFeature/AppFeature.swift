import AppStorageKeys
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesClient
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
        /// `true` only when the current authenticated session was reached by the user tapping
        /// the login button this launch — drives `AppView`'s zoom-from-the-button presentation.
        /// A restored/optimistic session (cold launch) leaves this `false` so the app just
        /// cross-fades in behind the splash instead.
        public var didAuthenticateFromLogin = false
        /// Tripped by `apiResult` (in FilesFeature) the moment any authenticated request
        /// answers 401. Watched by `AppView`, which sends `sessionExpiryDetected`.
        @Shared(.inMemory(SessionExpiry.sharedKey)) public var sessionDidExpire = false
        /// Cleared on every sign out so a staged copy/move never carries across into a
        /// different account's session.
        @Shared(.inMemory(FileClipboard.sharedKey)) public var fileClipboard: FileClipboard?
        /// The signed-in account's downloads scope (server + user id), so each account's saved
        /// files stay in their own folder. Set when a session is confirmed, cleared on sign out
        /// and expiry. Read by `BrowseFeature`/`DownloadsFeature`/`SettingsFeature`.
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""

        public init(destination: Destination.State = .loading) {
            self.destination = destination
        }

        public var isAuthenticated: Bool {
            if case .authenticated = destination { return true }
            return false
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
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    @Dependency(\.previewCacheStore) var previewCacheStore

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
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: credentials.serverBaseURL, userID: user.id)
                }
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
                state.didAuthenticateFromLogin = false
                state.$downloadScope.withLock { $0 = "" }
                withAnimation {
                    state.destination = .unauthenticated(.init())
                }
                let authClient = self.authClient
                let directoryCacheStore = self.directoryCacheStore
                let jsonCacheStore = self.jsonCacheStore
                let previewCacheStore = self.previewCacheStore
                AppStorageKeys.resetSessionPreferences()
                return .run { _ in
                    await authClient.clearSession()
                    directoryCacheStore.clearAll()
                    jsonCacheStore.clearAll()
                    try? previewCacheStore.clear()
                }

            case .sessionExpiryDetected:
                if state.sessionDidExpire { state.$sessionDidExpire.withLock { $0 = false } }
                state.$fileClipboard.withLock { $0 = nil }
                state.$downloadScope.withLock { $0 = "" }
                guard case .authenticated = state.destination else { return .none }
                state.didAuthenticateFromLogin = false
                withAnimation {
                    state.destination = .unauthenticated(.init())
                }
                let authClient = self.authClient
                let directoryCacheStore = self.directoryCacheStore
                let jsonCacheStore = self.jsonCacheStore
                let previewCacheStore = self.previewCacheStore
                AppStorageKeys.resetSessionPreferences()
                return .run { _ in
                    await authClient.clearSession()
                    directoryCacheStore.clearAll()
                    jsonCacheStore.clearAll()
                    try? previewCacheStore.clear()
                }

            case let .destination(.unauthenticated(.delegate(.authenticated(user, serverURL)))):
                if state.sessionDidExpire { state.$sessionDidExpire.withLock { $0 = false } }
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: serverURL, userID: user.id)
                }
                // A fresh sign in must never expose the previous account's cached listings for
                // the same server. Cleared synchronously before the authenticated destination
                // mounts, so the new `BrowseFeature`'s first cache read can't race it; the
                // downloaded file bytes are purged off the main thread since nothing reads them
                // until a preview opens.
                directoryCacheStore.clearAll()
                jsonCacheStore.clearAll()
                state.didAuthenticateFromLogin = true
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: serverURL, user: user)
                )
                let previewCacheStore = self.previewCacheStore
                return .run { _ in try? previewCacheStore.clear() }

            case .destination(.authenticated(.delegate(.loggedOut))):
                state.$fileClipboard.withLock { $0 = nil }
                state.$downloadScope.withLock { $0 = "" }
                state.didAuthenticateFromLogin = false
                state.destination = .unauthenticated(.init())
                // Explicit sign out purges both caches so the next user on a shared device can't
                // recover the previous session's directory listings or downloaded file bytes, and
                // resets per-device UI prefs (view modes, display toggles) so the next session
                // starts from defaults rather than inheriting this account's choices.
                let directoryCacheStore = self.directoryCacheStore
                let jsonCacheStore = self.jsonCacheStore
                let previewCacheStore = self.previewCacheStore
                AppStorageKeys.resetSessionPreferences()
                return .run { _ in
                    directoryCacheStore.clearAll()
                    jsonCacheStore.clearAll()
                    try? previewCacheStore.clear()
                }

            case .destination:
                return .none
            }
        }
    }
}

extension AppFeature.Destination.State: Equatable {}
