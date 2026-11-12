import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@MainActor
@Suite(.isolatedDependencies)
struct InspectorFollowsItemTests {
    private let serverURL = URL(fileURLWithPath: "/")
    private let report = FileItem(name: "report.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")
    private let notes = FileItem(name: "notes.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
    private let renamed = FileItem(name: "final.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")

    private func makeStore(
        showing item: FileItem,
        among items: [FileItem],
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.items = IdentifiedArray(uniqueElements: items)
        state.phase = .loaded
        state.infoItem = item
        state.infoPhase = .loaded
        return TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            configure(&$0)
        }
    }

    @Test("Deleting the inspected item closes the inspector")
    func deletingTheInspectedItemClosesTheInspector() async {
        let store = makeStore(showing: report, among: [report, notes])

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: "Docs/report.pdf")))) {
            $0.items = [notes]
            $0.infoItem = nil
            $0.infoPhase = .idle
        }
    }

    @Test("Deleting another item keeps the inspector open on its item")
    func removingAnotherItemKeepsTheInspectorOpen() async {
        let store = makeStore(showing: report, among: [report, notes])

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: "Docs/notes.txt")))) {
            $0.items = [report]
        }
    }

    @Test("Renaming the inspected item repoints the inspector and loads the new path")
    func renamingTheInspectedItemRepointsTheInspector() async {
        let fetched = LockIsolated<[String]>([])
        let metadata = FileMetadata(path: "Docs/final.pdf", name: "final.pdf", kind: "pdf", size: 1, dateModified: MockDate.date, dateCreated: MockDate.date)
        let store = makeStore(showing: report, among: [report]) {
            $0.filesClient.fetchMetadata = { _, path in
                fetched.withValue { $0.append(path) }
                return metadata
            }
        }

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(originalID: "Docs/report.pdf", renamed: renamed)))) {
            $0.items = [renamed]
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamed, previousName: "report.pdf"))] }
            $0.infoItem = renamed
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse.success) {
            $0.infoPhase = .loaded
            $0.infoMetadata = metadata
        }
        #expect(fetched.value == ["Docs/final.pdf"])
    }

    @Test("Renaming an item the inspector is not showing leaves the inspector alone")
    func renamingAnotherItemKeepsTheInspector() async {
        let store = makeStore(showing: report, among: [report, notes])
        let renamedNotes = FileItem(name: "todo.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(originalID: "Docs/notes.txt", renamed: renamedNotes)))) {
            $0.items = [report, renamedNotes]
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamedNotes, previousName: "notes.txt"))] }
        }
    }
}
