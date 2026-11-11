import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct ActivityLogFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    private func event(_ id: String, at: String = "2026-11-11T07:00:00.000Z", action: String = "sign-in") -> ActivityEvent {
        ActivityEvent(id: id, at: at, action: action, actor: "phillip")
    }

    private func store(
        state: ActivityLogFeature.State? = nil,
        settings: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(activity: ActivitySettings(isEnabled: true, retentionDays: 30)) },
        page: @escaping @Sendable (ActivityFilter, String?) throws -> ActivityPage = { _, _ in ActivityPage(isEnabled: true) },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() },
        clear: @escaping @Sendable () throws -> Void = {}
    ) -> TestStoreOf<ActivityLogFeature> {
        let store = TestStore(initialState: state ?? ActivityLogFeature.State(serverURL: serverURL)) {
            ActivityLogFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in try settings() }
            $0.filesClient.fetchActivity = { _, filter, before in try page(filter, before) }
            $0.filesClient.updateSystemSettings = { _, patch in try update(patch) }
            $0.filesClient.clearActivity = { _ in try clear() }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(_ settings: ActivitySettings = ActivitySettings(isEnabled: true, retentionDays: 30)) -> ActivityLogFeature.State {
        var state = ActivityLogFeature.State(serverURL: serverURL)
        state.loadedSettings = settings
        state.isEnabledDraft = settings.isEnabled
        state.retentionText = String(settings.retentionDays)
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingSeedsTheSettingsAndTheFirstPage() async {
        let store = store(page: { _, _ in
            ActivityPage(events: [ActivityEvent(id: "1", at: "2026-11-11T07:00:00.000Z", action: "sign-in")], nextBefore: "cursor", isEnabled: true, actions: ["sign-in"])
        })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.loadedSettings == ActivitySettings(isEnabled: true, retentionDays: 30))
        #expect(store.state.isEnabledDraft)
        #expect(store.state.retentionText == "30")
        #expect(store.state.events.map(\.id) == ["1"])
        #expect(store.state.actions == ["sign-in"])
        #expect(store.state.nextBefore == "cursor")
        #expect(store.state.phase == .loaded)
    }

    @Test
    func aNonAdminResponseWithoutActivitySettingsIsUnavailable() async {
        let store = store(settings: { SystemSettings() })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
    }

    @Test
    func aFirstPageFailureIsTheFailedPhase() async {
        let store = store(page: { _, _ in throw FilesClientError.server(statusCode: 403) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase.errorMessage != nil)
    }

    @Test
    func aLaterFailureKeepsWhatWasLoaded() async {
        var state = loadedState()
        state.events = [event("1")]
        let store = store(state: state, page: { _, _ in throw FilesClientError.offline })

        await store.send(.refreshTapped)
        await store.skipReceivedActions()

        #expect(store.state.events.map(\.id) == ["1"])
        #expect(store.state.listError != nil)
        #expect(store.state.phase == .loaded)
    }

    @Test
    func reloadingKeepsSettingsBeingEdited() async {
        var state = loadedState()
        state.retentionText = "999"
        let store = store(state: state, settings: { SystemSettings(activity: ActivitySettings(isEnabled: false, retentionDays: 7)) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.retentionText == "999")
        #expect(store.state.loadedSettings?.retentionDays == 7)
    }

    // MARK: Paging

    @Test
    func showMoreAppendsTheNextPageFromTheCursor() async {
        let asked = LockIsolated<String?>(nil)
        var state = loadedState()
        state.events = [event("1")]
        state.nextBefore = "cursor-1"
        let store = store(state: state, page: { _, before in
            asked.setValue(before)
            return ActivityPage(events: [ActivityEvent(id: "2", at: "2026-11-11T06:00:00.000Z", action: "sign-out")], nextBefore: nil, isEnabled: true)
        })

        await store.send(.loadMoreTapped)
        await store.skipReceivedActions()

        #expect(asked.value == "cursor-1")
        #expect(store.state.events.map(\.id) == ["1", "2"])
        #expect(store.state.nextBefore == nil)
        #expect(!store.state.isLoadingMore)
    }

    @Test
    func showMoreDoesNothingAtTheEnd() async {
        let store = store(state: loadedState(), page: { _, _ in
            Issue.record("There is no next page to ask for")
            return ActivityPage()
        })

        await store.send(.loadMoreTapped)

        #expect(!store.state.canLoadMore)
        #expect(!store.state.isLoadingMore)
    }

    @Test
    func aFailedShowMoreKeepsTheListAndAllowsRetry() async {
        var state = loadedState()
        state.events = [event("1")]
        state.nextBefore = "cursor"
        let store = store(state: state, page: { _, _ in throw FilesClientError.offline })

        await store.send(.loadMoreTapped)
        await store.skipReceivedActions()

        #expect(store.state.events.map(\.id) == ["1"])
        #expect(store.state.listError != nil)
        #expect(store.state.nextBefore == "cursor")
        #expect(store.state.canLoadMore)
    }

    // MARK: Filters

    @Test
    func changingAFilterReloadsFromTheTopWithThatFilter() async {
        let seen = LockIsolated<[ActivityFilter]>([])
        var state = loadedState()
        state.events = [event("old")]
        state.nextBefore = "stale"
        let store = store(state: state, page: { filter, before in
            seen.withValue { $0.append(filter) }
            #expect(before == nil)
            return ActivityPage(events: [ActivityEvent(id: "new", at: "2026-11-11T07:00:00.000Z", action: "file.delete")], isEnabled: true)
        })

        await store.send(.actionFilterChanged("file.delete"))
        await store.skipReceivedActions()
        await store.send(.outcomeFilterChanged(.refused))
        await store.skipReceivedActions()

        #expect(seen.value.first == ActivityFilter(action: "file.delete"))
        #expect(seen.value.last == ActivityFilter(action: "file.delete", outcome: .refused))
        #expect(store.state.events.map(\.id) == ["new"])
        #expect(store.state.nextBefore == nil)
    }

    @Test
    func typingASearchWaitsForSubmitBeforeAskingTheServer() async {
        let store = store(state: loadedState(), page: { _, _ in
            Issue.record("Typing alone must not search")
            return ActivityPage()
        })

        await store.send(.queryChanged("report"))

        #expect(store.state.filter.query == "report")
    }

    @Test
    func submittingTheSearchSendsTheQuery() async {
        let seen = LockIsolated<ActivityFilter?>(nil)
        let store = store(state: loadedState(), page: { filter, _ in
            seen.setValue(filter)
            return ActivityPage(isEnabled: true)
        })

        await store.send(.queryChanged("report"))
        await store.send(.searchSubmitted)
        await store.skipReceivedActions()

        #expect(seen.value?.query == "report")
    }

    // MARK: Settings

    @Test(arguments: ["", "0", "3651", "99999"])
    func aRetentionOutsideOneToThreeThousandSixHundredFiftyCannotBeSaved(text: String) async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged(text))
        await store.send(.saveSettingsTapped)

        #expect(!store.state.isRetentionValid)
        #expect(!store.state.isSaveSettingsEnabled)
        #expect(!store.state.isSavingSettings)
    }

    @Test(arguments: ["1", "90", "3650"])
    func aRetentionInRangeIsValid(text: String) async {
        let store = store(state: loadedState(ActivitySettings(isEnabled: true, retentionDays: 30)))

        await store.send(.retentionChanged(text))

        #expect(store.state.isRetentionValid)
    }

    @Test
    func retentionKeepsOnlyDigits() async {
        let store = store(state: loadedState())

        await store.send(.retentionChanged("1a2-3 "))

        #expect(store.state.retentionText == "123")
    }

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = store(state: loadedState())

        await store.send(.saveSettingsTapped)

        #expect(!store.state.isSaveSettingsEnabled)
        #expect(!store.state.isSavingSettings)
    }

    @Test
    func savingSendsBothFieldsAndReloadsTheLog() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let pages = LockIsolated(0)
        let echoed = ActivitySettings(isEnabled: false, retentionDays: 14)
        let store = store(state: loadedState(), page: { _, _ in
            pages.withValue { $0 += 1 }
            return ActivityPage(isEnabled: false)
        }, update: { patch in
            sent.setValue(patch)
            return SystemSettings(activity: echoed)
        })

        await store.send(.enabledChanged(false))
        await store.send(.retentionChanged("14"))
        await store.send(.saveSettingsTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.activity == echoed)
        #expect(sent.value?.uploads == nil)
        #expect(store.state.loadedSettings == echoed)
        #expect(!store.state.isSettingsDirty)
        #expect(pages.value == 1)
        #expect(!store.state.isSavingSettings)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(state: loadedState(), update: { _ in throw FilesClientError.serverMessage(statusCode: 400, message: "Bad retention.") })

        await store.send(.retentionChanged("14"))
        await store.send(.saveSettingsTapped)
        await store.skipReceivedActions()

        #expect(store.state.settingsError == "Bad retention.")
        #expect(store.state.retentionText == "14")
        #expect(store.state.isSettingsDirty)
    }

    @Test
    func anEchoWithoutActivityIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings() })

        await store.send(.enabledChanged(false))
        await store.send(.saveSettingsTapped)
        await store.skipReceivedActions()

        #expect(store.state.settingsError != nil)
        #expect(!store.state.isSavingSettings)
    }

    // MARK: Emptying the log

    @Test
    func emptyingTheLogAsksFirstAndCancelLeavesItAlone() async {
        let store = store(state: loadedState(), clear: {
            Issue.record("Cancelling must not clear the log")
        })

        await store.send(.clearTapped)
        #expect(store.state.isConfirmingClear)

        await store.send(.clearCancelled)
        #expect(!store.state.isConfirmingClear)
        #expect(!store.state.isClearing)
    }

    @Test
    func confirmingEmptiesTheLogThenReloadsIt() async {
        let cleared = LockIsolated(false)
        var state = loadedState()
        state.events = [event("1")]
        let store = store(state: state, page: { _, _ in ActivityPage(events: [], isEnabled: true) }, clear: {
            cleared.setValue(true)
        })

        await store.send(.clearTapped)
        await store.send(.clearConfirmed)
        await store.skipReceivedActions()

        #expect(cleared.value)
        #expect(store.state.events.isEmpty)
        #expect(!store.state.isClearing)
        #expect(!store.state.isConfirmingClear)
    }

    @Test
    func aFailedClearKeepsTheListAndShowsTheError() async {
        var state = loadedState()
        state.events = [event("1")]
        let store = store(state: state, clear: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.clearConfirmed)
        await store.skipReceivedActions()

        #expect(store.state.events.map(\.id) == ["1"])
        #expect(store.state.listError != nil)
        #expect(!store.state.isClearing)
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

    // MARK: Paging with an unsubmitted search

    @Test
    func showMoreKeepsTheSearchTheListWasFetchedWith() async {
        var state = loadedState()
        state.nextBefore = "cursor"
        state.events = [event("1")]
        let store = store(state: state, page: { filter, before in
            #expect(filter.query == "")
            #expect(before == "cursor")
            return ActivityPage(events: [ActivityEvent(id: "2", at: "2026-11-10T07:00:00.000Z", action: "sign-in")], isEnabled: true)
        })

        await store.send(.queryChanged("typed but not submitted"))
        await store.send(.loadMoreTapped)
        await store.skipReceivedActions()

        #expect(store.state.events.map(\.id) == ["1", "2"])
    }

    @Test
    func aSettingsReloadThatLandsDuringASaveIsIgnored() async {
        var state = loadedState()
        state.isSavingSettings = true
        let store = store(state: state)

        await store.send(.settingsResponse(.success(SystemSettings(activity: ActivitySettings(isEnabled: false, retentionDays: 1)))))

        #expect(store.state.loadedSettings == ActivitySettings(isEnabled: true, retentionDays: 30))
    }
}
