import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// A finger slide in select mode on Browse, Favorites and the Offline tab.
@Suite(.isolatedDependencies)
@MainActor
struct SelectionSweepTests: FavoritesTestSupport {
    private enum Constants {
        static let firstID = "1"
        static let secondID = "2"
        static let goneID = "9"
        static let savedFolder = "/tmp/Downloads/"
        static let pinnedPath = TestFolder.documents
        static let gonePath = "/tmp/Downloads/gone.pdf"
    }

    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestPath.docsLowercase, size: 1)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestPath.docsLowercase, size: 1)
    private let report = BrowseFixtures.file(TestFile.report, in: TestPath.docsLowercase, size: 1)

    private var savedReport: LocalDownload {
        LocalDownload(
            url: URL(fileURLWithPath: Constants.savedFolder + TestFile.report),
            fileName: TestFile.report,
            size: 1,
            modifiedDate: MockDate.date
        )
    }

    private func favoritesState(isSelecting: Bool) -> FavoritesFeature.State {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [
            makeFavorite(id: Constants.firstID, path: TestFolder.documents),
            makeFavorite(id: Constants.secondID, path: TestFolder.photos, position: 1),
        ]
        state.isSelecting = isSelecting
        return state
    }

    @Test("A slide over favorites selects what it covered, keeping only favorites still listed")
    func favoritesSweep() async {
        let store = TestStore(initialState: favoritesState(isSelecting: true)) { FavoritesFeature() }

        await store.send(.selectionSwept([Constants.firstID, Constants.secondID, Constants.goneID])) {
            $0.selectedFavoriteIDs = [Constants.firstID, Constants.secondID]
        }
    }

    @Test("A slide that lands after Favorites left select mode changes nothing")
    func favoritesSweepOutsideSelectMode() async {
        let store = TestStore(initialState: favoritesState(isSelecting: false)) { FavoritesFeature() }

        await store.send(.selectionSwept([Constants.firstID]))
    }

    @Test("A slide over the Offline tab picks pinned items and saved files together")
    func offlineTabSweep() async {
        var state = OfflineTabFeature.State()
        state.downloads = [savedReport]
        state.isSelecting = true
        let store = TestStore(initialState: state) { OfflineTabFeature() }

        await store.send(.selectionSwept(
            pinnedPaths: [Constants.pinnedPath],
            downloadIDs: [savedReport.id, Constants.gonePath]
        )) {
            $0.selectedPinnedPaths = [Constants.pinnedPath]
            $0.selectedDownloadIDs = [savedReport.id]
        }
    }

    @Test("The tab's slide ids keep pinned items and saved files apart and split back exactly")
    func offlineTabSweepIDsRoundTrip() {
        let ids: Set<String> = [
            OfflineTabSweepID.pinned(Constants.pinnedPath),
            OfflineTabSweepID.download(savedReport.id),
        ]

        let split = OfflineTabSweepID.split(ids)

        #expect(split.pinnedPaths == [Constants.pinnedPath])
        #expect(split.downloadIDs == [savedReport.id])
        #expect(OfflineTabSweepID.pinned(Constants.pinnedPath) != OfflineTabSweepID.download(Constants.pinnedPath))
    }

    @Test("A slide over Browse sets the selection, keeping only what the listing still has")
    func aSlideSetsTheSelection() async {
        var state = BrowseFixtures.loadedState(TestPath.docsLowercase, items: [photo, notes])
        state.isSelecting = true
        let store = BrowseFixtures.store(state)

        await store.send(.selectionSwept([photo.id, notes.id, report.id])) {
            $0.selectedItemIDs = [photo.id, notes.id]
        }
    }

    @Test("A slide that lands after Browse left select mode changes nothing")
    func aSlideOutsideSelectModeIsIgnored() async {
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestPath.docsLowercase, items: [photo]))

        await store.send(.selectionSwept([photo.id]))
    }
}
