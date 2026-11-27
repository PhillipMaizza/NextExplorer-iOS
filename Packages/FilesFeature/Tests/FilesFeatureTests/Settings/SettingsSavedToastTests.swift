import ComposableArchitecture
@testable import FilesFeature
import Localization
import Testing

@MainActor
struct SettingsSavedToastTests: SettingsFeatureTestSupport {
    @Test("Saving a server settings pane confirms it once, then the toast is cleared")
    func savingAPaneConfirmsIt() async {
        var state = makeState()
        state.accessRules = AccessRulesFeature.State(serverURL: serverURL)
        let store = makeStore(state: state)

        await store.send(.accessRules(.presented(.delegate(.saved)))) {
            $0.savedToast = L10n.Settings.changesSaved
        }
        await store.send(.savedToastShown) { $0.savedToast = nil }
    }
}
