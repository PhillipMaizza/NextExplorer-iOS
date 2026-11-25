import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseFolderSortTests {
    private enum Constants {
        static let newestFirst = FolderSort(field: BrowseFeature.SortOption.dateModified.rawValue, isAscending: false)
        static let largestFirst = FolderSort(field: BrowseFeature.SortOption.size.rawValue, isAscending: false)
        static let customColumn = FolderSort(field: "bitrate", isAscending: false)
    }

    private func folder(saved: [String: FolderSort]? = nil) -> BrowseFeature.State {
        let state = BrowseFixtures.state(TestPath.documentsWork)
        state.$preferences.withLock { $0.folderSorts = saved }
        return state
    }

    @Test("A folder opens in the sort saved for it, wherever it was set")
    func aFolderOpensInItsSavedSort() {
        let state = folder(saved: [TestPath.documentsWork: Constants.newestFirst])

        #expect(state.sortOption == .dateModified)
        #expect(state.sortDirection == .descending)
    }

    @Test("A folder with no saved sort, or one this app cannot show, opens in the default sort")
    func aFolderWithoutAUsableSortOpensInTheDefault() {
        for saved in [nil, [TestPath.documentsWork: Constants.customColumn]] {
            let state = folder(saved: saved)
            state.$defaultSortOption.withLock { $0 = .size }
            state.$defaultSortDirection.withLock { $0 = .descending }

            #expect(state.sortOption == .size)
            #expect(state.sortDirection == .descending)
        }
    }

    @Test("Changing the sort applies at once, saves it for the folder and keeps what the server stored")
    func changingTheSortSavesItForTheFolder() async {
        let sent = LockIsolated<[String]>([])
        let state = folder(saved: [:])
        state.$defaultSortDirection.withLock { $0 = .descending }
        let store = BrowseFixtures.store(state) {
            $0.filesClient.saveFolderSort = { _, path, sort in
                sent.withValue { $0.append(path) }
                #expect(sort == Constants.largestFirst)
                return Constants.largestFirst
            }
        }

        await store.send(.sortOptionChanged(.size)) {
            $0.$preferences.withLock { $0.folderSorts = [TestPath.documentsWork: Constants.largestFirst] }
        }
        await store.receive(\.folderSortSaved)

        #expect(store.state.sortOption == .size)
        #expect(sent.value == [TestPath.documentsWork])
    }

    @Test("A sort the server could not save still applies on screen")
    func aFailedSaveKeepsTheSortOnScreen() async {
        let store = BrowseFixtures.store(folder()) {
            $0.filesClient.saveFolderSort = { _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.sortDirectionChanged(.descending)) {
            $0.$preferences.withLock {
                $0.folderSorts = [TestPath.documentsWork: FolderSort(
                    field: BrowseFeature.SortOption.name.rawValue,
                    isAscending: false
                )]
            }
        }
        await store.finish()

        #expect(store.state.sortDirection == .descending)
    }

    @Test("The root cannot be saved on the server, so its sort stays on its own screen")
    func theRootKeepsItsSortOnScreen() async {
        let store = BrowseFixtures.store(BrowseFixtures.state())

        await store.send(.sortOptionChanged(.kind)) {
            $0.rootSort = FolderSort(field: BrowseFeature.SortOption.kind.rawValue, isAscending: true)
        }

        #expect(store.state.sortOption == .kind)
        #expect(store.state.preferences.folderSorts == nil)
    }
}
