import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
@testable import FolderPickerFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct DestinationPickerSidebarTests: DestinationPickerTestHelpers {
    private func readOnly() -> FileAccess {
        FileAccess(
            canRead: true,
            canWrite: false,
            canUpload: false,
            canDelete: false,
            canShare: false,
            canDownload: true
        )
    }

    private func moveState(in path: String = TestFolder.documents) -> DestinationPickerFeature.State {
        var state = DestinationPickerFeature.State(
            serverURL: serverURL,
            items: [file(TestFile.aText, path: TestFolder.inbox)]
        )
        state.directoryPath = path
        state.phase = .loaded
        state.currentAccess = access()
        return state
    }

    @Test("The sidebar lists My Files first, then the volumes by name, and a click opens one")
    func locationsListMyFilesFirst() async {
        let store = TestStore(initialState: DestinationPickerFeature.State(
            serverURL: serverURL,
            items: [file(TestFile.aText, path: TestFolder.inbox)]
        )) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.recentDestinations = { _ in [] }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(isPersonalEnabled: true) }
            $0.filesClient.browse = { _, path in
                BrowseResult(
                    items: path.isEmpty ? [folder(TestFolder.media), folder(TestFolder.documents), file("x.txt")] : [],
                    access: access(),
                    path: path
                )
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
        await store.receive(\.recentsResponse)
        await store.receive(\.locationsResponse) {
            $0.locations = [
                DestinationPickerFeature.personalSpaceFolder,
                folder(TestFolder.documents),
                folder(TestFolder.media),
            ]
        }
        await store.send(.locationTapped(TestFolder.media)) {
            $0.directoryPath = TestFolder.media
            $0.navigationHistory = [TestFolder.inbox]
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
        #expect(store.state.activeLocation == TestFolder.media)
        await store.send(.backTapped) {
            $0.directoryPath = TestFolder.inbox
            $0.navigationHistory = []
            $0.phase = .loading
            $0.currentAccess = nil
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: []) }
    }

    @Test("A new folder is made where the picker stands and becomes the target")
    func newFolderBecomesTheTarget() async {
        let created = LockIsolated<[String]>([])
        let store = TestStore(initialState: moveState()) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.createFolder = { _, path, name in
                created.withValue { $0.append("\(path)/\(name)") }
                return FileItem(
                    name: name,
                    path: path,
                    dateModified: MockDate.date,
                    size: 0,
                    kind: FileItem.directoryKind
                )
            }
        }

        await store.send(.newFolderTapped) { $0.newFolder = .init() }
        await store.send(.newFolderNameChanged("  Archive ")) { $0.newFolder?.name = "  Archive " }
        await store.send(.newFolderConfirmed) { $0.newFolder?.phase = .loading }
        await store.receive(\.newFolderResponse.success) {
            $0.newFolder = nil
            $0.folders = [folder("Archive", path: TestFolder.documents)]
            $0.selectedFolderPath = "\(TestFolder.documents)/Archive"
        }
        #expect(created.value == ["\(TestFolder.documents)/Archive"])
        #expect(store.state.transferDestination == "\(TestFolder.documents)/Archive")
    }

    @Test("A refused new folder keeps the prompt with the reason, and typing clears it")
    func newFolderFailureKeepsThePrompt() async {
        let store = TestStore(initialState: moveState()) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.createFolder = { _, _, _ in throw FilesClientError.forbidden(message: nil) }
        }

        await store.send(.newFolderTapped) { $0.newFolder = .init() }
        await store.send(.newFolderNameChanged("Archive")) { $0.newFolder?.name = "Archive" }
        await store.send(.newFolderConfirmed) { $0.newFolder?.phase = .loading }
        await store.receive(\.newFolderResponse.failure) { $0.newFolder?.phase = .failed(L10n.Error.forbidden) }
        await store.send(.newFolderNameChanged("Archives")) {
            $0.newFolder?.name = "Archives"
            $0.newFolder?.phase = .idle
        }
    }

    @Test(
        "New Folder needs a real folder, the right to make one and no search on screen",
        arguments: [
            (TestFolder.documents, true, "", true),
            ("", true, "", false),
            (TestFolder.documents, false, "", false),
            (TestFolder.documents, true, "reports", false),
        ]
    )
    func newFolderAvailability(path: String, canCreate: Bool, query: String, expected: Bool) {
        var state = moveState(in: path)
        state.currentAccess = canCreate ? access() : readOnly()
        state.searchQuery = query
        #expect(state.canCreateFolder == expected)
    }

    @Test(
        "The footer names why the folder can't take the items, and nothing while it loads",
        arguments: [
            (TestFolder.inbox, DataPhase.loaded, true, FileClipboard.Refusal?.some(.alreadyThere)),
            (TestFolder.documents, .loaded, false, .noRights),
            (TestFolder.documents, .loaded, true, nil),
            (TestFolder.inbox, .loading, true, nil),
        ]
    )
    func refusalReasons(path: String, phase: DataPhase, canCreate: Bool, expected: FileClipboard.Refusal?) {
        var state = moveState(in: path)
        state.phase = phase
        state.currentAccess = canCreate ? access() : readOnly()
        #expect(state.refusal == expected)
    }

    @Test("The path bar names a share by its name and the target trail follows a picked row")
    func crumbsUseTheShareName() {
        var state = moveState(in: "share/tok/Reports")
        state.shareName = "Team"
        #expect(state.crumbs.map(\.title) == [L10n.Shared.sharedWithMe, "Team", "Reports"])
        state.selectedFolderPath = "share/tok/Reports/Q3"
        #expect(state.destinationTrail == PathTrail.text("\(L10n.Shared.sharedWithMe)/Team/Reports/Q3"))
        #expect(state.destinationName == "Q3")
        state.selectedFolderPath = nil
        state.directoryPath = "share/tok"
        #expect(state.destinationName == "Team")
    }

    @Test("A recent that is on screen is the highlighted row, not its location")
    func aRecentOnScreenTakesTheHighlight() {
        var state = moveState(in: "\(TestFolder.media)/\(TestFolder.photos)")
        state.locations = [folder(TestFolder.media)]
        #expect(state.activeLocation == TestFolder.media)
        state.recents = [state.directoryPath]
        #expect(state.activeLocation == nil)
        state.recents = (1 ... DestinationPickerFeature.State.sidebarRecentLimit).map { "\(TestFolder.media)/\($0)" }
            + [state.directoryPath]
        #expect(state.activeLocation == TestFolder.media)
    }
}
