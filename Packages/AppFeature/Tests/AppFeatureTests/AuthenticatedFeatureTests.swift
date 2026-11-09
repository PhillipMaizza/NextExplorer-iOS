@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@MainActor
@Suite("AuthenticatedFeature")
struct AuthenticatedFeatureTests {
    private let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
    private let user = User(id: "1", username: "phillip", email: nil, roles: [])

    private func credentials(serverURL: URL, username: String) -> SessionCredentials {
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

    @Test("signing out the last account: removes it and delegates activeAccountChanged(nil)")
    func signOutLastAccount() async {
        let removedID = LockIsolated<String?>(nil)
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.removeAccount = { id in removedID.setValue(id); return nil }
        }

        await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
            $0.mainTab.settings.isSigningOut = true
        }
        await store.receive(\.accountChangeResolved) {
            $0.mainTab.settings.isSigningOut = false
        }
        await store.receive(\.delegate)

        #expect(removedID.value == serverURL.absoluteString + "|phillip")
    }

    @Test("signing out with another account left: switches to the next account")
    func signOutFallsThroughToNextAccount() async {
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let next = credentials(serverURL: otherServer, username: "jane")
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.removeAccount = { _ in next }
        }

        await store.send(.mainTab(.delegate(.signOutButtonTapped))) {
            $0.mainTab.settings.isSigningOut = true
        }
        await store.receive(\.accountChangeResolved) {
            $0.mainTab.settings.isSigningOut = false
        }
        await store.receive(\.delegate.activeAccountChanged)
    }

    @Test("removing account A with B still signed in clears A's caches and keeps B's")
    func removeAccountClearsOnlyThatAccountsCaches() async {
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let next = credentials(serverURL: otherServer, username: "jane")
        let removedID = serverURL.absoluteString + "|phillip"
        let directory = DirectoryCacheStore.inMemory()
        let json = JSONCacheStore.inMemory()
        let browse = BrowseResult(items: [], access: FileAccess(
            canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true
        ), path: "")
        let fetchedAt = Date(timeIntervalSince1970: 1)
        for id in [removedID, next.accountID] {
            directory.bound(to: id).write(serverURL: serverURL, path: "", result: browse, etag: nil, fetchedAt: fetchedAt)
            json.bound(to: id).write(key: "favorites", data: Data(id.utf8))
        }
        let previewCleared = LockIsolated<[String]>([])
        let offlineCleared = LockIsolated<[String]>([])
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.removeAccount = { _ in next }
            $0.directoryCacheStore = directory
            $0.jsonCacheStore = json
            $0.previewCacheStore.clearAccount = { id in previewCleared.withValue { $0.append(id) } }
            $0.offlineFileStore.removeAccount = { id in offlineCleared.withValue { $0.append(id) } }
        }
        store.exhaustivity = .off

        await store.send(.mainTab(.delegate(.removeAccount(removedID))))
        await store.receive(\.accountChangeResolved)
        await store.finish()

        #expect(directory.bound(to: removedID).read(serverURL: serverURL, path: "") == nil)
        #expect(directory.bound(to: next.accountID).read(serverURL: serverURL, path: "") != nil)
        #expect(json.bound(to: removedID).read(key: "favorites") == nil)
        #expect(json.bound(to: next.accountID).read(key: "favorites") != nil)
        #expect(previewCleared.value == [removedID])
        #expect(offlineCleared.value == [removedID])
    }

    @Test("signing out the active account clears that account's caches before handing off")
    func signOutClearsTheActiveAccountsCaches() async {
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let next = credentials(serverURL: otherServer, username: "jane")
        let activeID = serverURL.absoluteString + "|phillip"
        let json = JSONCacheStore.inMemory()
        json.bound(to: activeID).write(key: "shares.byMe", data: Data("a".utf8))
        json.bound(to: next.accountID).write(key: "shares.byMe", data: Data("b".utf8))
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.removeAccount = { _ in next }
            $0.jsonCacheStore = json
        }
        store.exhaustivity = .off

        await store.send(.mainTab(.delegate(.signOutButtonTapped)))
        await store.receive(\.accountChangeResolved)
        await store.finish()

        #expect(json.bound(to: activeID).read(key: "shares.byMe") == nil)
        #expect(json.bound(to: next.accountID).read(key: "shares.byMe") != nil)
    }

    @Test("switch account: performs the switch and delegates the new active account")
    func switchAccount() async {
        let otherServer = URL(string: "https://other.example.com") ?? URL(fileURLWithPath: "/")
        let switched = credentials(serverURL: otherServer, username: "jane")
        let requestedID = LockIsolated<String?>(nil)
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.authClient.switchAccount = { id in requestedID.setValue(id); return switched }
        }

        await store.send(.mainTab(.delegate(.switchAccount(switched.accountID))))
        await store.receive(\.accountChangeResolved)
        await store.receive(\.delegate.activeAccountChanged)

        #expect(requestedID.value == switched.accountID)
    }

    @Test("add account request bubbles straight up to the parent")
    func addAccountRequestBubbles() async {
        let store = TestStore(
            initialState: AuthenticatedFeature.State(serverURL: serverURL, user: user)
        ) {
            AuthenticatedFeature()
        }

        await store.send(.mainTab(.delegate(.addAccountRequested)))
        await store.receive(\.delegate.addAccountRequested)
    }
}
