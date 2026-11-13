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
    private let report = FileItem(
        name: TestFile.report,
        path: TestFolder.docs,
        dateModified: MockDate.date,
        size: 1,
        kind: TestKind.pdf
    )
    private let notes = FileItem(
        name: TestFile.notes,
        path: TestFolder.docs,
        dateModified: MockDate.date,
        size: 1,
        kind: TestKind.text
    )
    private let renamed = FileItem(
        name: "final.pdf",
        path: TestFolder.docs,
        dateModified: MockDate.date,
        size: 1,
        kind: TestKind.pdf
    )

    private func makeStore(
        showing item: FileItem,
        among items: [FileItem],
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs)
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

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: TestPath.docsNotes)))) {
            $0.items = [report]
        }
    }

    @Test("Renaming the inspected item repoints the inspector and loads the new path")
    func renamingTheInspectedItemRepointsTheInspector() async {
        let fetched = LockIsolated<[String]>([])
        let metadata = FileMetadata(
            path: "Docs/final.pdf",
            name: "final.pdf",
            kind: TestKind.pdf,
            size: 1,
            dateModified: MockDate.date,
            dateCreated: MockDate.date
        )
        let store = makeStore(showing: report, among: [report]) {
            $0.filesClient.fetchMetadata = { _, path in
                fetched.withValue { $0.append(path) }
                return metadata
            }
        }

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(
            originalID: "Docs/report.pdf",
            renamed: renamed
        )))) {
            $0.items = [renamed]
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamed, previousName: TestFile.report))] }
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
        let renamedNotes = FileItem(
            name: "todo.txt",
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 1,
            kind: TestKind.text
        )

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(
            originalID: TestPath.docsNotes,
            renamed: renamedNotes
        )))) {
            $0.items = [report, renamedNotes]
            $0.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamedNotes, previousName: TestFile.notes))] }
        }
    }

    // MARK: The selection moves

    private nonisolated func metadata(of item: FileItem) -> FileMetadata {
        FileMetadata(
            path: item.id,
            name: item.name,
            kind: item.kind,
            size: item.size,
            dateModified: MockDate.date,
            dateCreated: MockDate.date
        )
    }

    @Test("An open inspector follows the selection to the new row, after the settle delay")
    func anOpenInspectorFollowsTheSelectionToTheNewRow() async {
        let clock = TestClock()
        let fetched = LockIsolated<[String]>([])
        let store = makeStore(showing: report, among: [report, notes]) {
            $0.continuousClock = clock
            $0.filesClient.fetchMetadata = { _, path in
                fetched.withValue { $0.append(path) }
                return metadata(of: notes)
            }
        }

        await store.send(.tableSelectionChanged([notes.id])) {
            $0.selectedItemIDs = [notes.id]
            $0.infoItem = notes
            $0.infoPhase = .loading
        }
        #expect(fetched.value.isEmpty)
        await clock.advance(by: BrowseFeature.Constants.inspectorFollowDelay)
        await store.receive(\.infoMetadataResponse.success) {
            $0.infoPhase = .loaded
            $0.infoMetadata = metadata(of: notes)
        }
        #expect(fetched.value == [TestPath.docsNotes])
    }

    @Test("Quick selection changes only load the row the selection settles on")
    func anInspectorFollowingQuickSelectionChangesOnlyLoadsTheRowItSettlesOn() async {
        let draft = FileItem(
            name: "draft.txt",
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 1,
            kind: TestKind.text
        )
        let clock = TestClock()
        let fetched = LockIsolated<[String]>([])
        let store = makeStore(showing: report, among: [report, notes, draft]) {
            $0.continuousClock = clock
            $0.filesClient.fetchMetadata = { _, path in
                fetched.withValue { $0.append(path) }
                return metadata(of: draft)
            }
        }

        await store.send(.tableSelectionChanged([notes.id])) {
            $0.selectedItemIDs = [notes.id]
            $0.infoItem = notes
            $0.infoPhase = .loading
        }
        await store.send(.tableSelectionChanged([draft.id])) {
            $0.selectedItemIDs = [draft.id]
            $0.infoItem = draft
        }
        await clock.advance(by: BrowseFeature.Constants.inspectorFollowDelay)
        await store.receive(\.infoMetadataResponse.success) {
            $0.infoPhase = .loaded
            $0.infoMetadata = metadata(of: draft)
        }
        #expect(fetched.value == ["Docs/draft.txt"])
    }

    @Test("A closed inspector stays closed when the selection moves")
    func aClosedInspectorStaysClosedWhenTheSelectionMoves() async {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs)
        state.items = [report, notes]
        state.selectedItemIDs = [report.id]
        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        await store.send(.tableSelectionChanged([notes.id])) {
            $0.selectedItemIDs = [notes.id]
        }
    }
}
