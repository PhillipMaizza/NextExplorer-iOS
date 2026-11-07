@testable import AppFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import Foundation
import Testing

@Suite("Account cache wipe")
struct AccountCacheWipeTests {
    private enum Fixture {
        static let account = "https://files.example.com|alice"
        static let otherAccount = "https://files.example.com|bob"
        static let server = URL(fileURLWithPath: "/")
        static let path = "Docs"
        static let fetchedAt = Date(timeIntervalSince1970: 100)
        static let defaultsSuitePrefix = "account-cache-wipe-"
    }

    private final class Counters: Sendable {
        let thumbnailClears = LockIsolated(0)
        let previewClears = LockIsolated<[String]>([])
        let offlineRemovals = LockIsolated<[String]>([])
    }

    private func listing() -> BrowseResult {
        BrowseResult(
            items: [],
            access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true),
            path: Fixture.path
        )
    }

    private func makeWipe(
        directory: DirectoryCacheStore = .inMemory(),
        pending: PendingAccountWipes = .inMemory(),
        counters: Counters = Counters()
    ) -> AccountCacheWipe {
        AccountCacheWipe(
            directoryCacheStore: directory,
            jsonCacheStore: .inMemory(),
            previewCacheStore: PreviewCacheStore(
                size: { 0 }, clear: {}, clearAccount: { scope in counters.previewClears.withValue { $0.append(scope) } }
            ),
            offlineFileStore: {
                var store = OfflineFileStore.inMemory()
                store.removeAccount = { scope in counters.offlineRemovals.withValue { $0.append(scope) } }
                return store
            }(),
            thumbnailCache: ThumbnailCache(
                data: { _ in Data() }, resolvedURL: { _, _, _ in nil },
                clearMemory: { counters.thumbnailClears.withValue { $0 += 1 } }
            ),
            textEditorETagStore: TextEditorETagStore(),
            pendingWipes: pending
        )
    }

    @Test("wiping an account clears its disk entries, the thumbnails in memory and lists it as pending")
    func wipeClearsEverythingAndListsThePendingAccount() {
        let directory = DirectoryCacheStore.inMemory()
        directory.bound(to: Fixture.account).write(serverURL: Fixture.server, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        directory.bound(to: Fixture.otherAccount).write(serverURL: Fixture.server, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        let pending = PendingAccountWipes.inMemory()
        let counters = Counters()

        makeWipe(directory: directory, pending: pending, counters: counters)(Fixture.account)

        #expect(directory.bound(to: Fixture.account).read(serverURL: Fixture.server, path: Fixture.path) == nil)
        #expect(directory.bound(to: Fixture.otherAccount).read(serverURL: Fixture.server, path: Fixture.path) != nil)
        #expect(counters.thumbnailClears.value == 1)
        #expect(counters.previewClears.value == [Fixture.account])
        #expect(counters.offlineRemovals.value == [Fixture.account])
        #expect(pending.accounts() == [Fixture.account])
    }

    @Test("a writer that lands after the first wipe is cleaned by the second pass, which unlists the account")
    func lateWriterIsRemovedByTheSecondPass() {
        let directory = DirectoryCacheStore.inMemory()
        let pending = PendingAccountWipes.inMemory()
        let wipe = makeWipe(directory: directory, pending: pending)
        wipe(Fixture.account)

        directory.bound(to: Fixture.account).write(serverURL: Fixture.server, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)
        #expect(directory.bound(to: Fixture.account).read(serverURL: Fixture.server, path: Fixture.path) != nil)

        wipe.finishPending()

        #expect(directory.bound(to: Fixture.account).read(serverURL: Fixture.server, path: Fixture.path) == nil)
        #expect(pending.accounts().isEmpty)
    }

    @Test("an account left pending by a killed run is wiped by the next launch's pass")
    func pendingAccountSurvivesARestart() throws {
        let suite = "\(Fixture.defaultsSuitePrefix)\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = DirectoryCacheStore.inMemory()
        makeWipe(directory: directory, pending: .persisted(in: defaults))(Fixture.account)
        directory.bound(to: Fixture.account).write(serverURL: Fixture.server, path: Fixture.path, result: listing(), etag: nil, fetchedAt: Fixture.fetchedAt)

        let relaunched = PendingAccountWipes.persisted(in: defaults)
        #expect(relaunched.accounts() == [Fixture.account])
        makeWipe(directory: directory, pending: relaunched).finishPending()

        #expect(directory.bound(to: Fixture.account).read(serverURL: Fixture.server, path: Fixture.path) == nil)
        #expect(PendingAccountWipes.persisted(in: defaults).accounts().isEmpty)
    }

    @Test("listing the same account twice keeps one entry")
    func pendingListHasNoDuplicates() {
        let pending = PendingAccountWipes.inMemory()
        pending.add(Fixture.account)
        pending.add(Fixture.account)
        pending.add(Fixture.otherAccount)

        #expect(pending.accounts() == [Fixture.account, Fixture.otherAccount])
    }
}
