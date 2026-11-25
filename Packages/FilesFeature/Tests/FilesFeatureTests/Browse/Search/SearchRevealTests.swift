import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SearchRevealTests {
    private enum Constants {
        static let reportTerm = "report"
    }

    private let folder = BrowseFixtures.folder(TestFolder.photos)

    @Test("Show in Enclosing Folder selects and scrolls to the item without opening it")
    func selectRevealSelectsWithoutOpening() async {
        var state = BrowseFixtures.loadedState(items: [folder])
        state.reveal = .select(folder.id)
        let store = BrowseFixtures.store(state)

        await store.send(.revealItemShown(folder.id)) {
            $0.reveal = nil
            $0.scrollTargetID = folder.id
        }
        await store.receive(.tableSelectionChanged([folder.id])) {
            $0.selectedItemIDs = [folder.id]
        }
    }

    @Test("Revealing the same item again scrolls again, the first scroll cleared")
    func revealingTheSameItemTwiceScrollsAgain() async {
        var state = BrowseFixtures.loadedState(items: [folder])
        state.reveal = .select(folder.id)
        let store = BrowseFixtures.store(state)

        await store.send(.revealItemShown(folder.id)) {
            $0.reveal = nil
            $0.scrollTargetID = folder.id
        }
        await store.receive(.tableSelectionChanged([folder.id])) {
            $0.selectedItemIDs = [folder.id]
        }
        await store.send(.scrollTargetShown) { $0.scrollTargetID = nil }
    }

    @Test("Opening a search hit selects it, then opens it")
    func openRevealSelectsThenOpens() async {
        var state = BrowseFixtures.loadedState(items: [folder])
        state.reveal = .open(folder.id)
        let store = BrowseFixtures.store(state)

        await store.send(.revealItemShown(folder.id)) {
            $0.reveal = nil
            $0.scrollTargetID = folder.id
        }
        await store.receive(.tableSelectionChanged([folder.id])) {
            $0.selectedItemIDs = [folder.id]
        }
        await store.receive(.rowTapped(folder))
        await store.receive(.delegate(.openFolder(folder)))
    }

    @Test("A hit in the folder on screen is revealed there, the stack untouched")
    func revealInTheOpenFolderKeepsTheStack() async {
        var state = BrowseTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: BrowseTestSupport.serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))
        let screenID = state.path.ids[0]
        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(
            id: screenID,
            action: .delegate(.revealInFolder(
                path: TestFolder.photos,
                title: TestFolder.photos,
                itemID: TestFile.report
            ))
        ))) {
            $0.path[id: screenID]?.reveal = .select(TestFile.report)
        }
    }

    @Test("A hit in another folder opens on top, so Back returns to the search")
    func revealInAnotherFolderPushesIt() async {
        var state = BrowseTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: BrowseTestSupport.serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))
        let screenID = state.path.ids[0]
        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(
            id: screenID,
            action: .delegate(.revealInFolder(
                path: TestFolder.documents,
                title: TestFolder.documents,
                itemID: TestFile.report
            ))
        ))) {
            var documents = BrowseFeature.State(
                serverURL: BrowseTestSupport.serverURL,
                directoryPath: TestFolder.documents,
                title: TestFolder.documents
            )
            documents.reveal = .select(TestFile.report)
            $0.path.append(documents)
        }
    }

    @Test("A hit at the top is revealed on the root")
    func revealAtTheTopUsesTheRoot() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: BrowseTestSupport.serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.revealInFolder(
            path: "",
            title: TestFolder.photos,
            itemID: TestFile.report
        )))) {
            $0.root.reveal = .select(TestFile.report)
        }
    }

    @Test("Show in Enclosing Folder for a hit in this folder ends the search here")
    func showInEnclosingFolderForAHitHereEndsTheSearch() async {
        var state = BrowseFixtures.state(TestPath.documentsWork)
        state.searchQuery = Constants.reportTerm
        let result = SearchResultItem(
            name: TestFile.report,
            path: TestPath.documentsWork,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let store = BrowseFixtures.store(state)

        await store.send(.searchResultEnclosingFolderTapped(result)) {
            $0.searchQuery = ""
        }
        await store.receive(.delegate(.revealInFolder(
            path: TestPath.documentsWork,
            title: FilesFeatureTestValue.workFolder,
            itemID: result.id
        )))
    }

    @Test("Show in Enclosing Folder for a hit elsewhere keeps the search, so Back returns to it")
    func showInEnclosingFolderKeepsTheSearchAndOpensTheFolder() async {
        var state = BrowseFixtures.state()
        state.searchQuery = Constants.reportTerm
        let result = SearchResultItem(
            name: TestFile.report,
            path: TestPath.documentsWork,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let store = BrowseFixtures.store(state)

        await store.send(.searchResultEnclosingFolderTapped(result))
        await store.receive(.delegate(.revealInFolder(
            path: TestPath.documentsWork,
            title: FilesFeatureTestValue.workFolder,
            itemID: result.id
        )))
    }

    @Test("Show in Enclosing Folder on a hit at the top opens the root under its own title")
    func showInEnclosingFolderAtTheTopOpensTheRoot() async {
        var state = BrowseFixtures.state(TestFolder.photos)
        state.searchQuery = Constants.reportTerm
        state.searchScope = .everywhere
        let result = SearchResultItem(
            name: TestFile.report,
            path: "",
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let store = BrowseFixtures.store(state)

        await store.send(.searchResultEnclosingFolderTapped(result))
        await store.receive(.delegate(.revealInFolder(path: "", title: L10n.Browse.navigationTitle, itemID: result.id)))
    }

    @Test("Get Info on a search hit opens the inspector on it, wherever it lives")
    func getInfoOnASearchHitOpensTheInspector() async {
        let hit = SearchResultItem(
            name: TestFile.report,
            path: TestFolder.docs,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        let item = hit.actionItem
        let metadata = FileMetadata(
            path: item.id,
            name: item.name,
            kind: item.kind,
            size: 0,
            dateModified: MockDate.date,
            dateCreated: MockDate.date
        )
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(items: [folder])) {
            $0.filesClient.fetchMetadata = { _, _ in metadata }
        }

        await store.send(.infoTapped(item)) {
            $0.infoItem = item
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse) {
            $0.infoMetadata = metadata
            $0.infoPhase = .loaded
        }
    }
}
