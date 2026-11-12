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
    private let serverURL = URL(string: "https://example.com")!

    private func state(showing item: FileItem, among items: [FileItem]) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.items = IdentifiedArray(uniqueElements: items)
        state.phase = .loaded
        state.infoItem = item
        state.infoPhase = .loaded
        return state
    }

    @Test
    func deletingTheInspectedItemClosesTheInspector() async {
        let report = FileItem(name: "report.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")
        let notes = FileItem(name: "notes.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
        let store = TestStore(initialState: state(showing: report, among: [report, notes])) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: report.id)))) {
            $0.infoItem = nil
            $0.infoPhase = .idle
        }
    }

    @Test
    func removingAnotherItemKeepsTheInspectorOpen() async {
        let report = FileItem(name: "report.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")
        let notes = FileItem(name: "notes.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
        let store = TestStore(initialState: state(showing: report, among: [report, notes])) {
            BrowseFeature()
        }
        store.exhaustivity = .off

        await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: notes.id))))
        #expect(store.state.infoItem == report)
    }

    @Test
    func renamingTheInspectedItemRepointsTheInspector() async {
        let report = FileItem(name: "report.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")
        let renamed = FileItem(name: "final.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")
        let store = TestStore(initialState: state(showing: report, among: [report])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.fetchMetadata = { _, _ in throw FilesClientError.offline }
        }
        store.exhaustivity = .off

        await store.send(.renameResponse(.success(BrowseFeature.RenameResult(originalID: report.id, renamed: renamed)))) {
            $0.infoItem = renamed
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse)
    }
}
