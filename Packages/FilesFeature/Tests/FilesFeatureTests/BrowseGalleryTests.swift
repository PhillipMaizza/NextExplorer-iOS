import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The gallery pages through every file of a folder: which files it holds, which viewer each file
/// gets, when the cover may present, and handing a text file to the editor and back.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseGalleryTests {
    private enum Constants {
        static let installer = "installer.dmg"
        static let pointer = "plan.gdoc"
        static let notesText = "Gallery notes"
    }

    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestFolder.docs)
    private let notes = BrowseFixtures.file(TestFile.notes, in: TestFolder.docs)
    private let report = BrowseFixtures.file(TestFile.report, in: TestFolder.docs)
    private let pointer = BrowseFixtures.file(Constants.pointer, in: TestFolder.docs)
    private let folder = BrowseFixtures.folder(TestFolder.photos, in: TestFolder.docs)

    private func galleryState(previewing item: FileItem) -> BrowseFeature.State {
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [folder, photo, notes, pointer, report])
        state.previewItem = item
        return state
    }

    // MARK: Pages

    @Test("The gallery holds every file in list order, without folders or Google Drive stubs")
    func theGalleryHoldsEveryFileInListOrder() {
        let state = galleryState(previewing: report)
        #expect(state.galleryItems(startingAt: report).map(\.name) == [
            TestFile.aPhoto,
            TestFile.notes,
            TestFile.report,
        ])
    }

    @Test("A file opened on its own pages alone")
    func aFileOpenedOnItsOwnPagesAlone() {
        let state = BrowseFeature.State.previewHost(
            for: report,
            serverURL: BrowseTestSupport.serverURL,
            folderTitle: TestFolder.docs
        )
        #expect(state.galleryItems(startingAt: report).map(\.name) == [TestFile.report])
    }

    @Test("A search hit from another folder pages alone, not through the folder on screen")
    func aSearchHitPagesAlone() async {
        let hit = FileItem(
            name: TestFile.vacationPhoto,
            path: TestFolder.photos,
            dateModified: MockDate.date,
            size: 0,
            kind: TestKind.photo
        )
        let listing = BrowseFixtures.loadedState(TestFolder.docs, items: [folder, photo, notes, pointer, report])
        let store = TestStore(initialState: listing) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.offlineFileStore = .inMemory()
        }
        await store.send(.searchResultTapped(SearchResultItem(
            name: hit.name,
            path: TestFolder.photos,
            kind: SearchResultItem.fileKind
        ))) {
            $0.isPreviewOutsideListing = true
        }
        await store.receive(.rowTapped(hit)) { $0.previewItem = hit }
        #expect(store.state.galleryItems(startingAt: hit).map(\.name) == [TestFile.vacationPhoto])

        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.isPreviewOutsideListing = false
        }
        #expect(store.state.galleryItems(startingAt: report).map(\.name) == [
            TestFile.aPhoto,
            TestFile.notes,
            TestFile.report,
        ])
    }

    @Test("A deleted file leaves the gallery, which moves on or closes when nothing is left")
    func aDeletedFileLeavesTheGallery() {
        var state = galleryState(previewing: notes)
        state.items.remove(id: notes.id)
        #expect(state.galleryItems(startingAt: notes).map(\.name) == [TestFile.aPhoto, TestFile.report])
        state.items.removeAll()
        #expect(state.galleryItems(startingAt: notes).isEmpty)
    }

    @Test("Each file gets the viewer of its kind")
    func eachFileGetsTheViewerOfItsKind() {
        #expect(PreviewKind(photo) == .image)
        #expect(PreviewKind(report) == .document)
        #expect(PreviewKind(notes) == .text)
        #expect(PreviewKind(BrowseFixtures.file(TestFile.clip)) == .media)
        #expect(PreviewKind(BrowseFixtures.file(TestFile.archive)) == .archive)
        #expect(PreviewKind(BrowseFixtures.file(Constants.installer)) == .unsupported)
    }

    // MARK: Presenting

    @Test("A document holds the cover until its file is fetched, an image opens at once")
    func aDocumentHoldsTheCoverUntilItsFileIsFetched() {
        var state = galleryState(previewing: report)
        #expect(!state.isPreviewContentReady)
        state.previewFileURL = URL(fileURLWithPath: TestFile.report)
        #expect(state.isPreviewContentReady)
        #expect(galleryState(previewing: photo).isPreviewContentReady)
    }

    @Test("Every file opens in the gallery, the editor only while editing")
    func everyFileOpensInTheGallery() {
        var state = galleryState(previewing: notes)
        #expect(!state.showsTextEditor)
        #if os(iOS)
            #expect(state.isPreviewInGallery)
        #else
            #expect(!state.isPreviewInGallery)
        #endif
        state.isPreviewEditing = true
        #expect(state.showsTextEditor)
        #expect(!state.isPreviewInGallery)
    }

    // MARK: Editing

    @Test("Edit makes the swiped to file the preview and reads it fresh for the editor")
    func editReadsTheSwipedToFileFresh() async {
        let store = BrowseFixtures.store(galleryState(previewing: report)) {
            $0.filesClient.fetchTextContent = { _, _ in Constants.notesText }
        }

        await store.send(.previewEditTapped(notes)) {
            $0.previewItem = notes
            $0.isPreviewEditing = true
            $0.textPhase = .loading
        }
        #expect(store.state.isPreviewContentReady)
        await store.receive(\.textContentResponse) {
            $0.textPhase = .loaded
            $0.textContent = Constants.notesText
        }
    }

    @Test("Closing the editor goes back to the gallery and keeps the text")
    func closingTheEditorGoesBackToTheGallery() async {
        var state = galleryState(previewing: notes)
        state.isPreviewEditing = true
        state.textContent = Constants.notesText
        state.textPhase = .loaded
        state.textSaveError = FilesClientError.changedOnServer.userMessage
        let store = BrowseFixtures.store(state)

        await store.send(.previewEditorClosed) {
            $0.isPreviewEditing = false
            $0.textSaveError = nil
        }
        #expect(store.state.previewItem == notes)
        #expect(!store.state.showsTextEditor)
    }

    @Test("Closing the cover while editing ends editing")
    func closingTheCoverWhileEditingEndsEditing() async {
        var state = galleryState(previewing: notes)
        state.isPreviewEditing = true
        state.textContent = Constants.notesText
        state.textPhase = .loaded
        let store = BrowseFixtures.store(state)

        await store.send(.previewDismissed) {
            $0.previewItem = nil
            $0.isPreviewEditing = false
            $0.textContent = nil
            $0.textPhase = .idle
        }
    }

    @Test("Opening another file from the list leaves the editor")
    func openingAnotherFileLeavesTheEditor() async {
        var state = galleryState(previewing: notes)
        state.isPreviewEditing = true
        let store = BrowseFixtures.store(state)

        await store.send(.rowTapped(photo)) {
            $0.previewItem = photo
            $0.isPreviewEditing = false
        }
    }
}
