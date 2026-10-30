import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@Suite(.dependencies)
@MainActor
struct FileUndoTests {
    private let serverURL = URL(string: "https://example.com")!
    private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
    private let now = Date(timeIntervalSince1970: 100)

    private func folder(_ name: String, in path: String) -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
    }

    private func state(_ path: String, items: [FileItem]) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: path)
        state.items = IdentifiedArray(uniqueElements: items)
        state.access = access
        state.phase = .loaded
        return state
    }

    @Test
    func aDuplicateShowsInTheListingAtOnceAndUndoDeletesIt() async {
        let misc = folder("Misc", in: "Docs")
        var initial = state("Docs", items: [misc])
        initial.selectedItemIDs = [misc.id]
        let deleted = LockIsolated<[FileItem]>([])

        let store = TestStore(initialState: initial) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.transferItems = { _, _, destination, _ in
                TransferResult(destination: destination, items: [.init(from: "Docs/Misc", to: "Docs/Misc (2)")])
            }
            $0.filesClient.deleteItems = { _, items in deleted.setValue(items) }
        }
        store.exhaustivity = .off

        await store.send(.duplicateSelectionTapped)
        await store.receive(\.transferResponse.success)
        #expect(store.state.items.map(\.name) == ["Misc", "Misc (2)"])
        #expect(store.state.undoStack.count == 1)

        await store.send(.undoTapped)
        await store.receive(\.undoResponse.success)
        #expect(deleted.value.map(\.id) == ["Docs/Misc (2)"])
        #expect(store.state.undoStack.isEmpty)
    }

    @Test
    func undoingAMoveMovesTheItemsBackToWhereTheyCameFrom() async {
        let report = FileItem(name: "report.pdf", path: "Docs", dateModified: now, size: 10, kind: "pdf")
        let archive = folder("Archive", in: "Docs")
        let moved = LockIsolated<(ids: [String], destination: String)?>(nil)

        let store = TestStore(initialState: state("Docs", items: [report, archive])) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.transferItems = { _, items, destination, _ in
                if destination == "Docs" {
                    moved.setValue((items.map(\.id), destination))
                }
                return TransferResult(destination: destination, items: items.map {
                    .init(from: $0.id, to: "\(destination)/\($0.name)")
                })
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsDroppedOnFolder(ids: [report.id], folder: archive))
        await store.receive(\.transferResponse.success)
        #expect(store.state.items.map(\.name) == ["Archive"])

        await store.send(.undoTapped)
        await store.receive(\.undoResponse.success)
        #expect(moved.value?.ids == ["Docs/Archive/report.pdf"])
        #expect(moved.value?.destination == "Docs")
    }

    @Test
    func undoingARenameRestoresTheOldName() async {
        let original = FileItem(name: "vacation.jpg", path: "Photos", dateModified: now, size: 0, kind: "jpg")
        let renamedItem = FileItem(name: "beach.jpg", path: "Photos", dateModified: now, size: 0, kind: "jpg")
        var initial = state("Photos", items: [original])
        initial.renameSheetItem = original
        let renamedBack = LockIsolated<(id: String, name: String)?>(nil)

        let store = TestStore(initialState: initial) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.renameItem = { _, item, newName in
                if item.id == renamedItem.id {
                    renamedBack.setValue((item.id, newName))
                    return original
                }
                return renamedItem
            }
        }
        store.exhaustivity = .off

        await store.send(.renameConfirmed("beach.jpg"))
        await store.receive(\.renameResponse.success)
        await store.send(.undoTapped)
        await store.receive(\.undoResponse.success)
        #expect(renamedBack.value?.id == "Photos/beach.jpg")
        #expect(renamedBack.value?.name == "vacation.jpg")
    }

    @Test
    func nothingToUndoDoesNothing() async {
        let store = TestStore(initialState: state("Docs", items: [])) { BrowseFeature() }
        await store.send(.undoTapped)
    }
}
