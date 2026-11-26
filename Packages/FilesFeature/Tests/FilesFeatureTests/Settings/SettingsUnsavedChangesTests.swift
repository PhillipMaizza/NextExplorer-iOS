import CoreModels
@testable import FilesFeature
import Testing

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
}
