@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
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

    private final class WipeLog: Sendable {
        let wiped = LockIsolated<Set<String>>([])

        func record(_ store: Store) {
            wiped.withValue { _ = $0.insert(store.rawValue) }
        }

        var isComplete: Bool {
            wiped.value == Set(Store.allCases.map(\.rawValue))
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
        values.sessionScratchStore.purge = { log.record(.scratchFiles) }
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
    }

    @Test("An expired session with no other account wipes every store")
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
    }
}
