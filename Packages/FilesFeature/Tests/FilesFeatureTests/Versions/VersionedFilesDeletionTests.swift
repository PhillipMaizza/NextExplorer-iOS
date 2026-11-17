import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Ticking versions, deleting them or a whole history, and what the list does after.
@Suite(.isolatedDependencies)
@MainActor
struct VersionedFilesDeletionTests: VersionedFilesTestSupport {
    let pageGate = AsyncGate()
    let pageCalls = LockIsolated<[VersionedFilesPageCall]>([])
    let detailCalls = LockIsolated<[String]>([])
    let deleteCalls = LockIsolated<[VersionedFilesDeleteCall]>([])

    // MARK: Selecting and deleting

    @Test
    func versionsAreTickedAndUntickedPerFile() async {
        let store = makeStore(loadedState(files: [file("f1"), file("f2")]))

        await store
            .send(.versionToggled(fileID: "f1", versionID: TestETag.first)) { $0.selection["f1"] = [TestETag.first] }
        await store.send(.versionToggled(fileID: "f1", versionID: TestETag.second)) { $0.selection["f1"] = [
            TestETag.first,
            TestETag.second,
        ] }
        await store.send(.versionToggled(fileID: "f2", versionID: "v9")) { $0.selection["f2"] = ["v9"] }

        await store
            .send(.versionToggled(fileID: "f1", versionID: TestETag.first)) { $0.selection["f1"] = [TestETag.second] }
        await store.send(.versionToggled(fileID: "f1", versionID: TestETag.second)) { $0.selection["f1"] = nil }
        #expect(store.state.selection == ["f2": ["v9"]])
    }

    @Test
    func deletingSelectedAsksFirstWithTheTickedVersionsInOrder() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [
            Self.version(TestETag.first),
            Self.version(TestETag.second),
            Self.version("v3"),
        ])
        state.selection["f1"] = ["v3", TestETag.first]
        let store = makeStore(state)

        await store.send(.deleteSelectedTapped(fileID: "f1")) {
            $0.confirmation = .selected(fileID: "f1", versionIDs: [TestETag.first, "v3"])
        }
        #expect(deleteCalls.value.isEmpty)
    }

    @Test
    func deletingSelectedWithNothingTickedDoesNothing() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        let store = makeStore(state)

        await store.send(.deleteSelectedTapped(fileID: "f1"))
    }

    @Test
    func aTickedVersionThatNoLongerExistsIsNotOffered() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        state.selection["f1"] = ["ghost"]
        let store = makeStore(state)

        await store.send(.deleteSelectedTapped(fileID: "f1"))
    }

    @Test
    func deleteAllAsksFirst() async {
        let store = makeStore(loadedState(files: [file("f1")]))

        await store.send(.deleteAllTapped(fileID: "f1")) { $0.confirmation = .all(fileID: "f1") }
        #expect(deleteCalls.value.isEmpty)
    }

    @Test
    func cancellingTheConfirmationDeletesNothing() async {
        var state = loadedState(files: [file("f1")])
        state.confirmation = .all(fileID: "f1")
        let store = makeStore(state)

        await store.send(.confirmationCancelled) { $0.confirmation = nil }
        #expect(deleteCalls.value.isEmpty)
    }

    @Test
    func confirmingDeleteAllSendsNoIDsThenReloadsTheListAndTheOpenHistory() async {
        var state = loadedState(files: [file("f1")])
        state.expanded = ["f1"]
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        state.selection["f1"] = [TestETag.first]
        state.confirmation = .all(fileID: "f1")
        let newPage = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "f1.txt", versions: 1)], total: 1)
        let newDetail = VersionedFileDetail(versions: [Self.version("v9")])
        let store = makeStore(
            state,
            page: gatedPage(newPage),
            detail: { _ in newDetail },
            delete: { _, _ in VersionsDeletion(deleted: 1, remaining: 1) }
        )

        await store.send(.confirmationConfirmed) {
            $0.confirmation = nil
            $0.isWorking = true
        }
        await store.receive(\.deleteResponse) {
            $0.isWorking = false
            $0.selection = [:]
            $0.isReloading = true
        }
        await store.receive(.detailResponse(fileID: "f1", .success(newDetail))) { $0.details["f1"] = newDetail }
        pageGate.open()
        await receivePage(store, newPage)

        #expect(deleteCalls.value == [VersionedFilesDeleteCall(fileID: "f1", versionIDs: nil)])
        #expect(detailCalls.value == ["f1"])
    }

    @Test
    func confirmingDeleteSelectedSendsTheTickedIDsAndDropsAClosedRowsHistory() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [
            Self.version(TestETag.first),
            Self.version(TestETag.second),
            Self.version("v3"),
        ])
        state.selection["f1"] = [TestETag.first, "v3"]
        state.confirmation = .selected(fileID: "f1", versionIDs: [TestETag.first, "v3"])
        let newPage = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "f1.txt", versions: 1)], total: 1)
        let store = makeStore(
            state,
            page: { _, _ in newPage },
            delete: { _, _ in VersionsDeletion(deleted: 2, remaining: 1) }
        )

        await store.send(.confirmationConfirmed) {
            $0.confirmation = nil
            $0.isWorking = true
        }
        await store.receive(\.deleteResponse) {
            $0.isWorking = false
            $0.selection = [:]
            $0.details = [:]
            $0.isReloading = true
        }
        await receivePage(store, newPage)

        #expect(deleteCalls.value == [VersionedFilesDeleteCall(fileID: "f1", versionIDs: [TestETag.first, "v3"])])
        #expect(detailCalls.value.isEmpty)
    }

    @Test
    func deletingEverythingClosesTheRowInsteadOfReadingAHistoryThatMayBeGone() async {
        var state = loadedState(files: [file("f1", state: .orphaned)])
        state.expanded = ["f1"]
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        state.confirmation = .all(fileID: "f1")
        let empty = VersionedFilesPage()
        let store = makeStore(
            state,
            page: { _, _ in empty },
            delete: { _, _ in VersionsDeletion(deleted: 1, remaining: 0) }
        )

        await store.send(.confirmationConfirmed) {
            $0.confirmation = nil
            $0.isWorking = true
        }
        await store.receive(\.deleteResponse) {
            $0.isWorking = false
            $0.expanded = []
            $0.details = [:]
            $0.isReloading = true
        }
        await receivePage(store, empty)

        #expect(detailCalls.value.isEmpty)
        #expect(store.state.files.isEmpty)
    }

    @Test
    func aFailedDeletionKeepsTheSelectionAndShowsTheError() async {
        var state = loadedState(files: [file("f1")])
        state.selection["f1"] = [TestETag.first]
        state.confirmation = .selected(fileID: "f1", versionIDs: [TestETag.first])
        let store = makeStore(
            state,
            delete: { _, _ in throw FilesClientError.serverMessage(statusCode: 500, message: "Could not delete.") }
        )

        await store.send(.confirmationConfirmed) {
            $0.confirmation = nil
            $0.isWorking = true
        }
        await store.receive(\.deleteResponse) {
            $0.isWorking = false
            $0.listError = "Could not delete."
        }
        #expect(store.state.selection["f1"] == [TestETag.first])
    }

    @Test
    func confirmingWithNothingAskedDoesNothing() async {
        let store = makeStore(loadedState())

        await store.send(.confirmationConfirmed)
        #expect(deleteCalls.value.isEmpty)
    }

    @Test
    func anEmptyPageAfterADeleteStepsBackToTheLastPageWithRows() async {
        let pageSize = VersionedFilesPage.defaultPageSize
        let emptyLastPage = VersionedFilesPage(files: [], total: pageSize, offset: pageSize)
        let previousPage = VersionedFilesPage(files: [VersionedFile(id: "f2", name: "b")], total: pageSize, offset: 0)
        let store = makeStore(
            loadedState(files: [file("f1")], total: pageSize + 1, offset: pageSize),
            page: { _, offset in offset == pageSize ? emptyLastPage : previousPage }
        )

        await store
            .send(.deleteResponse(fileID: "f1", .success(VersionsDeletion(deleted: 1, remaining: 0)))) {
                $0.isReloading = true
            }
        await store.receive(.pageResponse(.success(emptyLastPage))) {
            $0.page = emptyLastPage
            $0.offset = 0
        }
        await receivePage(store, previousPage)

        #expect(pageCalls.value.map(\.offset) == [25, 0])
        #expect(store.state.files.map(\.id) == ["f2"])
    }

    @Test
    func versionsTheServerCouldNotDeleteShowAnErrorAfterTheReload() async {
        var state = loadedState(files: [file("f1")])
        state.confirmation = .all(fileID: "f1")
        let page = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1)
        let store = makeStore(
            state,
            page: { _, _ in page },
            delete: { _, _ in VersionsDeletion(deleted: 0, remaining: 2, failed: 2) }
        )

        await store.send(.confirmationConfirmed) {
            $0.confirmation = nil
            $0.isWorking = true
        }
        await store.receive(\.deleteResponse) {
            $0.isWorking = false
            $0.isReloading = true
            $0.listError = L10n.VersionedFiles.deleteFailed
        }
        await receivePage(store, page)
        #expect(store.state.listError == L10n.VersionedFiles.deleteFailed)
    }

    @Test
    func refreshingReadsTheListAndTheOpenHistoriesAgain() async {
        var state = loadedState(files: [file("f1")])
        state.expanded = ["f1"]
        state.details = ["f1": VersionedFileDetail(versions: [Self.version(TestValue.outdated)])]
        let page = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1)
        let fresh = VersionedFileDetail(versions: [Self.version("new")])
        let store = makeStore(state, page: gatedPage(page), detail: { _ in fresh })

        await store.send(.refreshTapped) {
            $0.details = [:]
            $0.isReloading = true
        }
        await store.receive(.detailResponse(fileID: "f1", .success(fresh))) { $0.details["f1"] = fresh }
        pageGate.open()
        await receivePage(store, page)
        #expect(detailCalls.value == ["f1"])
    }
}
