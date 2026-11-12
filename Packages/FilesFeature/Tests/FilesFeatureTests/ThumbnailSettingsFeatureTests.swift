import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

@MainActor
struct ThumbnailSettingsFeatureTests {
    private typealias Store = TestStoreOf<ThumbnailSettingsFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let sent = LockIsolated<[ThumbnailSettings]>([])

    private func store(
        state: ThumbnailSettingsFeature.State? = nil,
        fetch: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(thumbnails: ThumbnailSettings()) },
        update: @escaping @Sendable (ThumbnailSettings) throws -> ThumbnailSettings = { $0 }
    ) -> Store {
        let sent = sent
        return TestStore(initialState: state ?? ThumbnailSettingsFeature.State(serverURL: serverURL)) {
            ThumbnailSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in try fetch() }
            $0.filesClient.updateThumbnailSettings = { _, settings in
                sent.withValue { $0.append(settings) }
                return try update(settings)
            }
        }
    }

    private func loadedState(_ loaded: ThumbnailSettings = ThumbnailSettings(), draft: ThumbnailSettings? = nil) -> ThumbnailSettingsFeature.State {
        var state = ThumbnailSettingsFeature.State(serverURL: serverURL)
        state.loaded = loaded
        state.draft = draft ?? loaded
        return state
    }

    @Test
    func onAppearSeedsTheDraftFromTheServer() async {
        let loaded = ThumbnailSettings(isEnabled: true, size: 300, quality: 85, concurrency: 8)
        let store = store(fetch: { SystemSettings(thumbnails: loaded) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = loaded
            $0.draft = loaded
        }

        #expect(!store.state.isDirty)
    }

    @Test
    func aResponseWithoutThumbnailsMarksTheScreenUnavailable() async {
        let store = store(fetch: { SystemSettings() })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.isUnavailable = true
        }
    }

    @Test
    func aLoadFailureIsTheFailedPhase() async {
        let store = store(fetch: { throw FilesClientError.offline })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.failure) { $0.phase = .failed(L10n.Error.offline) }
    }

    @Test
    func reloadingKeepsAnEditInProgress() async {
        let store = store(
            state: loadedState(draft: ThumbnailSettings(quality: 30)),
            fetch: { SystemSettings(thumbnails: ThumbnailSettings(size: 400)) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = ThumbnailSettings(size: 400)
        }

        #expect(store.state.draft == ThumbnailSettings(quality: 30))
    }

    @Test
    func aChangeMakesItDirtyAndSaveSendsTheObjectThenReSeeds() async {
        let echoed = ThumbnailSettings(isEnabled: true, size: 200, quality: 40, concurrency: 10)
        let store = store(state: loadedState(), update: { _ in echoed })

        await store.send(.qualityChanged(40)) { $0.draft.quality = 40 }
        #expect(store.state.isDirty)

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.draft = echoed
        }
        await store.receive(.delegate(.saved))

        #expect(sent.value == [ThumbnailSettings(isEnabled: true, size: 200, quality: 40, concurrency: 10)])
        #expect(!store.state.isDirty)
    }

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = store(state: loadedState())

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(sent.value.isEmpty)
    }

    @Test
    func theSwitchEditsTheDraftAndClearsAShownError() async {
        var state = loadedState()
        state.errorMessage = "Nope"
        let store = store(state: state)

        await store.send(.enabledChanged(false)) {
            $0.draft.isEnabled = false
            $0.errorMessage = nil
        }
        #expect(store.state.isDirty)
    }

    struct ClampCase: Sendable {
        let action: ThumbnailSettingsFeature.Action
        let expected: ThumbnailSettings
    }

    @Test(arguments: [
        ClampCase(action: .sizeChanged(5000), expected: ThumbnailSettings(size: 1024)),
        ClampCase(action: .sizeChanged(5), expected: ThumbnailSettings(size: 64)),
        ClampCase(action: .sizeChanged(300), expected: ThumbnailSettings(size: 300)),
        ClampCase(action: .qualityChanged(0), expected: ThumbnailSettings(quality: 1)),
        ClampCase(action: .qualityChanged(101), expected: ThumbnailSettings(quality: 100)),
        ClampCase(action: .concurrencyChanged(99), expected: ThumbnailSettings(concurrency: 50)),
        ClampCase(action: .concurrencyChanged(0), expected: ThumbnailSettings(concurrency: 1)),
    ])
    func numericChangesAreClampedToTheServerBounds(_ testCase: ClampCase) async {
        let store = store(state: loadedState())

        await store.send(testCase.action) { $0.draft = testCase.expected }
    }

    @Test
    func aSaveFailureSurfacesTheMessageAndKeepsTheDraft() async {
        let store = store(state: loadedState(draft: ThumbnailSettings(quality: 30)), update: { _ in
            throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required for system settings.")
        })

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required for system settings."
        }

        #expect(store.state.draft == ThumbnailSettings(quality: 30))
        #expect(store.state.isDirty)
    }
}
