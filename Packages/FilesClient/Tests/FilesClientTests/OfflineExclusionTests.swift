import CoreModels
@testable import FilesClient
import Foundation
import Testing
import TestUtils

/// A file or folder inside a pinned folder taken off the device on its own: the folder stays pinned
/// and keeps everything else, the item's copy goes.
@Suite("Offline exclusions")
struct OfflineExclusionTests {
    private enum Constants {
        static let scopePrefix = "offline-exclusion-"
        static let sourcePrefix = "offline-exclusion-src-"
        static let docs = "Docs"
        static let trips = "Docs/Trips"
        static let docsFile = "Docs/\(TestFile.aText)"
        static let tripsFile = "Docs/Trips/\(TestFile.bText)"
        static let fileBytes = 3
    }

    private func makeScope() -> String {
        "\(Constants.scopePrefix)\(TestID.name())"
    }

    private func seed(_ name: String, in folder: String, scope: String) throws -> FileItem {
        let item = FileItem(
            name: name,
            path: folder,
            dateModified: MockDate.date,
            size: Int64(Constants.fileBytes),
            kind: TestKind.text
        )
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.sourcePrefix)\(TestID.name())")
        try Data(repeating: 0x61, count: Constants.fileBytes).write(to: source)
        _ = try OfflineCache.store(downloadedURL: source, item: item, scope: scope)
        return item
    }

    private func folder(_ path: String, excluding excluded: [String] = []) -> OfflinePinnedRoot {
        OfflinePinnedRoot(path: path, isDirectory: true, excludedPaths: excluded)
    }

    // MARK: on disk

    @Test("Taking a file inside a pinned folder off frees its copy and keeps the folder and its other files")
    func aFileComesOffAlone() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let removed = try seed(TestFile.aText, in: Constants.docs, scope: scope)
        let kept = try seed(TestFile.bText, in: Constants.trips, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([folder(Constants.docs)])

        pinned.removeRoot(Constants.docsFile)

        #expect(pinned.pinnedRoots() == [folder(Constants.docs, excluding: [Constants.docsFile])])
        #expect(pinned.localURL(removed) == nil)
        #expect(pinned.localURL(kept) != nil)
    }

    @Test("Taking a subfolder off frees everything below it, and its kept listing")
    func aSubfolderComesOffWithEverythingBelow() throws {
        let scope = makeScope()
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let removed = try seed(TestFile.bText, in: Constants.trips, scope: scope)
        let kept = try seed(TestFile.aText, in: Constants.docs, scope: scope)
        let pinned = store.pinned(to: scope)
        pinned.setPinnedRoots([folder(Constants.docs)])
        pinned.saveListing(CachedDirectory(
            path: Constants.trips,
            items: [removed],
            access: FileAccess(
                canRead: true,
                canWrite: false,
                canUpload: false,
                canDelete: false,
                canShare: false,
                canDownload: true
            ),
            fetchedAt: MockDate.date
        ))

        pinned.removeRoot(Constants.trips)

        #expect(pinned.localURL(removed) == nil)
        #expect(pinned.localURL(kept) != nil)
        #expect(pinned.listing(Constants.trips) == nil)
        #expect(pinned.pinnedRootUsages().map(\.sizeBytes) == [Int64(Constants.fileBytes)])
    }

    @Test("A manifest written before exclusions loads with none")
    func anOlderManifestLoads() throws {
        let data = try JSONSerialization.data(withJSONObject: [["path": Constants.docs, "isDirectory": true]])

        #expect(try JSONDecoder().decode([OfflinePinnedRoot].self, from: data) == [folder(Constants.docs)])
    }

    @Test("Exclusions survive a round trip through the manifest")
    func exclusionsRoundTrip() throws {
        let roots = [folder(Constants.docs, excluding: [Constants.trips])]

        #expect(try JSONDecoder().decode([OfflinePinnedRoot].self, from: JSONEncoder().encode(roots)) == roots)
    }

    // MARK: rules

    @Test("A pinned folder keeps what is below it except what was taken off and everything under that")
    func keepsHonorsExclusions() {
        let root = folder(Constants.docs, excluding: [Constants.trips])

        #expect(root.keeps(Constants.docs))
        #expect(root.keeps(Constants.docsFile))
        #expect(!root.keeps(Constants.trips))
        #expect(!root.keeps(Constants.tripsFile))
    }

    @Test("An item taken off has no pinned folder covering it any more")
    func anExcludedItemHasNoCoveringRoot() {
        let roots = [folder(Constants.docs, excluding: [Constants.trips])]

        #expect(roots.coveringRoot(of: Constants.tripsFile) == nil)
        #expect(roots.coveringRoot(of: Constants.docsFile)?.path == Constants.docs)
    }

    @Test("A file pinned on its own inside a folder taken off stays kept")
    func aPinnedFileInsideAnExcludedFolderStaysKept() {
        let roots = [
            folder(Constants.docs, excluding: [Constants.trips]),
            OfflinePinnedRoot(path: Constants.tripsFile, isDirectory: false),
        ]

        #expect(roots.keeps(Constants.tripsFile))
    }

    @Test("Taking off a pinned file inside a pinned folder unpins it and leaves it out of the folder")
    func takingOffANestedPinUnpinsAndExcludes() {
        let roots = [folder(Constants.docs), OfflinePinnedRoot(path: Constants.docsFile, isDirectory: false)]

        #expect(roots.takingOff(Constants.docsFile) == [folder(Constants.docs, excluding: [Constants.docsFile])])
    }

    @Test("Taking off a pinned folder only unpins it")
    func takingOffAFolderUnpinsIt() {
        #expect([folder(Constants.docs)].takingOff(Constants.docs).isEmpty)
    }

    @Test("Taking off what no pin keeps changes nothing")
    func takingOffSomethingNotKeptChangesNothing() {
        let roots = [folder(Constants.docs, excluding: [Constants.trips])]

        #expect(roots.takingOff(Constants.tripsFile) == roots)
    }
}
