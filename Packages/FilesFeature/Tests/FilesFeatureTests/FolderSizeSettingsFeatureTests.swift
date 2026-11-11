import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct FolderSizeSettingsFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    private func settings(
        mode: FolderSizeMode = .off,
        paths: [String] = [],
        environment: [String] = []
    ) -> FolderSizeSettings {
        FolderSizeSettings(mode: mode, excluded: ExcludedPaths(paths: paths, environmentPaths: environment))
    }

    private func store(
        state: FolderSizeSettingsFeature.State? = nil,
        loaded: FolderSizeSettings? = nil,
        features: (@Sendable () throws -> ServerFeatures)? = nil,
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> TestStoreOf<FolderSizeSettingsFeature> {
        let response = SystemSettings(folderSize: loaded)
        let flags: @Sendable () throws -> ServerFeatures = features ?? { ServerFeatures(folderSizeMode: loaded?.mode ?? .off) }
        let store = TestStore(initialState: state ?? FolderSizeSettingsFeature.State(serverURL: serverURL)) {
            FolderSizeSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in response }
            $0.filesClient.serverFeatures = { _ in try flags() }
            $0.filesClient.updateSystemSettings = { _, patch in try update(patch) }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(_ folderSize: FolderSizeSettings, lockedBy: String? = nil) -> FolderSizeSettingsFeature.State {
        var state = FolderSizeSettingsFeature.State(serverURL: serverURL)
        state.loaded = folderSize
        state.draftPaths = folderSize.excluded.paths
        state.lockedBy = lockedBy
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingSeedsTheModePathsAndLock() async {
        let loaded = settings(mode: .full, paths: ["docker"], environment: ["tmp"])
        let store = store(loaded: loaded, features: { ServerFeatures(folderSizeMode: .full, folderSizeLockedBy: "FOLDER_SIZE_MODE") })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.mode == .full)
        #expect(store.state.draftPaths == ["docker"])
        #expect(store.state.environmentPaths == ["tmp"])
        #expect(store.state.lockedBy == "FOLDER_SIZE_MODE")
        #expect(!store.state.isDirty)
    }

    @Test
    func beforeTheFirstLoadTheModeIsOff() {
        #expect(FolderSizeSettingsFeature.State(serverURL: serverURL).mode == .off)
    }

    @Test
    func aNonAdminResponseIsUnavailable() async {
        let store = store(loaded: nil)

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
    }

    @Test
    func whenTheFlagsCannotBeReadTheModeIsNotLocked() async {
        let store = store(loaded: settings(), features: { throw FilesClientError.offline })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.lockedBy == nil)
        #expect(store.state.phase == .loaded)
    }

    // MARK: The mode

    @Test(arguments: [(FolderSizeMode.off, FolderSizeMode.shallow), (.off, .full), (.shallow, .full), (.full, .off), (.shallow, .off)])
    func changingTheModeSavesAtOnceSendingOnlyTheMode(from: FolderSizeMode, to: FolderSizeMode) async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let store = store(state: loadedState(settings(mode: from, paths: ["a"])), update: { patch in
            sent.setValue(patch)
            return SystemSettings(folderSize: FolderSizeSettings(mode: to, excluded: ExcludedPaths(paths: ["a"])))
        })

        await store.send(.modeChanged(to))
        await store.skipReceivedActions()

        #expect(sent.value?.folderSize == .init(mode: to))
        #expect(store.state.mode == to)
        #expect(!store.state.isSaving)
    }

    @Test
    func aLockedModeDoesNotChangeOrCallTheServer() async {
        let store = store(state: loadedState(settings(mode: .full), lockedBy: "FOLDER_SIZE_MODE"), update: { _ in
            Issue.record("A locked mode must not save")
            return SystemSettings()
        })

        await store.send(.modeChanged(.off))

        #expect(store.state.mode == .full)
        #expect(!store.state.isSaving)
    }

    @Test
    func choosingTheModeAlreadyInForceDoesNothing() async {
        let store = store(state: loadedState(settings(mode: .shallow)), update: { _ in
            Issue.record("An unchanged mode must not save")
            return SystemSettings()
        })

        await store.send(.modeChanged(.shallow))

        #expect(!store.state.isSaving)
    }

    @Test
    func aFailedModeSaveLeavesTheModeWhereItWasAndShowsTheMessage() async {
        let store = store(state: loadedState(settings(mode: .off)), update: { _ in throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.") })

        await store.send(.modeChanged(.full))
        await store.skipReceivedActions()

        #expect(store.state.mode == .off)
        #expect(store.state.errorMessage == "Admin access required.")
        #expect(!store.state.isSaving)
    }

    @Test
    func theModeSavingKeepsUnsavedPathEdits() async {
        var state = loadedState(settings(mode: .off, paths: ["a"]))
        state.draftPaths = ["a", "typed"]
        let store = store(state: state, update: { _ in
            SystemSettings(folderSize: FolderSizeSettings(mode: .full, excluded: ExcludedPaths(paths: ["a"])))
        })

        await store.send(.modeChanged(.full))
        await store.skipReceivedActions()

        #expect(store.state.mode == .full)
        #expect(store.state.draftPaths == ["a", "typed"])
        #expect(store.state.isDirty)
    }

    // MARK: Excluded paths

    @Test
    func addingAPathNormalisesSortsAndClearsTheField() async {
        let store = store(state: loadedState(settings(paths: ["Zeta"])))

        await store.send(.newPathChanged("/Stacks/docker"))
        await store.send(.addPathTapped)

        #expect(store.state.draftPaths == ["Stacks/docker", "Zeta"])
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

        await store.send(.pathToggled("b"))
        #expect(store.state.draftPaths == ["a"])
        #expect(store.state.isDirty)

        await store.send(.discardTapped)
        #expect(store.state.draftPaths == ["a", "b"])
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
        let store = store(state: loadedState(settings(mode: .full)), update: { patch in
            sent.setValue(patch)
            return SystemSettings(folderSize: FolderSizeSettings(mode: .full, excluded: ExcludedPaths(paths: ["normalised"])))
        })

        await store.send(.newPathChanged("raw"))
        await store.send(.addPathTapped)
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.folderSize == .init(excludedPaths: ["raw"]))
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
    func anEchoWithoutFolderSizeIsAFailedSave() async {
        let store = store(state: loadedState(settings()), update: { _ in SystemSettings() })

        await store.send(.modeChanged(.full))
        await store.skipReceivedActions()

        #expect(store.state.errorMessage != nil)
        #expect(!store.state.isSaving)
    }

    @Test
    func anEnvironmentDecidedModeShowsWhatTheServerIsDoingNotTheStoredChoice() async {
        let store = store(
            loaded: settings(mode: .off),
            features: { ServerFeatures(folderSizeMode: .full, folderSizeLockedBy: "FOLDER_SIZE_MODE") }
        )

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.mode == .full)
        #expect(store.state.isModeLocked)
    }

    @Test
    func theModeFollowsTheSavedValueAndAPathsSaveLeavesItAlone() async {
        var state = loadedState(settings(mode: .shallow))
        state.effectiveMode = .shallow
        let store = store(state: state, update: { _ in SystemSettings(folderSize: FolderSizeSettings(mode: .full)) })

        await store.send(.modeChanged(.full))
        await store.skipReceivedActions()
        #expect(store.state.mode == .full)

        await store.send(.saveResponse(.success(FolderSizeSettings(mode: .off)), replacesPaths: true))
        #expect(store.state.mode == .full)
    }
}
