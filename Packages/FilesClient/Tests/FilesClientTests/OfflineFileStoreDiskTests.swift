import CoreModels
@testable import FilesClient
import Foundation
import Testing
import TestUtils

/// The durable offline store on disk, one unique account scope per test so nothing is shared and the process wide scope
/// is never touched.
/// `removeAll` is deliberately not exercised: it wipes every account's directory and would race the other suites.
@Suite("Offline file store on disk")
struct OfflineFileStoreDiskTests {
    private enum Constants {
        static let scopePrefix = "offline-disk-"
        static let sourcePrefix = "offline-disk-src-"
        static let docs = "Docs"
        static let docsSibling = "Docs2"
        static let docsSub = "Docs/sub"
        static let staleSizeDelta: Int64 = 1
        static let docsFile = "Docs/a.txt"
        static let cText = "c.txt"
    }

    private func makeScope() -> String {
        "\(Constants.scopePrefix)\(TestID.name())"
    }

    @discardableResult
    private func seed(
        _ name: String,
        in folder: String,
        bytes: Int,
        scope: String,
        modified: Date = MockDate.date
    ) throws -> FileItem {
        let item = FileItem(name: name, path: folder, dateModified: modified, size: Int64(bytes), kind: TestKind.text)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.sourcePrefix)\(TestID.name())")
        try Data(repeating: 0x61, count: bytes).write(to: source)
        _ = try OfflineCache.store(downloadedURL: source, item: item, scope: scope)
        return item
    }

    private func root(_ path: String, isDirectory: Bool = true) -> OfflinePinnedRoot {
        OfflinePinnedRoot(path: path, isDirectory: isDirectory)
    }

    // MARK: sizes

    @Test
    func totalSizeCountsOnlyTheDownloadedFilesNotTheSidecars() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        try seed(TestFile.bText, in: Constants.docsSub, bytes: 5, scope: scope)

        #expect(store.pinned(to: scope).totalSizeBytes() == 8)
    }

    @Test
    func totalSizeOfAnAccountWithNothingStoredIsZero() {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }

        #expect(store.pinned(to: scope).totalSizeBytes() == 0)
    }

    @Test
    func aSlotWithoutAPathSidecarIsNotCounted() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let item = FileItem(
            name: TestFile.aText,
            path: Constants.docs,
            dateModified: MockDate.date,
            size: 4,
            kind: TestKind.text
        )
        let slot = try #require(OfflineCache.slot(for: item, create: true, scope: scope))
        try FileManager.default.createDirectory(at: slot.directory, withIntermediateDirectories: true)
        try Data(repeating: 0x61, count: 4).write(to: slot.fileURL)

        #expect(store.pinned(to: scope).totalSizeBytes() == 0)
    }

    @Test
    func rootUsageSumsTheFilesBelowEachRootAndNotASiblingWithTheSamePrefix() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        try seed(TestFile.bText, in: Constants.docsSub, bytes: 5, scope: scope)
        try seed(Constants.cText, in: Constants.docsSibling, bytes: 7, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs), root(Constants.docsSibling), root(TestFolder.photos)])

        let usages = pinned.pinnedRootUsages()

        #expect(usages.map(\.root.path) == [Constants.docs, Constants.docsSibling, TestFolder.photos])
        #expect(usages.map(\.sizeBytes) == [8, 7, 0])
        #expect(usages.map(\.id) == [Constants.docs, Constants.docsSibling, TestFolder.photos])
    }

    @Test
    func aPinnedFileRootIsSizedByItsOwnSlot() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        try seed("ab.txt", in: Constants.docs, bytes: 9, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docsFile, isDirectory: false)])

        #expect(pinned.pinnedRootUsages().map(\.sizeBytes) == [3])
    }

    // MARK: manifest

    @Test
    func pinnedRootsRoundTripInOrderAndAreReplacedWholesale() {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let pinned = store.pinned(to: scope)
        let first = [root(Constants.docs), root(Constants.docsFile, isDirectory: false)]

        pinned.setPinnedRoots(first)
        #expect(pinned.pinnedRoots() == first)

        pinned.setPinnedRoots([root(TestFolder.photos)])
        #expect(pinned.pinnedRoots() == [root(TestFolder.photos)])

        pinned.setPinnedRoots([])
        #expect(pinned.pinnedRoots().isEmpty)
    }

    @Test
    func aLegacyManifestOfBarePathsInfersFolderOrFileFromTheSlot() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let scopeDirectory = try #require(OfflineCache.scopeDirectory(create: true, scope: scope))
        try FilesClientFixture.offlineLegacyManifest.data()
            .write(to: scopeDirectory.appendingPathComponent(OfflineCache.manifestFileName))

        #expect(store.pinned(to: scope).pinnedRoots() == [
            root(Constants.docsFile, isDirectory: false),
            root(Constants.docs),
        ])
    }

    @Test
    func aCorruptManifestReadsAsNothingPinned() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let scopeDirectory = try #require(OfflineCache.scopeDirectory(create: true, scope: scope))
        try FilesClientFixture.offlineCorruptManifest.data()
            .write(to: scopeDirectory.appendingPathComponent(OfflineCache.manifestFileName))

        #expect(store.pinned(to: scope).pinnedRoots().isEmpty)
    }

    // MARK: reconcile and unpinning

    @Test
    func reconcileDropsSlotsNoPinnedRootCoversAndKeepsTheCoveredOnes() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let kept = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let sibling = try seed(Constants.cText, in: Constants.docsSibling, bytes: 7, scope: scope)
        let orphan = try seed(TestFile.photo, in: TestFolder.photos, bytes: 5, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs)])

        pinned.reconcile(nil)

        #expect(pinned.localURL(kept) != nil)
        #expect(pinned.localURL(sibling) == nil)
        #expect(pinned.localURL(orphan) == nil)
        #expect(pinned.totalSizeBytes() == 3)
    }

    @Test
    func reconcileWithAFreshListingAlsoDropsFilesTheServerNoLongerHas() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let stillThere = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let deleted = try seed(TestFile.bText, in: Constants.docsSub, bytes: 5, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs)])

        pinned.reconcile([stillThere.id])

        #expect(pinned.localURL(stillThere) != nil)
        #expect(pinned.localURL(deleted) == nil)
    }

    @Test
    func reconcileWithAnEmptyFreshListingDropsEveryCoveredFile() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let item = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs)])

        pinned.reconcile([])

        #expect(pinned.localURL(item) == nil)
        #expect(pinned.pinnedRoots() == [root(Constants.docs)])
    }

    @Test
    func removeRootUnpinsItFreesItsFilesAndKeepsTheOtherRoots() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let removed = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let kept = try seed(Constants.cText, in: Constants.docsSibling, bytes: 7, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs), root(Constants.docsSibling)])
        _ = pinned.recordMissingRoot(Constants.docs)

        pinned.removeRoot(Constants.docs)

        #expect(pinned.pinnedRoots() == [root(Constants.docsSibling)])
        #expect(pinned.localURL(removed) == nil)
        #expect(pinned.localURL(kept) != nil)
        #expect(pinned.recordMissingRoot(Constants.docs) == 1)
    }

    @Test
    func removeRootKeepsFilesAnotherPinnedRootStillCovers() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let direct = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let nested = try seed(TestFile.bText, in: Constants.docsSub, bytes: 5, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs), root(Constants.docsSub)])

        pinned.removeRoot(Constants.docs)

        #expect(pinned.localURL(direct) == nil)
        #expect(pinned.localURL(nested) != nil)
        #expect(pinned.totalSizeBytes() == 5)
    }

    // MARK: freshness

    @Test
    func theStrictLookupRefusesAStaleCopyButTheLenientOneStillServesIt() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let item = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let changedOnServer = FileItem(
            name: item.name, path: item.path, dateModified: item.dateModified,
            size: item.size + Constants.staleSizeDelta, kind: item.kind
        )
        let pinned = store.pinned(to: scope)

        #expect(pinned.localURL(item) != nil)
        #expect(pinned.localURL(changedOnServer) == nil)
        #expect(pinned.localURLIgnoringStaleness(changedOnServer) == pinned.localURL(item))
        #expect(pinned.localFileSize(item.id) == 3)
    }

    @Test
    func downloadingAFileAgainReplacesTheEarlierCopyAndItsFreshnessMarker() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let first = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope, modified: MockDate.date)
        let second = try seed(
            TestFile.aText,
            in: Constants.docs,
            bytes: 6,
            scope: scope,
            modified: MockDate.date.addingTimeInterval(60)
        )
        let pinned = store.pinned(to: scope)

        #expect(pinned.localURL(first) == nil)
        #expect(pinned.localURL(second) != nil)
        #expect(pinned.localFileSize(second.id) == 6)
        #expect(pinned.totalSizeBytes() == 6)
    }

    // MARK: flags

    @Test
    func theInterruptedMarkerIsSetClearedAndKeptPerAccount() {
        let scope = makeScope()
        let other = makeScope()
        let store = OfflineFileStore.liveValue
        defer {
            store.removeAccount(scope)
            store.removeAccount(other)
        }
        let pinned = store.pinned(to: scope)
        #expect(!pinned.wasInterrupted())

        pinned.setInterrupted(true)
        #expect(pinned.wasInterrupted())
        #expect(!store.pinned(to: other).wasInterrupted())

        pinned.setInterrupted(false)
        #expect(!pinned.wasInterrupted())

        pinned.setInterrupted(false)
        #expect(!pinned.wasInterrupted())
    }

    @Test
    func theLastAutoSyncTimeIsNilUntilSetThenRoundTripsPerAccount() {
        let scope = makeScope()
        let other = makeScope()
        let store = OfflineFileStore.liveValue
        defer {
            store.removeAccount(scope)
            store.removeAccount(other)
        }
        let pinned = store.pinned(to: scope)
        #expect(pinned.lastAutoSyncAt() == nil)

        pinned.setLastAutoSyncAt(MockDate.date)
        #expect(pinned.lastAutoSyncAt() == MockDate.date)
        #expect(store.pinned(to: other).lastAutoSyncAt() == nil)

        pinned.setLastAutoSyncAt(MockDate.date.addingTimeInterval(3_600))
        #expect(pinned.lastAutoSyncAt() == MockDate.date.addingTimeInterval(3_600))
    }

    // MARK: wiping

    @Test
    func removingTheCurrentAccountWipesItsFilesManifestAndFlagsButNotAnotherAccounts() throws {
        let scope = makeScope()
        let other = makeScope()
        let store = OfflineFileStore.liveValue
        defer {
            store.removeAccount(scope)
            store.removeAccount(other)
        }
        let mine = try seed(TestFile.aText, in: Constants.docs, bytes: 3, scope: scope)
        let theirs = try seed(TestFile.aText, in: Constants.docs, bytes: 4, scope: other)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([root(Constants.docs)])
        pinned.setInterrupted(true)
        store.pinned(to: other).setPinnedRoots([root(Constants.docs)])

        pinned.removeCurrentAccount()

        #expect(pinned.localURL(mine) == nil)
        #expect(pinned.pinnedRoots().isEmpty)
        #expect(!pinned.wasInterrupted())
        #expect(pinned.totalSizeBytes() == 0)
        #expect(store.pinned(to: other).localURL(theirs) != nil)
        #expect(store.pinned(to: other).pinnedRoots() == [root(Constants.docs)])
    }
}
