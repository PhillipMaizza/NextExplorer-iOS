@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import NetworkClient
import Testing

/// Rule #11 end to end: every store that can hold one account's data is wiped at every
/// session boundary. Runs on iOS and macOS, so the Mac sign in path is covered by the same
/// assertions as the phone's.
@MainActor
@Suite("Session boundary wipe", .serialized)
struct SessionBoundaryWipeTests {
    private enum Store: String, CaseIterable {
        case directoryCache, jsonCache, previewCache, thumbnailMemory, offlineFiles, scratchFiles
    }

    private nonisolated static let certificatesWiped = "clientCertificates"

    private final class WipeLog: Sendable {
        let wiped = LockIsolated<Set<String>>([])
        let scratchScope = LockIsolated<SessionScratchStore.Scope?>(nil)

        func record(_ store: Store) {
            wiped.withValue { _ = $0.insert(store.rawValue) }
        }

        var isComplete: Bool {
            wiped.value.isSuperset(of: Set(Store.allCases.map(\.rawValue)))
        }

        var certificatesWiped: Bool {
            wiped.value.contains(SessionBoundaryWipeTests.certificatesWiped)
        }
    }

    private let serverURL = URL(string: "https://files.example.com")!
    private let user = User(id: "1", username: "phillip", email: nil, roles: [])

    init() {
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) var downloadScope = ""
        $downloadScope.withLock { $0 = "" }
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        $accounts.withLock { $0 = [] }
    }

    private func recordWipes(_ log: WipeLog, into values: inout DependencyValues) {
        values.directoryCacheStore.clearAll = { log.record(.directoryCache) }
        values.jsonCacheStore.clearAll = { log.record(.jsonCache) }
        values.previewCacheStore.clear = { log.record(.previewCache) }
        values.thumbnailCache.clearMemory = { log.record(.thumbnailMemory) }
        values.offlineFileStore.removeAll = { log.record(.offlineFiles) }
        values.sessionScratchStore.purge = { scope in
            log.scratchScope.setValue(scope)
            log.record(.scratchFiles)
        }
        values.clientCertificateClient.removeAll = { keep in
            if keep.isEmpty {
                log.wiped.withValue { _ = $0.insert(Self.certificatesWiped) }
            }
        }
        values.authClient.listSessions = { [] }
        values.authClient.activeAccountID = { nil }
        values.authClient.clearAllSessions = {}
        values.authClient.clearActiveSession = { nil }
    }

    @Test("A fresh sign in from the login screen wipes every store")
    func freshSignIn() async {
        let log = WipeLog()
        let store = TestStore(initialState: AppFeature.State(destination: .unauthenticated(.init()))) {
            AppFeature()
        } withDependencies: {
            recordWipes(log, into: &$0)
        }
        store.exhaustivity = .off

        await store.send(.destination(.unauthenticated(.delegate(.authenticated(user, serverURL)))))
        await store.finish()

        #expect(log.isComplete, "not wiped: \(Set(Store.allCases.map(\.rawValue)).subtracting(log.wiped.value))")
        #expect(log.scratchScope.value == .keepingActiveTransfers)
        #expect(!log.certificatesWiped, "a fresh sign in must keep the certificate it just used")
    }

    @Test("Signing the last account out wipes every store")
    func lastSignOut() async {
        let log = WipeLog()
        let store = TestStore(
            initialState: AppFeature.State(destination: .authenticated(.init(serverURL: serverURL, user: user)))
        ) {
            AppFeature()
        } withDependencies: {
            recordWipes(log, into: &$0)
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(nil)))))
        await store.finish()

        #expect(log.isComplete, "not wiped: \(Set(Store.allCases.map(\.rawValue)).subtracting(log.wiped.value))")
        #expect(log.scratchScope.value == .everything)
        #expect(log.certificatesWiped)
    }

    @Test("An expired session with no other account wipes every store but keeps the certificate")
    func expiry() async {
        let log = WipeLog()
        let store = TestStore(
            initialState: AppFeature.State(destination: .authenticated(.init(serverURL: serverURL, user: user)))
        ) {
            AppFeature()
        } withDependencies: {
            recordWipes(log, into: &$0)
        }
        store.exhaustivity = .off

        await store.send(.sessionExpiryDetected)
        await store.finish()

        #expect(log.isComplete, "not wiped: \(Set(Store.allCases.map(\.rawValue)).subtracting(log.wiped.value))")
        #expect(!log.certificatesWiped, "an expired session keeps the certificate the user installed")
    }

    @Test("Removing an account drops certificates for servers no remaining account uses")
    func accountRemovalPrunesCertificates() async {
        let remaining = SessionCredentials(
            serverBaseURL: URL(string: "https://other.example.com:8443")!,
            authMode: .local,
            cookieName: "connect.sid",
            cookieValue: "abc",
            cookieDomain: "other.example.com",
            cookiePath: "/",
            cookieIsSecure: true,
            expiresAt: nil,
            username: "phillip"
        )
        let kept = LockIsolated<Set<ClientCertificateOrigin>?>(nil)
        let store = TestStore(
            initialState: AppFeature.State(destination: .authenticated(.init(serverURL: serverURL, user: user)))
        ) {
            AppFeature()
        } withDependencies: {
            $0.authClient.listSessions = { [remaining] }
            $0.authClient.activeAccountID = { remaining.accountID }
            $0.clientCertificateClient.removeAll = { kept.setValue($0) }
            $0.authClient.me = { [user] _ in user }
        }
        store.exhaustivity = .off

        await store.send(.destination(.authenticated(.delegate(.activeAccountChanged(remaining)))))
        await store.finish()

        #expect(kept.value == [ClientCertificateOrigin(host: "other.example.com", port: 8443)])
    }
}
