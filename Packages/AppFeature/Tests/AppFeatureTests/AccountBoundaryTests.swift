@testable import AppFeature
import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import NetworkClient
import Testing

/// Account boundaries: a stale signal about an account that was already left must never act on the
/// account that is active now, and the record that lets a killed wipe finish is written before the
/// session goes.
@MainActor
@Suite("Account boundary", .serialized)
struct AccountBoundaryTests {
    private enum Fixture {
        static let serverA = URL(string: "https://a.example.com") ?? URL(fileURLWithPath: "/")
        static let serverB = URL(string: "https://b.example.com") ?? URL(fileURLWithPath: "/")
        static let usernameA = "alice"
        static let usernameB = "bob"
        static let path = "Docs"
        static let fetchedAt = Date(timeIntervalSince1970: 100)
        static let keychainFailure = "keychain unreadable"
    }

    private let userA = User(id: "1", username: Fixture.usernameA, email: nil, roles: [])
    private let userB = User(id: "2", username: Fixture.usernameB, email: nil, roles: [])

    init() {
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) var downloadScope = ""
        $downloadScope.withLock { $0 = "" }
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        $accounts.withLock { $0 = [] }
        @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
        $sessionDidExpire.withLock { $0 = false }
    }

    private func credentials(_ serverURL: URL, _ username: String) -> SessionCredentials {
        SessionCredentials(
            serverBaseURL: serverURL,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "v",
            cookieDomain: serverURL.host ?? "",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: username
        )
    }

    private func listing() -> BrowseResult {
        BrowseResult(
            items: [],
            access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
            path: Fixture.path
        )
    }

    private func activeState(_ serverURL: URL, _ user: User) -> AppFeature.State {
        AppFeature.State(destination: .authenticated(AuthenticatedFeature.State(serverURL: serverURL, user: user)))
    }

    // MARK: Stale signals

    @Test("a 401 burst from an account that was already left does not tear down the active account")
    func staleExpiryAfterASwitchLeavesTheNewAccountAlone() async {
        let pending = PendingAccountWipes.inMemory()
        let store = TestStore(initialState: activeState(Fixture.serverB, userB)) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = pending
            $0.authClient.me = { [userB] _ in userB }
            $0.authClient.clearActiveSession = {
                Issue.record("the active account must not be signed out for another account's 401")
                return nil
            }
        }
        store.state.$sessionDidExpire.withLock { $0 = true }

        await store.send(.sessionExpiryDetected) {
            $0.$sessionDidExpire.withLock { $0 = false }
        }
        await store.finish()

        #expect(pending.accounts().isEmpty)
        #expect(store.state.currentAccountID == credentials(Fixture.serverB, Fixture.usernameB).accountID)
    }

    @Test("a network error while confirming an expiry leaves the session in place")
    func unconfirmedExpiryIsIgnored() async {
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.authClient.me = { _ in throw AuthClientError.network("offline") }
            $0.authClient.clearActiveSession = {
                Issue.record("an unreachable server does not prove the session is gone")
                return nil
            }
        }
        store.state.$sessionDidExpire.withLock { $0 = true }

        await store.send(.sessionExpiryDetected) {
            $0.$sessionDidExpire.withLock { $0 = false }
        }
        await store.finish()
    }

    @Test("an expiry confirmed for an account that is no longer active is dropped")
    func staleConfirmationIsDropped() async {
        let store = TestStore(initialState: activeState(Fixture.serverB, userB)) {
            AppFeature()
        } withDependencies: {
            $0.authClient.clearActiveSession = {
                Issue.record("the active account must not be signed out")
                return nil
            }
        }

        await store.send(.sessionExpiryConfirmed(accountID: credentials(Fixture.serverA, Fixture.usernameA).accountID))
        await store.finish()
    }

    @Test("a session check answered for an account that was left changes nothing, success or failure")
    func staleValidationResponsesAreDropped() async {
        let store = TestStore(initialState: activeState(Fixture.serverB, userB)) {
            AppFeature()
        } withDependencies: {
            $0.authClient.clearActiveSession = {
                Issue.record("a stale failure must not sign the active account out")
                return nil
            }
        }
        let stale = credentials(Fixture.serverA, Fixture.usernameA)

        await store.send(.sessionValidationResponse(.failure(.sessionExpired), stale))
        await store.send(.sessionValidationResponse(.success(userA), stale))
        await store.finish()

        #expect(store.state.currentAccountID == credentials(Fixture.serverB, Fixture.usernameB).accountID)
        #expect(store.state.downloadScope.isEmpty)
    }

    // MARK: Record before the session goes

    private final class EventLog: Sendable {
        let events = LockIsolated<[String]>([])

        func record(_ event: String) {
            events.withValue { $0.append(event) }
        }

        func index(of event: String) -> Int? {
            events.value.firstIndex(of: event)
        }
    }

    private func recordingPending(_ log: EventLog) -> PendingAccountWipes {
        PendingAccountWipes(
            accounts: { [] },
            add: { log.record("pending.add \($0)") },
            remove: { log.record("pending.remove \($0)") }
        )
    }

    @Test("an expired session is listed as pending before its session is cleared")
    func expiryRecordsThePendingWipeFirst() async {
        let log = EventLog()
        let expiredID = credentials(Fixture.serverA, Fixture.usernameA).accountID
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = recordingPending(log)
            $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            $0.authClient.clearActiveSession = { log.record("clearActiveSession"); return nil }
            $0.offlineFileStore.removeAccount = { log.record("wipe \($0)") }
        }
        store.exhaustivity = .off

        await store.send(.sessionExpiryDetected)
        await store.receive(\.activeAccountTornDown)
        await store.finish()

        let add = log.index(of: "pending.add \(expiredID)")
        let clear = log.index(of: "clearActiveSession")
        let wipe = log.index(of: "wipe \(expiredID)")
        #expect(add != nil)
        #expect((add ?? .max) < (clear ?? .min))
        #expect((clear ?? .max) < (wipe ?? .min))
    }

    @Test("a rejected restored session is listed as pending before its session is cleared")
    func rejectedValidationRecordsThePendingWipeFirst() async {
        let log = EventLog()
        let rejected = credentials(Fixture.serverA, Fixture.usernameA)
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = recordingPending(log)
            $0.authClient.clearActiveSession = { log.record("clearActiveSession"); return nil }
        }
        store.exhaustivity = .off

        await store.send(.sessionValidationResponse(.failure(.sessionExpired), rejected))
        await store.receive(\.activeAccountTornDown)
        await store.finish()

        let add = log.index(of: "pending.add \(rejected.accountID)")
        #expect(add != nil)
        #expect((add ?? .max) < (log.index(of: "clearActiveSession") ?? .min))
    }

    @Test("signing out lists the account as pending before removing its session")
    func signOutRecordsThePendingWipeFirst() async {
        let log = EventLog()
        let accountID = credentials(Fixture.serverA, Fixture.usernameA).accountID
        let store = TestStore(initialState: AuthenticatedFeature.State(serverURL: Fixture.serverA, user: userA)) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.pendingAccountWipes = recordingPending(log)
            $0.authClient.removeAccount = { _ in log.record("removeAccount"); return nil }
        }
        store.exhaustivity = .off

        await store.send(.mainTab(.delegate(.signOutButtonTapped)))
        await store.receive(\.accountChangeResolved)
        await store.finish()

        let add = log.index(of: "pending.add \(accountID)")
        #expect(add != nil)
        #expect((add ?? .max) < (log.index(of: "removeAccount") ?? .min))
    }

    @Test("removing an account lists it as pending before removing its session")
    func removeAccountRecordsThePendingWipeFirst() async {
        let log = EventLog()
        let removedID = credentials(Fixture.serverB, Fixture.usernameB).accountID
        let store = TestStore(initialState: AuthenticatedFeature.State(serverURL: Fixture.serverA, user: userA)) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.pendingAccountWipes = recordingPending(log)
            $0.authClient.removeAccount = { _ in log.record("removeAccount"); return nil }
        }
        store.exhaustivity = .off

        await store.send(.mainTab(.delegate(.removeAccount(removedID))))
        await store.receive(\.accountChangeResolved)
        await store.finish()

        let add = log.index(of: "pending.add \(removedID)")
        #expect(add != nil)
        #expect((add ?? .max) < (log.index(of: "removeAccount") ?? .min))
    }

    // MARK: The pending list drains

    @Test("an expiry that falls through to another account finishes its second pass and drains the list")
    func fallThroughDrainsThePendingList() async {
        let pending = PendingAccountWipes.inMemory()
        let next = credentials(Fixture.serverB, Fixture.usernameB)
        let expiredID = credentials(Fixture.serverA, Fixture.usernameA).accountID
        let directory = DirectoryCacheStore.inMemory()
        let offlineRemovals = LockIsolated<[String]>([])
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = pending
            $0.directoryCacheStore = directory
            $0.authClient.me = { [userB] url in
                if url == Fixture.serverA {
                    throw AuthClientError.sessionExpired
                }
                return userB
            }
            $0.authClient.clearActiveSession = { next }
            $0.authClient.listSessions = { [next] }
            $0.authClient.listSessionsOrThrow = { [next] }
            $0.authClient.activeAccountID = { next.accountID }
            $0.offlineFileStore.removeAccount = { id in offlineRemovals.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.sessionExpiryDetected)
        await store.receive(\.sessionExpiryConfirmed)
        await store.receive(\.activeAccountTornDown)
        await store.receive(\.activateAccount)
        directory.bound(to: expiredID).write(serverURL: Fixture.serverA, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        await store.finish()

        #expect(pending.accounts().isEmpty, "the second pass never ran for \(pending.accounts())")
        #expect(offlineRemovals.value == [expiredID, expiredID], "wiped once on expiry and once more by the second pass")
    }

    @Test("activating an account unlists a stale pending entry for it, so it is never wiped")
    func activatingAnAccountDropsItsStalePendingEntry() async {
        let pending = PendingAccountWipes.inMemory()
        let readded = credentials(Fixture.serverA, Fixture.usernameA)
        pending.add(readded.accountID)
        let directory = DirectoryCacheStore.inMemory()
        directory.bound(to: readded.accountID).write(serverURL: Fixture.serverA, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        let store = TestStore(initialState: activeState(Fixture.serverB, userB)) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = pending
            $0.directoryCacheStore = directory
            $0.authClient.me = { [userA] _ in userA }
            $0.authClient.listSessions = { [readded] }
            $0.authClient.listSessionsOrThrow = { [] }
            $0.authClient.activeAccountID = { readded.accountID }
        }
        store.exhaustivity = .off

        await store.send(.activateAccount(readded))
        await store.finish()

        #expect(pending.accounts().isEmpty)
        #expect(directory.bound(to: readded.accountID).read(serverURL: Fixture.serverA, path: Fixture.path) != nil)
    }

    @Test("restoring a session at launch unlists a stale pending entry for it, so it is never wiped")
    func restoringAnAccountDropsItsStalePendingEntry() async {
        let pending = PendingAccountWipes.inMemory()
        let restored = credentials(Fixture.serverA, Fixture.usernameA)
        pending.add(restored.accountID)
        let directory = DirectoryCacheStore.inMemory()
        directory.bound(to: restored.accountID).write(serverURL: Fixture.serverA, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = pending
            $0.directoryCacheStore = directory
            $0.authClient.me = { [userA] _ in userA }
            $0.authClient.listSessions = { [restored] }
            $0.authClient.listSessionsOrThrow = { [] }
            $0.authClient.activeAccountID = { restored.accountID }
        }
        store.exhaustivity = .off

        await store.send(.sessionRestoreResponse(restored))
        await store.finish()

        #expect(pending.accounts().isEmpty)
        #expect(directory.bound(to: restored.accountID).read(serverURL: Fixture.serverA, path: Fixture.path) != nil)
    }

    @Test("signing in again at the login screen unlists a stale pending entry for the account")
    func signingInAgainDropsTheStalePendingEntry() async {
        let pending = PendingAccountWipes.inMemory()
        pending.add(credentials(Fixture.serverA, Fixture.usernameA).accountID)
        let store = TestStore(initialState: AppFeature.State(destination: .unauthenticated(.init()))) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = pending
            $0.authClient.listSessions = { [] }
            $0.authClient.activeAccountID = { nil }
        }
        store.exhaustivity = .off

        await store.send(.destination(.unauthenticated(.delegate(.authenticated(userA, Fixture.serverA)))))
        await store.finish()

        #expect(pending.accounts().isEmpty)
    }

    @Test("adding an account unlists a stale pending entry for it and finishes the other wipes")
    func addingAnAccountDropsItsStalePendingEntry() async {
        let pending = PendingAccountWipes.inMemory()
        let added = credentials(Fixture.serverB, Fixture.usernameB)
        pending.add(added.accountID)
        let directory = DirectoryCacheStore.inMemory()
        directory.bound(to: added.accountID).write(serverURL: Fixture.serverB, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        var state = activeState(Fixture.serverA, userA)
        state.pendingAddedAccount = AppFeature.AddedAccount(user: userB, serverURL: Fixture.serverB)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.pendingAccountWipes = pending
            $0.directoryCacheStore = directory
            $0.authClient.listSessions = { [added] }
            $0.authClient.listSessionsOrThrow = { [] }
            $0.authClient.activeAccountID = { added.accountID }
        }
        store.exhaustivity = .off

        await store.send(.addAccountSheetDismissed)
        await store.finish()

        #expect(pending.accounts().isEmpty)
        #expect(directory.bound(to: added.accountID).read(serverURL: Fixture.serverB, path: Fixture.path) != nil)
    }

    // MARK: Leaving an account stops its offline work

    @Test("switching accounts tells the offline engine which account is being left")
    func switchingAccountsStopsTheLeftAccountsOfflineWork() async {
        let next = credentials(Fixture.serverB, Fixture.usernameB)
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.authClient.me = { [userB] _ in userB }
            $0.authClient.listSessions = { [next] }
            $0.authClient.listSessionsOrThrow = { [next] }
            $0.authClient.activeAccountID = { next.accountID }
        }
        store.exhaustivity = .off

        await store.send(.activateAccount(next))
        await store.receive(
            \.destination.authenticated.mainTab.offline.accountDeactivated,
            credentials(Fixture.serverA, Fixture.usernameA).accountID
        )
        await store.finish()
    }

    // MARK: Certificates

    @Test("an unreadable keychain never prunes certificates, share uploads or upload defaults")
    func unreadableKeychainDoesNotPrune() async {
        let touched = LockIsolated<[String]>([])
        let active = credentials(Fixture.serverA, Fixture.usernameA)
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.authClient.listSessions = { [] }
            $0.authClient.listSessionsOrThrow = { throw AuthClientError.keychain(Fixture.keychainFailure) }
            $0.authClient.activeAccountID = { active.accountID }
            $0.clientCertificateClient.removeAll = { _ in touched.withValue { $0.append("certificates") } }
            $0.uploadDefaults.retain = { _ in touched.withValue { $0.append("uploadDefaults") } }
            $0.shareUploads.cancel = { _ in touched.withValue { $0.append("shareUploads") } }
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(active)))))
        await store.finish()

        #expect(touched.value.isEmpty, "pruned \(touched.value) on a keychain that could not be read")
    }

    @Test("a readable keychain still prunes to the servers and accounts that remain")
    func readableKeychainPrunes() async {
        let kept = LockIsolated<Set<ClientCertificateOrigin>?>(nil)
        let retained = LockIsolated<Set<String>?>(nil)
        let active = credentials(Fixture.serverA, Fixture.usernameA)
        let store = TestStore(initialState: activeState(Fixture.serverA, userA)) {
            AppFeature()
        } withDependencies: {
            $0.authClient.listSessions = { [active] }
            $0.authClient.listSessionsOrThrow = { [active] }
            $0.authClient.activeAccountID = { active.accountID }
            $0.clientCertificateClient.removeAll = { kept.setValue($0) }
            $0.uploadDefaults.retain = { retained.setValue($0) }
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(active)))))
        await store.finish()

        #expect(kept.value == [ClientCertificateOrigin(host: "a.example.com", port: 443)])
        #expect(retained.value == [active.accountID])
    }
}
