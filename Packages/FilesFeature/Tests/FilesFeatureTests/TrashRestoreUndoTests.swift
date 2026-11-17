import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct TrashRestoreUndoTests {
    private enum Constants {
        static let folder = "Files/Documents"
        static let restoredName = "notes (1).txt"
    }

    private let restored = TrashActionResult.Entry(
        key: "t3",
        status: .restored,
        name: "notes.txt",
        restoredName: Constants.restoredName,
        path: Constants.folder,
        isRenamed: true
    )

    private func store(
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<TrashRestoreFeature> {
        TestStore(initialState: TrashRestoreFeature.State(serverURL: TestHost.serverURL)) {
            TrashRestoreFeature()
        } withDependencies: {
            configure(&$0)
        }
    }

    private var summary: String {
        [L10n.Trash.restored(1), L10n.Trash.renamed("notes.txt", Constants.restoredName)].joined(separator: "\n")
    }

    @Test("Undo moves what the restore brought back, under its new name, to the trash again")
    func undoMovesBackToTrash() async {
        let sent = LockIsolated<[FileItem]>([])
        let store = store {
            $0.filesClient.restoreTrash = { _, _, _, _, _ in TrashActionResult(items: [restored]) }
            $0.filesClient.deleteItems = { _, items, permanent in
                #expect(!permanent)
                sent.setValue(items)
                return DeleteOutcome(items: [.init(path: items[0].id, status: .trashed)])
            }
        }

        await store.send(.restore(.items(["t3"]), shareCount: 0)) { $0.phase = .inPlace }
        await store.receive(\.response.success) {
            $0.phase = .idle
            $0.undoable = [FileItem(
                name: Constants.restoredName,
                path: Constants.folder,
                dateModified: .distantPast,
                size: 0,
                kind: ""
            )]
            $0.notice = TrashNotice(text: summary, isFailure: false, isUndoable: true, sequence: 1)
        }
        await store.receive(.delegate(.finished))

        await store.send(.undoTapped) { $0.undoable = [] }
        await store.receive(\.undoResponse.success) {
            $0.notice = TrashNotice(text: L10n.Trash.movedToTrash(1), isFailure: false, sequence: 2)
        }
        await store.receive(.delegate(.finished))
        #expect(sent.value.map(\.name) == [Constants.restoredName])
        #expect(sent.value.map(\.path) == [Constants.folder])
    }

    @Test("A restore the server gave no folder for offers no Undo")
    func noFolderNoUndo() async {
        let store = store {
            $0.filesClient.restoreTrash = { _, _, _, _, _ in
                TrashActionResult(items: [.init(key: "t3", status: .restored, name: "notes.txt")])
            }
        }

        await store.send(.restore(.items(["t3"]), shareCount: 0)) { $0.phase = .inPlace }
        await store.receive(\.response.success) {
            $0.phase = .idle
            $0.notice = TrashNotice(text: L10n.Trash.restored(1), isFailure: false, sequence: 1)
        }
        await store.receive(.delegate(.finished))
        await store.send(.undoTapped)
    }

    @Test("An Undo the server refuses says why and reloads")
    func undoFailure() async {
        let store = store {
            $0.filesClient.restoreTrash = { _, _, _, _, _ in TrashActionResult(items: [restored]) }
            $0.filesClient.deleteItems = { _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.restore(.items(["t3"]), shareCount: 0)) { $0.phase = .inPlace }
        await store.receive(\.response.success) {
            $0.phase = .idle
            $0.undoable = TrashRestoreFeature.restoredItems(in: TrashActionResult(items: [restored]))
            $0.notice = TrashNotice(text: summary, isFailure: false, isUndoable: true, sequence: 1)
        }
        await store.receive(.delegate(.finished))
        await store.send(.undoTapped) { $0.undoable = [] }
        await store.receive(\.undoResponse.failure) {
            $0.notice = TrashNotice(text: FilesClientError.offline.userMessage, isFailure: true, sequence: 2)
        }
        await store.receive(.delegate(.finished))
    }
}
