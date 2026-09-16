import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct SettingsFeatureTests {
    private let serverURL = URL(string: "https://example.com")!
    private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

    private func makeState() -> SettingsFeature.State {
        var state = SettingsFeature.State(serverURL: serverURL, user: user)
        // `.inMemory` shared state is a process-wide registry keyed by string, so every test
        // resets to a known value first rather than assuming a clean default.
        state.$preferences.withLock { $0 = UserPreferences() }
        state.$branding.withLock { $0 = Branding() }
        return state
    }

    @Test
    func tappingUserManagementPresentsItSeededFromTheSession() async {
        var state = SettingsFeature.State(serverURL: serverURL, user: User(
            id: "admin-1", username: "boss", email: "boss@example.com", roles: ["admin"]
        ))
        state.$preferences.withLock { $0 = UserPreferences() }
        let store = TestStore(initialState: state) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.userManagementButtonTapped) {
            $0.userManagement = UserManagementFeature.State(serverURL: serverURL, currentUserID: "admin-1")
        }
        await store.send(.userManagement(.dismiss)) {
            $0.userManagement = nil
        }
    }

    @Test
    func tappingChangePasswordPresentsIt() async {
        let store = TestStore(initialState: makeState()) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.changePasswordButtonTapped) {
            $0.changePassword = ChangePasswordFeature.State(serverURL: serverURL)
        }
        await store.send(.changePassword(.dismiss)) {
            $0.changePassword = nil
        }
    }

    @Test
    func onAppearFetchesPreferencesSuccessfully() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchPreferences = { _ in UserPreferences(showHiddenFiles: true, showThumbnails: false) }
            $0.filesClient.fetchBranding = { _ in Branding() }
            $0.filesClient.serverFeatures = { _ in ServerFeatures() }
            $0.localDownloadStore.list = { _ in [] }
            $0.previewCacheStore.size = { 0 }
        }
        // `onAppear` merges three independent effects (preferences fetch, downloads check,
        // cache-size check) — their completion order isn't guaranteed, so this asserts final
        // state rather than a specific receive order.
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoadingPreferences = true
        }
        await store.skipReceivedActions()

        #expect(store.state.isLoadingPreferences == false)
        #expect(store.state.hasDownloads == false)
        #expect(store.state.preferences == UserPreferences(showHiddenFiles: true, showThumbnails: false))
    }

    @Test
    func onAppearSurfacesAFetchFailureWithoutCrashing() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchPreferences = { _ in throw FilesClientError.sessionExpired }
            $0.filesClient.fetchBranding = { _ in Branding() }
            $0.filesClient.serverFeatures = { _ in ServerFeatures() }
            $0.localDownloadStore.list = { _ in [] }
            $0.previewCacheStore.size = { 0 }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoadingPreferences = true
        }
        await store.skipReceivedActions()

        #expect(store.state.isLoadingPreferences == false)
        #expect(store.state.hasDownloads == false)
    }

    @Test
    func onAppearIsANoOpWhilePreferencesAreAlreadyLoading() async {
        var state = makeState()
        state.isLoadingPreferences = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in [] }
            $0.previewCacheStore.size = { 0 }
        }
        // No `filesClient` dependency overridden: a network call here would crash with
        // "Unimplemented", proving the guard really does skip a concurrent preferences fetch
        // (the downloads/cache checks aren't guarded the same way, since they're cheap and
        // local — their receive order isn't guaranteed, so assert final state instead).
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.hasDownloads == false)
        #expect(store.state.cacheSize == 0)
    }

    @Test
    func serverUsageStaysHiddenWhenTheFeatureIsOff() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in
                Issue.record("volumes should not be fetched when volumeUsage is disabled")
                return []
            }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: false)))
        #expect(store.state.isVolumeUsageEnabled == false)
        #expect(store.state.serverUsage.isEmpty)
    }

    @Test
    func serverUsageLoadsAVolumeListThenFillsInEachBar() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in
                [Volume(name: "media", path: "media"), Volume(name: "home", path: "home")]
            }
            $0.filesClient.fetchUsage = { _, path in
                path == "media"
                    ? StorageUsage(path: "media", size: 40, free: 60, total: 100)
                    : StorageUsage(path: "home", size: 0, free: 0, total: 0)
            }
        }
        store.exhaustivity = .off

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: true)))
        await store.skipReceivedActions()

        #expect(store.state.isVolumeUsageEnabled)
        #expect(store.state.serverUsage.map(\.volume.path) == ["media", "home"])
        #expect(store.state.serverUsage[id: "media"]?.usage?.used == 40)
        // `home` came back all zeros — still stored, the view decides not to draw a bar.
        #expect(store.state.serverUsage[id: "home"]?.usage?.isMeaningful == false)
    }

    @Test
    func serverDetailsIsAdminOnly() async {
        let store = TestStore(initialState: makeState()) { SettingsFeature() }
        store.exhaustivity = .off

        // Non-admin (the default `user`): the tap does nothing.
        await store.send(.serverDetailsButtonTapped)
        #expect(store.state.serverDetails == nil)
    }

    @Test
    func serverDetailsOpensForAnAdminSeededFromTheSharedBranding() async {
        var state = SettingsFeature.State(serverURL: serverURL, user: User(
            id: "admin-1", username: "boss", email: "boss@example.com", roles: [UserRole.admin]
        ))
        state.$preferences.withLock { $0 = UserPreferences() }
        state.$branding.withLock { $0 = Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath) }
        let store = TestStore(initialState: state) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.serverDetailsButtonTapped) {
            $0.serverDetails = ServerDetailsFeature.State(
                serverURL: serverURL,
                branding: Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath)
            )
        }
    }

    @Test
    func thumbnailAndAccessRuleScreensAreAdminOnly() async {
        let store = TestStore(initialState: makeState()) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.thumbnailSettingsButtonTapped)
        #expect(store.state.thumbnailSettings == nil)
        await store.send(.accessRulesButtonTapped)
        #expect(store.state.accessRules == nil)
    }

    @Test
    func anAdminOpensTheThumbnailAndAccessRuleScreens() async {
        var state = SettingsFeature.State(serverURL: serverURL, user: User(
            id: "admin-1", username: "boss", email: "boss@example.com", roles: [UserRole.admin]
        ))
        state.$preferences.withLock { $0 = UserPreferences() }
        let store = TestStore(initialState: state) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.thumbnailSettingsButtonTapped) {
            $0.thumbnailSettings = ThumbnailSettingsFeature.State(serverURL: serverURL)
        }
        await store.send(.accessRulesButtonTapped) {
            $0.accessRules = AccessRulesFeature.State(serverURL: serverURL)
        }
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
    func confirmSignOutTappedKeepsTheSheetUpAndDelegatesTheActualSignOut() async {
        var state = makeState()
        state.isConfirmingSignOut = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        // The sheet stays presented so its confirm button can show the spinner the parent
        // drives via `isSigningOut`; the whole scope is torn down once sign out completes.
        await store.send(.confirmSignOutTapped)
        await store.receive(\.delegate)
    }

    @Test
    func removeAllDownloadsTappedShowsTheConfirmationAlert() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        }

        await store.send(.removeAllDownloadsTapped) {
            $0.removeAllDownloadsConfirmationIsPresented = true
        }
    }

    @Test
    func removeAllDownloadsCancelledHidesTheConfirmationAlert() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.removeAllDownloadsCancelled) {
            $0.removeAllDownloadsConfirmationIsPresented = false
        }
    }

    @Test
    func removeAllDownloadsConfirmedDeletesEveryDownloadAndDelegatesUpward() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        state.downloadsSize = 30
        let downloads = [
            LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/a.pdf"), fileName: "a.pdf", location: .documents, size: 10, modifiedDate: Date()),
            LocalDownload(url: URL(fileURLWithPath: "/tmp/Caches/Downloads/b.jpg"), fileName: "b.jpg", location: .cache, size: 20, modifiedDate: Date()),
        ]

        let deletedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in downloads }
            $0.localDownloadStore.delete = { url in deletedURLs.withValue { $0.append(url) } }
        }

        await store.send(.removeAllDownloadsConfirmed) {
            $0.removeAllDownloadsConfirmationIsPresented = false
            $0.isRemovingAllDownloads = true
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.isRemovingAllDownloads = false
            $0.hasDownloads = false
            $0.downloadsSize = 0
        }
        await store.receive(\.delegate)

        #expect(deletedURLs.value == downloads.map(\.url))
    }

    @Test
    func removeAllDownloadsConfirmedIsBestEffortWhenOneFileFailsToDelete() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        let downloads = [
            LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/a.pdf"), fileName: "a.pdf", location: .documents, size: 10, modifiedDate: Date()),
        ]

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in downloads }
            $0.localDownloadStore.delete = { _ in throw FilesClientError.network("permission denied") }
        }

        await store.send(.removeAllDownloadsConfirmed) {
            $0.removeAllDownloadsConfirmationIsPresented = false
            $0.isRemovingAllDownloads = true
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.isRemovingAllDownloads = false
            $0.hasDownloads = false
            $0.downloadsSize = 0
        }
        await store.receive(\.delegate)
    }

    @Test
    func hasDownloadsResponseUpdatesWhetherRemoveAllIsAvailable() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        }

        await store.send(.hasDownloadsResponse(true)) {
            $0.hasDownloads = true
        }
        await store.send(.hasDownloadsResponse(false)) {
            $0.hasDownloads = false
        }
    }

    @Test
    func downloadsSizeResponseUpdatesTheDisplayedSize() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        }

        await store.send(.downloadsSizeResponse(2_048)) {
            $0.downloadsSize = 2_048
        }
    }

    @Test
    func cacheSizeResponseUpdatesTheDisplayedSize() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        }

        await store.send(.cacheSizeResponse(4_096)) {
            $0.cacheSize = 4_096
        }
    }

    @Test
    func clearCacheTappedShowsTheConfirmationAlert() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        }

        await store.send(.clearCacheTapped) {
            $0.clearCacheConfirmationIsPresented = true
        }
    }

    @Test
    func clearCacheCancelledHidesTheConfirmationAlert() async {
        var state = makeState()
        state.clearCacheConfirmationIsPresented = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.clearCacheCancelled) {
            $0.clearCacheConfirmationIsPresented = false
        }
    }

    @Test
    func clearCacheConfirmedClearsTheCacheAndResetsTheSize() async {
        var state = makeState()
        state.clearCacheConfirmationIsPresented = true
        state.cacheSize = 4_096

        let didClear = LockIsolated(false)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.previewCacheStore.clear = { didClear.setValue(true) }
        }

        await store.send(.clearCacheConfirmed) {
            $0.clearCacheConfirmationIsPresented = false
            $0.isClearingCache = true
        }
        await store.receive(\.clearCacheResponse) {
            $0.isClearingCache = false
            $0.cacheSize = 0
        }

        #expect(didClear.value)
    }

    @Test
    func clearCacheConfirmedStillSucceedsWhenClearingFails() async {
        var state = makeState()
        state.clearCacheConfirmationIsPresented = true
        state.cacheSize = 4_096

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.previewCacheStore.clear = { throw FilesClientError.network("permission denied") }
        }

        await store.send(.clearCacheConfirmed) {
            $0.clearCacheConfirmationIsPresented = false
            $0.isClearingCache = true
        }
        await store.receive(\.clearCacheResponse) {
            $0.isClearingCache = false
            $0.cacheSize = 0
        }
    }
}
