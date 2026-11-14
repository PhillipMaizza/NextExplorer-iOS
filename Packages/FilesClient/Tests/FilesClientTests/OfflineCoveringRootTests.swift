import CoreModels
@testable import FilesClient
import Testing
import TestUtils

/// The pinned folder that keeps a path on the device.
struct OfflineCoveringRootTests {
    private enum Constants {
        static let trips = "Docs/Trips"
        static let tripsPhoto = "Docs/Trips/a.jpg"
        static let siblingPhoto = "Docs/Trips2/a.jpg"
    }

    private func store(_ roots: [OfflinePinnedRoot]) -> OfflineFileStore {
        let store = OfflineFileStore.inMemory()
        store.setPinnedRoots(roots)
        return store
    }

    @Test("The nearest of two pinned folders around a path keeps it")
    func theNearestFolderWins() {
        let store = store([
            OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true),
            OfflinePinnedRoot(path: Constants.trips, isDirectory: true),
        ])

        #expect(store.coveringRoot(of: Constants.tripsPhoto) == Constants.trips)
    }

    @Test("A pinned file keeps nothing below it")
    func aPinnedFileCoversNothing() {
        let store = store([OfflinePinnedRoot(path: Constants.trips, isDirectory: false)])

        #expect(store.coveringRoot(of: Constants.tripsPhoto) == nil)
    }

    @Test("A folder that only shares a name prefix does not keep the path")
    func aSiblingPrefixIsNotCovered() {
        let store = store([OfflinePinnedRoot(path: Constants.trips, isDirectory: true)])

        #expect(store.coveringRoot(of: Constants.siblingPhoto) == nil)
    }

    @Test("A pinned folder does not cover itself")
    func aFolderDoesNotCoverItself() {
        let store = store([OfflinePinnedRoot(path: Constants.trips, isDirectory: true)])

        #expect(store.coveringRoot(of: Constants.trips) == nil)
    }

    @Test("With nothing pinned nothing is covered")
    func nothingPinnedCoversNothing() {
        #expect(store([]).coveringRoot(of: Constants.tripsPhoto) == nil)
    }
}
