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
struct ActivityLogFeatureTests {
    private typealias Store = TestStoreOf<ActivityLogFeature>
    private typealias State = ActivityLogFeature.State

    struct PageCall: Equatable, Sendable {
        let filter: ActivityFilter
        let before: String?
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let enabledSettings = ActivitySettings(isEnabled: true, retentionDays: 30)
    private let pageGate = AsyncGate()
    private let pageCalls = LockIsolated<[PageCall]>([])
    private let patches = LockIsolated<[SystemSettingsPatch]>([])
    private let settingsFetches = LockIsolated(0)
    private let clearCalls = LockIsolated(0)

    private func event(_ id: String, at: String = "2026-11-11T07:00:00.000Z", action: String = "sign-in") -> ActivityEvent {
        ActivityEvent(id: id, at: at, action: action, actor: TestAccount.username)
    }

    /// The settings read and the first page start together, so a test that loads both holds the
    /// page behind `pageGate` and receives the settings answer first.
    private func makeStore(
        _ state: State? = nil,
        settings: @escaping @Sendable () async throws -> SystemSettings = { SystemSettings(activity: ActivitySettings(isEnabled: true, retentionDays: 30)) },
        page: @escaping @Sendable (ActivityFilter, String?) async throws -> ActivityPage = { _, _ in ActivityPage(isEnabled: true) },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() },
        clear: @escaping @Sendable () throws -> Void = {}
    ) -> Store {
        let pageCalls = pageCalls
        let patches = patches
        let settingsFetches = settingsFetches
        let clearCalls = clearCalls
        return TestStore(initialState: state ?? State(serverURL: serverURL)) {
            ActivityLogFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in
                settingsFetches.withValue { $0 += 1 }
                return try await settings()
            }
            $0.filesClient.fetchActivity = { _, filter, before in
                pageCalls.withValue { $0.append(PageCall(filter: filter, before: before)) }
                return try await page(filter, before)
            }
            $0.filesClient.updateSystemSettings = { _, patch in
                patches.withValue { $0.append(patch) }
                return try update(patch)
            }
            $0.filesClient.clearActivity = { _ in
                clearCalls.withValue { $0 += 1 }
                try clear()
            }
        }
    }

    private func loadedState(_ settings: ActivitySettings = ActivitySettings(isEnabled: true, retentionDays: 30)) -> State {
        var state = State(serverURL: serverURL)
        state.loadedSettings = settings
        state.isEnabledDraft = settings.isEnabled
        state.retentionText = String(settings.retentionDays)
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingSeedsTheSettingsAndTheFirstPage() async {
        let first = event("1")
        let store = makeStore(page: { [pageGate] _, _ in
            try await pageGate.wait()
            return ActivityPage(events: [first], nextBefore: "cursor", isEnabled: true, actions: ["sign-in"])
        })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.loadedSettings = ActivitySettings(isEnabled: true, retentionDays: 30)
            $0.isEnabledDraft = true
            $0.retentionText = "30"
        }
        pageGate.open()
        await store.receive(\.pageResponse) {
            $0.phase = .loaded
            $0.events = [first]
            $0.actions = ["sign-in"]
            $0.isLogEnabled = true
            $0.nextBefore = "cursor"
        }
        #expect(pageCalls.value == [PageCall(filter: ActivityFilter(), before: nil)])
    }

    @Test
    func aNonAdminResponseWithoutActivitySettingsIsUnavailable() async {
        let store = makeStore(settings: { SystemSettings() }, page: { [pageGate] _, _ in
            try await pageGate.wait()
            return ActivityPage()
        })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) { $0.isUnavailable = true }
        pageGate.open()
        await store.receive(\.pageResponse) { $0.phase = .loaded }
    }

    @Test
    func aSettingsReadThatLaterFindsActivityClearsTheUnavailableFlag() async {
        var state = loadedState()
        state.isUnavailable = true
        let store = makeStore(state)

        await store.send(.settingsResponse(.success(SystemSettings(activity: enabledSettings)))) { $0.isUnavailable = false }
    }

    @Test
    func aFailedSettingsReadShowsTheMessage() async {
        let store = makeStore(loadedState())

        await store.send(.settingsResponse(.failure(.offline))) { $0.settingsError = L10n.Error.offline }
    }

    @Test
    func aFirstPageFailureIsTheFailedPhase() async {
        let store = makeStore(page: { [pageGate] _, _ in
            try await pageGate.wait()
            throw FilesClientError.server(statusCode: 403)
        })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.loadedSettings = ActivitySettings(isEnabled: true, retentionDays: 30)
            $0.isEnabledDraft = true
            $0.retentionText = "30"
        }
        pageGate.open()
        await store.receive(\.pageResponse) { $0.phase = .failed(L10n.Error.server(403)) }
    }

    @Test
    func aLaterFailureKeepsWhatWasLoaded() async {
        var state = loadedState()
        state.events = [event("1")]
        let store = makeStore(state, page: { _, _ in throw FilesClientError.offline })

        await store.send(.refreshTapped)
        await store.receive(.pageResponse(.failure(.offline), isMore: false)) { $0.listError = L10n.Error.offline }
        #expect(store.state.events.map(\.id) == ["1"])
        #expect(store.state.phase == .loaded)
    }

    @Test
    func reloadingKeepsSettingsBeingEdited() async {
        var state = loadedState()
        state.retentionText = "999"
        let store = makeStore(
            state,
            settings: { SystemSettings(activity: ActivitySettings(isEnabled: false, retentionDays: 7)) },
            page: { [pageGate] _, _ in
                try await pageGate.wait()
                return ActivityPage()
            }
        )

        await store.send(.onAppear)
        await store.receive(\.settingsResponse.success) { $0.loadedSettings = ActivitySettings(isEnabled: false, retentionDays: 7) }
        pageGate.open()
        await store.receive(\.pageResponse)
        #expect(store.state.retentionText == "999")
        #expect(store.state.isEnabledDraft)
    }

    @Test
    func openingTheScreenWhileASaveIsRunningLoadsNothing() async {
        var state = loadedState()
        state.isSavingSettings = true
        let store = makeStore(state)

        await store.send(.onAppear)
        #expect(settingsFetches.value == 0)
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func aSettingsReloadThatLandsDuringASaveIsIgnored() async {
        var state = loadedState()
        state.isSavingSettings = true
        let store = makeStore(state)

        await store.send(.settingsResponse(.success(SystemSettings(activity: ActivitySettings(isEnabled: false, retentionDays: 1)))))
        #expect(store.state.loadedSettings == enabledSettings)
    }

    // MARK: Paging

    @Test
    func showMoreAppendsTheNextPageFromTheCursor() async {
        var state = loadedState()
        state.events = [event("1")]
        state.nextBefore = "cursor-1"
        let second = ActivityEvent(id: "2", at: "2026-11-11T06:00:00.000Z", action: "sign-out")
        let page = ActivityPage(events: [second], nextBefore: nil, isEnabled: true)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.loadMoreTapped) { $0.isLoadingMore = true }
        await store.receive(.pageResponse(.success(page), isMore: true)) {
            $0.isLoadingMore = false
            $0.events = [self.event("1"), second]
            $0.isLogEnabled = true
            $0.nextBefore = nil
        }
        #expect(pageCalls.value == [PageCall(filter: ActivityFilter(), before: "cursor-1")])
    }

    @Test
    func showMoreDoesNothingAtTheEnd() async {
        let store = makeStore(loadedState())

        await store.send(.loadMoreTapped)
        #expect(!store.state.canLoadMore)
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func showMoreIsIgnoredWhileAPageIsAlreadyLoading() async {
        var state = loadedState()
        state.nextBefore = "cursor"
        state.isLoadingMore = true
        let store = makeStore(state)

        await store.send(.loadMoreTapped)
        #expect(!store.state.canLoadMore)
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func aFailedShowMoreKeepsTheListAndAllowsRetry() async {
        var state = loadedState()
        state.events = [event("1")]
        state.nextBefore = "cursor"
        let store = makeStore(state, page: { _, _ in throw FilesClientError.offline })

        await store.send(.loadMoreTapped) { $0.isLoadingMore = true }
        await store.receive(.pageResponse(.failure(.offline), isMore: true)) {
            $0.isLoadingMore = false
            $0.listError = L10n.Error.offline
        }
        #expect(store.state.events.map(\.id) == ["1"])
        #expect(store.state.nextBefore == "cursor")
        #expect(store.state.canLoadMore)
    }

    @Test
    func showMoreKeepsTheSearchTheListWasFetchedWith() async {
        var state = loadedState()
        state.nextBefore = "cursor"
        state.events = [event("1")]
        let second = ActivityEvent(id: "2", at: "2026-11-10T07:00:00.000Z", action: "sign-in")
        let page = ActivityPage(events: [second], isEnabled: true)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.queryChanged("typed but not submitted")) { $0.filter.query = "typed but not submitted" }
        await store.send(.loadMoreTapped) { $0.isLoadingMore = true }
        await store.receive(.pageResponse(.success(page), isMore: true)) {
            $0.isLoadingMore = false
            $0.events = [self.event("1"), second]
            $0.isLogEnabled = true
            $0.nextBefore = nil
        }
        #expect(pageCalls.value == [PageCall(filter: ActivityFilter(), before: "cursor")])
    }

    // MARK: Filters

    @Test
    func changingFiltersReloadsFromTheTopWithThatFilter() async {
        var state = loadedState()
        state.events = [event(TestValue.outdated)]
        state.nextBefore = "stale"
        let fresh = ActivityEvent(id: "new", at: "2026-11-11T07:00:00.000Z", action: "file.delete")
        let page = ActivityPage(events: [fresh], isEnabled: true)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.actionFilterChanged("file.delete")) {
            $0.filter.action = "file.delete"
            $0.submittedFilter.action = "file.delete"
            $0.nextBefore = nil
        }
        await store.receive(.pageResponse(.success(page), isMore: false)) {
            $0.events = [fresh]
            $0.isLogEnabled = true
        }
        await store.send(.outcomeFilterChanged(.refused)) {
            $0.filter.outcome = .refused
            $0.submittedFilter.outcome = .refused
        }
        await store.receive(.pageResponse(.success(page), isMore: false))

        #expect(pageCalls.value == [
            PageCall(filter: ActivityFilter(action: "file.delete"), before: nil),
            PageCall(filter: ActivityFilter(action: "file.delete", outcome: .refused), before: nil),
        ])
    }

    @Test
    func choosingAnyActionDropsTheActionFilter() async {
        var state = loadedState()
        state.filter = ActivityFilter(action: "file.delete", outcome: .ok)
        state.submittedFilter = state.filter
        let page = ActivityPage(isEnabled: true)
        let store = makeStore(state, page: { _, _ in page })

        await store.send(.actionFilterChanged(nil)) {
            $0.filter.action = nil
            $0.submittedFilter.action = nil
        }
        await store.receive(.pageResponse(.success(page), isMore: false)) { $0.isLogEnabled = true }
        #expect(pageCalls.value == [PageCall(filter: ActivityFilter(outcome: .ok), before: nil)])
    }

    @Test
    func typingASearchWaitsForSubmitBeforeAskingTheServer() async {
        let store = makeStore(loadedState())

        await store.send(.queryChanged("report")) { $0.filter.query = "report" }
        #expect(store.state.submittedFilter.query.isEmpty)
        #expect(pageCalls.value.isEmpty)
    }

    @Test
    func submittingTheSearchSendsTheQuery() async {
        let page = ActivityPage(isEnabled: true)
        let store = makeStore(loadedState(), page: { _, _ in page })

        await store.send(.queryChanged("report")) { $0.filter.query = "report" }
        await store.send(.searchSubmitted) { $0.submittedFilter.query = "report" }
        await store.receive(.pageResponse(.success(page), isMore: false)) { $0.isLogEnabled = true }
        #expect(pageCalls.value == [PageCall(filter: ActivityFilter(query: "report"), before: nil)])
    }

    // MARK: Settings

    @Test(arguments: ["", "0", "3651", "99999"])
    func aRetentionOutsideOneToThreeThousandSixHundredFiftyCannotBeSaved(text: String) async {
        let store = makeStore(loadedState())

        await store.send(.retentionChanged(text)) { $0.retentionText = text }
        await store.send(.saveSettingsTapped)

        #expect(!store.state.isRetentionValid)
        #expect(!store.state.isSaveSettingsEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test(arguments: ["1", "90", "3650"])
    func aRetentionInRangeIsValidAndEnablesSaving(text: String) async {
        let store = makeStore(loadedState())

        await store.send(.retentionChanged(text)) { $0.retentionText = text }

        #expect(store.state.isRetentionValid)
        #expect(store.state.isSaveSettingsEnabled)
    }

    @Test
    func retentionKeepsOnlyDigits() async {
        let store = makeStore(loadedState())

        await store.send(.retentionChanged("1a2-3 ")) { $0.retentionText = "123" }
    }

    @Test
    func editingTheSettingsClearsAShownError() async {
        var state = loadedState()
        state.settingsError = TestValue.outdated
        let store = makeStore(state)

        await store.send(.enabledChanged(false)) {
            $0.isEnabledDraft = false
            $0.settingsError = nil
        }
    }

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = makeStore(loadedState())

        await store.send(.saveSettingsTapped)
        #expect(!store.state.isSaveSettingsEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test
    func savingSendsBothFieldsAndReloadsTheLog() async {
        let echoed = ActivitySettings(isEnabled: false, retentionDays: 14)
        let reloaded = ActivityPage(events: [event("fresh")], isEnabled: false)
        let store = makeStore(loadedState(), page: { _, _ in reloaded }, update: { _ in SystemSettings(activity: echoed) })

        await store.send(.enabledChanged(false)) { $0.isEnabledDraft = false }
        await store.send(.retentionChanged("14")) { $0.retentionText = "14" }
        await store.send(.saveSettingsTapped) { $0.isSavingSettings = true }
        await store.receive(\.saveSettingsResponse.success) {
            $0.isSavingSettings = false
            $0.loadedSettings = echoed
        }
        await store.receive(.pageResponse(.success(reloaded), isMore: false)) { $0.events = [self.event("fresh")] }

        #expect(patches.value == [SystemSettingsPatch(activity: ActivitySettings(isEnabled: false, retentionDays: 14))])
        #expect(!store.state.isSettingsDirty)
        #expect(pageCalls.value.count == 1)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = makeStore(loadedState(), update: { _ in throw FilesClientError.serverMessage(statusCode: 400, message: "Bad retention.") })

        await store.send(.retentionChanged("14")) { $0.retentionText = "14" }
        await store.send(.saveSettingsTapped) { $0.isSavingSettings = true }
        await store.receive(\.saveSettingsResponse.failure) {
            $0.isSavingSettings = false
            $0.settingsError = "Bad retention."
        }
        #expect(store.state.retentionText == "14")
        #expect(store.state.isSettingsDirty)
    }

    @Test
    func anEchoWithoutActivityIsAFailedSave() async {
        let store = makeStore(loadedState(), update: { _ in SystemSettings() })

        await store.send(.enabledChanged(false)) { $0.isEnabledDraft = false }
        await store.send(.saveSettingsTapped) { $0.isSavingSettings = true }
        await store.receive(\.saveSettingsResponse.failure) {
            $0.isSavingSettings = false
            $0.settingsError = L10n.Error.decoding
        }
    }

    // MARK: Emptying the log

    @Test
    func emptyingTheLogAsksFirstAndCancelLeavesItAlone() async {
        let store = makeStore(loadedState())

        await store.send(.clearTapped) { $0.isConfirmingClear = true }
        await store.send(.clearCancelled) { $0.isConfirmingClear = false }
        #expect(clearCalls.value == 0)
    }

    @Test
    func confirmingEmptiesTheLogThenReloadsIt() async {
        var state = loadedState()
        state.events = [event("1")]
        let empty = ActivityPage(events: [], isEnabled: true)
        let store = makeStore(state, page: { _, _ in empty })

        await store.send(.clearTapped) { $0.isConfirmingClear = true }
        await store.send(.clearConfirmed) {
            $0.isConfirmingClear = false
            $0.isClearing = true
        }
        await store.receive(\.clearResponse.success) { $0.isClearing = false }
        await store.receive(.pageResponse(.success(empty), isMore: false)) {
            $0.events = []
            $0.isLogEnabled = true
        }
        #expect(clearCalls.value == 1)
        #expect(pageCalls.value.count == 1)
    }

    @Test
    func aFailedClearKeepsTheListAndShowsTheError() async {
        var state = loadedState()
        state.events = [event("1")]
        let store = makeStore(state, clear: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.clearConfirmed) { $0.isClearing = true }
        await store.receive(\.clearResponse.failure) {
            $0.isClearing = false
            $0.listError = L10n.Error.server(500)
        }
        #expect(store.state.events.map(\.id) == ["1"])
        #expect(pageCalls.value.isEmpty)
    }

    // MARK: Admin only

    @Test
    func aNonAdminCannotOpenTheActivityLog() async {
        let user = User(id: "1", username: "jdoe", email: nil, roles: [])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: user)) { SettingsFeature() }

        await store.send(.activityLogButtonTapped)
        #expect(store.state.activityLog == nil)
    }

    @Test
    func anAdminOpensTheActivityLog() async {
        let admin = User(id: "a", username: "boss", email: nil, roles: [UserRole.admin])
        let store = TestStore(initialState: SettingsFeature.State(serverURL: serverURL, user: admin)) { SettingsFeature() }

        await store.send(.activityLogButtonTapped) { $0.activityLog = ActivityLogFeature.State(serverURL: serverURL) }
    }
}
