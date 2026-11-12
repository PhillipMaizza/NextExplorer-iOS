import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.dependencies)
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
    func tappingTwoFactorPresentsItAndDismissingClearsIt() async {
        let store = TestStore(initialState: makeState()) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.twoFactorButtonTapped) {
            $0.twoFactor = TwoFactorFeature.State(serverURL: serverURL)
        }
        await store.send(.twoFactor(.dismiss)) {
            $0.twoFactor = nil
        }
    }

    @Test
    func tappingAPITokensPresentsItAndDismissingClearsIt() async {
        let store = TestStore(initialState: makeState()) { SettingsFeature() }
        store.exhaustivity = .off

        await store.send(.apiTokensButtonTapped)
        #expect(store.state.apiTokens?.serverURL == serverURL)
        await store.send(.apiTokens(.dismiss)) { $0.apiTokens = nil }
    }

    @Test
    func aSingleSignOnAccountIsNotAskedForAPasswordToMakeATokenButOthersAre() async {
        let sso = methodsStore { [SignInMethod(id: "m2", type: "oidc", provider: "PocketID")] }
        await sso.send(.onAppear)
        await sso.skipReceivedActions()
        await sso.send(.apiTokensButtonTapped)
        #expect(sso.state.apiTokens?.requiresPassword == false)

        let local = methodsStore { [SignInMethod(id: "m1", type: SignInMethod.localPasswordType, provider: "Password")] }
        await local.send(.onAppear)
        await local.skipReceivedActions()
        await local.send(.apiTokensButtonTapped)
        #expect(local.state.apiTokens?.requiresPassword == true)

        let unknown = methodsStore { throw FilesClientError.server(statusCode: 500) }
        await unknown.send(.onAppear)
        await unknown.skipReceivedActions()
        await unknown.send(.apiTokensButtonTapped)
        #expect(unknown.state.apiTokens?.requiresPassword == true)
    }

    // MARK: Password rows (`GET /api/auth/methods`)

    private func methodsStore(
        state: SettingsFeature.State? = nil,
        status: @escaping @Sendable () throws -> AuthStatus = { AuthStatus(localEnabled: true, oidcEnabled: false) },
        methods: @escaping @Sendable () throws -> [SignInMethod]
    ) -> TestStoreOf<SettingsFeature> {
        let store = TestStore(initialState: state ?? makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchAuthMethods = { _ in try methods() }
            $0.filesClient.fetchAuthStatus = { _ in try status() }
            $0.filesClient.fetchPreferences = { _ in UserPreferences() }
            $0.filesClient.fetchBranding = { _ in Branding() }
            $0.filesClient.serverFeatures = { _ in ServerFeatures() }
            $0.localDownloadStore.list = { _ in [] }
            $0.previewCacheStore.size = { 0 }
        }
        store.exhaustivity = .off
        return store
    }

    @Test
    func anAccountWithAPasswordKeepsTheChangePasswordRow() async {
        let store = methodsStore { [SignInMethod(id: "m1", type: SignInMethod.localPasswordType, provider: "Password")] }

        await store.send(.onAppear)
        await store.skipReceivedActions()
        #expect(store.state.passwordStatus == .present)

        await store.send(.changePasswordButtonTapped)
        #expect(store.state.changePassword?.mode == .change)
    }

    @Test
    func aSingleSignOnAccountIsOfferedAddPassword() async {
        let store = methodsStore { [SignInMethod(id: "m2", type: "oidc", provider: "PocketID")] }

        await store.send(.onAppear)
        await store.skipReceivedActions()
        #expect(store.state.passwordStatus == .absent)

        await store.send(.changePasswordButtonTapped)
        #expect(store.state.changePassword?.mode == .add)
    }

    @Test
    func whenTheMethodsCannotBeFetchedTheRowStaysChangePassword() async {
        let store = methodsStore { throw FilesClientError.server(statusCode: 500) }

        await store.send(.onAppear)
        await store.skipReceivedActions()
        #expect(store.state.passwordStatus == .unknown)

        await store.send(.changePasswordButtonTapped)
        #expect(store.state.changePassword?.mode == .change)
    }

    // MARK: Password and two factor rows on a server with password sign in off (`GET /api/auth/status`)

    @Test
    func aServerWithPasswordSignInOffHidesTheRows() async {
        let store = methodsStore(status: { AuthStatus(localEnabled: false, oidcEnabled: true) }) {
            [SignInMethod(id: "m1", type: SignInMethod.localPasswordType, provider: "Password")]
        }

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.localSignInStatus == .disabled)
        #expect(!store.state.showsPasswordRow)
        #expect(!store.state.showsTwoFactorRow)
    }

    @Test
    func aServerWithPasswordSignInOnKeepsBothRowsForAnAccountWithAPassword() async {
        let store = methodsStore {
            [SignInMethod(id: "m1", type: SignInMethod.localPasswordType, provider: "Password")]
        }

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.localSignInStatus == .enabled)
        #expect(store.state.showsPasswordRow)
        #expect(store.state.showsTwoFactorRow)
    }

    @Test
    func aSingleSignOnAccountOnAServerWithPasswordSignInOnIsOfferedAddPasswordButNoTwoFactor() async {
        let store = methodsStore {
            [SignInMethod(id: "m2", type: "oidc", provider: "PocketID")]
        }

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.showsPasswordRow)
        #expect(!store.state.showsTwoFactorRow)
    }

    @Test
    func whenTheStatusCannotBeFetchedTheRowsStayVisible() async {
        let store = methodsStore(status: { throw FilesClientError.server(statusCode: 500) }) {
            [SignInMethod(id: "m1", type: SignInMethod.localPasswordType, provider: "Password")]
        }

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.localSignInStatus == .unknown)
        #expect(store.state.showsPasswordRow)
        #expect(store.state.showsTwoFactorRow)
    }

    @Test
    func theRowsStayVisibleUntilTheStatusArrives() {
        let state = makeState()

        #expect(state.localSignInStatus == .unknown)
        #expect(state.showsPasswordRow)
        #expect(state.showsTwoFactorRow)
    }

    // MARK: Admin settings pages stay admin only

    @Test
    func aNonAdminCannotOpenAnyAdminSettingsPage() async {
        let store = TestStore(initialState: makeState()) { SettingsFeature() }

        await store.send(.uploadSettingsButtonTapped)
        await store.send(.ffmpegSettingsButtonTapped)
        await store.send(.searchIndexSettingsButtonTapped)
        await store.send(.folderSizeSettingsButtonTapped)
        await store.send(.activityLogButtonTapped)
        await store.send(.trashSettingsButtonTapped)
        await store.send(.versionedFilesButtonTapped)

        #expect(store.state.activityLog == nil)
        #expect(store.state.trashSettings == nil)
        #expect(store.state.versionedFiles == nil)
        #expect(store.state.uploadSettings == nil)
        #expect(store.state.ffmpegSettings == nil)
        #expect(store.state.searchIndexSettings == nil)
        #expect(store.state.folderSizeSettings == nil)
    }

    @Test
    func anAdminOpensEachAdminSettingsPage() async {
        let admin = User(id: "admin-1", username: "boss", email: "boss@example.com", roles: [UserRole.admin])
        var state = makeState()
        state.user = admin
        let store = TestStore(initialState: state) { SettingsFeature() }

        await store.send(.uploadSettingsButtonTapped) { $0.uploadSettings = UploadSettingsFeature.State(serverURL: serverURL) }
        await store.send(.ffmpegSettingsButtonTapped) { $0.ffmpegSettings = FFmpegSettingsFeature.State(serverURL: serverURL) }
        await store.send(.searchIndexSettingsButtonTapped) { $0.searchIndexSettings = SearchIndexSettingsFeature.State(serverURL: serverURL) }
        await store.send(.folderSizeSettingsButtonTapped) { $0.folderSizeSettings = FolderSizeSettingsFeature.State(serverURL: serverURL) }
    }

    @Test
    func addingAPasswordClosesTheScreenAndTurnsTheRowIntoChangePassword() async {
        var state = makeState()
        state.passwordStatus = .absent
        state.changePassword = ChangePasswordFeature.State(serverURL: serverURL, mode: .add)
        let store = methodsStore(state: state) { [] }

        await store.send(.changePassword(.presented(.delegate(.passwordAdded))))

        #expect(store.state.passwordStatus == .present)
        #expect(store.state.changePassword == nil)
    }

    @Test
    func openingSettingsAgainRefreshesTheStatus() async {
        var state = makeState()
        state.passwordStatus = .absent
        let store = methodsStore(state: state) { [SignInMethod(id: "m1", type: SignInMethod.localPasswordType, provider: "Password")] }

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.passwordStatus == .present)
    }

    @Test
    func onAppearFetchesPreferencesSuccessfully() async {
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchAuthMethods = { _ in [] }
            $0.filesClient.fetchAuthStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: false) }
            $0.filesClient.fetchPreferences = { _ in UserPreferences(showHiddenFiles: true, showThumbnails: false) }
            $0.filesClient.fetchBranding = { _ in Branding() }
            $0.filesClient.serverFeatures = { _ in ServerFeatures() }
            $0.localDownloadStore.list = { _ in [] }
            $0.previewCacheStore.size = { 0 }
        }
        // `onAppear` merges three independent effects (preferences fetch, downloads check,
        // cache-size check): their completion order isn't guaranteed, so this asserts final
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
            $0.filesClient.fetchAuthMethods = { _ in [] }
            $0.filesClient.fetchAuthStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: false) }
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
        // local: their receive order isn't guaranteed, so assert final state instead).
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
        // `home` came back all zeros: still stored, the view decides not to draw a bar.
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
    func removeAllDownloadsConfirmedDeletesEveryDownloadAndDelegatesUpward() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        state.downloadsSize = 30
        let downloads = [
            LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/a.pdf"), fileName: "a.pdf", location: .documents, size: 10, modifiedDate: MockDate.date),
            LocalDownload(url: URL(fileURLWithPath: "/tmp/Caches/Downloads/b.jpg"), fileName: "b.jpg", location: .cache, size: 20, modifiedDate: MockDate.date),
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
            LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/a.pdf"), fileName: "a.pdf", location: .documents, size: 10, modifiedDate: MockDate.date),
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
