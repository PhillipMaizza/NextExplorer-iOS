import Foundation
import TestUtils

enum FilesClientFixture: String, FixtureFile {
    static let bundle = Bundle.module

    // MARK: admin-users

    case adminUsersListTwo = "admin-users/list-two"
    case adminUsersSingle = "admin-users/single"
    case adminUsersVolumesTwo = "admin-users/volumes-two"
    case adminUsersVolumeSingle = "admin-users/volume-single"
    case adminUsersDirectoryListing = "admin-users/directory-listing"
    case adminUsersDirectoryRoot = "admin-users/directory-root"
    case adminUsersErrorEmailInUse = "admin-users/error-email-in-use"
    case adminUsersErrorLastAdmin = "admin-users/error-last-admin"

    // MARK: activity-log

    case activityLogClearedTwelve = "activity-log/cleared-twelve"
    case activityLogDisabledEmpty = "activity-log/disabled-empty"
    case activityLogEnabledEmpty = "activity-log/enabled-empty"

    // MARK: api-token

    case apiTokenErrorLimitReached = "api-token/error-limit-reached"
    case apiTokenErrorNoAccounts = "api-token/error-no-accounts"
    case apiTokenErrorNotFound = "api-token/error-not-found"
    case apiTokenErrorWrongPassword = "api-token/error-wrong-password"
    case apiTokenIssued = "api-token/issued"
    case apiTokenListEmpty = "api-token/list-empty"
    case apiTokenListOne = "api-token/list-one"
    case apiTokenSingle = "api-token/single"

    // MARK: auth-status

    case authStatusLocalAndOidc = "auth-status/local-and-oidc"
    case authStatusOidcOnly = "auth-status/oidc-only"

    // MARK: branding

    case brandingGetCustom = "branding/get-custom"
    case brandingSettingsCustom = "branding/settings-custom"
    case brandingLogoUploaded = "branding/logo-uploaded"
    case brandingErrorLogoRejected = "branding/error-logo-rejected"

    // MARK: browse

    case browseDocsDirectory = "browse/docs-directory"
    case browseEmptyDocsWithAccess = "browse/empty-docs-with-access"
    case browseErrorVolumeAccessDenied = "browse/error-volume-access-denied"
    case browseVolumesList = "browse/volumes-list"

    // MARK: common

    case commonEmptyArray = "common/empty-array"
    case commonEmptyObject = "common/empty-object"
    case commonErrorAdminRequired = "common/error-admin-required"
    case commonItemsEmpty = "common/items-empty"
    case commonSuccessNoItems = "common/success-no-items"
    case commonSuccessTrue = "common/success-true"
    case commonUnexpectedKeyNope = "common/unexpected-key-nope"
    case commonUnexpectedKeyUnexpected = "common/unexpected-key-unexpected"

    // MARK: editor

    case editorContentHi = "editor/content-hi"
    case editorContentTheirs = "editor/content-theirs"

    // MARK: favorite

    case favoriteErrorOrderMismatch = "favorite/error-order-mismatch"
    case favoriteListTwo = "favorite/list-two"
    case favoriteStar = "favorite/star"
    case favoriteUpdated = "favorite/updated"

    // MARK: features

    case featuresUserVolumesEnabled = "features/user-volumes-enabled"

    // MARK: item-mutation

    case itemMutationArchiveStartLine = "item-mutation/archive-start-line"
    case itemMutationCompressedBundleDirectory = "item-mutation/compressed-bundle-directory"
    case itemMutationCompressedDocumentsZip = "item-mutation/compressed-documents-zip"
    case itemMutationCreatedNotesTxt = "item-mutation/created-notes-txt"
    case itemMutationErrorTransferToRoot = "item-mutation/error-transfer-to-root"
    case itemMutationNdjsonCompressDone = "item-mutation/ndjson-compress-done"
    case itemMutationNdjsonCompressError = "item-mutation/ndjson-compress-error"
    case itemMutationNdjsonExtractDone = "item-mutation/ndjson-extract-done"
    case itemMutationRenameMTxt = "item-mutation/rename-m-txt"
    case itemMutationRenameVacation = "item-mutation/rename-vacation"
    case itemMutationTransferCopyToDocuments = "item-mutation/transfer-copy-to-documents"
    case itemMutationTransferToArchive = "item-mutation/transfer-to-archive"
    case itemMutationTransferToOther = "item-mutation/transfer-to-other"

    // MARK: metadata

    case metadataDirectorySummary = "metadata/directory-summary"
    case metadataHashTagDirectory = "metadata/hash-tag-directory"
    case metadataPlainFile = "metadata/plain-file"

    // MARK: offline

    case offlineCorruptManifest = "offline/corrupt-manifest"
    case offlineLegacyManifest = "offline/legacy-manifest"

    // MARK: password

    case passwordAddedMessage = "password/added-message"
    case passwordErrorAlreadyExists = "password/error-already-exists"
    case passwordErrorCurrentIncorrect = "password/error-current-incorrect"
    case passwordErrorTooShort = "password/error-too-short"

    // MARK: permissions

    case permissionsFile644 = "permissions/file-644"
    case permissionsErrorDenied = "permissions/error-denied"
    case permissionsErrorInvalidMode = "permissions/error-invalid-mode"

    // MARK: preferences

    case preferencesEmptyBranding = "preferences/empty-branding"
    case preferencesShowHiddenFiles = "preferences/show-hidden-files"

    // MARK: preview

    case previewThumbnailEmpty = "preview/thumbnail-empty"
    case previewThumbnailPreviewQuery = "preview/thumbnail-preview-query"
    case previewThumbnailStaticPath = "preview/thumbnail-static-path"

    // MARK: search

    case searchMixedMatches = "search/mixed-matches"
    case searchSingleDirectory = "search/single-directory"

    // MARK: share

    case shareCreated = "share/created"
    case shareErrorExpiryInPast = "share/error-expiry-in-past"
    case shareErrorNotFound = "share/error-not-found"
    case shareFull = "share/full"
    case shareInfoQ3Report = "share/info-q3-report"
    case shareListTwo = "share/list-two"
    case shareShareableUsers = "share/shareable-users"

    // MARK: sign-in-method

    case signInMethodEmpty = "sign-in-method/empty"
    case signInMethodLocalPassword = "sign-in-method/local-password"
    case signInMethodOidcPocketId = "sign-in-method/oidc-pocket-id"

    // MARK: system-settings

    case systemSettingsErrorAdminRequired = "system-settings/error-admin-required"
    case systemSettingsHiddenAccessRuleEcho = "system-settings/hidden-access-rule-echo"
    case systemSettingsSearchIndex = "system-settings/search-index"
    case systemSettingsThumbnailsAndAccessRules = "system-settings/thumbnails-and-access-rules"
    case systemSettingsThumbnailsDisabledEcho = "system-settings/thumbnails-disabled-echo"
    case systemSettingsUploadsChunked = "system-settings/uploads-chunked"

    // MARK: text-content

    case textContentHelloWorld = "text-content/hello-world"

    // MARK: trash

    case trashTrashAndVersionsSettings = "trash/trash-and-versions-settings"
    case trashVerificationViolations = "trash/verification-violations"
    case trashZonesEmpty = "trash/zones-empty"
    case trashZonesOneVolume = "trash/zones-one-volume"

    // MARK: two-factor

    case twoFactorErrorAlreadyEnabled = "two-factor/error-already-enabled"
    case twoFactorErrorIncorrectPassword = "two-factor/error-incorrect-password"
    case twoFactorErrorInvalidCode = "two-factor/error-invalid-code"
    case twoFactorErrorPasswordRequired = "two-factor/error-password-required"
    case twoFactorRecoveryCodesOne = "two-factor/recovery-codes-one"
    case twoFactorRecoveryCodesTwo = "two-factor/recovery-codes-two"
    case twoFactorSetupSecret = "two-factor/setup-secret"
    case twoFactorStatusEnabled = "two-factor/status-enabled"

    // MARK: upload

    case uploadErrorForbidden = "upload/error-forbidden"
    case uploadRenamedNotesCopy = "upload/renamed-notes-copy"
    case uploadRenamedWeirdName = "upload/renamed-weird-name"

    // MARK: versioned-files

    case versionedFilesFilesEmpty = "versioned-files/files-empty"
    case versionedFilesPageEmpty = "versioned-files/page-empty"

    // MARK: versions

    case versionsDeletionRemainingOne = "versions/deletion-remaining-one"
    case versionsDeletionRemainingZero = "versions/deletion-remaining-zero"
    case versionsDeletionResult = "versions/deletion-result"
    case versionsEmptyWithTotals = "versions/empty-with-totals"
    case versionsErrorHistoryMissing = "versions/error-history-missing"
    case versionsListNotesTwoVersions = "versions/list-notes-two-versions"
    case versionsRestoreResult = "versions/restore-result"
    case versionsSaveAsCopyResult = "versions/save-as-copy-result"
    case versionsVersionPinned = "versions/version-pinned"

    var fileExtension: String {
        switch self {
        case .itemMutationNdjsonCompressDone, .itemMutationNdjsonCompressError, .itemMutationNdjsonExtractDone:
            "ndjson"
        default:
            "json"
        }
    }
}
