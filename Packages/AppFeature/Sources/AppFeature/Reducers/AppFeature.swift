import AppStorageKeys
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import DesignSystem
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
        case locked(LockFeature)
    }

    @ObservableState
    public struct State: Equatable {
        public var destination: Destination.State
        /// Login sheet for adding another server while already signed in (multi-server).
        @Presents public var addAccount: LoginFormFeature.State?
        @Presents public var tipJar: TipJarFeature.State?
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
        @Shared(.inMemory(FileUndoEntry.redoSharedKey)) public var fileRedoStack: [FileUndoEntry] = []
        @Shared(.inMemory(UserPreferences.sharedKey)) var preferences = UserPreferences()
        @Shared(.inMemory(SharedFileInbox.sharedKey)) public var sharedFileInbox: [URL] = []
        /// The signed-in account's downloads scope (server + user id), so each account's saved
        /// files stay in their own folder. Set when a session is confirmed, cleared on sign out
        /// and expiry. Read by `BrowseFeature`/`OfflineTabFeature`/`SettingsFeature`.
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) public var downloadScope = ""
        /// Every signed-in account, for the Settings switcher. Rebuilt after any account change.
        @Shared(.inMemory(AccountSummary.sharedKey)) public var accounts: [AccountSummary] = []
        public var leftAt: Date?

        public init(destination: Destination.State = .loading) {
            self.destination = destination
        }

        mutating func clearAccountSharedState() {
            $fileClipboard.withLock { $0 = nil }
            $fileUndoStack.withLock { $0 = [] }
            $fileRedoStack.withLock { $0 = [] }
            $preferences.withLock { $0 = UserPreferences() }
            @Shared(.inMemory(Branding.sharedKey)) var branding = Branding()
            $branding.withLock { $0 = Branding() }
        }

        var currentAccountID: String? {
            guard case let .authenticated(authenticated) = destination else { return nil }
            return authenticated.accountID
        }

        var shouldCoverWhenInactive: Bool {
            guard case .authenticated = destination else { return false }
            return accounts.contains { $0.requireSignIn != nil }
        }

        var currentServerURL: URL? {
            guard case let .authenticated(authenticated) = destination else { return nil }
            return authenticated.serverURL
        }
    }

    public enum Action {
        case onAppear
        /// The stored session, and the saved files folder recorded for its account (read with it, so
        /// the account's files list before `me` answers, or with no connection at all).
        case sessionRestoreResponse(SessionCredentials?, recordedDownloadScope: String? = nil)
        /// The saved files folder recorded for the account, read before `me` answers (or offline,
        /// when it never does).
        case recordedDownloadScopeLoaded(scope: String, accountID: String)
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
        case tipJarRequested
        case tipJar(PresentationAction<TipJarFeature.Action>)
        /// Files opened in the app from another app's share sheet.
        case incomingFiles([URL])
        /// The user tapped an "upload finished" notification: open the folder the files went to.
        case uploadNotificationTapped(UploadNotificationTaps.Tap)
        case appLeft
        case appReturned
        case lockShown(AccountSummary)
        case accountsLocked([SessionCredentials])
        case lockedAccountSignedOut(SessionCredentials?)
        case destination(Destination.Action)
    }

    public struct AddedAccount: Equatable {
        public let user: User
        public let serverURL: URL
    }

    @Dependency(\.authClient) var authClient
    @Dependency(\.thumbnailCache) var thumbnailCache
    @Dependency(\.offlineFileStore) var offlineFileStore
    @Dependency(\.localDownloadStore) var localDownloadStore
    @Dependency(\.pendingAccountWipes) var pendingAccountWipes
    @Dependency(\.sessionScratchStore) var sessionScratchStore
    @Dependency(\.clientCertificateClient) var clientCertificateClient
    @Dependency(\.uploadDefaults) var uploadDefaults
    @Dependency(\.shareUploads) var shareUploads
    @Dependency(\.date) var date

    public init() {}

    var accountCacheWipe: AccountCacheWipe {
        .fromDependencies
    }

    /// Points the active account at its own folder of saved files and remembers it as their owner,
    /// so removing the account removes them.
    func beginDownloadScope(
        _ state: inout State,
        accountID: String,
        serverURL: URL,
        userID: String
    ) -> Effect<Action> {
        let scope = DownloadAccountScope.identifier(serverURL: serverURL, userID: userID)
        state.$downloadScope.withLock { $0 = scope }
        let localDownloadStore = localDownloadStore
        return .run { _ in localDownloadStore.recordOwner(accountID, scope) }
    }

    /// Reads the folder recorded for `accountID` off the main actor, so its saved files list before
    /// `me` confirms the user, and with no connection at all.
    private func loadRecordedDownloadScope(_ accountID: String) -> Effect<Action> {
        let localDownloadStore = localDownloadStore
        return .run { send in
            guard let scope = localDownloadStore.ownerScope(accountID) else { return }
            await send(.recordedDownloadScopeLoaded(scope: scope, accountID: accountID))
        }
    }

    /// The second pass of an account wipe, run once the account's screens are gone.
    var finishAccountWipes: Effect<Action> {
        let accountCacheWipe = accountCacheWipe
        let authClient = authClient
        return .run { _ in await accountCacheWipe.finishPending(authClient: authClient) }
    }

    /// Stops the offline sync and the Save to Device queue of the account the app is leaving, so
    /// neither keeps running behind the next account nor shows its progress there.
    func stopOfflineWork(leaving accountID: String?) -> Effect<Action> {
        guard let accountID else { return .none }
        return .concatenate(
            .send(.destination(.authenticated(.mainTab(.offline(.accountDeactivated(scope: accountID)))))),
            .send(.destination(.authenticated(.mainTab(.downloadQueue(.accountLeft)))))
        )
    }

    /// Drops the active account whose session the server rejected and wipes its caches. It is
    /// listed as pending before its session goes, so a kill in between cannot orphan its files.
    /// When the stored accounts can't be read the account stays signed in, since tearing down then
    /// would sign every account out, and the next 401 asks again; its caches still go, because the
    /// server already ended its session.
    private func tearDownExpired(accountID: String) -> Effect<Action> {
        let authClient = authClient
        let accountCacheWipe = accountCacheWipe
        return .run { send in
            accountCacheWipe.markPending(accountID)
            let next: SessionCredentials?
            do {
                next = try await authClient.clearActiveSession()
            } catch {
                accountCacheWipe.wipe(accountID)
                accountCacheWipe.pendingWipes.remove(accountID)
                return
            }
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

    private struct AccountWork: Hashable {
        let accountID: String
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            let accountID = state.currentAccountID
            let effect = Scope(state: \State.destination, action: \Action.Cases.destination) {
                Destination.body
            }
            .reduce(into: &state, action: action)
            guard let accountID else { return effect }
            return effect.cancellable(id: AccountWork(accountID: accountID))
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                let authClient = authClient
                let localDownloadStore = localDownloadStore
                let accountCacheWipe = accountCacheWipe
                return .run { send in
                    let locked = await (try? authClient.lockSessions { $0.requireSignIn != nil }) ?? []
                    let credentials = await authClient.restoreSession().map { restored in
                        restored.requireSignIn == nil ? restored : restored.locked
                    }
                    let scope = credentials.flatMap { localDownloadStore.ownerScope($0.accountID) }
                    await send(.sessionRestoreResponse(credentials, recordedDownloadScope: scope))
                    await Self.endLockedSessions(locked, authClient: authClient, accountCacheWipe: accountCacheWipe)
                }

            case let .sessionRestoreResponse(credentials, recordedScope):
                guard let credentials else {
                    withAnimation(DSMotion.contentReveal) {
                        state.destination = .unauthenticated(.init())
                    }
                    return refreshAccounts
                }
                if credentials.isLocked {
                    let account = AccountSummary(credentials, isActive: true)
                    withAnimation(DSMotion.contentReveal) {
                        state.destination = .locked(LockFeature.State(account: account))
                    }
                    return refreshAccounts
                }

                // The active account's cache namespace must be live before the optimistic Browse
                // mounts, so its first cache read hits this account's entries, not the previous
                // one's.
                CacheAccountScope.set(credentials.accountID)
                pendingAccountWipes.remove(credentials.accountID)
                if let recordedScope {
                    state.$downloadScope.withLock { $0 = recordedScope }
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
                guard credentials.username == nil || credentials.username == user.username else {
                    return tearDownExpired(accountID: credentials.accountID)
                }
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                let recordOwner = beginDownloadScope(
                    &state,
                    accountID: credentials.accountID,
                    serverURL: credentials.serverBaseURL,
                    userID: user.id
                )
                if case let .authenticated(current) = state.destination, current.user == user {
                    return .merge(refreshAccounts, recordOwner)
                }
                withAnimation(DSMotion.contentReveal) {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: credentials.serverBaseURL, user: user)
                    )
                }
                return .merge(refreshAccounts, recordOwner)

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
                state.clearAccountSharedState()
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
                if credentials.isLocked {
                    return .concatenate(
                        stopOfflineWork(leaving: leavingAccountID),
                        .send(.lockShown(AccountSummary(credentials, isActive: true))),
                        refreshAccounts
                    )
                }
                state.clearAccountSharedState()
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                CacheAccountScope.set(credentials.accountID)
                pendingAccountWipes.remove(credentials.accountID)
                // Decoded thumbnails are keyed by URL alone, and two accounts on one server share paths.
                thumbnailCache.clearMemory()
                // Finalized once `me` confirms the user id; empty in the meantime.
                state.$downloadScope.withLock { $0 = "" }
                state.didAuthenticateFromLogin = false
                withAnimation(DSMotion.contentReveal) {
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
                    .concatenate(loadRecordedDownloadScope(credentials.accountID), refreshAccounts),
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

            case let .recordedDownloadScopeLoaded(scope, accountID):
                // Only for the account still active, and never over the scope `me` confirmed.
                guard accountID == state.currentAccountID, state.downloadScope.isEmpty else { return .none }
                state.$downloadScope.withLock { $0 = scope }
                return .none

            case let .accountsRefreshed(accounts):
                state.$accounts.withLock { $0 = accounts }
                return .none

            case let .destination(.unauthenticated(.delegate(.authenticated(user, serverURL)))):
                if state.sessionDidExpire {
                    state.$sessionDidExpire.withLock { $0 = false }
                }
                let accountID = SessionCredentials.accountID(serverURL: serverURL, username: user.username)
                CacheAccountScope.set(accountID)
                pendingAccountWipes.remove(accountID)
                let recordOwner = beginDownloadScope(
                    &state,
                    accountID: accountID,
                    serverURL: serverURL,
                    userID: user.id
                )
                state.didAuthenticateFromLogin = true
                state.destination = .authenticated(
                    AuthenticatedFeature.State(serverURL: serverURL, user: user)
                )
                // A fresh sign in on the login screen means no account is currently active, so
                // clear every cache: on a shared device this must not expose a previous account's
                // cached listings. Every store is scoped by account, so the new one reads only its own.
                let caches = RebuildableCaches.fromDependencies
                let offlineFileStore = offlineFileStore
                let localDownloadStore = localDownloadStore
                let sessionScratchStore = sessionScratchStore
                return .merge(
                    refreshAccounts,
                    .run { _ in
                        caches.clearAll()
                        offlineFileStore.removeAll()
                        // Files of accounts signed out in a version that kept them; the owner is
                        // recorded after, so the new account starts its own empty folder.
                        localDownloadStore.removeAll()
                        sessionScratchStore.purge(.keepingActiveTransfers)
                    }
                    .concatenate(with: recordOwner),
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

            case let .destination(.authenticated(.mainTab(.delegate(.requireSignInChanged(accountID, requireSignIn))))):
                let authClient = authClient
                return .concatenate(
                    .run { _ in try? await authClient.setRequireSignIn(accountID, requireSignIn) },
                    refreshAccounts
                )

            case .appLeft, .appReturned, .lockShown, .accountsLocked, .lockedAccountSignedOut,
                 .destination(.locked(.delegate)):
                return reduceLock(into: &state, action: action)

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

            case .tipJarRequested:
                state.tipJar = TipJarFeature.State()
                return .none

            case .tipJar(.presented(.delegate(.tipped))):
                state.tipJar = nil
                return .none

            case .tipJar:
                return .none

            case .addAccountSheetDismissed:
                // Login already persisted and activated the new account; adopt it without a cache
                // wipe so the accounts already signed in keep their caches. The real user is in
                // hand, so no `me` round trip is needed.
                guard let added = state.pendingAddedAccount else { return .none }
                state.pendingAddedAccount = nil
                let user = added.user
                let serverURL = added.serverURL
                state.clearAccountSharedState()
                let accountID = SessionCredentials.accountID(serverURL: serverURL, username: user.username)
                let leavingAccountID = state.currentAccountID
                CacheAccountScope.set(accountID)
                pendingAccountWipes.remove(accountID)
                thumbnailCache.clearMemory()
                let recordOwner = beginDownloadScope(
                    &state,
                    accountID: accountID,
                    serverURL: serverURL,
                    userID: user.id
                )
                state.didAuthenticateFromLogin = false
                withAnimation(DSMotion.contentReveal) {
                    state.destination = .authenticated(
                        AuthenticatedFeature.State(serverURL: serverURL, user: user)
                    )
                }
                return .merge(
                    stopOfflineWork(leaving: leavingAccountID),
                    refreshAccounts,
                    recordOwner,
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
        .ifLet(\.$tipJar, action: \.tipJar) {
            TipJarFeature()
        }
        .onChange(of: \.currentAccountID) { leftAccountID, _ in
            Reduce { _, _ in
                leftAccountID.map { .cancel(id: AccountWork(accountID: $0)) } ?? .none
            }
        }

        UploadFolderRouting()
    }

    /// Removes the client certificates of servers no remaining account is signed in to, so an
    /// account that leaves the device takes its mTLS identity with it.
    /// `serverURL` is the server just signed in to, kept even before its session shows up in
    /// the stored list.
    func pruneClientCertificates(keeping serverURL: URL? = nil) -> Effect<Action> {
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
    var refreshAccounts: Effect<Action> {
        let authClient = authClient
        return .run { send in
            let sessions = await authClient.listSessions()
            let active = await authClient.activeAccountID()
            await send(.accountsRefreshed(Self.summaries(sessions, activeID: active)))
        }
    }

    private static func summaries(_ sessions: [SessionCredentials], activeID: String?) -> [AccountSummary] {
        sessions.map { AccountSummary($0, isActive: $0.accountID == activeID) }
    }

    /// Full teardown to the login screen: no account left signed in. Clears every cache and
    /// per-session state so nothing leaks into the next sign in.
    func teardownToLogin(_ state: inout State, removesClientCertificates: Bool) -> Effect<Action> {
        state.clearAccountSharedState()
        state.$downloadScope.withLock { $0 = "" }
        CacheAccountScope.set("")
        CacheAccountScope.markEveryAccountWiped()
        state.didAuthenticateFromLogin = false
        state.addAccount = nil
        state.pendingAddedAccount = nil
        withAnimation(DSMotion.contentReveal) {
            state.destination = .unauthenticated(.init())
        }
        let authClient = authClient
        let caches = RebuildableCaches.fromDependencies
        let offlineFileStore = offlineFileStore
        let localDownloadStore = localDownloadStore
        let sessionScratchStore = sessionScratchStore
        let pendingAccountWipes = pendingAccountWipes
        let clientCertificateClient = clientCertificateClient
        let uploadDefaults = uploadDefaults
        let shareUploads = shareUploads
        return .merge(
            refreshAccounts,
            .run { @MainActor _ in AppStorageKeys.resetSessionPreferences() },
            .run { _ in
                await authClient.clearAllSessions()
                // A download still landing is dropped by its `CacheAccountScope.wipeStamp`.
                caches.clearAll()
                offlineFileStore.removeAll()
                localDownloadStore.removeAll()
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
