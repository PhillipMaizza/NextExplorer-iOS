import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct ThumbnailSettingsFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    @Test
    func onAppearSeedsTheDraftFromTheServer() async {
        let loaded = ThumbnailSettings(isEnabled: true, size: 300, quality: 85, concurrency: 8)
        let store = TestStore(initialState: ThumbnailSettingsFeature.State(serverURL: serverURL)) {
            ThumbnailSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings(thumbnails: loaded) }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = loaded
            $0.draft = loaded
        }
        #expect(!store.state.isDirty)
    }

    @Test
    func aChangeMakesItDirtyAndSaveSendsTheObjectThenReSeeds() async {
        let loaded = ThumbnailSettings()
        let echoed = ThumbnailSettings(isEnabled: true, size: 200, quality: 40, concurrency: 10)
        let sent = LockIsolated<ThumbnailSettings?>(nil)

        var state = ThumbnailSettingsFeature.State(serverURL: serverURL)
        state.loaded = loaded
        state.draft = loaded
        let store = TestStore(initialState: state) {
            ThumbnailSettingsFeature()
        } withDependencies: {
            $0.filesClient.updateThumbnailSettings = { _, settings in
                sent.setValue(settings)
                return echoed
            }
        }
        store.exhaustivity = .off

        await store.send(.qualityChanged(40)) { $0.draft.quality = 40 }
        #expect(store.state.isDirty)

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.draft = echoed
        }
        await store.receive(\.delegate)
        #expect(sent.value?.quality == 40)
    }

    @Test
    func numericChangesAreClampedToTheServerBounds() async {
        var state = ThumbnailSettingsFeature.State(serverURL: serverURL)
        state.loaded = ThumbnailSettings()
        state.draft = ThumbnailSettings()
        let store = TestStore(initialState: state) { ThumbnailSettingsFeature() }

        await store.send(.sizeChanged(5000)) { $0.draft.size = ThumbnailSettings.sizeRange.upperBound }
        await store.send(.qualityChanged(0)) { $0.draft.quality = ThumbnailSettings.qualityRange.lowerBound }
        await store.send(.concurrencyChanged(99)) { $0.draft.concurrency = ThumbnailSettings.concurrencyRange.upperBound }
    }

    @Test
    func aSaveFailureSurfacesTheMessageAndKeepsTheDraft() async {
        var state = ThumbnailSettingsFeature.State(serverURL: serverURL)
        state.loaded = ThumbnailSettings()
        state.draft = ThumbnailSettings(quality: 30)
        let store = TestStore(initialState: state) {
            ThumbnailSettingsFeature()
        } withDependencies: {
            $0.filesClient.updateThumbnailSettings = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required for system settings.")
            }
        }
        store.exhaustivity = .off

        await store.send(.saveTapped)
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required for system settings."
        }
        #expect(store.state.draft.quality == 30)
    }

    @Test
    func aResponseWithoutThumbnailsMarksTheScreenUnavailable() async {
        let store = TestStore(initialState: ThumbnailSettingsFeature.State(serverURL: serverURL)) {
            ThumbnailSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings() }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.settingsResponse.success) {
            $0.isUnavailable = true
        }
    }
}
