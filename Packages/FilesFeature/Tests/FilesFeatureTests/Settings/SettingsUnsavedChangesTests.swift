import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Testing

@MainActor
struct SettingsUnsavedChangesTests: SettingsFeatureTestSupport {
    @Test("An admin pane reports unsaved changes only once its draft differs from what loaded")
    func unsavedChangesFollowTheDraft() {
        let loaded = ThumbnailSettings(isEnabled: true, size: 200, quality: 70, concurrency: 10)
        var state = makeState()
        #expect(!state.hasUnsavedChanges(in: .thumbnails))

        var thumbnails = ThumbnailSettingsFeature.State(serverURL: serverURL)
        thumbnails.loaded = loaded
        thumbnails.draft = loaded
        state.thumbnailSettings = thumbnails
        #expect(!state.hasUnsavedChanges(in: .thumbnails))

        state.thumbnailSettings?.draft.size = 256
        #expect(state.hasUnsavedChanges(in: .thumbnails))
        #expect(!state.hasUnsavedChanges(in: .uploads))
        #expect(!state.hasUnsavedChanges(in: .users))
    }

    @Test("Switching account with unsaved admin edits asks first; Keep Editing stays, Discard switches")
    func switchWithUnsavedEditsAsks() async {
        let loaded = ThumbnailSettings(isEnabled: true, size: 200, quality: 70, concurrency: 10)
        var state = makeState()
        var thumbnails = ThumbnailSettingsFeature.State(serverURL: serverURL)
        thumbnails.loaded = loaded
        thumbnails.draft = loaded
        thumbnails.draft.size = 256
        state.thumbnailSettings = thumbnails
        let store = makeStore(state: state)

        await store.send(.switchAccountTapped("other")) { $0.accountPendingSwitch = "other" }
        await store.send(.switchDiscardingChangesCancelled) { $0.accountPendingSwitch = nil }
        await store.send(.switchAccountTapped("other")) { $0.accountPendingSwitch = "other" }
        await store.send(.switchDiscardingChangesConfirmed) { $0.accountPendingSwitch = nil }
        await store.receive(\.delegate, .switchAccount("other"))
    }
}
