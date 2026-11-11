import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct SearchIndexSettingsFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    private func settings(
        enabled: Bool = false,
        paths: [String] = [],
        environment: [String] = []
    ) -> SearchIndexSettings {
        SearchIndexSettings(isEnabled: enabled, excluded: ExcludedPaths(paths: paths, environmentPaths: environment))
    }

    private func store(
        state: SearchIndexSettingsFeature.State? = nil,
        loaded: SearchIndexSettings? = nil,
        features: (@Sendable () throws -> ServerFeatures)? = nil,
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> TestStoreOf<SearchIndexSettingsFeature> {
        let response = SystemSettings(searchIndex: loaded)
        let flags: @Sendable () throws -> ServerFeatures = features ?? { ServerFeatures(isSearchIndexEnabled: loaded?.isEnabled ?? false) }
        let store = TestStore(initialState: state ?? SearchIndexSettingsFeature.State(serverURL: serverURL)) {
            SearchIndexSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in response }
            $0.filesClient.serverFeatures = { _ in try flags() }
            $0.filesClient.updateSystemSettings = { _, patch in try update(patch) }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(_ searchIndex: SearchIndexSettings, lockedBy: String? = nil) -> SearchIndexSettingsFeature.State {
        var state = SearchIndexSettingsFeature.State(serverURL: serverURL)
        state.loaded = searchIndex
        state.draftPaths = searchIndex.excluded.paths
        state.lockedBy = lockedBy
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingSeedsThePathsAndTheLock() async {
        let loaded = settings(enabled: true, paths: ["Backups"], environment: ["tmp"])
        let store = store(loaded: loaded, features: { ServerFeatures(isSearchIndexEnabled: true, searchIndexLockedBy: "SEARCH_INDEX") })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.loaded == loaded)
        #expect(store.state.draftPaths == ["Backups"])
        #expect(store.state.environmentPaths == ["tmp"])
        #expect(store.state.lockedBy == "SEARCH_INDEX")
        #expect(store.state.isEnabled)
        #expect(!store.state.isDirty)
    }

    @Test
    func whenTheFlagsCannotBeReadTheSwitchIsNotLocked() async {
        let store = store(loaded: settings(), features: { throw FilesClientError.offline })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.lockedBy == nil)
        #expect(store.state.phase == .loaded)
    }

    @Test
    func aNonAdminResponseIsUnavailable() async {
        let store = store(loaded: nil)

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
    }

    @Test
    func reloadingKeepsPathsBeingEdited() async {
        var state = loadedState(settings(paths: ["a"]))
        state.draftPaths = ["a", "typed"]
        let store = store(state: state, loaded: settings(paths: ["a", "server"]))

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.draftPaths == ["a", "typed"])
        #expect(store.state.loaded?.excluded.paths == ["a", "server"])
    }

    // MARK: The switch

    @Test
    func movingTheSwitchSavesAtOnceSendingOnlyTheSwitch() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let store = store(state: loadedState(settings(paths: ["a"])), update: { patch in
            sent.setValue(patch)
            return SystemSettings(searchIndex: SearchIndexSettings(isEnabled: true, excluded: ExcludedPaths(paths: ["a"])))
        })

        await store.send(.enabledChanged(true))
        await store.skipReceivedActions()

        #expect(sent.value?.searchIndex == .init(enabled: true))
        #expect(store.state.isEnabled)
        #expect(!store.state.isSaving)
    }

    @Test
    func aLockedSwitchDoesNotMoveOrCallTheServer() async {
        let store = store(state: loadedState(settings(enabled: true), lockedBy: "SEARCH_INDEX"), update: { _ in
            Issue.record("A locked switch must not save")
            return SystemSettings()
        })

        await store.send(.enabledChanged(false))

        #expect(store.state.isEnabled)
        #expect(!store.state.isSaving)
    }

    @Test
    func choosingTheValueAlreadyInForceDoesNothing() async {
        let store = store(state: loadedState(settings(enabled: true)), update: { _ in
            Issue.record("An unchanged switch must not save")
            return SystemSettings()
        })

        await store.send(.enabledChanged(true))

        #expect(!store.state.isSaving)
    }

    @Test
    func aFailedSwitchSaveLeavesTheSwitchWhereItWasAndShowsTheMessage() async {
        let store = store(state: loadedState(settings(enabled: false)), update: { _ in throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.") })

        await store.send(.enabledChanged(true))
        await store.skipReceivedActions()

        #expect(!store.state.isEnabled)
        #expect(store.state.errorMessage == "Admin access required.")
        #expect(!store.state.isSaving)
    }

    @Test
    func theSwitchSavingKeepsUnsavedPathEdits() async {
        var state = loadedState(settings(paths: ["a"]))
        state.draftPaths = ["a", "typed"]
        let store = store(state: state, update: { _ in
            SystemSettings(searchIndex: SearchIndexSettings(isEnabled: true, excluded: ExcludedPaths(paths: ["a"])))
        })

        await store.send(.enabledChanged(true))
        await store.skipReceivedActions()

        #expect(store.state.isEnabled)
        #expect(store.state.draftPaths == ["a", "typed"])
        #expect(store.state.isDirty)
    }

    // MARK: Excluded paths

    @Test
    func addingAPathNormalisesSortsAndClearsTheField() async {
        let store = store(state: loadedState(settings(paths: ["Zeta"])))

        await store.send(.newPathChanged("/Backups/2024"))
        await store.send(.addPathTapped)

        #expect(store.state.draftPaths == ["Backups/2024", "Zeta"])
        #expect(store.state.newPath.isEmpty)
        #expect(store.state.isDirty)
    }

    @Test(arguments: ["", "  ", "/", "a", "/a", "tmp"])
    func addingABlankDuplicateOrEnvironmentPathChangesNothing(raw: String) async {
        let store = store(state: loadedState(settings(paths: ["a"], environment: ["tmp"])))

        await store.send(.newPathChanged(raw))
        await store.send(.addPathTapped)

        #expect(store.state.draftPaths == ["a"])
        #expect(!store.state.isDirty)
    }

    @Test
    func uncheckingAPathMakesItDirtyAndDiscardingRestoresIt() async {
        let store = store(state: loadedState(settings(paths: ["a", "b"])))

        await store.send(.pathToggled("a"))
        #expect(store.state.draftPaths == ["b"])
        #expect(store.state.isDirty)

        await store.send(.newPathChanged("half typed"))
        await store.send(.discardTapped)
        #expect(store.state.draftPaths == ["a", "b"])
        #expect(store.state.newPath.isEmpty)
        #expect(!store.state.isDirty)
    }

    @Test
    func anUncheckedPathStaysListedAndCanBeCheckedAgain() async {
        let store = store(state: loadedState(settings(paths: ["a", "b"])))

        await store.send(.pathToggled("a"))
        #expect(store.state.draftPaths == ["b"])
        #expect(store.state.displayedPaths == ["a", "b"])

        await store.send(.pathToggled("a"))
        #expect(store.state.draftPaths == ["a", "b"])
        #expect(!store.state.isDirty)
    }

    @Test
    func displayedPathsMergeServerAndDraftSorted() {
        var state = loadedState(settings(paths: ["Zeta", "alpha"]))
        state.draftPaths = ["alpha", "Mid"]

        #expect(state.displayedPaths == ["alpha", "Mid", "Zeta"])
    }

    @Test
    func savingThePathsSendsOnlyThePathsAndAdoptsTheServersList() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let store = store(state: loadedState(settings(enabled: true, paths: [])), update: { patch in
            sent.setValue(patch)
            return SystemSettings(searchIndex: SearchIndexSettings(isEnabled: true, excluded: ExcludedPaths(paths: ["normalised"])))
        })

        await store.send(.newPathChanged("raw"))
        await store.send(.addPathTapped)
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.searchIndex == .init(excludedPaths: ["raw"]))
        #expect(store.state.draftPaths == ["normalised"])
        #expect(!store.state.isDirty)
        #expect(!store.state.isSaving)
    }

    @Test
    func savingIsOffUntilThePathsChange() async {
        let store = store(state: loadedState(settings(paths: ["a"])), update: { _ in
            Issue.record("Nothing changed, nothing to save")
            return SystemSettings()
        })

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
    }

    @Test
    func aFailedPathsSaveKeepsTheDraft() async {
        let store = store(state: loadedState(settings()), update: { _ in throw FilesClientError.server(statusCode: 500) })

        await store.send(.newPathChanged("a"))
        await store.send(.addPathTapped)
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.draftPaths == ["a"])
        #expect(store.state.errorMessage != nil)
        #expect(store.state.isDirty)
    }

    @Test
    func anEchoWithoutTheSearchIndexIsAFailedSave() async {
        let store = store(state: loadedState(settings()), update: { _ in SystemSettings() })

        await store.send(.enabledChanged(true))
        await store.skipReceivedActions()

        #expect(store.state.errorMessage != nil)
        #expect(!store.state.isSaving)
    }

    @Test
    func anEnvironmentDecidedSwitchShowsWhatTheServerIsDoingNotTheStoredChoice() async {
        let store = store(
            loaded: settings(enabled: false),
            features: { ServerFeatures(isSearchIndexEnabled: true, searchIndexLockedBy: "SEARCH_INDEX") }
        )

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isEnabled)
        #expect(store.state.lockedBy == "SEARCH_INDEX")
    }

    @Test
    func theSwitchFollowsTheSavedValueAndAPathsSaveLeavesItAlone() async {
        var state = loadedState(settings(enabled: true))
        state.effectiveIsEnabled = true
        let store = store(state: state, update: { _ in SystemSettings(searchIndex: SearchIndexSettings(isEnabled: false)) })

        await store.send(.enabledChanged(false))
        await store.skipReceivedActions()
        #expect(!store.state.isEnabled)

        await store.send(.saveResponse(.success(SearchIndexSettings(isEnabled: true)), replacesPaths: true))
        #expect(!store.state.isEnabled)
    }
}
