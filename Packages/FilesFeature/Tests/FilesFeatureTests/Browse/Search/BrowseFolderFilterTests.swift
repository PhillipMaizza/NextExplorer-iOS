import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The kind filter over a folder's own items: when its chips are offered and how a pick narrows the
/// folder.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseFolderFilterTests {
    private let folder = BrowseFixtures.folder(TestFolder.photos)
    private let photo = BrowseFixtures.file(TestFile.photo)
    private let report = BrowseFixtures.file(TestFile.report)

    private func state(_ items: [FileItem]) -> BrowseFeature.State {
        BrowseFixtures.state("", title: TestFolder.files, items: items)
    }

    @Test("A folder holding several kinds offers each, in display order")
    func severalKindsAreOffered() {
        #expect(state([report, folder, photo]).availableFolderCategories == [.folder, .image, .document])
    }

    @Test("An empty folder, or one holding a single kind, offers no filter")
    func oneKindOrNothingOffersNoFilter() {
        #expect(state([]).availableFolderCategories.isEmpty)
        #expect(state([folder]).availableFolderCategories.isEmpty)
    }

    @Test("Picking a kind narrows the folder, and All shows everything again")
    func pickingAKindNarrowsTheFolder() async {
        let store = BrowseFixtures.store(state([folder, photo, report]))

        await store.send(.folderCategoryToggled(.image)) {
            $0.selectedFolderCategories = [.image]
        }
        #expect(store.state.displayedItems.map(\.id) == [photo.id])
        #expect(store.state.displayedItemCount == 1)

        await store.send(.folderFilterCleared) {
            $0.selectedFolderCategories = []
        }
        #expect(store.state.displayedItemCount == 3)
    }

    @Test("A picked kind the folder no longer holds is ignored rather than emptying the list")
    func aKindNoLongerPresentIsIgnored() {
        var state = state([folder, report])
        state.selectedFolderCategories = [.image]

        #expect(state.displayedItems.count == 2)
        #expect(state.hasDisplayedItems)
    }
}
