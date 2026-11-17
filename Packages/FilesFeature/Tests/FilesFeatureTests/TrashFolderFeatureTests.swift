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
struct TrashFolderFeatureTests {
    private let folder = TrashItem(id: "t2", name: "Photos", isDirectory: true, shareCount: 1)
    private let summer = TrashEntry(name: "Summer", isDirectory: true, shareCount: 1)
    private let beach = TrashEntry(name: "beach.jpg")
    private let itinerary = TrashEntry(name: "itinerary.md")

    private func store(configure: (inout DependencyValues) -> Void = { _ in }) -> TestStoreOf<TrashFolderFeature> {
        TestStore(initialState: TrashFolderFeature.State(serverURL: TestHost.serverURL, item: folder)) {
            TrashFolderFeature()
        } withDependencies: {
            configure(&$0)
        }
    }

    private func listing(_ path: String, _ entries: [TrashEntry]) -> TrashFolderListing {
        TrashFolderListing(item: folder, path: path, entries: entries)
    }

    @Test("The folder lists its top, walks into a subfolder and back up")
    func walk() async {
        let folder = folder
        let summer = summer
        let beach = beach
        let store = store {
            $0.filesClient.fetchTrashEntries = { _, id, path in
                #expect(id == "t2")
                return TrashFolderListing(item: folder, path: path, entries: path.isEmpty ? [summer] : [beach])
            }
        }

        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.loadResponse) {
            $0.phase = .loaded
            $0.entries = [summer]
        }
        await store.send(.entryTapped(summer)) {
            $0.path = "Summer"
            $0.phase = .loading
            $0.entries = []
        }
        await store.receive(\.loadResponse) {
            $0.phase = .loaded
            $0.entries = [beach]
        }
        #expect(store.state.title == "Summer")
        await store.send(.upTapped) {
            $0.path = ""
            $0.phase = .loading
            $0.entries = []
        }
        await store.receive(\.loadResponse) {
            $0.phase = .loaded
            $0.entries = [summer]
        }
        #expect(store.state.title == "Photos")
    }

    @Test("An answer for a folder no longer shown is dropped")
    func staleAnswerIsDropped() async {
        var state = TrashFolderFeature.State(serverURL: TestHost.serverURL, item: folder)
        state.path = "Summer"
        state.phase = .loading
        let store = TestStore(initialState: state) { TrashFolderFeature() }

        await store.send(.loadResponse(path: "", .success(listing("", [summer]))))
        await store.send(.loadResponse(path: "", .failure(.offline)))
    }

    @Test("A failed listing says the folder could not be opened")
    func loadFailure() async {
        let store = store { $0.filesClient.fetchTrashEntries = { _, _, _ in
            throw FilesClientError.server(statusCode: 404)
        } }

        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.loadResponse) { $0.phase = .failed(L10n.Trash.folderLoadFailed) }
    }

    @Test("Restoring chosen entries names them by their path inside the folder, then reloads and tells the trash")
    func restoreEntries() async {
        var state = TrashFolderFeature.State(serverURL: TestHost.serverURL, item: folder)
        state.path = "Summer"
        state.phase = .loaded
        state.entries = [beach, itinerary]
        let folder = folder
        let store = TestStore(initialState: state) {
            TrashFolderFeature()
        } withDependencies: {
            $0.filesClient.restoreTrash = { _, target, _, shares, _ in
                #expect(target == .entries(itemID: "t2", paths: ["Summer/beach.jpg", "Summer/itinerary.md"]))
                #expect(shares == .drop)
                return TrashActionResult(items: [
                    .init(key: "Summer/beach.jpg", status: .restored),
                    .init(key: "Summer/itinerary.md", status: .restored),
                ])
            }
            $0.filesClient
                .fetchTrashEntries = { _, _, path in TrashFolderListing(item: folder, path: path, entries: []) }
        }

        await store.send(.restoreTapped([beach, itinerary]))
        await store.receive(\.restore.restore) { $0.restore.phase = .inPlace }
        await store.receive(\.restore.response.success) {
            $0.restore.phase = .idle
            $0.restore.notice = TrashNotice(text: L10n.Trash.restored(2), isFailure: false, sequence: 1)
        }
        await store.receive(.restore(.delegate(.finished))) {
            $0.phase = .loading
            $0.entries = []
        }
        await store.receive(.delegate(.restored(isWholeFolder: false)))
        await store.receive(\.loadResponse) { $0.phase = .loaded }
    }

    @Test("Restore Whole Folder restores the item itself and closes the folder")
    func restoreWholeFolder() async {
        var state = TrashFolderFeature.State(serverURL: TestHost.serverURL, item: folder)
        state.phase = .loaded
        let store = TestStore(initialState: state) {
            TrashFolderFeature()
        } withDependencies: {
            $0.filesClient.restoreTrash = { _, target, _, shares, _ in
                #expect(target == .items(["t2"]))
                #expect(shares == .restore)
                return TrashActionResult(items: [.init(key: "t2", status: .restored)])
            }
        }

        await store.send(.restoreFolderTapped) { $0.isRestoringWholeFolder = true }
        await store.receive(\.restore.restore) {
            $0.restore.awaitingShareChoice = .init(target: .items(["t2"]), destination: nil, shareCount: 1)
        }
        await store.send(.restore(.shareChoiceMade(.restore))) {
            $0.restore.awaitingShareChoice = nil
            $0.restore.phase = .inPlace
        }
        await store.receive(\.restore.response.success) {
            $0.restore.phase = .idle
            $0.restore.notice = TrashNotice(text: L10n.Trash.restored(1), isFailure: false, sequence: 1)
        }
        await store.receive(.restore(.delegate(.finished))) { $0.isRestoringWholeFolder = false }
        await store.receive(.delegate(.restored(isWholeFolder: true)))
    }

    @Test("A text entry opens by its path inside the folder")
    func textEntry() async {
        var state = TrashFolderFeature.State(serverURL: TestHost.serverURL, item: folder)
        state.path = "Summer"
        state.phase = .loaded
        let store = TestStore(initialState: state) {
            TrashFolderFeature()
        } withDependencies: {
            $0.filesClient.fetchTrashText = { _, _, path in
                #expect(path == "Summer/itinerary.md")
                throw FilesClientError.serverMessage(statusCode: 400, message: "Too large")
            }
        }

        await store.send(.entryTapped(itinerary)) { $0.text = .loading(name: "itinerary.md") }
        await store.receive(\.textResponse.failure) {
            $0.text = .closed
            $0.notice = TrashNotice(text: "Too large", isFailure: true, sequence: 1)
        }
    }
}
