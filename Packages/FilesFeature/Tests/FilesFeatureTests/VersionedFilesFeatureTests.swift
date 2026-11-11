import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct VersionedFilesFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    private func file(_ id: String, versions: Int = 2, state: VersionedFileState = .live) -> VersionedFile {
        VersionedFile(id: id, name: "\(id).txt", state: state, versions: versions, bytes: 100)
    }

    private nonisolated static func version(_ id: String) -> FileVersion {
        FileVersion(id: id, size: 10, modifiedAt: Date(timeIntervalSince1970: 0), capturedAt: Date(timeIntervalSince1970: 60))
    }

    private func store(
        state: VersionedFilesFeature.State? = nil,
        page: @escaping @Sendable (VersionedFilesFilter, Int) throws -> VersionedFilesPage = { _, _ in VersionedFilesPage() },
        detail: @escaping @Sendable (String) throws -> VersionedFileDetail = { _ in VersionedFileDetail() },
        delete: @escaping @Sendable (String, [String]?) throws -> VersionsDeletion = { _, _ in VersionsDeletion() }
    ) -> TestStoreOf<VersionedFilesFeature> {
        let store = TestStore(initialState: state ?? VersionedFilesFeature.State(serverURL: serverURL)) {
            VersionedFilesFeature()
        } withDependencies: {
            $0.filesClient.fetchVersionedFiles = { _, filter, offset, _ in try page(filter, offset) }
            $0.filesClient.fetchVersionedFile = { _, id in try detail(id) }
            $0.filesClient.deleteVersionsOfFile = { _, id, ids in try delete(id, ids) }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(files: [VersionedFile] = [], total: Int? = nil, offset: Int = 0) -> VersionedFilesFeature.State {
        var state = VersionedFilesFeature.State(serverURL: serverURL)
        state.page = VersionedFilesPage(files: files, total: total ?? files.count, offset: offset)
        state.offset = offset
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingShowsTheFirstPage() async {
        let store = store(page: { _, offset in
            #expect(offset == 0)
            return VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1, totalBytes: 100, totalVersions: 2)
        })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.files.map(\.id) == ["f1"])
        #expect(store.state.phase == .loaded)
    }

    @Test
    func appearingAgainDoesNotReload() async {
        let store = store(state: loadedState(files: [file("f1")]), page: { _, _ in
            Issue.record("An already loaded page must not be fetched again on appear")
            return VersionedFilesPage()
        })

        await store.send(.onAppear)
    }

    @Test
    func aFirstLoadFailureIsTheFailedPhase() async {
        let store = store(page: { _, _ in throw FilesClientError.server(statusCode: 403) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase.errorMessage != nil)
    }

    @Test
    func aLaterFailureKeepsThePage() async {
        let store = store(state: loadedState(files: [file("f1")]), page: { _, _ in throw FilesClientError.offline })

        await store.send(.searchSubmitted)
        await store.skipReceivedActions()

        #expect(store.state.files.map(\.id) == ["f1"])
        #expect(store.state.listError != nil)
        #expect(!store.state.isReloading)
    }

    // MARK: Filters

    @Test
    func changingAFilterGoesBackToTheFirstPageAndClosesEveryRow() async {
        let asked = LockIsolated<[(VersionedFilesFilter, Int)]>([])
        var state = loadedState(files: [file("f1")], total: 80, offset: 50)
        state.expanded = ["f1"]
        let store = store(state: state, page: { filter, offset in
            asked.withValue { $0.append((filter, offset)) }
            return VersionedFilesPage()
        })

        await store.send(.zoneFilterChanged("z1"))
        await store.skipReceivedActions()
        await store.send(.stateFilterChanged(.orphaned))
        await store.skipReceivedActions()
        await store.send(.sortChanged(.path))
        await store.skipReceivedActions()

        #expect(asked.value.map(\.1) == [0, 0, 0])
        #expect(asked.value.last?.0 == VersionedFilesFilter(zoneID: "z1", state: .orphaned, sort: .path))
        #expect(store.state.expanded.isEmpty)
        #expect(store.state.offset == 0)
    }

    @Test
    func typingASearchWaitsForSubmit() async {
        let store = store(state: loadedState(), page: { _, _ in
            Issue.record("Typing alone must not search")
            return VersionedFilesPage()
        })

        await store.send(.queryChanged("report"))

        #expect(store.state.filter.query == "report")
    }

    @Test
    func submittingTheSearchSendsTheQuery() async {
        let seen = LockIsolated<VersionedFilesFilter?>(nil)
        let store = store(state: loadedState(), page: { filter, _ in
            seen.setValue(filter)
            return VersionedFilesPage()
        })

        await store.send(.queryChanged("report"))
        await store.send(.searchSubmitted)
        await store.skipReceivedActions()

        #expect(seen.value?.query == "report")
    }

    // MARK: Paging

    @Test
    func nextAndPreviousMoveByOnePage() async {
        let offsets = LockIsolated<[Int]>([])
        let files = (0 ..< 25).map { file("f\($0)") }
        let store = store(state: loadedState(files: files, total: 60), page: { _, offset in
            offsets.withValue { $0.append(offset) }
            return VersionedFilesPage(files: files, total: 60, offset: offset)
        })

        await store.send(.nextPageTapped)
        await store.skipReceivedActions()
        await store.send(.nextPageTapped)
        await store.skipReceivedActions()
        await store.send(.previousPageTapped)
        await store.skipReceivedActions()

        #expect(offsets.value == [25, 50, 25])
        #expect(store.state.offset == 25)
    }

    @Test
    func nextDoesNothingOnTheLastPageAndPreviousDoesNothingOnTheFirst() async {
        let store = store(state: loadedState(files: [file("f1")], total: 1), page: { _, _ in
            Issue.record("There is no other page to fetch")
            return VersionedFilesPage()
        })

        await store.send(.nextPageTapped)
        await store.send(.previousPageTapped)

        #expect(store.state.offset == 0)
    }

    @Test
    func changingPageClosesTheOpenRows() async {
        var state = loadedState(files: (0 ..< 25).map { file("f\($0)") }, total: 60)
        state.expanded = ["f1"]
        let store = store(state: state, page: { _, _ in VersionedFilesPage(total: 60) })

        await store.send(.nextPageTapped)

        #expect(store.state.expanded.isEmpty)
    }

    // MARK: Opening a history

    @Test
    func openingARowLoadsItsVersionsOnce() async {
        let reads = LockIsolated(0)
        let store = store(state: loadedState(files: [file("f1")]), detail: { _ in
            reads.withValue { $0 += 1 }
            return VersionedFileDetail(versions: [Self.version("v1")], totalBytes: 10)
        })

        await store.send(.fileToggled("f1"))
        await store.skipReceivedActions()
        #expect(store.state.expanded == ["f1"])
        #expect(store.state.details["f1"]?.versions.map(\.id) == ["v1"])

        await store.send(.fileToggled("f1"))
        #expect(store.state.expanded.isEmpty)

        await store.send(.fileToggled("f1"))
        #expect(reads.value == 1)
    }

    @Test
    func aFailedHistoryReadShowsTheErrorUnderTheRowAndRetriesOnReopen() async {
        let store = store(state: loadedState(files: [file("f1")]), detail: { _ in throw FilesClientError.offline })

        await store.send(.fileToggled("f1"))
        await store.skipReceivedActions()
        #expect(store.state.detailErrors["f1"] != nil)
        #expect(store.state.details["f1"] == nil)

        await store.send(.fileToggled("f1"))
        await store.send(.fileToggled("f1"))
        #expect(store.state.detailErrors["f1"] == nil)
    }

    // MARK: Selecting and deleting

    @Test
    func versionsAreTickedAndUntickedPerFile() async {
        let store = store(state: loadedState(files: [file("f1"), file("f2")]))

        await store.send(.versionToggled(fileID: "f1", versionID: "v1"))
        await store.send(.versionToggled(fileID: "f1", versionID: "v2"))
        await store.send(.versionToggled(fileID: "f2", versionID: "v9"))
        #expect(store.state.selection["f1"] == ["v1", "v2"])
        #expect(store.state.selection["f2"] == ["v9"])

        await store.send(.versionToggled(fileID: "f1", versionID: "v1"))
        await store.send(.versionToggled(fileID: "f1", versionID: "v2"))
        #expect(store.state.selection["f1"] == nil)
        #expect(store.state.selection["f2"] == ["v9"])
    }

    @Test
    func deletingSelectedAsksFirstWithTheTickedVersionsInOrder() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version("v1"), Self.version("v2"), Self.version("v3")])
        state.selection["f1"] = ["v3", "v1"]
        let store = store(state: state, delete: { _, _ in
            Issue.record("Nothing is deleted before the confirmation")
            return VersionsDeletion()
        })

        await store.send(.deleteSelectedTapped(fileID: "f1"))

        #expect(store.state.confirmation == .selected(fileID: "f1", versionIDs: ["v1", "v3"]))
    }

    @Test
    func deletingSelectedWithNothingTickedDoesNothing() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version("v1")])
        let store = store(state: state)

        await store.send(.deleteSelectedTapped(fileID: "f1"))

        #expect(store.state.confirmation == nil)
    }

    @Test
    func aTickedVersionThatNoLongerExistsIsNotOffered() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version("v1")])
        state.selection["f1"] = ["ghost"]
        let store = store(state: state)

        await store.send(.deleteSelectedTapped(fileID: "f1"))

        #expect(store.state.confirmation == nil)
    }

    @Test
    func cancellingTheConfirmationDeletesNothing() async {
        var state = loadedState(files: [file("f1")])
        state.confirmation = .all(fileID: "f1")
        let store = store(state: state, delete: { _, _ in
            Issue.record("Cancelling must not delete")
            return VersionsDeletion()
        })

        await store.send(.confirmationCancelled)

        #expect(store.state.confirmation == nil)
        #expect(!store.state.isWorking)
    }

    @Test
    func confirmingDeleteAllSendsNoIDsThenReloadsTheListAndTheOpenHistory() async {
        let sent = LockIsolated<(String, [String]?)?>(nil)
        let reads = LockIsolated(0)
        var state = loadedState(files: [file("f1")])
        state.expanded = ["f1"]
        state.details["f1"] = VersionedFileDetail(versions: [Self.version("v1")])
        state.selection["f1"] = ["v1"]
        state.confirmation = .all(fileID: "f1")
        let store = store(state: state, page: { _, _ in
            VersionedFilesPage(files: [VersionedFile(id: "f1", name: "f1.txt", versions: 1)], total: 1)
        }, detail: { _ in
            reads.withValue { $0 += 1 }
            return VersionedFileDetail(versions: [Self.version("v9")])
        }, delete: { id, ids in
            sent.setValue((id, ids))
            return VersionsDeletion(deleted: 1, remaining: 1)
        })

        await store.send(.confirmationConfirmed)
        await store.skipReceivedActions()

        #expect(sent.value?.0 == "f1")
        #expect(sent.value?.1 == nil)
        #expect(reads.value == 1)
        #expect(store.state.selection["f1"] == nil)
        #expect(store.state.details["f1"]?.versions.map(\.id) == ["v9"])
        #expect(store.state.confirmation == nil)
        #expect(!store.state.isWorking)
    }

    @Test
    func confirmingDeleteSelectedSendsTheTickedIDs() async {
        let sent = LockIsolated<[String]?>(nil)
        var state = loadedState(files: [file("f1")])
        state.confirmation = .selected(fileID: "f1", versionIDs: ["v1", "v3"])
        let store = store(state: state, delete: { _, ids in
            sent.setValue(ids)
            return VersionsDeletion(deleted: 2, remaining: 1)
        })

        await store.send(.confirmationConfirmed)
        await store.skipReceivedActions()

        #expect(sent.value == ["v1", "v3"])
    }

    @Test
    func deletingEverythingClosesTheRowInsteadOfReadingAHistoryThatMayBeGone() async {
        let reads = LockIsolated(0)
        var state = loadedState(files: [file("f1", state: .orphaned)])
        state.expanded = ["f1"]
        state.details["f1"] = VersionedFileDetail(versions: [Self.version("v1")])
        state.confirmation = .all(fileID: "f1")
        let store = store(state: state, page: { _, _ in VersionedFilesPage() }, detail: { _ in
            reads.withValue { $0 += 1 }
            throw FilesClientError.serverMessage(statusCode: 404, message: "This history does not exist.")
        }, delete: { _, _ in VersionsDeletion(deleted: 1, remaining: 0) })

        await store.send(.confirmationConfirmed)
        await store.skipReceivedActions()

        #expect(reads.value == 0)
        #expect(store.state.expanded.isEmpty)
        #expect(store.state.details["f1"] == nil)
        #expect(store.state.detailErrors["f1"] == nil)
        #expect(store.state.files.isEmpty)
    }

    @Test
    func aFailedDeletionKeepsTheSelectionAndShowsTheError() async {
        var state = loadedState(files: [file("f1")])
        state.selection["f1"] = ["v1"]
        state.confirmation = .selected(fileID: "f1", versionIDs: ["v1"])
        let store = store(state: state, delete: { _, _ in throw FilesClientError.serverMessage(statusCode: 500, message: "Could not delete.") })

        await store.send(.confirmationConfirmed)
        await store.skipReceivedActions()

        #expect(store.state.listError == "Could not delete.")
        #expect(store.state.selection["f1"] == ["v1"])
        #expect(!store.state.isWorking)
    }

    @Test
    func confirmingWithNothingAskedDoesNothing() async {
        let store = store(state: loadedState(), delete: { _, _ in
            Issue.record("There was nothing to confirm")
            return VersionsDeletion()
        })

        await store.send(.confirmationConfirmed)

        #expect(!store.state.isWorking)
    }

    // MARK: Admin only

    @Test
    func aNonAdminCannotOpenTheVersionsList() async {
        let user = User(id: "1", username: "jdoe", email: nil, roles: [])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: user)) { SettingsFeature() }

        await store.send(.versionedFilesButtonTapped)

        #expect(store.state.versionedFiles == nil)
    }

    @Test
    func anAdminOpensTheVersionsList() async {
        let admin = User(id: "a", username: "boss", email: nil, roles: [UserRole.admin])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: admin)) { SettingsFeature() }

        await store.send(.versionedFilesButtonTapped) { $0.versionedFiles = VersionedFilesFeature.State(serverURL: serverURL) }
    }

    // MARK: Retry, paging after a delete

    @Test
    func appearingAgainAfterAFailedFirstLoadTriesAgain() async {
        var state = VersionedFilesFeature.State(serverURL: serverURL)
        state.phase = .failed("offline")
        let store = store(state: state, page: { _, _ in VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase == .loaded)
        #expect(store.state.files.map(\.id) == ["f1"])
    }

    @Test
    func anEmptyPageAfterADeleteStepsBackToTheLastPageWithRows() async {
        let pageSize = VersionedFilesPage.defaultPageSize
        let store = store(
            state: loadedState(files: [file("f1")], total: pageSize + 1, offset: pageSize),
            page: { _, offset in
                offset == pageSize
                    ? VersionedFilesPage(files: [], total: pageSize, offset: offset)
                    : VersionedFilesPage(files: [VersionedFile(id: "f2", name: "b")], total: pageSize, offset: offset)
            }
        )

        await store.send(.deleteResponse(fileID: "f1", .success(VersionsDeletion(deleted: 1, remaining: 0))))
        await store.skipReceivedActions()

        #expect(store.state.offset == 0)
        #expect(store.state.files.map(\.id) == ["f2"])
    }

    @Test
    func versionsTheServerCouldNotDeleteShowAnErrorAfterTheReload() async {
        var state = loadedState(files: [file("f1")])
        state.confirmation = .all(fileID: "f1")
        let store = store(state: state, page: { _, _ in VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1) }, delete: { _, _ in
            VersionsDeletion(deleted: 0, remaining: 2, failed: 2)
        })

        await store.send(.confirmationConfirmed)
        await store.skipReceivedActions()

        #expect(store.state.listError != nil)
    }

    @Test
    func refreshingReadsTheListAndTheOpenHistoriesAgain() async {
        var state = loadedState(files: [file("f1")])
        state.expanded = ["f1"]
        state.details = ["f1": VersionedFileDetail(versions: [Self.version("old")])]
        let store = store(state: state, page: { _, _ in VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1) }, detail: { _ in
            VersionedFileDetail(versions: [Self.version("new")])
        })

        await store.send(.refreshTapped)
        await store.skipReceivedActions()

        #expect(store.state.details["f1"]?.versions.map(\.id) == ["new"])
    }
}
