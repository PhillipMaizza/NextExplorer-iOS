import CoreModels
@testable import FilesClient
import Foundation
import Testing
import TestUtils

/// The pinned roots and run markers answer from memory and reach the disk behind, in order, and a
/// removal is never undone by a write queued before it.
@Suite("Offline manifest kept in memory")
struct OfflineManifestStateTests {
    private enum Constants {
        static let scopePrefix = "offline-manifest-"
        static let docs = "Docs"
    }

    private let store = OfflineFileStore.liveValue
    private let roots = [OfflinePinnedRoot(path: Constants.docs, isDirectory: true)]

    private func makeScope() -> String {
        "\(Constants.scopePrefix)\(TestID.name())"
    }

    private func fileURL(_ name: String, scope: String) throws -> URL {
        try #require(OfflineCache.scopeDirectory(create: false, scope: scope)).appendingPathComponent(name)
    }

    @Test
    func changesReachTheDiskInTheOrderTheyWereMade() throws {
        let scope = makeScope()
        defer { store.removeAccount(scope) }
        let pinned = store.pinned(to: scope)

        pinned.setPinnedRoots(roots)
        pinned.setInterrupted(true)
        pinned.setInterrupted(false)
        pinned.setLastAutoSyncAt(MockDate.date)
        OfflineManifestState.shared.flush()

        let manifest = try Data(contentsOf: fileURL(OfflineCache.manifestFileName, scope: scope))
        #expect(try JSONDecoder().decode([OfflinePinnedRoot].self, from: manifest) == roots)
        let interrupted = try fileURL(OfflineCache.interruptedFileName, scope: scope)
        #expect(!FileManager.default.fileExists(atPath: interrupted.path))
        let lastSync = try String(contentsOf: fileURL(OfflineCache.lastSyncFileName, scope: scope), encoding: .utf8)
        #expect(Double(lastSync) == MockDate.date.timeIntervalSince1970)
    }

    @Test
    func aRemovalIsNotUndoneByAWriteQueuedBeforeIt() throws {
        let scope = makeScope()
        defer { store.removeAccount(scope) }
        let pinned = store.pinned(to: scope)

        pinned.setPinnedRoots(roots)
        pinned.setInterrupted(true)
        store.removeAccount(scope)
        OfflineManifestState.shared.flush()

        let directory = try #require(OfflineCache.scopeDirectory(create: false, scope: scope))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(pinned.pinnedRoots().isEmpty)
        #expect(!pinned.wasInterrupted())
    }
}
