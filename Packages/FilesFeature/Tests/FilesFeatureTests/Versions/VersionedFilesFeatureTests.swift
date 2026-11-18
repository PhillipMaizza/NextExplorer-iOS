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
struct VersionedFilesFeatureTests: VersionedFilesTestSupport {
    let pageGate = AsyncGate()
    let pageCalls = LockIsolated<[VersionedFilesPageCall]>([])
    let detailCalls = LockIsolated<[String]>([])
    let deleteCalls = LockIsolated<[VersionedFilesDeleteCall]>([])

    // MARK: Loading

    @Test
    func loadingShowsTheFirstPage() async {
        let page = VersionedFilesPage(
            files: [VersionedFile(id: "f1", name: "a")],
            total: 1,
            totalBytes: 100,
            totalVersions: 2
        )
        let store = makeStore(page: { _, _ in page })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(.pageResponse(.success(page))) {
            $0.phase = .loaded
            $0.page = page
        }
        #expect(pageCalls.value == [VersionedFilesPageCall(filter: VersionedFilesFilter(), offset: 0, limit: 25)])
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
        await store
            .receive(.pageResponse(.failure(.server(statusCode: 403)))) { $0.phase = .failed(L10n.Error.server(403)) }
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
        #expect(pageCalls.value == [VersionedFilesPageCall(filter: testCase.expected, offset: 0, limit: 25)])
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
        #expect(pageCalls.value == [VersionedFilesPageCall(
            filter: VersionedFilesFilter(query: "report"),
            offset: 0,
            limit: 25
        )])
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
            if attempts.withValue({ $0 += 1; return $0 }) == 1 {
                throw FilesClientError.offline
            }
            return detail
        })

        await store.send(.fileToggled("f1")) { $0.expanded = ["f1"] }
        await store
            .receive(.detailResponse(fileID: "f1", .failure(.offline))) { $0.detailErrors["f1"] = L10n.Error.offline }
        #expect(store.state.details["f1"] == nil)

        await store.send(.fileToggled("f1")) { $0.expanded = [] }
        await store.send(.fileToggled("f1")) {
            $0.expanded = ["f1"]
            $0.detailErrors["f1"] = nil
        }
        await store.receive(.detailResponse(fileID: "f1", .success(detail))) { $0.details["f1"] = detail }
        #expect(detailCalls.value == ["f1", "f1"])
    }

    // MARK: Admin only

    @Test
    func aNonAdminCannotOpenTheVersionsList() async {
        let user = User(id: "1", username: "jdoe", email: nil, roles: [])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: user)) {
            SettingsFeature()
        }

        await store.send(.versionedFilesButtonTapped)
        #expect(store.state.versionedFiles == nil)
    }

    @Test
    func anAdminOpensTheVersionsList() async {
        let admin = User(id: "a", username: "boss", email: nil, roles: [UserRole.admin])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: admin)) {
            SettingsFeature()
        }

        await store
            .send(.versionedFilesButtonTapped) { $0.versionedFiles = VersionedFilesFeature.State(serverURL: serverURL) }
    }
}
