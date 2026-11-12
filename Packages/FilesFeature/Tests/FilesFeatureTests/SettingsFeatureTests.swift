import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite(.dependencies)
@MainActor
struct SettingsFeatureTests {
    private typealias Store = TestStoreOf<SettingsFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])
    private let admin = User(id: "admin-1", username: "boss", email: "boss@example.com", roles: [UserRole.admin])

    private func makeState(user: User? = nil) -> SettingsFeature.State {
        let state = SettingsFeature.State(serverURL: serverURL, user: user ?? self.user)
        // `.inMemory` shared state is keyed by string, so every test starts from a known value
        // rather than assuming a clean default.
        state.$preferences.withLock { $0 = UserPreferences() }
        state.$branding.withLock { $0 = Branding() }
        return state
    }

    private func makeStore(state: SettingsFeature.State? = nil) -> Store {
        TestStore(initialState: state ?? makeState()) { SettingsFeature() }
    }

    // MARK: Presenting a screen

    struct PresentCase: Sendable, CustomStringConvertible {
        let description: String
        let tap: SettingsFeature.Action
        let dismiss: SettingsFeature.Action
        let present: @Sendable (inout SettingsFeature.State, URL) -> Void
        let clear: @Sendable (inout SettingsFeature.State) -> Void
    }

    @Test(arguments: [
        PresentCase(
            description: "user management",
            tap: .userManagementButtonTapped,
            dismiss: .userManagement(.dismiss),
            present: { $0.userManagement = UserManagementFeature.State(serverURL: $1, currentUserID: "1") },
            clear: { $0.userManagement = nil }
        ),
        PresentCase(
            description: "change password",
            tap: .changePasswordButtonTapped,
            dismiss: .changePassword(.dismiss),
            present: { $0.changePassword = ChangePasswordFeature.State(serverURL: $1) },
            clear: { $0.changePassword = nil }
        ),
        PresentCase(
            description: "two factor",
            tap: .twoFactorButtonTapped,
            dismiss: .twoFactor(.dismiss),
            present: { $0.twoFactor = TwoFactorFeature.State(serverURL: $1) },
            clear: { $0.twoFactor = nil }
        ),
        PresentCase(
            description: "api tokens",
            tap: .apiTokensButtonTapped,
            dismiss: .apiTokens(.dismiss),
            present: { $0.apiTokens = APITokensFeature.State(serverURL: $1, requiresPassword: true) },
            clear: { $0.apiTokens = nil }
        ),
    ])
    func tappingARowPresentsItAndDismissingClearsIt(_ testCase: PresentCase) async {
        let store = makeStore()

        await store.send(testCase.tap) { testCase.present(&$0, serverURL) }
        await store.send(testCase.dismiss) { testCase.clear(&$0) }
    }

    @Test
    func userManagementIsSeededFromTheSession() async {
        let store = makeStore(state: makeState(user: User(id: "admin-1", username: "boss", email: "boss@example.com", roles: ["admin"])))

        await store.send(.userManagementButtonTapped) {
            $0.userManagement = UserManagementFeature.State(serverURL: serverURL, currentUserID: "admin-1")
        }
    }

    // MARK: Password rows

    struct MethodsCase: Sendable {
        let result: Result<[SignInMethod], FilesClientError>
        let expected: SettingsFeature.PasswordStatus?
    }

    @Test(arguments: [
        MethodsCase(result: .success([SignInMethod(id: "m1", type: "local_password", provider: "Password")]), expected: .present),
        MethodsCase(result: .success([SignInMethod(id: "m2", type: "oidc", provider: "PocketID")]), expected: .absent),
        MethodsCase(result: .success([]), expected: .absent),
        MethodsCase(result: .failure(.server(statusCode: 500)), expected: nil),
    ])
    func theSignInMethodsDecideWhetherTheAccountHasAPassword(_ testCase: MethodsCase) async {
        let store = makeStore()

        if let expected = testCase.expected {
            await store.send(.authMethodsResponse(testCase.result)) { $0.passwordStatus = expected }
        } else {
            await store.send(.authMethodsResponse(testCase.result))
            #expect(store.state.passwordStatus == .unknown)
        }
    }

    struct StatusCase: Sendable {
        let result: Result<AuthStatus, FilesClientError>
        let expected: SettingsFeature.LocalSignInStatus?
    }

    @Test(arguments: [
        StatusCase(result: .success(AuthStatus(localEnabled: true, oidcEnabled: false)), expected: .enabled),
        StatusCase(result: .success(AuthStatus(localEnabled: false, oidcEnabled: true)), expected: .disabled),
        StatusCase(result: .failure(.server(statusCode: 500)), expected: nil),
    ])
    func theServerStatusDecidesWhetherPasswordSignInIsOn(_ testCase: StatusCase) async {
        let store = makeStore()

        if let expected = testCase.expected {
            await store.send(.authStatusResponse(testCase.result)) { $0.localSignInStatus = expected }
        } else {
            await store.send(.authStatusResponse(testCase.result))
            #expect(store.state.localSignInStatus == .unknown)
        }
    }

    struct RowsCase: Sendable {
        let signIn: SettingsFeature.LocalSignInStatus
        let password: SettingsFeature.PasswordStatus
        let showsPassword: Bool
        let showsTwoFactor: Bool
    }

    @Test(arguments: [
        RowsCase(signIn: .unknown, password: .unknown, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .unknown, password: .present, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .unknown, password: .absent, showsPassword: true, showsTwoFactor: false),
        RowsCase(signIn: .enabled, password: .present, showsPassword: true, showsTwoFactor: true),
        RowsCase(signIn: .enabled, password: .absent, showsPassword: true, showsTwoFactor: false),
        RowsCase(signIn: .disabled, password: .present, showsPassword: false, showsTwoFactor: false),
        RowsCase(signIn: .disabled, password: .absent, showsPassword: false, showsTwoFactor: false),
    ])
    func thePasswordAndTwoFactorRowsFollowTheServerAndTheAccount(_ testCase: RowsCase) {
        var state = makeState()
        state.localSignInStatus = testCase.signIn
        state.passwordStatus = testCase.password

        #expect(state.showsPasswordRow == testCase.showsPassword)
        #expect(state.showsTwoFactorRow == testCase.showsTwoFactor)
    }

    @Test
    func theRowsStayVisibleUntilTheStatusArrives() {
        let state = makeState()

        #expect(state.passwordStatus == .unknown)
        #expect(state.localSignInStatus == .unknown)
        #expect(state.showsPasswordRow)
        #expect(state.showsTwoFactorRow)
    }

    @Test(arguments: [
        (SettingsFeature.PasswordStatus.present, ChangePasswordFeature.Mode.change),
        (.absent, .add),
        (.unknown, .change),
    ])
    func theChangePasswordScreenOpensInTheModeTheAccountNeeds(status: SettingsFeature.PasswordStatus, mode: ChangePasswordFeature.Mode) async {
        var state = makeState()
        state.passwordStatus = status
        let store = makeStore(state: state)

        await store.send(.changePasswordButtonTapped) {
            $0.changePassword = ChangePasswordFeature.State(serverURL: serverURL, mode: mode)
        }
    }

    @Test(arguments: [
        (SettingsFeature.PasswordStatus.present, true),
        (.absent, false),
        (.unknown, true),
    ])
    func aSingleSignOnAccountIsNotAskedForAPasswordToMakeAToken(status: SettingsFeature.PasswordStatus, requiresPassword: Bool) async {
        var state = makeState()
        state.passwordStatus = status
        let store = makeStore(state: state)

        await store.send(.apiTokensButtonTapped) {
            $0.apiTokens = APITokensFeature.State(serverURL: serverURL, requiresPassword: requiresPassword)
        }
    }

    @Test
    func addingAPasswordClosesTheScreenAndTurnsTheRowIntoChangePassword() async {
        var state = makeState()
        state.passwordStatus = .absent
        state.changePassword = ChangePasswordFeature.State(serverURL: serverURL, mode: .add)
        let store = makeStore(state: state)

        await store.send(.changePassword(.presented(.delegate(.passwordAdded)))) {
            $0.passwordStatus = .present
            $0.changePassword = nil
        }
    }

    // MARK: Appearing

    // `onAppear` starts about ten effects at once, several of them synchronous reads (downloads,
    // caches, certificate) whose actions arrive in no fixed order, and ordering them would need the
    // process wide serial executor. So each answer it delivers is sent directly instead.

    @Test
    func theDownloadsCheckAnswersSetTheirState() async {
        let store = makeStore()

        await store.send(.hasDownloadsResponse(false)) { $0.hasDownloads = false }
        await store.send(.downloadsSizeResponse(30)) { $0.downloadsSize = 30 }
    }

    @Test
    func theCacheAndOfflineSizeAnswersSetTheirState() async {
        let store = makeStore()

        await store.send(.cacheSizeResponse(4096)) { $0.cacheSize = 4096 }
        await store.send(.offlineSizeResponse(2048)) { $0.offlineSize = 2048 }
    }

    @Test
    func theClientCertificateAnswerShowsOnTheRow() async {
        let store = makeStore()
        let summary = ClientCertificateSummary(subject: "Dev Client")

        await store.send(.clientCertificateStatusLoaded(nil)) { $0.clientCertificateStatus = .empty }
        await store.send(.clientCertificateStatusLoaded(summary)) { $0.clientCertificateStatus = .installed(summary) }
    }

    @Test
    func theLoadedPreferencesReplaceTheSharedOnes() async {
        var state = makeState()
        state.isLoadingPreferences = true
        let store = makeStore(state: state)

        await store.send(.preferencesResponse(.success(UserPreferences(showHiddenFiles: true, showThumbnails: false)))) {
            $0.isLoadingPreferences = false
            $0.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: true, showThumbnails: false) }
        }
    }

    @Test
    func aFailedPreferencesLoadKeepsTheSharedOnes() async {
        var state = makeState()
        state.isLoadingPreferences = true
        let store = makeStore(state: state)

        await store.send(.preferencesResponse(.failure(.sessionExpired))) { $0.isLoadingPreferences = false }

        #expect(store.state.preferences == UserPreferences())
    }

    // MARK: Server usage

    @Test
    func serverUsageStaysHiddenWhenTheFeatureIsOff() async {
        let volumeReads = LockIsolated(0)
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in
                volumeReads.withValue { $0 += 1 }
                return []
            }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: false)))

        #expect(!store.state.isVolumeUsageEnabled)
        #expect(store.state.serverUsage.isEmpty)
        #expect(volumeReads.value == 0)
    }

    @Test
    func serverUsageLoadsAVolumeListThenFillsInEachBar() async {
        let homeGate = AsyncGate()
        let media = Volume(name: "media", path: "media")
        let home = Volume(name: "home", path: "home")
        let mediaUsage = StorageUsage(path: "media", size: 40, free: 60, total: 100)
        let homeUsage = StorageUsage(path: "home", size: 0, free: 0, total: 0)
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in [media, home] }
            $0.filesClient.fetchUsage = { _, path in
                if path == "home" {
                    try await homeGate.wait()
                    return homeUsage
                }
                return mediaUsage
            }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: true))) { $0.isVolumeUsageEnabled = true }
        await store.receive(\.volumesResponse) {
            $0.serverUsage = [
                SettingsFeature.VolumeUsage(volume: media, usage: nil),
                SettingsFeature.VolumeUsage(volume: home, usage: nil),
            ]
        }
        await store.receive(\.serverUsageResponse) { $0.serverUsage[id: "media"]?.usage = mediaUsage }
        homeGate.open()
        await store.receive(\.serverUsageResponse) { $0.serverUsage[id: "home"]?.usage = homeUsage }

        // `home` came back all zeros: still stored, the view decides not to draw a bar.
        #expect(store.state.serverUsage[id: "home"]?.usage?.isMeaningful == false)
        #expect(store.state.serverUsage[id: "media"]?.usage?.used == 40)
    }

    @Test
    func aVolumeWhoseUsageFailsKeepsItsRowWithoutABar() async {
        let media = Volume(name: "media", path: "media")
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in [media] }
            $0.filesClient.fetchUsage = { _, _ in throw FilesClientError.offline }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: true))) { $0.isVolumeUsageEnabled = true }
        await store.receive(\.volumesResponse) { $0.serverUsage = [SettingsFeature.VolumeUsage(volume: media, usage: nil)] }
        await store.receive(\.serverUsageResponse)

        #expect(store.state.serverUsage[id: "media"]?.usage == nil)
    }

    // MARK: Admin settings pages stay admin only

    struct AdminPageCase: Sendable, CustomStringConvertible {
        let description: String
        let tap: SettingsFeature.Action
        let isOpen: @Sendable (SettingsFeature.State) -> Bool
        let open: @Sendable (inout SettingsFeature.State, URL) -> Void
    }

    nonisolated static let adminPages = [
        AdminPageCase(
            description: "server details",
            tap: .serverDetailsButtonTapped,
            isOpen: { $0.serverDetails != nil },
            open: { $0.serverDetails = ServerDetailsFeature.State(serverURL: $1, branding: Branding()) }
        ),
        AdminPageCase(
            description: "thumbnails",
            tap: .thumbnailSettingsButtonTapped,
            isOpen: { $0.thumbnailSettings != nil },
            open: { $0.thumbnailSettings = ThumbnailSettingsFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "access rules",
            tap: .accessRulesButtonTapped,
            isOpen: { $0.accessRules != nil },
            open: { $0.accessRules = AccessRulesFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "uploads",
            tap: .uploadSettingsButtonTapped,
            isOpen: { $0.uploadSettings != nil },
            open: { $0.uploadSettings = UploadSettingsFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "ffmpeg",
            tap: .ffmpegSettingsButtonTapped,
            isOpen: { $0.ffmpegSettings != nil },
            open: { $0.ffmpegSettings = FFmpegSettingsFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "search index",
            tap: .searchIndexSettingsButtonTapped,
            isOpen: { $0.searchIndexSettings != nil },
            open: { $0.searchIndexSettings = SearchIndexSettingsFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "folder size",
            tap: .folderSizeSettingsButtonTapped,
            isOpen: { $0.folderSizeSettings != nil },
            open: { $0.folderSizeSettings = FolderSizeSettingsFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "activity log",
            tap: .activityLogButtonTapped,
            isOpen: { $0.activityLog != nil },
            open: { $0.activityLog = ActivityLogFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "trash",
            tap: .trashSettingsButtonTapped,
            isOpen: { $0.trashSettings != nil },
            open: { $0.trashSettings = TrashSettingsFeature.State(serverURL: $1) }
        ),
        AdminPageCase(
            description: "versioned files",
            tap: .versionedFilesButtonTapped,
            isOpen: { $0.versionedFiles != nil },
            open: { $0.versionedFiles = VersionedFilesFeature.State(serverURL: $1) }
        ),
    ]

    @Test(arguments: adminPages)
    func aNonAdminCannotOpenAnAdminSettingsPage(_ page: AdminPageCase) async {
        let store = makeStore()

        await store.send(page.tap)

        #expect(!page.isOpen(store.state))
    }

    @Test(arguments: adminPages)
    func anAdminOpensAnAdminSettingsPage(_ page: AdminPageCase) async {
        let store = makeStore(state: makeState(user: admin))

        await store.send(page.tap) { page.open(&$0, serverURL) }
    }

    @Test
    func serverDetailsOpensSeededFromTheSharedBranding() async {
        let state = makeState(user: admin)
        state.$branding.withLock { $0 = Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath) }
        let store = makeStore(state: state)

        await store.send(.serverDetailsButtonTapped) {
            $0.serverDetails = ServerDetailsFeature.State(
                serverURL: serverURL,
                branding: Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath)
            )
        }
    }

    // MARK: Preferences

    struct ToggleCase: Sendable {
        let action: SettingsFeature.Action
        let key: UserPreferenceKey
        let value: Bool
        let expected: UserPreferences
    }

    @Test(arguments: [
        ToggleCase(action: .setShowHiddenFiles(true), key: .showHiddenFiles, value: true, expected: UserPreferences(showHiddenFiles: true, showThumbnails: true)),
        ToggleCase(action: .setShowThumbnails(false), key: .showThumbnails, value: false, expected: UserPreferences(showHiddenFiles: false, showThumbnails: false)),
    ])
    func aToggleUpdatesTheSharedPreferencesAndPersistsOptimistically(_ testCase: ToggleCase) async {
        let recorded = LockIsolated<[String]>([])
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, key, value in
                recorded.withValue { $0.append("\(key.rawValue)=\(value)") }
            }
        }

        await store.send(testCase.action) { state in
            state.$preferences.withLock { $0 = testCase.expected }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(recorded.value == ["\(testCase.key.rawValue)=\(testCase.value)"])
    }

    @Test
    func aFailedPersistLeavesTheOptimisticToggleInPlace() async {
        // Fire and forget by design: a failed PATCH does not roll the switch back.
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, _, _ in throw FilesClientError.network("offline") }
        }

        await store.send(.setShowHiddenFiles(true)) { state in
            state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: true, showThumbnails: true) }
        }
        await store.receive(\.updatePreferenceResponse)

        #expect(store.state.preferences.showHiddenFiles)
    }

    @Test
    func aSecondToggleOfTheSameSwitchReplacesTheSaveStillInFlight() async throws {
        let firstStarted = AsyncGate()
        let hold = AsyncGate()
        let calls = LockIsolated<[Bool]>([])
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.updatePreference = { _, _, value in
                let isFirst = calls.withValue { calls -> Bool in
                    calls.append(value)
                    return calls.count == 1
                }
                if isFirst {
                    firstStarted.open()
                    try await hold.wait()
                }
            }
        }

        await store.send(.setShowHiddenFiles(true)) { state in
            state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: true, showThumbnails: true) }
        }
        try await firstStarted.wait()
        await store.send(.setShowHiddenFiles(false)) { state in
            state.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: false, showThumbnails: true) }
        }
        await store.receive(\.updatePreferenceResponse)
        await store.finish()

        #expect(calls.value == [true, false])
    }

    // MARK: Signing out

    @Test
    func theSignOutButtonAsksFirstAndCancelWithdrawsTheQuestion() async {
        let store = makeStore()

        await store.send(.signOutButtonTapped) { $0.isConfirmingSignOut = true }
        await store.send(.cancelSignOutTapped) { $0.isConfirmingSignOut = false }
    }

    @Test
    func confirmSignOutTappedKeepsTheSheetUpAndDelegatesTheActualSignOut() async {
        var state = makeState()
        state.isConfirmingSignOut = true
        let store = makeStore(state: state)

        // The sheet stays presented so its confirm button can show the spinner the parent drives
        // through `isSigningOut`; the whole scope is torn down once sign out completes.
        await store.send(.confirmSignOutTapped)
        await store.receive(\.delegate, .signOutButtonTapped)

        #expect(store.state.isConfirmingSignOut)
    }

    // MARK: Downloads and cache

    private func download(_ name: String, location: DownloadLocation, size: Int64) -> LocalDownload {
        LocalDownload(url: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, location: location, size: size, modifiedDate: MockDate.date)
    }

    @Test
    func removeAllDownloadsConfirmedDeletesEveryDownloadOfThisAccountAndDelegatesUpward() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        state.downloadsSize = 30
        state.$downloadScope.withLock { $0 = "account-a" }
        let downloads = [download("a.pdf", location: .documents, size: 10), download("b.jpg", location: .cache, size: 20)]
        let listedScopes = LockIsolated<[String]>([])
        let deletedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { scope in
                listedScopes.withValue { $0.append(scope) }
                return downloads
            }
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
        await store.receive(\.delegate, .allDownloadsRemoved)

        #expect(listedScopes.value == ["account-a"])
        #expect(deletedURLs.value == [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.jpg")])
    }

    @Test
    func removeAllDownloadsConfirmedIsBestEffortWhenOneFileFailsToDelete() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        let downloads = [download("a.pdf", location: .documents, size: 10), download("b.jpg", location: .cache, size: 20)]
        let attempted = LockIsolated<[URL]>([])
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in downloads }
            $0.localDownloadStore.delete = { url in
                attempted.withValue { $0.append(url) }
                if url.lastPathComponent == "a.pdf" {
                    throw FilesClientError.network("permission denied")
                }
            }
        }

        await store.send(.removeAllDownloadsConfirmed) {
            $0.removeAllDownloadsConfirmationIsPresented = false
            $0.isRemovingAllDownloads = true
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.isRemovingAllDownloads = false
            $0.hasDownloads = false
        }
        await store.receive(\.delegate, .allDownloadsRemoved)

        #expect(attempted.value == [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.jpg")])
    }

    @Test(arguments: [false, true])
    func clearCacheConfirmedClearsTheCacheAndResetsTheSizeEvenWhenClearingFails(clearFails: Bool) async {
        var state = makeState()
        state.clearCacheConfirmationIsPresented = true
        state.cacheSize = 4096
        let clears = LockIsolated(0)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.previewCacheStore.clear = {
                clears.withValue { $0 += 1 }
                if clearFails {
                    throw FilesClientError.network("permission denied")
                }
            }
        }

        await store.send(.clearCacheConfirmed) {
            $0.clearCacheConfirmationIsPresented = false
            $0.isClearingCache = true
        }
        await store.receive(\.clearCacheResponse) {
            $0.isClearingCache = false
            $0.cacheSize = 0
        }

        #expect(clears.value == 1)
    }
}
