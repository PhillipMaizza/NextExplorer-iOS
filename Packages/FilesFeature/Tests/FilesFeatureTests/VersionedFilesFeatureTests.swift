import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

@Suite(.isolatedDependencies)
@MainActor
struct VersionedFilesFeatureTests {
    private typealias Store = TestStoreOf<VersionedFilesFeature>
    private typealias State = VersionedFilesFeature.State

    struct PageCall: Equatable, Sendable {
        let filter: VersionedFilesFilter
        let offset: Int
        let limit: Int
    }

    struct DeleteCall: Equatable, Sendable {
        let fileID: String
        let versionIDs: [String]?
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let pageGate = AsyncGate()
    private let pageCalls = LockIsolated<[PageCall]>([])
    private let detailCalls = LockIsolated<[String]>([])
    private let deleteCalls = LockIsolated<[DeleteCall]>([])

    private func file(_ id: String, versions: Int = 2, state: VersionedFileState = .live) -> VersionedFile {
        VersionedFile(id: id, name: "\(id).txt", state: state, versions: versions, bytes: 100)
    }

    private nonisolated static func version(_ id: String) -> FileVersion {
        FileVersion(id: id, size: 10, modifiedAt: MockDate.date, capturedAt: MockDate.date.addingTimeInterval(60))
    }

    private func makeStore(
        _ state: State? = nil,
        page: @escaping @Sendable (VersionedFilesFilter, Int) async throws -> VersionedFilesPage = { _, _ in VersionedFilesPage() },
        detail: @escaping @Sendable (String) async throws -> VersionedFileDetail = { _ in VersionedFileDetail() },
        delete: @escaping @Sendable (String, [String]?) async throws -> VersionsDeletion = { _, _ in VersionsDeletion() }
    ) -> Store {
        let pageCalls = pageCalls
        let detailCalls = detailCalls
        let deleteCalls = deleteCalls
        return TestStore(initialState: state ?? State(serverURL: serverURL)) {
            VersionedFilesFeature()
        } withDependencies: {
            $0.filesClient.fetchVersionedFiles = { _, filter, offset, limit in
                pageCalls.withValue { $0.append(PageCall(filter: filter, offset: offset, limit: limit)) }
                return try await page(filter, offset)
            }
            $0.filesClient.fetchVersionedFile = { _, id in
                detailCalls.withValue { $0.append(id) }
                return try await detail(id)
            }
            $0.filesClient.deleteVersionsOfFile = { _, id, ids in
                deleteCalls.withValue { $0.append(DeleteCall(fileID: id, versionIDs: ids)) }
                return try await delete(id, ids)
            }
        }
    }

    /// A page answer that waits until the test opens `pageGate`, for the actions that start a
    /// page read and a history read side by side.
    private func gatedPage(_ page: VersionedFilesPage) -> @Sendable (VersionedFilesFilter, Int) async throws -> VersionedFilesPage {
        { [pageGate] _, _ in
            try await pageGate.wait()
            return page
        }
    }

    private func loadedState(files: [VersionedFile] = [], total: Int? = nil, offset: Int = 0) -> State {
        var state = State(serverURL: serverURL)
        state.page = VersionedFilesPage(files: files, total: total ?? files.count, offset: offset)
        state.offset = offset
        state.phase = .loaded
        return state
    }

    /// The answer to the page read a reload started: it ends the reload and replaces the page.
    private func receivePage(_ store: Store, _ page: VersionedFilesPage) async {
        await store.receive(.pageResponse(.success(page))) {
            $0.isReloading = false
            $0.page = page
        }
    }

    // MARK: Loading

    @Test
    func loadingShowsTheFirstPage() async {
        let page = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1, totalBytes: 100, totalVersions: 2)
        let store = makeStore(page: { _, _ in page })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(.pageResponse(.success(page))) {
            $0.phase = .loaded
            $0.page = page
        }
        #expect(pageCalls.value == [PageCall(filter: VersionedFilesFilter(), offset: 0, limit: 25)])
    }

    @Test
    func appearingAgainDoesNotReload() async {
        let store = makeStore(loadedState(files: [file("f1")]))

        await store.send(.onAppear)
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func aFirstLoadFailureIsTheFailedPhase() async {
        let store = makeStore(page: { _, _ in throw FilesClientError.server(statusCode: 403) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(.pageResponse(.failure(.server(statusCode: 403)))) { $0.phase = .failed(L10n.Error.server(403)) }
    }

    @Test
    func appearingAgainAfterAFailedFirstLoadTriesAgain() async {
        var state = State(serverURL: serverURL)
        state.phase = .failed(TestFailure.offline)
        let page = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "a")], total: 1)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(.pageResponse(.success(page))) {
            $0.phase = .loaded
            $0.page = page
        }
    }

    @Test
    func aLaterFailureKeepsThePage() async {
        let store = makeStore(loadedState(files: [file("f1")]), page: { _, _ in throw FilesClientError.offline })

        await store.send(.searchSubmitted) { $0.isReloading = true }
        await store.receive(.pageResponse(.failure(.offline))) {
            $0.isReloading = false
            $0.listError = L10n.Error.offline
        }
        #expect(store.state.files.map(\.id) == ["f1"])
    }

    @Test
    func aPageThatDropsAFileAlsoDropsItsHistoryAndSelection() async {
        var state = loadedState(files: [file("f1"), file("f2")])
        let detail = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        state.details = ["f1": detail, "f2": VersionedFileDetail(versions: [Self.version(TestETag.second)])]
        state.selection = ["f1": [TestETag.first], "f2": [TestETag.second]]
        let page = VersionedFilesPage(files: [file("f1")], total: 1)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.searchSubmitted) { $0.isReloading = true }
        await store.receive(.pageResponse(.success(page))) {
            $0.isReloading = false
            $0.page = page
            $0.details = ["f1": detail]
            $0.selection = ["f1": [TestETag.first]]
        }
    }

    // MARK: Filters

    struct FilterCase: Sendable {
        let action: VersionedFilesFeature.Action
        let expected: VersionedFilesFilter
    }

    @Test(
        "Changing a filter goes back to the first page and closes every row",
        arguments: [
            FilterCase(action: .zoneFilterChanged("z1"), expected: VersionedFilesFilter(zoneID: "z1")),
            FilterCase(action: .stateFilterChanged(.orphaned), expected: VersionedFilesFilter(state: .orphaned)),
            FilterCase(action: .sortChanged(.path), expected: VersionedFilesFilter(sort: .path)),
        ]
    )
    func changingAFilterGoesBackToTheFirstPageAndClosesEveryRow(_ testCase: FilterCase) async {
        var state = loadedState(files: [file("f1")], total: 80, offset: 50)
        state.expanded = ["f1"]
        let page = VersionedFilesPage()
        let store = makeStore(state, page: { _, _ in page })

        await store.send(testCase.action) {
            $0.filter = testCase.expected
            $0.offset = 0
            $0.expanded = []
            $0.isReloading = true
        }
        await receivePage(store, page)
        #expect(pageCalls.value == [PageCall(filter: testCase.expected, offset: 0, limit: 25)])
    }

    @Test
    func typingASearchWaitsForSubmit() async {
        let store = makeStore(loadedState())

        await store.send(.queryChanged("report")) { $0.filter.query = "report" }
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func submittingTheSearchSendsTheQuery() async {
        let page = VersionedFilesPage()
        let store = makeStore(loadedState(), page: { _, _ in page })

        await store.send(.queryChanged("report")) { $0.filter.query = "report" }
        await store.send(.searchSubmitted) { $0.isReloading = true }
        await receivePage(store, page)
        #expect(pageCalls.value == [PageCall(filter: VersionedFilesFilter(query: "report"), offset: 0, limit: 25)])
    }

    // MARK: Paging

    @Test
    func nextAndPreviousMoveByOnePage() async {
        let files = (0 ..< 25).map { file("f\($0)") }
        let store = makeStore(loadedState(files: files, total: 60), page: { _, offset in
            VersionedFilesPage(files: files, total: 60, offset: offset)
        })

        await store.send(.nextPageTapped) {
            $0.offset = 25
            $0.isReloading = true
        }
        await receivePage(store, VersionedFilesPage(files: files, total: 60, offset: 25))
        await store.send(.nextPageTapped) {
            $0.offset = 50
            $0.isReloading = true
        }
        await receivePage(store, VersionedFilesPage(files: files, total: 60, offset: 50))
        await store.send(.previousPageTapped) {
            $0.offset = 25
            $0.isReloading = true
        }
        await receivePage(store, VersionedFilesPage(files: files, total: 60, offset: 25))

        #expect(pageCalls.value.map(\.offset) == [25, 50, 25])
    }

    @Test
    func nextDoesNothingOnTheLastPageAndPreviousDoesNothingOnTheFirst() async {
        let store = makeStore(loadedState(files: [file("f1")], total: 1))

        await store.send(.nextPageTapped)
        await store.send(.previousPageTapped)
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func changingPageClosesTheOpenRows() async {
        let files = (0 ..< 25).map { file("f\($0)") }
        var state = loadedState(files: files, total: 60)
        state.expanded = ["f1"]
        let page = VersionedFilesPage(files: files, total: 60, offset: 25)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.nextPageTapped) {
            $0.offset = 25
            $0.expanded = []
            $0.isReloading = true
        }
        await receivePage(store, page)
    }

    // MARK: Opening a history

    @Test
    func openingARowLoadsItsVersionsOnce() async {
        let detail = VersionedFileDetail(versions: [Self.version(TestETag.first)], totalBytes: 10)
        let store = makeStore(loadedState(files: [file("f1")]), detail: { _ in detail })

        await store.send(.fileToggled("f1")) { $0.expanded = ["f1"] }
        await store.receive(.detailResponse(fileID: "f1", .success(detail))) { $0.details["f1"] = detail }

        await store.send(.fileToggled("f1")) { $0.expanded = [] }
        await store.send(.fileToggled("f1")) { $0.expanded = ["f1"] }
        #expect(detailCalls.value == ["f1"])
    }

    @Test
    func aFailedHistoryReadShowsTheErrorUnderTheRowAndRetriesOnReopen() async {
        let attempts = LockIsolated(0)
        let detail = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        let store = makeStore(loadedState(files: [file("f1")]), detail: { _ in
            if attempts.withValue({ $0 += 1; return $0 }) == 1 { throw FilesClientError.offline }
            return detail
        })

        await store.send(.fileToggled("f1")) { $0.expanded = ["f1"] }
        await store.receive(.detailResponse(fileID: "f1", .failure(.offline))) { $0.detailErrors["f1"] = L10n.Error.offline }
        #expect(store.state.details["f1"] == nil)

        await store.send(.fileToggled("f1")) { $0.expanded = [] }
        await store.send(.fileToggled("f1")) {
            $0.expanded = ["f1"]
            $0.detailErrors["f1"] = nil
        }
        await store.receive(.detailResponse(fileID: "f1", .success(detail))) { $0.details["f1"] = detail }
        #expect(detailCalls.value == ["f1", "f1"])
    }

    // MARK: Selecting and deleting

    @Test
    func versionsAreTickedAndUntickedPerFile() async {
        let store = makeStore(loadedState(files: [file("f1"), file("f2")]))

        await store.send(.versionToggled(fileID: "f1", versionID: TestETag.first)) { $0.selection["f1"] = [TestETag.first] }
        await store.send(.versionToggled(fileID: "f1", versionID: TestETag.second)) { $0.selection["f1"] = [TestETag.first, TestETag.second] }
        await store.send(.versionToggled(fileID: "f2", versionID: "v9")) { $0.selection["f2"] = ["v9"] }

        await store.send(.versionToggled(fileID: "f1", versionID: TestETag.first)) { $0.selection["f1"] = [TestETag.second] }
        await store.send(.versionToggled(fileID: "f1", versionID: TestETag.second)) { $0.selection["f1"] = nil }
        #expect(store.state.selection == ["f2": ["v9"]])
    }

    @Test
    func deletingSelectedAsksFirstWithTheTickedVersionsInOrder() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first), Self.version(TestETag.second), Self.version("v3")])
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

        #expect(deleteCalls.value == [DeleteCall(fileID: "f1", versionIDs: nil)])
        #expect(detailCalls.value == ["f1"])
    }

    @Test
    func confirmingDeleteSelectedSendsTheTickedIDsAndDropsAClosedRowsHistory() async {
        var state = loadedState(files: [file("f1")])
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first), Self.version(TestETag.second), Self.version("v3")])
        state.selection["f1"] = [TestETag.first, "v3"]
        state.confirmation = .selected(fileID: "f1", versionIDs: [TestETag.first, "v3"])
        let newPage = VersionedFilesPage(files: [VersionedFile(id: "f1", name: "f1.txt", versions: 1)], total: 1)
        let store = makeStore(state, page: { _, _ in newPage }, delete: { _, _ in VersionsDeletion(deleted: 2, remaining: 1) })

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

        #expect(deleteCalls.value == [DeleteCall(fileID: "f1", versionIDs: [TestETag.first, "v3"])])
        #expect(detailCalls.value.isEmpty)
    }

    @Test
    func deletingEverythingClosesTheRowInsteadOfReadingAHistoryThatMayBeGone() async {
        var state = loadedState(files: [file("f1", state: .orphaned)])
        state.expanded = ["f1"]
        state.details["f1"] = VersionedFileDetail(versions: [Self.version(TestETag.first)])
        state.confirmation = .all(fileID: "f1")
        let empty = VersionedFilesPage()
        let store = makeStore(state, page: { _, _ in empty }, delete: { _, _ in VersionsDeletion(deleted: 1, remaining: 0) })

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
        let store = makeStore(state, delete: { _, _ in throw FilesClientError.serverMessage(statusCode: 500, message: "Could not delete.") })

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

        await store.send(.deleteResponse(fileID: "f1", .success(VersionsDeletion(deleted: 1, remaining: 0)))) { $0.isReloading = true }
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
        let store = makeStore(state, page: { _, _ in page }, delete: { _, _ in VersionsDeletion(deleted: 0, remaining: 2, failed: 2) })

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
}
