import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct UploadSettingsFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!
    private let mib = UploadSettings.bytesPerMiB

    private func store(
        state: UploadSettingsFeature.State? = nil,
        settings: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(uploads: UploadSettings()) },
        features: @escaping @Sendable () throws -> ServerFeatures = { ServerFeatures() },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> TestStoreOf<UploadSettingsFeature> {
        let store = TestStore(initialState: state ?? UploadSettingsFeature.State(serverURL: serverURL)) {
            UploadSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in try settings() }
            $0.filesClient.serverFeatures = { _ in try features() }
            $0.filesClient.updateSystemSettings = { _, patch in try update(patch) }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(_ uploads: UploadSettings = UploadSettings(), maxMiB: Int = 512) -> UploadSettingsFeature.State {
        var state = UploadSettingsFeature.State(serverURL: serverURL)
        state.loaded = uploads
        state.draft = uploads
        state.maxChunkSizeMiB = maxMiB
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingSeedsTheDraftAndTheServersChunkCeiling() async {
        let uploads = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 16 * mib)
        let store = store(
            settings: { SystemSettings(uploads: uploads) },
            features: { ServerFeatures(maxUploadChunkSizeBytes: 64 * UploadSettings.bytesPerMiB) }
        )

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase == .loaded)
        #expect(store.state.loaded == uploads)
        #expect(store.state.draft == uploads)
        #expect(store.state.maxChunkSizeMiB == 64)
        #expect(!store.state.isDirty)
    }

    @Test
    func theCeilingFallsBackWhenTheFeatureFlagsCannotBeRead() async {
        let store = store(features: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase == .loaded)
        #expect(store.state.maxChunkSizeMiB == UploadSettings.fallbackMaxChunkSizeMiB)
    }

    @Test
    func aCeilingBelowOneMiBStillAllowsOneMiB() async {
        let store = store(features: { ServerFeatures(maxUploadChunkSizeBytes: 100) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.maxChunkSizeMiB == UploadSettings.minChunkSizeMiB)
    }

    @Test
    func aNonAdminResponseWithoutUploadsIsUnavailable() async {
        let store = store(settings: { SystemSettings() })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
        #expect(store.state.loaded == nil)
    }

    @Test
    func aLoadFailureIsTheFailedPhase() async {
        let store = store(settings: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase.errorMessage != nil)
    }

    @Test
    func reloadingKeepsAnEditInProgress() async {
        var state = loadedState(UploadSettings(isChunkedEnabled: false))
        state.draft.isChunkedEnabled = true
        let store = store(state: state, settings: { SystemSettings(uploads: UploadSettings(isChunkedEnabled: false, chunkSizeBytes: 4 * UploadSettings.bytesPerMiB)) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.draft.isChunkedEnabled)
        #expect(store.state.loaded?.chunkSizeBytes == 4 * mib)
    }

    // MARK: Editing

    @Test
    func forcedChunkingAndTheAutoFallbackExcludeEachOther() async {
        let store = store(state: loadedState())

        await store.send(.chunkedChanged(true))
        #expect(store.state.draft.isChunkedEnabled)
        #expect(!store.state.draft.isChunkedAutoFallback)

        await store.send(.autoFallbackChanged(true))
        #expect(store.state.draft.isChunkedAutoFallback)
        #expect(!store.state.draft.isChunkedEnabled)

        await store.send(.chunkedChanged(true))
        #expect(!store.state.draft.isChunkedAutoFallback)
    }

    @Test
    func turningAnOptionOffLeavesTheOtherAlone() async {
        let store = store(state: loadedState(UploadSettings(isChunkedAutoFallback: true)))

        await store.send(.chunkedChanged(false))

        #expect(store.state.draft.isChunkedAutoFallback)
    }

    @Test(arguments: [(0, 1), (-3, 1), (1, 1), (32, 32), (64, 64), (65, 64), (10_000, 64)])
    func theChunkSizeIsClampedToOneAndTheCeiling(input: Int, expected: Int) async {
        let store = store(state: loadedState(maxMiB: 64))

        await store.send(.chunkSizeChanged(input))

        #expect(store.state.draft.chunkSizeBytes == expected * mib)
    }

    @Test
    func aServerSizeAboveALoweredCeilingShowsAsTheCeilingAndIsNotDirty() {
        let state = loadedState(UploadSettings(chunkSizeBytes: 200 * UploadSettings.bytesPerMiB), maxMiB: 64)

        #expect(state.chunkSizeMiB == 64)
        #expect(!state.isDirty)
    }

    // MARK: Saving

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = store(state: loadedState())

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(!store.state.isSaving)
    }

    @Test
    func savingSendsAllThreeFieldsAndAdoptsTheEcho() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let echoed = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 24 * UploadSettings.bytesPerMiB)
        let store = store(state: loadedState(), update: { patch in
            sent.setValue(patch)
            return SystemSettings(uploads: echoed)
        })

        await store.send(.chunkedChanged(true))
        await store.send(.chunkSizeChanged(24))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.uploads == echoed)
        #expect(sent.value?.ffmpeg == nil)
        #expect(store.state.loaded == echoed)
        #expect(store.state.draft == echoed)
        #expect(!store.state.isSaving)
        #expect(!store.state.isDirty)
    }

    @Test
    func aSavedSizeAboveALoweredCeilingIsSentAtTheCeiling() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        var state = loadedState(UploadSettings(chunkSizeBytes: 8 * UploadSettings.bytesPerMiB), maxMiB: 16)
        state.draft.isChunkedEnabled = true
        state.draft.chunkSizeBytes = 100 * UploadSettings.bytesPerMiB
        let store = store(state: state, update: { patch in
            sent.setValue(patch)
            return SystemSettings(uploads: patch.uploads)
        })

        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.uploads?.chunkSizeBytes == 16 * mib)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(state: loadedState(), update: { _ in throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.") })

        await store.send(.chunkedChanged(true))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.errorMessage == "Admin access required.")
        #expect(store.state.draft.isChunkedEnabled)
        #expect(store.state.isDirty)
        #expect(!store.state.isSaving)
    }

    @Test
    func anEchoWithoutUploadsIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings() })

        await store.send(.chunkedChanged(true))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.errorMessage != nil)
        #expect(!store.state.isSaving)
    }

    @Test
    func editingClearsAPreviousSaveError() async {
        var state = loadedState()
        state.errorMessage = "Nope"
        let store = store(state: state)

        await store.send(.autoFallbackChanged(true))

        #expect(store.state.errorMessage == nil)
    }

    @Test
    func anUntouchedChunkSizeIsSentBackAsTheServerHeldIt() async {
        let held = UploadSettings(isChunkedEnabled: false, isChunkedAutoFallback: false, chunkSizeBytes: 5_000_000)
        var state = UploadSettingsFeature.State(serverURL: URL(string: "https://files.example.com")!)
        state.loaded = held
        state.draft = held
        state.phase = .loaded
        let captured = LockIsolated<SystemSettingsPatch?>(nil)
        let store = TestStore(initialState: state) {
            UploadSettingsFeature()
        } withDependencies: {
            $0.filesClient.updateSystemSettings = { _, patch in
                captured.setValue(patch)
                return SystemSettings(uploads: patch.uploads)
            }
        }
        store.exhaustivity = .off

        await store.send(.chunkedChanged(true))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(captured.value?.uploads?.chunkSizeBytes == 5_000_000)
    }
}
