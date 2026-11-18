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
struct SearchIndexSettingsFeatureTests {
    private typealias Store = TestStoreOf<SearchIndexSettingsFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let fetchedURLs = LockIsolated<[URL]>([])
    private let patches = LockIsolated<[SystemSettingsPatch]>([])

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
        fetch: (@Sendable () throws -> SystemSettings)? = nil,
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> Store {
        let response: @Sendable () throws -> SystemSettings = fetch ?? { SystemSettings(searchIndex: loaded) }
        let flags: @Sendable () throws -> ServerFeatures = features ??
            { ServerFeatures(isSearchIndexEnabled: loaded?.isEnabled ?? false) }
        let fetchedURLs = fetchedURLs
        let patches = patches
        return TestStore(initialState: state ?? SearchIndexSettingsFeature.State(serverURL: serverURL)) {
            SearchIndexSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { url in
                fetchedURLs.withValue { $0.append(url) }
                return try response()
            }
            $0.filesClient.serverFeatures = { _ in try flags() }
            $0.filesClient.updateSystemSettings = { _, patch in
                patches.withValue { $0.append(patch) }
                return try update(patch)
            }
        }
    }

    private func loadedState(
        _ searchIndex: SearchIndexSettings,
        lockedBy: String? = nil
    ) -> SearchIndexSettingsFeature.State {
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
        let store = store(
            loaded: loaded,
            features: { ServerFeatures(isSearchIndexEnabled: true, searchIndexLockedBy: "SEARCH_INDEX") }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.lockedBy = "SEARCH_INDEX"
            $0.effectiveIsEnabled = true
            $0.loaded = loaded
            $0.draftPaths = ["Backups"]
        }

        #expect(store.state.environmentPaths == ["tmp"])
        #expect(store.state.isEnabled)
        #expect(!store.state.isDirty)
        #expect(fetchedURLs.value == [serverURL])
    }

    @Test
    func whenTheFlagsCannotBeReadTheSwitchIsNotLocked() async {
        let loaded = settings(enabled: true)
        let store = store(loaded: loaded, features: { throw FilesClientError.offline })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.loaded = loaded
        }

        #expect(store.state.lockedBy == nil)
        #expect(store.state.effectiveIsEnabled == nil)
        #expect(store.state.isEnabled)
    }

    @Test
    func aNonAdminResponseIsUnavailable() async {
        let store = store(loaded: nil)

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.effectiveIsEnabled = false
            $0.isUnavailable = true
        }
    }

    @Test
    func aFirstLoadFailureIsTheFailedPhase() async {
        let store = store(fetch: { throw FilesClientError.timedOut })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.failure) { $0.phase = .failed(L10n.Error.timedOut) }
    }

    @Test
    func aReloadFailureKeepsTheFormAndShowsTheMessage() async {
        let store = store(state: loadedState(settings()), fetch: { throw FilesClientError.timedOut })

        await store.send(.onAppear)
        await store.receive(\.loadResponse.failure) { $0.errorMessage = L10n.Error.timedOut }
    }

    @Test
    func reloadingKeepsPathsBeingEdited() async {
        var state = loadedState(settings(paths: ["a"]))
        state.draftPaths = ["a", "typed"]
        let store = store(state: state, loaded: settings(paths: ["a", "server"]))

        await store.send(.onAppear)
        await store.receive(\.loadResponse.success) {
            $0.effectiveIsEnabled = false
            $0.loaded = SearchIndexSettings(isEnabled: false, excluded: ExcludedPaths(paths: ["a", "server"]))
        }

        #expect(store.state.draftPaths == ["a", "typed"])
    }

    @Test
    func nothingReloadsWhileASaveIsInFlight() async {
        var state = loadedState(settings())
        state.isSaving = true
        let store = store(state: state)

        await store.send(.onAppear)
        await store
            .send(
                .loadResponse(
                    .success(ServerSettingsSnapshot(settings: SystemSettings(searchIndex: settings(enabled: true))))
                )
            )

        #expect(fetchedURLs.value.isEmpty)
    }

    @Test
    func anEnvironmentDecidedSwitchShowsWhatTheServerIsDoingNotTheStoredChoice() async {
        let loaded = settings(enabled: false)
        let store = store(
            loaded: loaded,
            features: { ServerFeatures(isSearchIndexEnabled: true, searchIndexLockedBy: "SEARCH_INDEX") }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.lockedBy = "SEARCH_INDEX"
            $0.effectiveIsEnabled = true
            $0.loaded = loaded
        }

        #expect(!(store.state.loaded?.isEnabled ?? true))
        #expect(store.state.isEnabled)
        #expect(store.state.isSwitchLocked)
    }

    // MARK: The switch

    @Test
    func movingTheSwitchSavesAtOnceSendingOnlyTheSwitch() async {
        let echoed = settings(enabled: true, paths: ["a"])
        let store = store(
            state: loadedState(settings(paths: ["a"])),
            update: { _ in SystemSettings(searchIndex: echoed) }
        )

        await store.send(.enabledChanged(true)) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(echoed), replacesPaths: false)) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.effectiveIsEnabled = true
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.searchIndex) == [SystemSettingsPatch.SearchIndexPatch(enabled: true)])
    }

    @Test
    func aLockedSwitchDoesNotMoveOrCallTheServer() async {
        let store = store(state: loadedState(settings(enabled: true), lockedBy: "SEARCH_INDEX"))

        await store.send(.enabledChanged(false))

        #expect(store.state.isEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test
    func choosingTheValueAlreadyInForceDoesNothing() async {
        let store = store(state: loadedState(settings(enabled: true)))

        await store.send(.enabledChanged(true))

        #expect(patches.value.isEmpty)
    }

    @Test
    func aSecondSwitchMoveWhileSavingIsIgnored() async {
        var state = loadedState(settings(enabled: false))
        state.isSaving = true
        let store = store(state: state)

        await store.send(.enabledChanged(true))

        #expect(patches.value.isEmpty)
    }

    @Test
    func aFailedSwitchSaveLeavesTheSwitchWhereItWasAndShowsTheMessage() async {
        let store = store(state: loadedState(settings(enabled: false)), update: { _ in
            throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.")
        })

        await store.send(.enabledChanged(true)) { $0.isSaving = true }
        await store.receive(.saveResponse(
            .failure(.serverMessage(statusCode: 403, message: "Admin access required.")),
            replacesPaths: false
        )) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required."
        }

        #expect(!store.state.isEnabled)
    }

    @Test
    func theSwitchSavingKeepsUnsavedPathEdits() async {
        var state = loadedState(settings(paths: ["a"]))
        state.draftPaths = ["a", "typed"]
        let echoed = settings(enabled: true, paths: ["a"])
        let store = store(state: state, update: { _ in SystemSettings(searchIndex: echoed) })

        await store.send(.enabledChanged(true)) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(echoed), replacesPaths: false)) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.effectiveIsEnabled = true
        }
        await store.receive(.delegate(.saved))

        #expect(store.state.draftPaths == ["a", "typed"])
        #expect(store.state.isDirty)
    }

    @Test
    func theSwitchFollowsTheSavedValueAndAPathsSaveLeavesItAlone() async {
        var state = loadedState(settings(enabled: true))
        state.effectiveIsEnabled = true
        let echoed = settings(enabled: false)
        let store = store(state: state, update: { _ in SystemSettings(searchIndex: echoed) })

        await store.send(.enabledChanged(false)) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(echoed), replacesPaths: false)) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.effectiveIsEnabled = false
        }
        await store.receive(.delegate(.saved))

        await store.send(.saveResponse(.success(settings(enabled: true)), replacesPaths: true)) {
            $0.loaded = SearchIndexSettings(isEnabled: true)
        }
        await store.receive(.delegate(.saved))

        #expect(!store.state.isEnabled)
    }

    // MARK: Excluded paths

    @Test
    func addingAPathNormalisesSortsAndClearsTheField() async {
        let store = store(state: loadedState(settings(paths: ["Zeta"])))

        await store.send(.newPathChanged("/Backups/2024")) { $0.newPath = "/Backups/2024" }
        await store.send(.addPathTapped) {
            $0.draftPaths = ["Backups/2024", "Zeta"]
            $0.newPath = ""
        }

        #expect(store.state.isDirty)
    }

    @Test(arguments: ["  ", "/", "a", "/a", "tmp"])
    func addingABlankDuplicateOrEnvironmentPathChangesNothing(raw: String) async {
        var state = loadedState(settings(paths: ["a"], environment: ["tmp"]))
        state.newPath = "previous"
        let store = store(state: state)

        await store.send(.newPathChanged(raw)) { $0.newPath = raw }
        await store.send(.addPathTapped) { $0.newPath = "" }

        #expect(store.state.draftPaths == ["a"])
        #expect(!store.state.isDirty)
    }

    @Test
    func addingAnEmptyFieldChangesNothing() async {
        let store = store(state: loadedState(settings(paths: ["a"])))

        await store.send(.addPathTapped)

        #expect(store.state.draftPaths == ["a"])
    }

    @Test
    func uncheckingAPathMakesItDirtyAndDiscardingRestoresIt() async {
        let store = store(state: loadedState(settings(paths: ["a", "b"])))

        await store.send(.pathToggled("a")) { $0.draftPaths = ["b"] }
        #expect(store.state.isDirty)

        await store.send(.newPathChanged("half typed")) { $0.newPath = "half typed" }
        await store.send(.discardTapped) {
            $0.draftPaths = ["a", "b"]
            $0.newPath = ""
        }
        #expect(!store.state.isDirty)
    }

    @Test
    func anUncheckedPathStaysListedAndCanBeCheckedAgain() async {
        let store = store(state: loadedState(settings(paths: ["a", "b"])))

        await store.send(.pathToggled("a")) { $0.draftPaths = ["b"] }
        #expect(store.state.displayedPaths == ["a", "b"])

        await store.send(.pathToggled("a")) { $0.draftPaths = ["a", "b"] }
        #expect(!store.state.isDirty)
    }

    @Test
    func displayedPathsMergeServerAndDraftSorted() {
        var state = loadedState(settings(paths: ["Zeta", Constants.alphaPath]))
        state.draftPaths = [Constants.alphaPath, "Mid"]

        #expect(state.displayedPaths == [Constants.alphaPath, "Mid", "Zeta"])
    }

    @Test
    func savingThePathsSendsOnlyThePathsAndAdoptsTheServersList() async {
        let echoed = settings(enabled: true, paths: ["normalised"])
        let store = store(
            state: loadedState(settings(enabled: true)),
            update: { _ in SystemSettings(searchIndex: echoed) }
        )

        await store.send(.newPathChanged("raw")) { $0.newPath = "raw" }
        await store.send(.addPathTapped) {
            $0.draftPaths = ["raw"]
            $0.newPath = ""
        }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(echoed), replacesPaths: true)) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.draftPaths = ["normalised"]
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.searchIndex) == [SystemSettingsPatch.SearchIndexPatch(excludedPaths: ["raw"])])
        #expect(!store.state.isDirty)
    }

    @Test
    func savingIsOffUntilThePathsChange() async {
        let store = store(state: loadedState(settings(paths: ["a"])))

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test
    func aFailedPathsSaveKeepsTheDraft() async {
        let store = store(
            state: loadedState(settings()),
            update: { _ in throw FilesClientError.server(statusCode: 500) }
        )

        await store.send(.newPathChanged("a")) { $0.newPath = "a" }
        await store.send(.addPathTapped) {
            $0.draftPaths = ["a"]
            $0.newPath = ""
        }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(.saveResponse(.failure(.server(statusCode: 500)), replacesPaths: true)) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.server(500)
        }

        #expect(store.state.isDirty)
    }

    @Test
    func anEchoWithoutTheSearchIndexIsAFailedSave() async {
        let store = store(state: loadedState(settings()), update: { _ in SystemSettings() })

        await store.send(.enabledChanged(true)) { $0.isSaving = true }
        await store.receive(.saveResponse(
            .failure(.decoding("Settings response carried no search index.")),
            replacesPaths: false
        )) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.decoding
        }
    }
}

private enum Constants {
    static let alphaPath = "alpha"
}
