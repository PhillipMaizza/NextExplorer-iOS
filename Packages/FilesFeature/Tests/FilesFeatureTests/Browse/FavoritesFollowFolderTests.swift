import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@MainActor
@Suite(.isolatedDependencies)
struct FavoritesFollowFolderTests {
    private let docs = FileItem(
        name: TestFolder.docs,
        path: TestFolder.files,
        dateModified: MockDate.date,
        size: 0,
        kind: FileItem.directoryKind
    )
    private let renamedDocs = FileItem(
        name: TestFolder.archive,
        path: TestFolder.files,
        dateModified: MockDate.date,
        size: 0,
        kind: FileItem.directoryKind
    )
    private let documents = FileItem(
        name: TestFolder.documents,
        path: TestFolder.files,
        dateModified: MockDate.date,
        size: 0,
        kind: FileItem.directoryKind
    )

    private var nestedFavorite: String {
        "\(docs.id)/\(TestFolder.photos)"
    }

    private func makeStore(favorites: Set<String>) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFeature.State(
            serverURL: TestHost.serverURL,
            directoryPath: TestFolder.files,
            title: TestFolder.files
        )
        state.items = [docs, documents]
        state.phase = .loaded
        state.favoritePaths = favorites
        state.hasLoadedFavorites = true
        return TestStore(initialState: state) {
            BrowseFeature()
        }
    }

    @Test("Renaming a favorite folder moves its star and the stars under it, and refreshes Favorites")
    func renameRepointsFavorites() async {
        let store = makeStore(favorites: [docs.id, nestedFavorite, documents.id])

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(
            originalID: docs.id,
            renamed: renamedDocs
        )))) {
            $0.items = [renamedDocs, documents]
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamedDocs, previousName: TestFolder.docs))] }
            $0.favoritePaths = [renamedDocs.id, "\(renamedDocs.id)/\(TestFolder.photos)", documents.id]
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test("Renaming a folder with no favorite in it leaves Favorites alone")
    func renameWithoutFavoritesStaysQuiet() async {
        let store = makeStore(favorites: [documents.id])

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(
            originalID: docs.id,
            renamed: renamedDocs
        )))) {
            $0.items = [renamedDocs, documents]
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamedDocs, previousName: TestFolder.docs))] }
        }
    }

    @Test("Deleting the folder that holds a favorite drops its star and refreshes Favorites")
    func deletingParentDropsNestedFavorite() async {
        let store = makeStore(favorites: [nestedFavorite, documents.id])

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(removedIDs: [docs.id])))) {
            $0.items = [documents]
            $0.favoritePaths = [documents.id]
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test("Undoing a folder rename or move refreshes Favorites; undoing a copy does not")
    func undoOfFolderRelocationRefreshesFavorites() {
        #expect(FileUndoEntry(.renamed(renamedDocs, previousName: TestFolder.docs)).isFolderRelocation)
        #expect(FileUndoEntry(.moved([.init(item: docs, originalParent: TestFolder.files)])).isFolderRelocation)
        #expect(!FileUndoEntry(.created([docs])).isFolderRelocation)
    }
}
