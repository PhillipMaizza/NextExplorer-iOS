@testable import AppFeature
import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import NetworkClient
import Testing

/// Records, in order, every store wipe and session teardown the app performs, so a test can assert
/// exactly what was wiped and when. Each store's closures only append an event: nothing is wiped.
final class WipeRecorder: Sendable {
    enum Event: Equatable, Sendable {
        case sessionsCleared
        case directoryCacheCleared
        case jsonCacheCleared
        case previewCacheCleared
        case thumbnailMemoryCleared
        case offlineFilesCleared
        case scratchPurged(SessionScratchStore.Scope)
        case certificatesKept(Set<ClientCertificateOrigin>)
        case directoryAccountCleared(String)
        case jsonAccountCleared(String)
        case previewAccountCleared(String)
        case offlineAccountCleared(String)
        case uploadDefaultsRetained(Set<String>)
        case shareUploadsKept(Set<String>)
        case activeSessionCleared
        case accountRemoved(String)
        case pendingAdded(String)
        case pendingRemoved(String)
    }

    /// What dropping one account wipes while other accounts stay signed in.
    static func accountWipe(_ accountID: String) -> [Event] {
        [
            .directoryAccountCleared(accountID),
            .jsonAccountCleared(accountID),
            .previewAccountCleared(accountID),
            .offlineAccountCleared(accountID),
            .thumbnailMemoryCleared,
        ]
    }

    /// What signing the last account out also removes from the device.
    static let lastSignOutCredentialWipe: [Event] = prune(origins: [], accounts: [])

    /// What the full teardown to the login screen wipes, in order.
    static let fullTeardown: [Event] = [
        .sessionsCleared,
        .directoryCacheCleared,
        .jsonCacheCleared,
        .previewCacheCleared,
        .thumbnailMemoryCleared,
        .offlineFilesCleared,
        .scratchPurged(.everything),
    ]

    /// What pruning leaves behind once the accounts that remain are known: the certificates of their
    /// servers, their upload defaults and their pending share uploads.
    static func prune(origins: Set<ClientCertificateOrigin>, accounts: Set<String>) -> [Event] {
        [.certificatesKept(origins), .uploadDefaultsRetained(accounts), .shareUploadsKept(accounts)]
    }

    /// Same events, same counts, in any order.
    static func areSame(_ actual: [Event], _ expected: [Event]) -> Bool {
        var remaining = expected
        for event in actual {
            guard let index = remaining.firstIndex(of: event) else { return false }
            remaining.remove(at: index)
        }
        return remaining.isEmpty
    }

    let events = LockIsolated<[Event]>([])

    func record(_ event: Event) {
        events.withValue { $0.append(event) }
    }

    func install(into values: inout DependencyValues) {
        values.authClient.clearAllSessions = { self.record(.sessionsCleared) }
        values.directoryCacheStore.clearAll = { self.record(.directoryCacheCleared) }
        values.directoryCacheStore.clearScope = { self.record(.directoryAccountCleared($0)) }
        values.jsonCacheStore.clearAll = { self.record(.jsonCacheCleared) }
        values.jsonCacheStore.clearScope = { self.record(.jsonAccountCleared($0)) }
        values.previewCacheStore.clear = { self.record(.previewCacheCleared) }
        values.previewCacheStore.clearAccount = { self.record(.previewAccountCleared($0)) }
        values.thumbnailCache.clearMemory = { self.record(.thumbnailMemoryCleared) }
        values.offlineFileStore.removeAll = { self.record(.offlineFilesCleared) }
        values.offlineFileStore.removeAccount = { self.record(.offlineAccountCleared($0)) }
        values.sessionScratchStore.purge = { self.record(.scratchPurged($0)) }
        values.clientCertificateClient.removeAll = { self.record(.certificatesKept($0)) }
        values.uploadDefaults.retain = { self.record(.uploadDefaultsRetained($0)) }
        values.shareUploads.cancel = { self.record(.shareUploadsKept($0)) }
        values.authClient.clearActiveSession = {
            self.record(.activeSessionCleared)
            return nil
        }
        values.authClient.removeAccount = {
            self.record(.accountRemoved($0))
            return nil
        }
    }

    /// Lists the accounts the app marks as pending, in the order it does, without keeping any.
    func installPendingLog(into values: inout DependencyValues) {
        values.pendingAccountWipes = PendingAccountWipes(
            accounts: { [] },
            add: { self.record(.pendingAdded($0)) },
            remove: { self.record(.pendingRemoved($0)) }
        )
    }
}

/// Parent of every AppFeature suite that drives merged effects. They run on the main serial executor,
/// a process wide switch, so the suites run one at a time and never flip it under each other.
@Suite("AppFeature", .serialized)
enum AppSuites {
    /// The in memory shared values are process wide, so each test starts from the same blank state.
    @MainActor
    static func resetSharedState() {
        @Shared(.inMemory(DownloadAccountScope.sharedKey)) var downloadScope = ""
        $downloadScope.withLock { $0 = "" }
        @Shared(.inMemory(AccountSummary.sharedKey)) var accounts: [AccountSummary] = []
        $accounts.withLock { $0 = [] }
        @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
        $sessionDidExpire.withLock { $0 = false }
        @Shared(.inMemory(SharedFileInbox.sharedKey)) var inbox: [URL] = []
        $inbox.withLock { $0 = [] }
    }
}

enum AppFixtures {
    static let serverA = URL(string: "https://a.example.com") ?? URL(fileURLWithPath: "/")
    static let serverB = URL(string: "https://b.example.com") ?? URL(fileURLWithPath: "/")
    static let userA = User(id: "1", username: "alice", email: nil, roles: [])
    static let userB = User(id: "2", username: "bob", email: nil, roles: [])
    static let accountA = "https://a.example.com|alice"
    static let accountB = "https://b.example.com|bob"
    static let downloadScopeA = "afedf24dbf2fc23413b9282ff0b95bae"
    static let downloadScopeB = "c7934fa255b1a9cb66884b5a6730585e"
    static let originA = ClientCertificateOrigin(host: "a.example.com", port: 443)
    static let originB = ClientCertificateOrigin(host: "b.example.com", port: 443)
    static let summaryA = AccountSummary(id: accountA, username: "alice", serverURL: serverA, isActive: true)
    static let summaryB = AccountSummary(id: accountB, username: "bob", serverURL: serverB, isActive: true)

    static func credentials(_ serverURL: URL, _ username: String) -> SessionCredentials {
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
}
