import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

/// The selection driven actions behind the Mac file table's keyboard and Edit menu commands.
@Suite(.dependencies)
@MainActor
struct BrowseKeyboardActionsTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func access(canWrite: Bool = true, canDelete: Bool = true) -> FileAccess {
        FileAccess(canRead: true, canWrite: canWrite, canUpload: true, canDelete: canDelete, canShare: false, canDownload: true)
    }

    private nonisolated func item(_ name: String) -> FileItem {
        FileItem(name: name, path: "Docs", dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "txt")
    }

    private func makeState(items: [FileItem], selected: [FileItem], access: FileAccess) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.items = IdentifiedArray(uniqueElements: items)
        state.selectedItemIDs = Set(selected.map(\.id))
        state.access = access
        state.$clipboard.withLock { $0 = nil }
        return state
    }

    @Test
    func tableSelectionChangedTracksTheSelectionWithoutEnteringSelectMode() async {
        let a = item("a.txt")
        let store = TestStore(initialState: makeState(items: [a], selected: [], access: access())) { BrowseFeature() }

        await store.send(.tableSelectionChanged([a.id])) {
            $0.selectedItemIDs = [a.id]
        }
    }

    @Test
    func copySelectionStagesEverySelectedItemInListOrder() async {
        let a = item("a.txt"), b = item("b.txt"), c = item("c.txt")
        let store = TestStore(initialState: makeState(items: [a, b, c], selected: [c, a], access: access())) { BrowseFeature() }

        await store.send(.copySelectionTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [a, c], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedMany(2)
        }
    }

    @Test
    func cutSelectionStagesAMove() async {
        let a = item("a.txt")
        let store = TestStore(initialState: makeState(items: [a], selected: [a], access: access())) { BrowseFeature() }

        await store.send(.cutSelectionTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [a], operation: .move) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCutOne("a.txt")
        }
    }

    @Test
    func cutSelectionIsIgnoredWithoutDeletePermission() async {
        let a = item("a.txt")
        let store = TestStore(initialState: makeState(items: [a], selected: [a], access: access(canDelete: false))) { BrowseFeature() }

        await store.send(.cutSelectionTapped)
    }

    @Test
    func deleteSelectionOfOneItemRoutesToTheSingleDelete() async {
        let a = item("a.txt")
        let store = TestStore(initialState: makeState(items: [a], selected: [a], access: access())) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteImpact = { _, _ in DeleteImpact(shareCount: 0) }
        }
        // The single delete then checks for linked shares, covered by BrowseFeatureTests.
        store.exhaustivity = .off

        await store.send(.deleteSelectionTapped)
        await store.receive(\.deleteTapped)
    }

    @Test
    func deleteSelectionOfSeveralItemsRoutesToTheBulkDelete() async {
        let a = item("a.txt"), b = item("b.txt")
        let store = TestStore(initialState: makeState(items: [a, b], selected: [a, b], access: access())) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.deleteImpact = { _, _ in DeleteImpact(shareCount: 0) }
        }
        store.exhaustivity = .off

        await store.send(.deleteSelectionTapped)
        await store.receive(\.bulkDeleteTapped)
    }

    @Test
    func renameSelectionNeedsExactlyOneItemAndWriteAccess() async {
        let a = item("a.txt"), b = item("b.txt")
        let several = TestStore(initialState: makeState(items: [a, b], selected: [a, b], access: access())) { BrowseFeature() }
        await several.send(.renameSelectionTapped)

        let readOnly = TestStore(initialState: makeState(items: [a], selected: [a], access: access(canWrite: false))) { BrowseFeature() }
        await readOnly.send(.renameSelectionTapped)

        let single = TestStore(initialState: makeState(items: [a], selected: [a], access: access())) { BrowseFeature() }
        single.exhaustivity = .off
        await single.send(.renameSelectionTapped)
        await single.receive(\.renameTapped)
    }

    @Test
    func goToEnclosingFolderPopsTheVisibleFolder() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A/B", title: "B"))
        let store = TestStore(initialState: state) { BrowseTabFeature() }

        await store.send(.goToEnclosingFolder) {
            $0.path.removeLast()
        }
    }

    @Test
    func goToEnclosingFolderAtTheRootDoesNothing() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) { BrowseTabFeature() }

        await store.send(.goToEnclosingFolder)
    }

    // MARK: Drag onto a folder

    private nonisolated func folder(_ name: String, path: String = "Docs") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
    }

    @Test
    func droppingRowsOnAFolderMovesThemInside() async {
        let a = item("a.txt"), archive = folder("Archive")
        let moved = LockIsolated<(String, TransferOperation)?>(nil)
        let store = TestStore(initialState: makeState(items: [a, archive], selected: [], access: access())) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                BrowseResult(items: [], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true), path: path)
            }
            $0.filesClient.transferItems = { _, _, destination, operation in
                moved.setValue((destination, operation))
                return TransferResult(destination: destination, items: [.init(from: "Docs/a.txt", to: "Docs/Archive/a.txt")])
            }
        }
        // The move then runs the shared transfer flow, covered by BrowseFeatureTransferTests.
        store.exhaustivity = .off

        await store.send(.itemsDroppedOnFolder(ids: [a.id], folder: archive)) {
            $0.isPerformingFileAction = true
        }
        await store.skipReceivedActions()
        #expect(moved.value?.0 == archive.id)
        #expect(moved.value?.1 == .move)
    }

    @Test
    func droppingAFolderIntoItselfOrItsOwnSubfolderIsIgnored() async {
        let outer = folder("Outer")
        let inner = folder("Inner", path: "Docs/Outer")
        let store = TestStore(initialState: makeState(items: [outer], selected: [], access: access())) { BrowseFeature() }

        await store.send(.itemsDroppedOnFolder(ids: [outer.id], folder: outer))
        await store.send(.itemsDroppedOnFolder(ids: [outer.id], folder: inner))
    }

    @Test
    func droppingWithoutDeletePermissionIsIgnored() async {
        let a = item("a.txt"), archive = folder("Archive")
        let store = TestStore(initialState: makeState(items: [a, archive], selected: [], access: access(canDelete: false))) {
            BrowseFeature()
        }

        await store.send(.itemsDroppedOnFolder(ids: [a.id], folder: archive))
    }

    // MARK: Inspector

    @Test
    func anOpenInspectorFollowsTheSelectionToTheNewRow() async {
        let a = item("a.txt"), b = item("b.txt")
        var state = makeState(items: [a, b], selected: [a], access: access())
        state.infoItem = a
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, path in
                FileMetadata(path: path, name: "b.txt", kind: "txt", size: 0, dateModified: Date(timeIntervalSince1970: 1), dateCreated: Date(timeIntervalSince1970: 1))
            }
        }
        // The metadata load itself is covered by BrowseFeatureTests.
        store.exhaustivity = .off

        await store.send(.tableSelectionChanged([b.id])) {
            $0.selectedItemIDs = [b.id]
            $0.infoItem = b
        }
        await store.skipReceivedActions()
    }

    @Test
    func aClosedInspectorStaysClosedWhenTheSelectionMoves() async {
        let a = item("a.txt"), b = item("b.txt")
        let store = TestStore(initialState: makeState(items: [a, b], selected: [a], access: access())) { BrowseFeature() }

        await store.send(.tableSelectionChanged([b.id])) {
            $0.selectedItemIDs = [b.id]
        }
    }

    @Test
    func getInfoOnTheItemAlreadyShownClosesTheInspector() async {
        let a = item("a.txt")
        var state = makeState(items: [a], selected: [a], access: access())
        state.infoItem = a
        let store = TestStore(initialState: state) { BrowseFeature() }
        store.exhaustivity = .off

        await store.send(.infoSelectionTapped)
        await store.receive(\.infoDismissed) {
            $0.infoItem = nil
        }
    }
}
