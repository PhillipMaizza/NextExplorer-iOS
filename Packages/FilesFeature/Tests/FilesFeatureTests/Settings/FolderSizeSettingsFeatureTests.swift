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
struct FolderSizeSettingsFeatureTests {
    private typealias Store = TestStoreOf<FolderSizeSettingsFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let fetchedURLs = LockIsolated<[URL]>([])
    private let patches = LockIsolated<[SystemSettingsPatch]>([])

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
        fetch: (@Sendable () throws -> SystemSettings)? = nil,
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> Store {
        let response: @Sendable () throws -> SystemSettings = fetch ?? { SystemSettings(folderSize: loaded) }
        let flags: @Sendable () throws -> ServerFeatures = features ??
            { ServerFeatures(folderSizeMode: loaded?.mode ?? .off) }
        let fetchedURLs = fetchedURLs
        let patches = patches
        return TestStore(initialState: state ?? FolderSizeSettingsFeature.State(serverURL: serverURL)) {
            FolderSizeSettingsFeature()
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
        _ folderSize: FolderSizeSettings,
        lockedBy: String? = nil
    ) -> FolderSizeSettingsFeature.State {
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
        let store = store(
            loaded: loaded,
            features: { ServerFeatures(folderSizeMode: .full, folderSizeLockedBy: "FOLDER_SIZE_MODE") }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.lockedBy = "FOLDER_SIZE_MODE"
            $0.effectiveMode = .full
            $0.loaded = loaded
            $0.draftPaths = ["docker"]
        }

        #expect(store.state.mode == .full)
        #expect(store.state.environmentPaths == ["tmp"])
        #expect(!store.state.isDirty)
        #expect(fetchedURLs.value == [serverURL])
    }

    @Test
    func beforeTheFirstLoadTheModeIsOff() {
        #expect(FolderSizeSettingsFeature.State(serverURL: serverURL).mode == .off)
    }

    @Test
    func aNonAdminResponseIsUnavailable() async {
        let store = store(loaded: nil)

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.effectiveMode = FolderSizeMode.off
            $0.isUnavailable = true
        }
    }

    @Test
    func whenTheFlagsCannotBeReadTheModeIsNotLocked() async {
        let loaded = settings(mode: .shallow)
        let store = store(loaded: loaded, features: { throw FilesClientError.offline })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.loaded = loaded
        }

        #expect(store.state.lockedBy == nil)
        #expect(store.state.effectiveMode == nil)
        #expect(store.state.mode == .shallow)
    }

    @Test
    func anEnvironmentDecidedModeShowsWhatTheServerIsDoingNotTheStoredChoice() async {
        let loaded = settings(mode: .off)
        let store = store(
            loaded: loaded,
            features: { ServerFeatures(folderSizeMode: .full, folderSizeLockedBy: "FOLDER_SIZE_MODE") }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.lockedBy = "FOLDER_SIZE_MODE"
            $0.effectiveMode = .full
            $0.loaded = loaded
        }

        #expect(store.state.loaded?.mode == FolderSizeMode.off)
        #expect(store.state.mode == .full)
        #expect(store.state.isModeLocked)
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
            $0.effectiveMode = FolderSizeMode.off
            $0.loaded = FolderSizeSettings(mode: .off, excluded: ExcludedPaths(paths: ["a", "server"]))
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
                    .success(ServerSettingsSnapshot(settings: SystemSettings(folderSize: settings(mode: .full))))
                )
            )

        #expect(fetchedURLs.value.isEmpty)
    }

    // MARK: The mode

    @Test(arguments: [
        (FolderSizeMode.off, FolderSizeMode.shallow),
        (.off, .full),
        (.shallow, .full),
        (.full, .off),
        (.shallow, .off)
    ])
    func changingTheModeSavesAtOnceSendingOnlyTheMode(from: FolderSizeMode, to: FolderSizeMode) async {
        let store = store(state: loadedState(settings(mode: from, paths: ["a"])), update: { _ in
            SystemSettings(folderSize: FolderSizeSettings(mode: to, excluded: ExcludedPaths(paths: ["a"])))
        })

        await store.send(.modeChanged(to)) { $0.isSaving = true }
        await store.receive(.saveResponse(
            .success(FolderSizeSettings(mode: to, excluded: ExcludedPaths(paths: ["a"]))),
            replacesPaths: false
        )) {
            $0.isSaving = false
            $0.loaded = FolderSizeSettings(mode: to, excluded: ExcludedPaths(paths: ["a"]))
            $0.effectiveMode = to
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.folderSize) == [SystemSettingsPatch.FolderSizePatch(mode: to)])
    }

    @Test
    func aLockedModeDoesNotChangeOrCallTheServer() async {
        let store = store(state: loadedState(settings(mode: .full), lockedBy: "FOLDER_SIZE_MODE"))

        await store.send(.modeChanged(.off))

        #expect(store.state.mode == .full)
        #expect(patches.value.isEmpty)
    }

    @Test
    func choosingTheModeAlreadyInForceDoesNothing() async {
        let store = store(state: loadedState(settings(mode: .shallow)))

        await store.send(.modeChanged(.shallow))

        #expect(patches.value.isEmpty)
    }

    @Test
    func aSecondModeChangeWhileSavingIsIgnored() async {
        var state = loadedState(settings(mode: .off))
        state.isSaving = true
        let store = store(state: state)

        await store.send(.modeChanged(.full))

        #expect(patches.value.isEmpty)
    }

    @Test
    func aFailedModeSaveLeavesTheModeWhereItWasAndShowsTheMessage() async {
        let store = store(state: loadedState(settings(mode: .off)), update: { _ in
            throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.")
        })

        await store.send(.modeChanged(.full)) { $0.isSaving = true }
        await store.receive(.saveResponse(
            .failure(.serverMessage(statusCode: 403, message: "Admin access required.")),
            replacesPaths: false
        )) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required."
        }

        #expect(store.state.mode == .off)
    }

    @Test
    func theModeSavingKeepsUnsavedPathEdits() async {
        var state = loadedState(settings(mode: .off, paths: ["a"]))
        state.draftPaths = ["a", "typed"]
        let echoed = settings(mode: .full, paths: ["a"])
        let store = store(state: state, update: { _ in SystemSettings(folderSize: echoed) })

        await store.send(.modeChanged(.full)) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(echoed), replacesPaths: false)) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.effectiveMode = .full
        }
        await store.receive(.delegate(.saved))

        #expect(store.state.draftPaths == ["a", "typed"])
        #expect(store.state.isDirty)
    }

    @Test
    func theModeFollowsTheSavedValueAndAPathsSaveLeavesItAlone() async {
        var state = loadedState(settings(mode: .shallow))
        state.effectiveMode = .shallow
        let echoed = settings(mode: .full)
        let store = store(state: state, update: { _ in SystemSettings(folderSize: echoed) })

        await store.send(.modeChanged(.full)) { $0.isSaving = true }
        await store.receive(.saveResponse(.success(echoed), replacesPaths: false)) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.effectiveMode = .full
        }
        await store.receive(.delegate(.saved))

        await store.send(.saveResponse(.success(settings(mode: .off)), replacesPaths: true)) {
            $0.loaded = FolderSizeSettings(mode: .off)
        }
        await store.receive(.delegate(.saved))

        #expect(store.state.mode == .full)
    }

    // MARK: Excluded paths

    @Test
    func addingAPathNormalisesSortsAndClearsTheField() async {
        let store = store(state: loadedState(settings(paths: ["Zeta"])))

        await store.send(.newPathChanged("/Stacks/docker")) { $0.newPath = "/Stacks/docker" }
        await store.send(.addPathTapped) {
            $0.draftPaths = ["Stacks/docker", "Zeta"]
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

        await store.send(.pathToggled("b")) { $0.draftPaths = ["a"] }
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
    func savingThePathsSendsOnlyThePathsAndAdoptsTheServersList() async {
        let echoed = settings(mode: .full, paths: ["normalised"])
        let store = store(
            state: loadedState(settings(mode: .full)),
            update: { _ in SystemSettings(folderSize: echoed) }
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

        #expect(patches.value.map(\.folderSize) == [SystemSettingsPatch.FolderSizePatch(excludedPaths: ["raw"])])
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
    func anEchoWithoutFolderSizeIsAFailedSave() async {
        let store = store(state: loadedState(settings()), update: { _ in SystemSettings() })

        await store.send(.modeChanged(.full)) { $0.isSaving = true }
        await store.receive(.saveResponse(
            .failure(.decoding("Settings response carried no folder size.")),
            replacesPaths: false
        )) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.decoding
        }
    }
}
