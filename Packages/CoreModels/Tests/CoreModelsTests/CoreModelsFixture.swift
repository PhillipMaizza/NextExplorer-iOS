import Foundation
import TestUtils

enum CoreModelsFixture: String, FixtureFile {
    static let bundle = Bundle.module

    // MARK: activity-log
    case activityLogEmptyPage = "activity-log/empty-page"
    case activityLogNumericEventId = "activity-log/numeric-event-id"
    case activityLogPageWithEvents = "activity-log/page-with-events"
    case activityLogSystemSettingsWithActivity = "activity-log/system-settings-with-activity"
    case activityLogTimestampWithFractionalSeconds = "activity-log/timestamp-with-fractional-seconds"
    case activityLogTimestampWithoutFractionalSeconds = "activity-log/timestamp-without-fractional-seconds"
    case activityLogUnknownOutcome = "activity-log/unknown-outcome"
    case activityLogUnparseableTimestamp = "activity-log/unparseable-timestamp"

    // MARK: api-token
    case apiTokenFull = "api-token/full"
    case apiTokenIssuedWithSecret = "api-token/issued-with-secret"
    case apiTokenIssuedWithShortSecret = "api-token/issued-with-short-secret"
    case apiTokenNeverExpiresNeverUsed = "api-token/never-expires-never-used"
    case apiTokenUnknownScope = "api-token/unknown-scope"

    // MARK: auth-status
    case authStatusLocalEnabledOidcDisabled = "auth-status/local-enabled-oidc-disabled"

    // MARK: branding
    case brandingFullObject = "branding/full-object"

    // MARK: browse-result
    case browseResultDirectoryWithAccess = "browse-result/directory-with-access"
    case browseResultEmptyDirectory = "browse-result/empty-directory"

    // MARK: common
    case emptyObject = "common/empty-object"

    // MARK: favorite
    case favoriteFullRow = "favorite/full-row"

    // MARK: file-access
    case fileAccessFullGrant = "file-access/full-grant"
    case fileAccessMissingRequiredFields = "file-access/missing-required-fields"
    case fileAccessReadOnlyGrant = "file-access/read-only-grant"
    case fileAccessWithCreateFlags = "file-access/with-create-flags"
    case fileAccessWithoutCreateFlags = "file-access/without-create-flags"

    // MARK: file-item
    case fileItemDirectoryWithThumbnail = "file-item/directory-with-thumbnail"
    case fileItemMissingRequiredFields = "file-item/missing-required-fields"
    case fileItemMissingSupportsThumbnail = "file-item/missing-supports-thumbnail"
    case fileItemSizeInvalidType = "file-item/size-invalid-type"
    case fileItemSizeMissing = "file-item/size-missing"
    case fileItemSizeNull = "file-item/size-null"

    // MARK: file-metadata
    case fileMetadataDirectorySummary = "file-metadata/directory-summary"
    case fileMetadataImageDimensionsOnly = "file-metadata/image-dimensions-only"
    case fileMetadataImageWithGps = "file-metadata/image-with-gps"
    case fileMetadataPlainFile = "file-metadata/plain-file"
    case fileMetadataVideo = "file-metadata/video"

    // MARK: file-permissions
    case filePermissionsBackendShape = "file-permissions/backend-shape"

    // MARK: google-docs-pointer
    case googleDocsPointerDriveStub = "google-docs-pointer/drive-stub"
    case googleDocsPointerMissingUrl = "google-docs-pointer/missing-url"
    case googleDocsPointerNonHttpLink = "google-docs-pointer/non-http-link"
    case googleDocsPointerNotJson = "google-docs-pointer/not-json"

    // MARK: search-result-item
    case searchResultItemContentMatch = "search-result-item/content-match"
    case searchResultItemDirectoryKind = "search-result-item/directory-kind"
    case searchResultItemFilenameMatch = "search-result-item/filename-match"

    // MARK: server-features
    case serverFeaturesEditorExtensions = "server-features/editor-extensions"
    case serverFeaturesPersonalEnabled = "server-features/personal-enabled"
    case serverFeaturesVolumeUsageEnabledUserVolumesDisabled = "server-features/volume-usage-enabled-user-volumes-disabled"

    // MARK: server-settings
    case serverSettingsFolderSizeUnknownMode = "server-settings/folder-size-unknown-mode"
    case serverSettingsServerFeaturesCeilingAndLocks = "server-settings/server-features-ceiling-and-locks"
    case serverSettingsSystemSettingsFourBackgroundSections = "server-settings/system-settings-four-background-sections"
    case serverSettingsSystemSettingsUserOnly = "server-settings/system-settings-user-only"

    // MARK: share-info
    case shareInfoInfoEndpointShape = "share-info/info-endpoint-shape"
    case shareInfoMinimalExpiredUsersShare = "share-info/minimal-expired-users-share"

    // MARK: sign-in-method
    case signInMethodListWithoutDates = "sign-in-method/list-without-dates"
    case signInMethodPasswordAndOidcList = "sign-in-method/password-and-oidc-list"

    // MARK: storage-usage
    case storageUsageDeniedAllZero = "storage-usage/denied-all-zero"
    case storageUsageFortyOfHundred = "storage-usage/forty-of-hundred"
    case storageUsageNoTotalReported = "storage-usage/no-total-reported"
    case storageUsageSmallFolderOnNearlyFullDisk = "storage-usage/small-folder-on-nearly-full-disk"
    case storageUsageUsedExceedsCapacity = "storage-usage/used-exceeds-capacity"

    // MARK: system-settings
    case systemSettingsFullAdminShape = "system-settings/full-admin-shape"
    case systemSettingsNonAdminShape = "system-settings/non-admin-shape"

    // MARK: transfer-result
    case transferResultMissingSkipped = "transfer-result/missing-skipped"
    case transferResultMoveWithSkippedItem = "transfer-result/move-with-skipped-item"

    // MARK: trash-admin
    case trashAdminSystemSettingsTrashAndVersions = "trash-admin/system-settings-trash-and-versions"
    case trashAdminVerificationEmptyViolations = "trash-admin/verification-empty-violations"
    case trashAdminVerificationMissingViolations = "trash-admin/verification-missing-violations"
    case trashAdminVerificationMixedViolationShapes = "trash-admin/verification-mixed-violation-shapes"
    case trashAdminVerificationWithInvariantAndDetail = "trash-admin/verification-with-invariant-and-detail"
    case trashAdminZoneUnavailableWithoutBudget = "trash-admin/zone-unavailable-without-budget"
    case trashAdminZoneUnknownKind = "trash-admin/zone-unknown-kind"
    case trashAdminZoneWithLastPassAndEvents = "trash-admin/zone-with-last-pass-and-events"

    // MARK: two-factor
    case twoFactorEnabled = "two-factor/enabled"
    case twoFactorMissingRequiredKeys = "two-factor/missing-required-keys"
    case twoFactorPendingNeverConfirmed = "two-factor/pending-never-confirmed"
    case twoFactorSetup = "two-factor/setup"
    case twoFactorWithoutConfirmedDate = "two-factor/without-confirmed-date"

    // MARK: user-preferences
    case userPreferencesEmptyObject = "user-preferences/empty-object"
    case userPreferencesExplicitValues = "user-preferences/explicit-values"
    case userPreferencesPartialObject = "user-preferences/partial-object"
    case userPreferencesShareExpirationNull = "user-preferences/share-expiration-null"
    case userPreferencesShareExpirationWeeks = "user-preferences/share-expiration-weeks"

    // MARK: user
    case userAdminWithAuthMethods = "user/admin-with-auth-methods"
    case userAdminWithEmail = "user/admin-with-email"
    case userGarbageTimestamp = "user/garbage-timestamp"
    case userGuestMissingEmailAndRoles = "user/guest-missing-email-and-roles"
    case userIntegerId = "user/integer-id"
    case userLoginResponseIsoTimestamps = "user/login-response-iso-timestamps"
    case userMissingUsername = "user/missing-username"
    case userNonAdminRole = "user/non-admin-role"
    case userNullUsername = "user/null-username"

    // MARK: versioned-files
    case versionedFilesDeletionWithFailures = "versioned-files/deletion-with-failures"
    case versionedFilesDeletionWithRemaining = "versioned-files/deletion-with-remaining"
    case versionedFilesDetailWithPinnedUnavailableVersion = "versioned-files/detail-with-pinned-unavailable-version"
    case versionedFilesPageWithRowsTotalsAndVolumes = "versioned-files/page-with-rows-totals-and-volumes"
    case versionedFilesUnknownStateAndZoneKind = "versioned-files/unknown-state-and-zone-kind"

    // MARK: volume
    case volumeWithAccessMode = "volume/with-access-mode"
    case volumeWithoutAccessMode = "volume/without-access-mode"
}
