import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import NetworkClient
@testable import ShareExtensionFeature
import ShareUploads
import Testing
import TestUtils

/// Parent of every share upload suite. Serialized for the same reason as the login suites: ninety
/// TestStore tests waiting at once starve the executor that has to deliver the effect, and TCA's one
/// second default timeout runs out. The suites are nested extensions of this type so they all
/// inherit `.serialized`.
@MainActor
@Suite(.serialized, .isolatedDependencies)
struct ShareUploadFeatureTests {
    typealias Store = TestStoreOf<ShareUploadFeature>

    /// What a store's fake extension did: the batch calls it saw, in order.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        private var indexLists: [[Int]?] = []
        private var uploadedFolders: [String] = []

        var all: [String] {
            lock.withLock { entries }
        }

        var preparedIndexes: [[Int]?] {
            lock.withLock { indexLists }
        }

        var folders: [String] {
            lock.withLock { uploadedFolders }
        }

        func record(_ name: String) {
            lock.withLock { entries.append(name) }
        }

        func record(indexes: [Int]?, folder: String) {
            lock.withLock {
                entries.append("prepare")
                indexLists.append(indexes)
                uploadedFolders.append(folder)
            }
        }
    }
}

/// Shared fixtures and store builders for the suites nested in `ShareUploadFeatureTests`.
@MainActor
protocol ShareUploadHarness {}

extension ShareUploadHarness {
    var credentials: SessionCredentials {
        .preview
    }

    nonisolated static func listing(canUpload: Bool = true) -> BrowseResult {
        BrowseResult(
            items: [],
            access: FileAccess(
                canRead: true, canWrite: canUpload, canUpload: canUpload, canDelete: false,
                canShare: false, canDownload: true
            ),
            path: TestFolder.photos
        )
    }

    nonisolated static var user: User {
        User(id: "1", username: TestAccount.username, email: nil, roles: [])
    }

    /// A store whose fake extension records what it is asked. Exhaustive: every state change and
    /// every received action is asserted.
    func store(
        count: Int = 3,
        credentials: SessionCredentials? = .preview,
        defaults: UploadDefaults = UploadDefaults(),
        calls: ShareUploadFeatureTests.Calls = ShareUploadFeatureTests.Calls(),
        report: PreparationReport? = nil,
        browse: (@Sendable (URL, String) async throws -> BrowseResult)? = nil,
        clock: any Clock<Duration> = TestClock(),
        isAssistive: Bool = false,
        announcements: LockIsolated<[String]> = LockIsolated([])
    ) -> ShareUploadFeatureTests.Store {
        TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { count }
            $0.sharedItems.prepare = { _, destination, indexes, _ in
                calls.record(indexes: indexes, folder: destination)
                return report ?? PreparationReport(stagedCount: count, failures: [])
            }
            $0.sharedItems.start = {
                calls.record("start")
                return report?.stagedCount ?? count
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { credentials }
            $0.authClient.listSessions = { credentials.map { [$0] } ?? [] }
            $0.authClient.me = { _ in Self.user }
            $0.filesClient.browse = browse ?? { _, _ in Self.listing() }
            $0.uploadDefaults = .inMemory(credentials.map { [$0.accountID: defaults] } ?? [:])
            $0.continuousClock = clock
            $0.shareAccessibility = ShareAccessibilityClient(
                isAssistiveTechnologyRunning: { isAssistive },
                announce: { message in announcements.withValue { $0.append(message) } }
            )
        }
    }

    /// Opens the sheet and lets the connection check finish, ending ready for the user.
    func becomeReady(_ store: ShareUploadFeatureTests.Store, count: Int = 3, folder: String = "") async {
        await store.send(.onAppear) { $0.itemCount = count }
        await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = credentials
            $0.destination = folder
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked) { $0.phase = .ready }
    }

    /// Opens the sheet with Upload Without Asking on, up to the connection check that starts the
    /// default folder check.
    func startAutomatic(_ store: ShareUploadFeatureTests.Store, count: Int = 3, folder: String = TestFolder.photos) async {
        await store.send(.onAppear) { $0.itemCount = count }
        await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = credentials
            $0.destination = folder
            $0.shouldUploadWithoutAsking = true
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked)
    }

    /// Taps Upload on a ready sheet and lets a clean pass hand off, ending started.
    func uploadCleanly(_ store: ShareUploadFeatureTests.Store, count: Int = 3) async {
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = count
        }
        await store.receive(\.preparationFinished) {
            $0.stagedCount = count
            $0.phase = .handingOff
        }
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
    }
}
