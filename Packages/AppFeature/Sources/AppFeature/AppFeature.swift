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
        /// Login sheet for adding another server while already signed in (multi-server).
        @Presents public var addAccount: LoginFormFeature.State?
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
        /// Every signed-in account, for the Settings switcher. Rebuilt after any account change.
        @Shared(.inMemory(AccountSummary.sharedKey)) public var accounts: [AccountSummary] = []

        public init(destination: Destination.State = .loading) {
            self.destination = destination
        }

        public var isAuthenticated: Bool {
            if case .authenticated = destination {
                return true
            }
            return false
        }

        var currentAccountID: String? {
            guard case let .authenticated(authenticated) = destination else { return nil }
            return authenticated.accountID
        }
    }

    public enum Action {
        case onAppear
        case sessionRestoreResponse(SessionCredentials?)
        case sessionValidationResponse(Result<User, AuthClientError>, SessionCredentials)
        case sessionExpiryDetected
        case activeAccountTornDown(SessionCredentials?)
        case activateAccount(SessionCredentials)
        case accountsRefreshed([AccountSummary])
        case addAccount(PresentationAction<LoginFormFeature.Action>)
        case destination(Destination.Action)
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    @Dependency(\.previewCacheStore) var previewCacheStore
    @Dependency(\.thumbnailCache) var thumbnailCache

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.destination, action: \.destination) {
            Destination.body
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                let authClient = authClient
                return .run { send in
                    let credentials = await authClient.restoreSession()
                    await send(.sessionRestoreResponse(credentials))
                }

            case let .sessionRestoreResponse(credentials):
                guard let credentials else {
                    withAnimation {
                        state.destination = .unauthenticated(.init())
                    }
                    return refreshAccounts
                }

                // The active account's cache namespace must be live before the optimistic Browse
                // mounts, so its first cache read hits this account's entries, not the previous
                // one's.
                CacheAccountScope.set(credentials.accountID)

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

                let authClient = authClient
                return .merge(
                    refreshAccounts,
                    .run { send in
                        do {
                            let user = try await authClient.me(credentials.serverBaseURL)
                            await send(.sessionValidationResponse(.success(user), credentials))
                        } catch {
                            let authError = (error as? AuthClientError) ?? .network(String(describing: error))
                            await send(.sessionValidationResponse(.failure(authError), credentials))
                        }
                    }
                )

            case let .sessionValidationResponse(.success(user), credentials):
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: credentials.serverBaseURL, userID: user.id)
                }
                if case let .authenticated(current) = state.destination, current.user == user {
                    return refreshAccounts
                }
                withAnimation {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: credentials.serverBaseURL, user: user)
                    )
                }
                return refreshAccounts

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
                // The active account is invalid: drop it and fall through to whatever account
                // remains (or the login screen when it was the last one).
                let authClient = authClient
                return .run { send in
                    await send(.activeAccountTornDown(authClient.clearActiveSession()))
                }

            case .sessionExpiryDetected:
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                guard case .authenticated = state.destination else { return .none }
                let authClient = authClient
                return .run { send in
                    await send(.activeAccountTornDown(authClient.clearActiveSession()))
                }

            case let .activeAccountTornDown(next):
                state.$fileClipboard.withLock { $0 = nil }
                if let next {
                    // Another account is still signed in — switch to it rather than dropping the
                    // user out to the login screen.
                    return .send(.activateAccount(next))
                }
                // Last account gone: full teardown to the login screen.
                return teardownToLogin(&state)

            case let .activateAccount(credentials):
                state.$fileClipboard.withLock { $0 = nil }
                CacheAccountScope.set(credentials.accountID)
                // Finalized once `me` confirms the user id; empty in the meantime.
                state.$downloadScope.withLock { $0 = "" }
                state.didAuthenticateFromLogin = false
                withAnimation {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(
                            serverURL: credentials.serverBaseURL,
                            user: User(id: "", username: credentials.username ?? "", email: nil)
                        )
                    )
                }
                let authClient = authClient
                return .merge(
                    refreshAccounts,
                    .run { send in
                        do {
                            let user = try await authClient.me(credentials.serverBaseURL)
                            await send(.sessionValidationResponse(.success(user), credentials))
                        } catch {
                            let authError = (error as? AuthClientError) ?? .network(String(describing: error))
                            await send(.sessionValidationResponse(.failure(authError), credentials))
                        }
                    }
                )

            case let .accountsRefreshed(accounts):
                state.$accounts.withLock { $0 = accounts }
                return .none

            case let .destination(.unauthenticated(.delegate(.authenticated(user, serverURL)))):
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                let accountID = serverURL.absoluteString + "|" + user.username
                CacheAccountScope.set(accountID)
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: serverURL, userID: user.id)
                }
                // A fresh sign in on the login screen means no account is currently active, so
                // clear every cache: on a shared device this must not expose a previous account's
                // cached listings for the same server before its own namespace takes over.
                directoryCacheStore.clearAll()
                jsonCacheStore.clearAll()
                thumbnailCache.clearMemory()
                state.didAuthenticateFromLogin = true
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: serverURL, user: user)
                )
                let previewCacheStore = previewCacheStore
                return .merge(
                    refreshAccounts,
                    .run { _ in try? previewCacheStore.clear() }
                )

            case .destination(.authenticated(.delegate(.addAccountRequested))):
                state.addAccount = LoginFormFeature.State()
                return .none

            case let .destination(.authenticated(.delegate(.activeAccountChanged(credentials)))):
                guard let credentials else {
                    // The last account was signed out.
                    return teardownToLogin(&state)
                }
                // Removing a non-active account leaves the active one unchanged — just refresh the
                // switcher list, keep the UI where it is.
                if credentials.accountID == state.currentAccountID {
                    return refreshAccounts
                }
                // Switched accounts (or signed the active one out and fell through to the next):
                // mount the new account without clearing caches, so both accounts' caches survive.
                return .send(.activateAccount(credentials))

            case .destination:
                return .none

            case let .addAccount(.presented(.delegate(.authenticated(user, serverURL)))):
                // Login already persisted and activated the new account; adopt it without a cache
                // wipe so the accounts already signed in keep their caches. The real user is in
                // hand, so no `me` round trip is needed.
                state.addAccount = nil
                state.$fileClipboard.withLock { $0 = nil }
                let accountID = serverURL.absoluteString + "|" + user.username
                CacheAccountScope.set(accountID)
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: serverURL, userID: user.id)
                }
                state.didAuthenticateFromLogin = false
                withAnimation {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: serverURL, user: user)
                    )
                }
                return refreshAccounts

            case .addAccount:
                return .none
            }
        }
        .ifLet(\.$addAccount, action: \.addAccount) {
            LoginFormFeature()
        }
    }

    /// Rebuilds the published account list from the current stored sessions.
    private var refreshAccounts: Effect<Action> {
        let authClient = authClient
        return .run { send in
            let sessions = await authClient.listSessions()
            let active = await authClient.activeAccountID()
            await send(.accountsRefreshed(Self.summaries(sessions, activeID: active)))
        }
    }

    private static func summaries(_ sessions: [SessionCredentials], activeID: String?) -> [AccountSummary] {
        sessions.map {
            AccountSummary(
                id: $0.accountID,
                username: $0.username ?? "",
                serverURL: $0.serverBaseURL,
                isActive: $0.accountID == activeID
            )
        }
    }

    /// Full teardown to the login screen: no account left signed in. Clears every cache and
    /// per-session state so nothing leaks into the next sign in.
    private func teardownToLogin(_ state: inout State) -> Effect<Action> {
        state.$fileClipboard.withLock { $0 = nil }
        state.$downloadScope.withLock { $0 = "" }
        CacheAccountScope.set("")
        state.didAuthenticateFromLogin = false
        state.addAccount = nil
        withAnimation {
            state.destination = .unauthenticated(.init())
        }
        let authClient = authClient
        let directoryCacheStore = directoryCacheStore
        let jsonCacheStore = jsonCacheStore
        let previewCacheStore = previewCacheStore
        let thumbnailCache = thumbnailCache
        AppStorageKeys.resetSessionPreferences()
        return .merge(
            refreshAccounts,
            .run { _ in
                await authClient.clearAllSessions()
                directoryCacheStore.clearAll()
                jsonCacheStore.clearAll()
                try? previewCacheStore.clear()
                thumbnailCache.clearMemory()
            }
        )
    }
}

extension AppFeature.Destination.State: Equatable {}
