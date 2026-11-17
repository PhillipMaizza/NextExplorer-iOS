import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// A screen pushed from the Offline tab offers only what works on files kept on the device: its
/// access is narrowed when a listing lands, so writes, deletes and uploads are not offered there.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseKeptOfflineTests {
    private enum Constants {
        /// `BrowseTestSupport.fullAccess` with everything that changes the server taken away.
        static let keptOfflineAccess = FileAccess(
            canRead: true,
            canWrite: false,
            canUpload: false,
            canDelete: false,
            canShare: true,
            canDownload: true,
            canCreateFolder: false,
            canCreateFile: false
        )
    }

    private func emptyListing() -> BrowseResult {
        BrowseResult(items: [], access: BrowseTestSupport.fullAccess, path: TestPath.docsLowercase)
    }

    @Test("A listing on an offline screen keeps reading, sharing and saving, and drops every write")
    func anOfflineScreenNarrowsTheAccess() async {
        var state = BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)
        state.isKeptOffline = true
        let store = BrowseFixtures.store(state)

        await store.send(.itemsResponse(.success(emptyListing()))) {
            $0.phase = .loaded
            $0.access = Constants.keptOfflineAccess
        }
    }

    @Test("A listing on any other screen keeps the server's access")
    func anOrdinaryScreenKeepsTheServersAccess() async {
        let store = BrowseFixtures.store(BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs))

        await store.send(.itemsResponse(.success(emptyListing()))) {
            $0.phase = .loaded
            $0.access = BrowseTestSupport.fullAccess
        }
    }

    @Test("A screen pushed for a folder carries the offline mark only when asked")
    func navigationMarksOfflineScreens() {
        let folder = BrowseFixtures.folder(TestFolder.photos, in: "")

        #expect(BrowseNavigation.screen(for: folder, serverURL: BrowseTestSupport.serverURL, isKeptOffline: true)
            .isKeptOffline)
        #expect(!BrowseNavigation.screen(for: folder, serverURL: BrowseTestSupport.serverURL).isKeptOffline)
    }

    private let keptPhoto = BrowseFixtures.file(TestFile.aPhoto, in: TestPath.docsLowercase, size: 1)
    private let savedNotes = BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 1)

    private func listing(_ items: [FileItem], access: FileAccess = BrowseTestSupport.fullAccess) -> CachedDirectory {
        CachedDirectory(path: TestPath.docsLowercase, items: items, access: access, fetchedAt: MockDate.date)
    }

    @Test("An offline screen lists what is kept on the device, with no request")
    func anOfflineScreenListsFromTheDevice() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestPath.docsLowercase, isDirectory: true)])
        offline.saveListing(listing([keptPhoto]))
        var state = BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)
        state.isKeptOffline = true
        let store = BrowseFixtures.store(state) { $0.offlineFileStore = offline }

        await store.send(.refreshButtonTapped) { $0.phase = .loading }
        await store.receive(\.keptListingResolved) {
            $0.phase = .loaded
            $0.items = [keptPhoto]
            $0.access = Constants.keptOfflineAccess
        }
        await store.receive(\.offlineAvailabilityComputed) { $0.offlineItemIDs = [keptPhoto.id] }
    }

    @Test("An offline screen leaves out what was taken off inside the pinned folder")
    func anOfflineScreenLeavesOutWhatWasTakenOff() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([
            OfflinePinnedRoot(path: TestPath.docsLowercase, isDirectory: true, excludedPaths: [savedNotes.id]),
        ])
        offline.saveListing(listing([keptPhoto, savedNotes]))
        var state = BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)
        state.isKeptOffline = true
        let store = BrowseFixtures.store(state) { $0.offlineFileStore = offline }

        await store.send(.refreshButtonTapped) { $0.phase = .loading }
        await store.receive(\.keptListingResolved) {
            $0.phase = .loaded
            $0.items = [keptPhoto]
            $0.access = Constants.keptOfflineAccess
        }
        await store.receive(\.offlineAvailabilityComputed) { $0.offlineItemIDs = [keptPhoto.id] }
    }

    @Test("With no network, a saved copy shows with the kept files it lacks, and only offline actions")
    func aSavedCopyMergesTheKeptFiles() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestPath.docsLowercase, isDirectory: true)])
        offline.saveListing(listing([keptPhoto, savedNotes]))
        let store = BrowseFixtures.store(BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)) {
            $0.offlineFileStore = offline
            let saved = listing([savedNotes])
            $0.directoryCacheStore.read = { _, _ in saved }
        }

        await store.send(.itemsResponse(.failure(.offline)))
        await store.receive(\.offlineListingResolved) {
            $0.phase = .loaded
            $0.items = [keptPhoto, savedNotes]
            $0.access = Constants.keptOfflineAccess
            $0.dataSource = .cached(fetchedAt: MockDate.date)
        }
        await store.receive(\.offlineAvailabilityComputed) { $0.offlineItemIDs = [keptPhoto.id, savedNotes.id] }
    }

    @Test("Share hands the kept copies of the picked files to the share sheet, leaving folders out")
    func shareHandsTheKeptCopiesOver() async {
        let copy = URL(fileURLWithPath: "/kept/\(TestFile.aPhoto)")
        let folder = BrowseFixtures.folder(TestFolder.photos, in: TestPath.docsLowercase)
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [keptPhoto, folder])
        state.isSelecting = true
        state.selectedItemIDs = [keptPhoto.id, folder.id]
        let store = BrowseFixtures.store(state) { $0.offlineFileStore = .inMemory(localURLs: [keptPhoto.id: copy]) }

        await store.send(.keptShareTapped([keptPhoto, folder]))
        await store.receive(\.keptShareResolved) {
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.keptShare = KeptFilesShare(urls: [copy])
        }
        await store.send(.keptShareDismissed) { $0.keptShare = nil }
    }

    @Test("Share with no kept copy found keeps the selection and says the files are not on the device yet")
    func shareWithNoCopyKeepsTheSelection() async {
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [keptPhoto])
        state.isSelecting = true
        state.selectedItemIDs = [keptPhoto.id]
        let store = BrowseFixtures.store(state) { $0.offlineFileStore = .inMemory() }

        await store.send(.keptShareTapped([keptPhoto]))
        await store.receive(\.keptShareResolved) { $0.fileActionErrorMessage = L10n.Offline.shareNotKept }
    }

    @Test("A saved listing and the kept one merge, the saved entry winning for a file in both")
    func mergingKeepsTheSavedEntry() {
        let saved = listing([savedNotes])
        let kept = listing([keptPhoto, BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 9)])

        #expect(CachedDirectory.merging(saved: saved, kept: kept)?.items == [savedNotes, keptPhoto])
        #expect(CachedDirectory.merging(saved: saved, kept: nil) == saved)
        #expect(CachedDirectory.merging(saved: nil, kept: kept) == kept)
        #expect(CachedDirectory.merging(saved: nil, kept: nil) == nil)
    }
}
