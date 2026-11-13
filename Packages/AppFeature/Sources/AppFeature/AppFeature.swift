import AppStorageKeys
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import NetworkClient
import ShareUploads
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
        /// An account the add account sheet just signed in, adopted once the sheet has fully
        /// dismissed (`addAccountSheetDismissed`).
        public var pendingAddedAccount: AddedAccount?
        /// The folder of a tapped upload notification, waiting for its account's tabs to be up.
        public var pendingUploadFolder: PendingUploadFolder?
        /// `true` only when the current authenticated session was reached by the user tapping
        /// the login button this launch: drives `AppView`'s zoom-from-the-button presentation.
        /// A restored/optimistic session (cold launch) leaves this `false` so the app just
        /// cross-fades in behind the splash instead.
        public var didAuthenticateFromLogin = false
        /// Tripped by `apiResult` (FolderPickerFeature) the moment any authenticated request
        /// answers 401. Watched by `AppView`, which sends `sessionExpiryDetected`.
        @Shared(.inMemory(SessionExpiry.sharedKey)) public var sessionDidExpire = false
        /// Cleared on every sign out so a staged copy/move never carries across into a
        /// different account's session.
        @Shared(.inMemory(FileClipboard.sharedKey)) public var fileClipboard: FileClipboard?
        @Shared(.inMemory(FileUndoEntry.sharedKey)) public var fileUndoStack: [FileUndoEntry] = []
        @Shared(.inMemory(SharedFileInbox.sharedKey)) public var sharedFileInbox: [URL] = []
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

        var currentServerURL: URL? {
            guard case let .authenticated(authenticated) = destination else { return nil }
            return authenticated.serverURL
        }
    }

    public enum Action {
        case onAppear
        case sessionRestoreResponse(SessionCredentials?)
        case sessionValidationResponse(Result<User, AuthClientError>, SessionCredentials)
        case sessionExpiryDetected
        /// The server confirmed the session of this account is rejected, so it is torn down unless
        /// the active account changed in the meantime.
        case sessionExpiryConfirmed(accountID: String)
        case activeAccountTornDown(SessionCredentials?)
        case activateAccount(SessionCredentials)
        case accountsRefreshed([AccountSummary])
        case addAccount(PresentationAction<LoginFormFeature.Action>)
        case addAccountSheetDismissed
        /// Files opened in the app from another app's share sheet.
        case incomingFiles([URL])
        /// The user tapped an "upload finished" notification: open the folder the files went to.
        case uploadNotificationTapped(UploadNotificationTaps.Tap)
        case destination(Destination.Action)
    }

    public struct AddedAccount: Equatable {
        public let user: User
        public let serverURL: URL
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.directoryCacheStore) var directoryCacheStore
    @Dependency(\.jsonCacheStore) var jsonCacheStore
    @Dependency(\.previewCacheStore) var previewCacheStore
    @Dependency(\.thumbnailCache) var thumbnailCache
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.textEditorETagStore) var textEditorETagStore
    @Dependency(\.localThumbnailStore) var localThumbnailStore
    @Dependency(\.pendingAccountWipes) var pendingAccountWipes
    @Dependency(\.sessionScratchStore) var sessionScratchStore
    @Dependency(\.clientCertificateClient) var clientCertificateClient
    @Dependency(\.uploadDefaults) var uploadDefaults
    @Dependency(\.shareUploads) var shareUploads

    public init() {}

    private var accountCacheWipe: AccountCacheWipe {
        .fromDependencies
    }

    /// The second pass of an account wipe, run once the account's screens are gone.
    private var finishAccountWipes: Effect<Action> {
        let accountCacheWipe = accountCacheWipe
        let authClient = authClient
        return .run { _ in await accountCacheWipe.finishPending(authClient: authClient) }
    }

    /// Stops the offline sync and download of the account the app is leaving, so it neither keeps
    /// running behind the next account nor shows its progress there.
    private func stopOfflineWork(leaving accountID: String?) -> Effect<Action> {
        guard let accountID else { return .none }
        return .send(.destination(.authenticated(.mainTab(.offline(.accountDeactivated(scope: accountID))))))
    }

    /// Drops the active account whose session the server rejected and wipes its caches. It is
    /// listed as pending before its session goes, so a kill in between cannot orphan its files.
    private func tearDownExpired(accountID: String) -> Effect<Action> {
        let authClient = authClient
        let accountCacheWipe = accountCacheWipe
        return .run { send in
            accountCacheWipe.markPending(accountID)
            let next = await authClient.clearActiveSession()
            accountCacheWipe.wipe(accountID)
            await send(.activeAccountTornDown(next))
        }
    }

    private static func isSessionRejection(_ error: AuthClientError) -> Bool {
        switch error {
        case .sessionExpired, .sessionCookieMissing, .invalidCredentials,
             .server(statusCode: Constants.unauthorizedStatusCode):
            true
        default:
            false
        }
    }

    private enum Constants {
        static let unauthorizedStatusCode = 401
    }

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
                pendingAccountWipes.remove(credentials.accountID)

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
                    finishAccountWipes,
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
                // An answer for an account that is no longer the active one must not touch the one
                // that is.
                guard credentials.accountID == state.currentAccountID else { return .none }
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

            case let .sessionValidationResponse(.failure(error), credentials):
                // Only a real auth rejection tears down the optimistic session; a network
                // hiccup or a non-auth server error leaves it in place for the next request
                // to sort out.
                guard credentials.accountID == state.currentAccountID, Self.isSessionRejection(error) else {
                    return .none
                }
                // The active account is invalid: drop it and fall through to whatever account
                // remains (or the login screen when it was the last one).
                return tearDownExpired(accountID: credentials.accountID)

            case .sessionExpiryDetected:
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                guard let accountID = state.currentAccountID,
                      let serverURL = state.currentServerURL else { return .none }
                // Any request that answers 401 raises this flag, including late ones from an account
                // that was already left, so the server is asked about the current account first.
                let authClient = authClient
                return .run { send in
                    do {
                        _ = try await authClient.me(serverURL)
                    } catch let error as AuthClientError where Self.isSessionRejection(error) {
                        await send(.sessionExpiryConfirmed(accountID: accountID))
                    } catch {}
                }

            case let .sessionExpiryConfirmed(accountID):
                guard accountID == state.currentAccountID else { return .none }
                return tearDownExpired(accountID: accountID)

            case let .activeAccountTornDown(next):
                state.$fileClipboard.withLock { $0 = nil }
                state.$fileUndoStack.withLock { $0 = [] }
                if let next {
                    // Another account is still signed in: switch to it rather than dropping the
                    // user out to the login screen.
                    return .send(.activateAccount(next))
                }
                // Last account gone: full teardown to the login screen.
                // The session ran out; nobody chose to leave, so the client certificate the user
                // installed stays and the login screen can still reach the server.
                return teardownToLogin(&state, removesClientCertificates: false)

            case let .activateAccount(credentials):
                let leavingAccountID = state.currentAccountID
                state.$fileClipboard.withLock { $0 = nil }
                state.$fileUndoStack.withLock { $0 = [] }
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                CacheAccountScope.set(credentials.accountID)
                pendingAccountWipes.remove(credentials.accountID)
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
                    stopOfflineWork(leaving: leavingAccountID),
                    refreshAccounts,
                    finishAccountWipes,
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
                let accountID = AuthenticatedFeature.State.accountID(serverURL: serverURL, username: user.username)
                CacheAccountScope.set(accountID)
                pendingAccountWipes.remove(accountID)
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: serverURL, userID: user.id)
                }
                // A fresh sign in on the login screen means no account is currently active, so
                // clear every cache: on a shared device this must not expose a previous account's
                // cached listings for the same server before its own namespace takes over.
                directoryCacheStore.clearAll()
                jsonCacheStore.clearAll()
                thumbnailCache.clearMemory()
                textEditorETagStore.clearAll()
                localThumbnailStore.clearAll()
                state.didAuthenticateFromLogin = true
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: serverURL, user: user)
                )
                let previewCacheStore = previewCacheStore
                let offlineFileStore = offlineFileStore
                let sessionScratchStore = sessionScratchStore
                return .merge(
                    refreshAccounts,
                    .run { _ in
                        try? previewCacheStore.clear()
                        offlineFileStore.removeAll()
                        sessionScratchStore.purge(.keepingActiveTransfers)
                    },
                    // A session that ran out kept its certificate for the login screen; once
                    // someone signs in, only the servers with an account keep theirs.
                    pruneClientCertificates(keeping: serverURL)
                )

            case .destination(.authenticated(.delegate(.addAccountRequested))):
                state.addAccount = LoginFormFeature.State()
                return .none

            case let .destination(.authenticated(.delegate(.activeAccountChanged(credentials)))):
                guard let credentials else {
                    // The last account was signed out.
                    return teardownToLogin(&state, removesClientCertificates: true)
                }
                // Removing a non-active account leaves the active one unchanged: just refresh the
                // switcher list, keep the UI where it is.
                // While Add Account is open its certificate has no stored session yet, so pruning
                // waits for the sheet (`addAccountSheetDismissed`).
                let prune = state.addAccount == nil ? pruneClientCertificates() : .none
                if credentials.accountID == state.currentAccountID {
                    return .merge(refreshAccounts, prune, finishAccountWipes)
                }
                // Switched accounts (or signed the active one out and fell through to the next):
                // mount the new account without clearing caches, so both accounts' caches survive.
                return .merge(.send(.activateAccount(credentials)), prune)

            case .uploadNotificationTapped:
                // UploadFolderRouting opens the folder.
                return .none

            case .destination:
                return .none

            case let .addAccount(.presented(.delegate(.authenticated(user, serverURL)))):
                // Remounting the app while the sheet was still dismissing left the sheet's
                // presentation container over the new tree, swallowing every tap. Dismiss first,
                // adopt from `addAccountSheetDismissed`.
                state.pendingAddedAccount = AddedAccount(user: user, serverURL: serverURL)
                state.addAccount = nil
                return .none

            case let .incomingFiles(urls):
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return .none }
                state.$sharedFileInbox.withLock { $0.append(contentsOf: files) }
                // Signed in: hand them over now. Otherwise the tab shell drains the inbox on mount.
                guard case .authenticated = state.destination else { return .none }
                return .send(.destination(.authenticated(.mainTab(.sharedFilesArrived))))

            case .addAccountSheetDismissed:
                // Login already persisted and activated the new account; adopt it without a cache
                // wipe so the accounts already signed in keep their caches. The real user is in
                // hand, so no `me` round trip is needed.
                guard let added = state.pendingAddedAccount else { return .none }
                state.pendingAddedAccount = nil
                let user = added.user
                let serverURL = added.serverURL
                state.$fileClipboard.withLock { $0 = nil }
                state.$fileUndoStack.withLock { $0 = [] }
                let accountID = AuthenticatedFeature.State.accountID(serverURL: serverURL, username: user.username)
                let leavingAccountID = state.currentAccountID
                CacheAccountScope.set(accountID)
                pendingAccountWipes.remove(accountID)
                state.$downloadScope.withLock {
                    $0 = DownloadAccountScope.identifier(serverURL: serverURL, userID: user.id)
                }
                state.didAuthenticateFromLogin = false
                withAnimation {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: serverURL, user: user)
                    )
                }
                return .merge(
                    stopOfflineWork(leaving: leavingAccountID),
                    refreshAccounts,
                    finishAccountWipes,
                    pruneClientCertificates(keeping: serverURL)
                )

            case .addAccount:
                return .none
            }
        }
        .ifLet(\.$addAccount, action: \.addAccount) {
            LoginFormFeature()
        }

        UploadFolderRouting()
    }

    /// Removes the client certificates of servers no remaining account is signed in to, so an
    /// account that leaves the device takes its mTLS identity with it.
    /// `serverURL` is the server just signed in to, kept even before its session shows up in
    /// the stored list.
    private func pruneClientCertificates(keeping serverURL: URL? = nil) -> Effect<Action> {
        let authClient = authClient
        let clientCertificateClient = clientCertificateClient
        let uploadDefaults = uploadDefaults
        let shareUploads = shareUploads
        return .run { _ in
            // An unreadable keychain is not "nobody is signed in": prune nothing then.
            guard let sessions = try? await authClient.listSessionsOrThrow() else { return }
            var keep = Set(sessions.compactMap { ClientCertificateOrigin(url: $0.serverBaseURL) })
            if let serverURL, let origin = ClientCertificateOrigin(url: serverURL) {
                keep.insert(origin)
            }
            await clientCertificateClient.removeAll(keep)
            // A signed out account's default upload folder and pending share uploads go with it.
            let signedIn = Set(sessions.map(\.accountID))
            uploadDefaults.retain(signedIn)
            shareUploads.cancel(signedIn)
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
    private func teardownToLogin(_ state: inout State, removesClientCertificates: Bool) -> Effect<Action> {
        state.$fileClipboard.withLock { $0 = nil }
        state.$fileUndoStack.withLock { $0 = [] }
        state.$downloadScope.withLock { $0 = "" }
        CacheAccountScope.set("")
        state.didAuthenticateFromLogin = false
        state.addAccount = nil
        state.pendingAddedAccount = nil
        withAnimation {
            state.destination = .unauthenticated(.init())
        }
        let authClient = authClient
        let directoryCacheStore = directoryCacheStore
        let jsonCacheStore = jsonCacheStore
        let previewCacheStore = previewCacheStore
        let thumbnailCache = thumbnailCache
        let offlineFileStore = offlineFileStore
        let sessionScratchStore = sessionScratchStore
        let textEditorETagStore = textEditorETagStore
        let localThumbnailStore = localThumbnailStore
        let pendingAccountWipes = pendingAccountWipes
        let clientCertificateClient = clientCertificateClient
        let uploadDefaults = uploadDefaults
        let shareUploads = shareUploads
        AppStorageKeys.resetSessionPreferences()
        return .merge(
            refreshAccounts,
            .run { _ in
                await authClient.clearAllSessions()
                directoryCacheStore.clearAll()
                jsonCacheStore.clearAll()
                try? previewCacheStore.clear()
                thumbnailCache.clearMemory()
                textEditorETagStore.clearAll()
                localThumbnailStore.clearAll()
                offlineFileStore.removeAll()
                sessionScratchStore.purge(.everything)
                for accountID in pendingAccountWipes.accounts() {
                    pendingAccountWipes.remove(accountID)
                }
                if removesClientCertificates {
                    await clientCertificateClient.removeAll([])
                    uploadDefaults.retain([])
                    shareUploads.cancel([])
                }
            }
        )
    }
}

extension AppFeature.Destination.State: Equatable {}
