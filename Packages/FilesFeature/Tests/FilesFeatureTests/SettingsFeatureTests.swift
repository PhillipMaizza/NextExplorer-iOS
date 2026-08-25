import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct SettingsFeatureTests {
    private let serverURL = URL(string: "https://example.com")!
    private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

    private func makeState() -> SettingsFeature.State {
        var state = SettingsFeature.State(serverURL: serverURL, user: user)
        // `.inMemory` shared state is a process-wide registry keyed by string, so every test
        // resets to a known value first rather than assuming a clean default.
        state.$preferences.withLock { $0 = UserPreferences() }
        return state
    }

    @Test
    func onAppearFetchesPreferencesSuccessfully() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchPreferences = { _ in UserPreferences(showHiddenFiles: true, showThumbnails: false) }
        }

        await store.send(.onAppear) {
            $0.isLoadingPreferences = true
        }
        await store.receive(\.preferencesResponse.success) { state in
            state.isLoadingPreferences = false
            state.$preferences.withLock { prefs in prefs = UserPreferences(showHiddenFiles: true, showThumbnails: false) }
        }
    }

    @Test
    func onAppearSurfacesAFetchFailureWithoutCrashing() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchPreferences = { _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.onAppear) {
            $0.isLoadingPreferences = true
        }
        await store.receive(\.preferencesResponse.failure) {
            $0.isLoadingPreferences = false
        }
    }

    @Test
    func onAppearIsANoOpWhilePreferencesAreAlreadyLoading() async {
        var state = makeState()
        state.isLoadingPreferences = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        // No `filesClient` dependency overridden: a network call here would crash with
        // "Unimplemented", proving the guard really does skip a concurrent fetch.
        await store.send(.onAppear)
    }

    @Test
    func setShowHiddenFilesUpdatesSharedPreferencesAndPersistsOptimistically() async {
        let recordedKey = LockIsolated<UserPreferenceKey?>(nil)
        let recordedValue = LockIsolated<Bool?>(nil)
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, key, value in
                recordedKey.setValue(key)
                recordedValue.setValue(value)
            }
        }

        await store.send(.setShowHiddenFiles(true)) { state in
            state.$preferences.withLock { prefs in prefs = UserPreferences(showHiddenFiles: true, showThumbnails: prefs.showThumbnails) }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(recordedKey.value == .showHiddenFiles)
        #expect(recordedValue.value == true)
    }

    @Test
    func setShowThumbnailsUpdatesSharedPreferencesAndPersistsOptimistically() async {
        let recordedKey = LockIsolated<UserPreferenceKey?>(nil)
        let recordedValue = LockIsolated<Bool?>(nil)
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, key, value in
                recordedKey.setValue(key)
                recordedValue.setValue(value)
            }
        }

        await store.send(.setShowThumbnails(false)) { state in
            state.$preferences.withLock { prefs in prefs = UserPreferences(showHiddenFiles: prefs.showHiddenFiles, showThumbnails: false) }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(recordedKey.value == .showThumbnails)
        #expect(recordedValue.value == false)
    }

    @Test
    func aFailedPersistLeavesTheOptimisticToggleInPlace() async {
        // Fire-and-forget by design: a failed PATCH doesn't roll the switch back, it just
        // means the server is out of sync until the next successful toggle.
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, _, _ in throw FilesClientError.network("offline") }
        }

        await store.send(.setShowHiddenFiles(true)) { state in
            state.$preferences.withLock { prefs in prefs = UserPreferences(showHiddenFiles: true, showThumbnails: prefs.showThumbnails) }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(store.state.preferences.showHiddenFiles == true)
    }

    @Test
    func signOutButtonTappedShowsTheConfirmationSheet() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        }

        await store.send(.signOutButtonTapped) {
            $0.isConfirmingSignOut = true
        }
    }

    @Test
    func cancelSignOutTappedHidesTheConfirmationSheet() async {
        var state = makeState()
        state.isConfirmingSignOut = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.cancelSignOutTapped) {
            $0.isConfirmingSignOut = false
        }
    }

    @Test
    func confirmSignOutTappedHidesTheSheetAndDelegatesTheActualSignOut() async {
        var state = makeState()
        state.isConfirmingSignOut = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.confirmSignOutTapped) {
            $0.isConfirmingSignOut = false
        }
        await store.receive(\.delegate)
    }
}
