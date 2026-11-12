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
struct UploadSettingsFeatureTests {
    private typealias Store = TestStoreOf<UploadSettingsFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let patches = LockIsolated<[SystemSettingsPatch]>([])
    private let mib = 1_048_576

    private func store(
        state: UploadSettingsFeature.State? = nil,
        settings: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(uploads: UploadSettings()) },
        features: @escaping @Sendable () throws -> ServerFeatures = { ServerFeatures() },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> Store {
        let patches = patches
        return TestStore(initialState: state ?? UploadSettingsFeature.State(serverURL: serverURL)) {
            UploadSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in try settings() }
            $0.filesClient.serverFeatures = { _ in try features() }
            $0.filesClient.updateSystemSettings = { _, patch in
                patches.withValue { $0.append(patch) }
                return try update(patch)
            }
        }
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
            features: { ServerFeatures(maxUploadChunkSizeBytes: 64 * 1_048_576) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.maxChunkSizeMiB = 64
            $0.loaded = uploads
            $0.draft = uploads
        }

        #expect(!store.state.isDirty)
    }

    @Test
    func theCeilingFallsBackWhenTheFeatureFlagsCannotBeRead() async {
        let store = store(features: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.loaded = UploadSettings()
        }

        #expect(store.state.maxChunkSizeMiB == 512)
    }

    @Test(arguments: [nil, 0, -5])
    func aMissingOrNonPositiveCeilingKeepsTheFallback(bytes: Int?) async {
        let store = store(features: { ServerFeatures(maxUploadChunkSizeBytes: bytes) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.loaded = UploadSettings()
        }

        #expect(store.state.maxChunkSizeMiB == 512)
    }

    @Test
    func aCeilingBelowOneMiBStillAllowsOneMiB() async {
        let store = store(features: { ServerFeatures(maxUploadChunkSizeBytes: 100) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.maxChunkSizeMiB = 1
            $0.loaded = UploadSettings()
        }
    }

    @Test
    func aNonAdminResponseWithoutUploadsIsUnavailable() async {
        let store = store(settings: { SystemSettings() })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.isUnavailable = true
        }

        #expect(store.state.loaded == nil)
    }

    @Test
    func aLoadFailureIsTheFailedPhase() async {
        let store = store(settings: { throw FilesClientError.server(statusCode: 500) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.failure) { $0.phase = .failed(L10n.Error.server(500)) }
    }

    @Test
    func aReloadFailureKeepsTheFormAndShowsTheMessage() async {
        let store = store(state: loadedState(), settings: { throw FilesClientError.timedOut })

        await store.send(.onAppear)
        await store.receive(\.loadResponse.failure) { $0.errorMessage = L10n.Error.timedOut }
    }

    @Test
    func reloadingKeepsAnEditInProgress() async {
        var state = loadedState(UploadSettings(isChunkedEnabled: false))
        state.draft.isChunkedEnabled = true
        let store = store(state: state, settings: {
            SystemSettings(uploads: UploadSettings(isChunkedEnabled: false, chunkSizeBytes: 4 * 1_048_576))
        })

        await store.send(.onAppear)
        await store.receive(\.loadResponse.success) {
            $0.loaded = UploadSettings(isChunkedEnabled: false, chunkSizeBytes: 4 * 1_048_576)
        }

        #expect(store.state.draft == UploadSettings(isChunkedEnabled: true))
    }

    @Test
    func nothingReloadsWhileASaveIsInFlight() async {
        var state = loadedState()
        state.isSaving = true
        let store = store(state: state, settings: {
            Issue.record("A save in flight must not trigger a reload")
            return SystemSettings()
        })

        await store.send(.onAppear)
        await store.send(.loadResponse(.success(ServerSettingsSnapshot(settings: SystemSettings(uploads: UploadSettings(isChunkedEnabled: true))))))
    }

    // MARK: Editing

    @Test
    func forcedChunkingAndTheAutoFallbackExcludeEachOther() async {
        let store = store(state: loadedState())

        await store.send(.chunkedChanged(true)) { $0.draft.isChunkedEnabled = true }
        await store.send(.autoFallbackChanged(true)) {
            $0.draft.isChunkedAutoFallback = true
            $0.draft.isChunkedEnabled = false
        }
        await store.send(.chunkedChanged(true)) {
            $0.draft.isChunkedEnabled = true
            $0.draft.isChunkedAutoFallback = false
        }
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

        await store.send(.chunkSizeChanged(input)) { $0.draft.chunkSizeBytes = expected * 1_048_576 }
    }

    @Test
    func aServerSizeAboveALoweredCeilingShowsAsTheCeilingAndIsNotDirty() {
        let state = loadedState(UploadSettings(chunkSizeBytes: 200 * mib), maxMiB: 64)

        #expect(state.chunkSizeMiB == 64)
        #expect(!state.isDirty)
    }

    @Test
    func editingClearsAPreviousSaveError() async {
        var state = loadedState()
        state.errorMessage = "Nope"
        let store = store(state: state)

        await store.send(.autoFallbackChanged(true)) {
            $0.draft.isChunkedAutoFallback = true
            $0.errorMessage = nil
        }
    }

    // MARK: Saving

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = store(state: loadedState())

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test
    func savingSendsAllThreeFieldsAndAdoptsTheEcho() async {
        let echoed = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 24 * mib)
        let store = store(state: loadedState(), update: { _ in SystemSettings(uploads: echoed) })

        await store.send(.chunkedChanged(true)) { $0.draft.isChunkedEnabled = true }
        await store.send(.chunkSizeChanged(24)) { $0.draft.chunkSizeBytes = 24 * 1_048_576 }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.draft = echoed
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.uploads) == [echoed])
        #expect(patches.value.map(\.ffmpeg) == [nil])
        #expect(!store.state.isDirty)
    }

    @Test
    func aSavedSizeAboveALoweredCeilingIsSentAtTheCeiling() async {
        var state = loadedState(UploadSettings(chunkSizeBytes: 8 * mib), maxMiB: 16)
        state.draft.isChunkedEnabled = true
        state.draft.chunkSizeBytes = 100 * mib
        let sizeAtCeiling = UploadSettings(isChunkedEnabled: true, chunkSizeBytes: 16 * mib)
        let store = store(state: state, update: { _ in SystemSettings(uploads: sizeAtCeiling) })

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = sizeAtCeiling
            $0.draft = sizeAtCeiling
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.uploads) == [sizeAtCeiling])
    }

    @Test
    func anUntouchedChunkSizeIsSentBackAsTheServerHeldIt() async {
        let held = UploadSettings(isChunkedEnabled: false, isChunkedAutoFallback: false, chunkSizeBytes: 5_000_000)
        let echoed = UploadSettings(isChunkedEnabled: true, isChunkedAutoFallback: false, chunkSizeBytes: 5_000_000)
        let store = store(state: loadedState(held), update: { _ in SystemSettings(uploads: echoed) })

        await store.send(.chunkedChanged(true)) { $0.draft.isChunkedEnabled = true }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.uploads) == [echoed])
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(state: loadedState(), update: { _ in
            throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required.")
        })

        await store.send(.chunkedChanged(true)) { $0.draft.isChunkedEnabled = true }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required."
        }

        #expect(store.state.isDirty)
    }

    @Test
    func anEchoWithoutUploadsIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings() })

        await store.send(.chunkedChanged(true)) { $0.draft.isChunkedEnabled = true }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.decoding
        }
    }
}
