import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsPresentationTests: SettingsFeatureTestSupport {
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
}
