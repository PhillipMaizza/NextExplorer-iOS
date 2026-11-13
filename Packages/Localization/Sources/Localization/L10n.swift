import Foundation

// Generated from strings.tsv by Scripts/gen-l10n.py. Do not edit by hand.

public enum L10n {
    public enum AccessMode {
        public static var readonly: String { tr("accessMode.readonly") }  // "Read Only"
        public static var readwrite: String { tr("accessMode.readwrite") }  // "Read & Write"
    }
    public enum AccessRules {
        public static var addRule: String { tr("accessRules.addRule") }  // "Add Rule"
        public static var empty: String { tr("accessRules.empty") }  // "No access rules configured."
        public static var emptyHint: String { tr("accessRules.emptyHint") }  // "Add a rule to override access for a path."
        public static var navigationTitle: String { tr("accessRules.navigationTitle") }  // "Folder Access Rules"
        public static var pathLabel: String { tr("accessRules.pathLabel") }  // "Path"
        public static var pathPlaceholder: String { tr("accessRules.pathPlaceholder") }  // "Documents/Reports"
        public static var permissionHidden: String { tr("accessRules.permissionHidden") }  // "Hidden"
        public static var permissionReadOnly: String { tr("accessRules.permissionReadOnly") }  // "Read Only"
        public static var permissionReadWrite: String { tr("accessRules.permissionReadWrite") }  // "Read & Write"
        public static var recursive: String { tr("accessRules.recursive") }  // "Apply to Subfolders"
        public static var remove: String { tr("accessRules.remove") }  // "Remove"
        public static var saveButton: String { tr("accessRules.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("accessRules.subtitle") }  // "Override read and write access for specific paths."
        public static var unavailable: String { tr("accessRules.unavailable") }  // "Access rules are only available to administrators."
    }
    public enum ActivityLog {
        public static var actionAccountPasskey: String { tr("activityLog.action.accountPasskey") }  // "Passkey changed"
        public static var actionAccountPassword: String { tr("activityLog.action.accountPassword") }  // "Password changed"
        public static var actionAccountToken: String { tr("activityLog.action.accountToken") }  // "API token changed"
        public static var actionAccountTwoFactor: String { tr("activityLog.action.accountTwoFactor") }  // "Second factor changed"
        public static var actionAdminActivityClear: String { tr("activityLog.action.adminActivityClear") }  // "Log cleared"
        public static var actionAdminSettings: String { tr("activityLog.action.adminSettings") }  // "Settings changed"
        public static var actionAdminUser: String { tr("activityLog.action.adminUser") }  // "Account changed"
        public static var actionFileDelete: String { tr("activityLog.action.fileDelete") }  // "Sent to the trash"
        public static var actionFileDownload: String { tr("activityLog.action.fileDownload") }  // "Downloaded"
        public static var actionFilePurge: String { tr("activityLog.action.filePurge") }  // "Removed for good"
        public static var actionFileRestore: String { tr("activityLog.action.fileRestore") }  // "Restored"
        public static var actionFileUpload: String { tr("activityLog.action.fileUpload") }  // "Uploaded"
        public static var actionShareCreate: String { tr("activityLog.action.shareCreate") }  // "Share created"
        public static var actionShareDelete: String { tr("activityLog.action.shareDelete") }  // "Share deleted"
        public static var actionShareDownload: String { tr("activityLog.action.shareDownload") }  // "Downloaded through a link"
        public static var actionShareUpload: String { tr("activityLog.action.shareUpload") }  // "Uploaded through a link"
        public static var actionSignIn: String { tr("activityLog.action.signIn") }  // "Signed in"
        public static var actionSignOut: String { tr("activityLog.action.signOut") }  // "Signed out"
        public static var actionVersionsPurge: String { tr("activityLog.action.versionsPurge") }  // "Versions deleted"
        public static var anyAction: String { tr("activityLog.anyAction") }  // "Any kind"
        public static var anyOutcome: String { tr("activityLog.anyOutcome") }  // "Any outcome"
        public static var clear: String { tr("activityLog.clear") }  // "Empty the Log"
        public static var clearConfirm: String { tr("activityLog.clearConfirm") }  // "Empty the Log"
        public static var clearMessage: String { tr("activityLog.clearMessage") }  // "Every recorded line is deleted. This cannot be undone."
        public static var clearTitle: String { tr("activityLog.clearTitle") }  // "Empty the log?"
        public static var enabled: String { tr("activityLog.enabled") }  // "Record activity"
        public static var enabledHelp: String { tr("activityLog.enabledHelp") }
        public static var filterAction: String { tr("activityLog.filterAction") }  // "Kind"
        public static var filterOutcome: String { tr("activityLog.filterOutcome") }  // "Outcome"
        public static func fromAddress(_ a0: CVarArg) -> String { tr("activityLog.fromAddress", a0) }
        public static var more: String { tr("activityLog.more") }  // "Show More"
        public static var navigationTitle: String { tr("activityLog.navigationTitle") }  // "Activity Log"
        public static var none: String { tr("activityLog.none") }  // "Nothing recorded yet."
        public static var off: String { tr("activityLog.off") }  // "The log is off, so nothing is being recorded."
        public static var outcomeOk: String { tr("activityLog.outcomeOk") }  // "Succeeded"
        public static var outcomeRefused: String { tr("activityLog.outcomeRefused") }  // "Refused"
        public static var refresh: String { tr("activityLog.refresh") }  // "Refresh"
        public static var refusedSuffix: String { tr("activityLog.refusedSuffix") }  // "Refused"
        public static var retention: String { tr("activityLog.retention") }  // "Keep for (days)"
        public static var retentionInvalid: String { tr("activityLog.retentionInvalid") }  // "Between 1 and 3650 days."
        public static var saveButton: String { tr("activityLog.saveButton") }  // "Save Changes"
        public static var searchButton: String { tr("activityLog.searchButton") }  // "Search"
        public static var searchPlaceholder: String { tr("activityLog.searchPlaceholder") }  // "A name or a path"
        public static var subtitle: String { tr("activityLog.subtitle") }
        public static var unavailable: String { tr("activityLog.unavailable") }  // "The activity log is only available to administrators."
    }
    public enum ApiTokens {
        public static var copiedToken: String { tr("apiTokens.copiedToken") }  // "Copied"
        public static var copyToken: String { tr("apiTokens.copyToken") }  // "Copy Token"
        public static var createSubmit: String { tr("apiTokens.createSubmit") }  // "Create Token"
        public static func created(_ a0: CVarArg) -> String { tr("apiTokens.created", a0) }
        public static var emptyMessage: String { tr("apiTokens.emptyMessage") }  // "Create one to let a script use your account."
        public static var emptyTitle: String { tr("apiTokens.emptyTitle") }  // "No API tokens"
        public static func expired(_ a0: CVarArg) -> String { tr("apiTokens.expired", a0) }
        public static func expires(_ a0: CVarArg) -> String { tr("apiTokens.expires", a0) }
        public static var expiry30: String { tr("apiTokens.expiry30") }  // "In 30 days"
        public static var expiry90: String { tr("apiTokens.expiry90") }  // "In 90 days"
        public static var expiryNever: String { tr("apiTokens.expiryNever") }  // "Never"
        public static var expiryYear: String { tr("apiTokens.expiryYear") }  // "In 1 year"
        public static var fieldAccess: String { tr("apiTokens.fieldAccess") }  // "Access"
        public static var fieldExpiry: String { tr("apiTokens.fieldExpiry") }  // "Expires"
        public static var fieldName: String { tr("apiTokens.fieldName") }  // "Name"
        public static var fieldPassword: String { tr("apiTokens.fieldPassword") }  // "Your password"
        public static var formTitle: String { tr("apiTokens.formTitle") }  // "New API Token"
        public static var intro: String { tr("apiTokens.intro") }
        public static var issuedDone: String { tr("apiTokens.issuedDone") }  // "I've Copied It"
        public static var issuedIntro: String { tr("apiTokens.issuedIntro") }
        public static var issuedTitle: String { tr("apiTokens.issuedTitle") }  // "Copy your token"
        public static func lastUsed(_ a0: CVarArg) -> String { tr("apiTokens.lastUsed", a0) }
        public static func lastUsedFrom(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("apiTokens.lastUsedFrom", a0, a1) }
        public static func limitReached(_ a0: CVarArg) -> String { tr("apiTokens.limitReached", a0) }
        public static func menuAccessibilityLabel(_ a0: CVarArg) -> String { tr("apiTokens.menuAccessibilityLabel", a0) }
        public static var namePlaceholder: String { tr("apiTokens.namePlaceholder") }  // "For example, backup script"
        public static var navigationTitle: String { tr("apiTokens.navigationTitle") }  // "API Tokens"
        public static var neverExpires: String { tr("apiTokens.neverExpires") }  // "Never expires"
        public static var neverUsed: String { tr("apiTokens.neverUsed") }  // "Never used"
        public static var newButton: String { tr("apiTokens.newButton") }  // "New Token"
        public static var noPasswordWarning: String { tr("apiTokens.noPasswordWarning") }
        public static var passwordHint: String { tr("apiTokens.passwordHint") }  // "Enter your password to create a token."
        public static var renameAction: String { tr("apiTokens.renameAction") }  // "Rename"
        public static var renameSave: String { tr("apiTokens.renameSave") }  // "Save"
        public static var renameTitle: String { tr("apiTokens.renameTitle") }  // "Rename Token"
        public static var revokeAction: String { tr("apiTokens.revokeAction") }  // "Revoke"
        public static var revokeConfirm: String { tr("apiTokens.revokeConfirm") }  // "Revoke"
        public static func revokeMessage(_ a0: CVarArg) -> String { tr("apiTokens.revokeMessage", a0) }
        public static var revokeTitle: String { tr("apiTokens.revokeTitle") }  // "Revoke Token?"
        public static var scopeRead: String { tr("apiTokens.scopeRead") }  // "Read only"
        public static var scopeWrite: String { tr("apiTokens.scopeWrite") }  // "Read and write"
        public static var sectionHeader: String { tr("apiTokens.sectionHeader") }  // "Developers"
    }
    public enum Appearance {
        public static var dark: String { tr("appearance.dark") }  // "Dark"
        public static var light: String { tr("appearance.light") }  // "Light"
        public static var system: String { tr("appearance.system") }  // "System"
    }
    public enum Archive {
        public static var emptyFolder: String { tr("archive.emptyFolder") }  // "This folder is empty."
        public static var entryTooLarge: String { tr("archive.entryTooLarge") }  // "This item is too large to open."
        public static var openArchiveFailed: String { tr("archive.openArchiveFailed") }  // "Couldn't open this archive."
        public static var openFailed: String { tr("archive.openFailed") }  // "Couldn't open this file."
    }
    public enum Browse {
        public static var actionAddToFavorites: String { tr("browse.actionAddToFavorites") }  // "Add to Favorites"
        public static var actionAvailableOffline: String { tr("browse.actionAvailableOffline") }  // "Available Offline"
        public static var actionClearClipboard: String { tr("browse.actionClearClipboard") }  // "Clear clipboard"
        public static var actionCompress: String { tr("browse.actionCompress") }  // "Compress"
        public static var actionCopy: String { tr("browse.actionCopy") }  // "Copy"
        public static var actionCut: String { tr("browse.actionCut") }  // "Cut"
        public static var actionDelete: String { tr("browse.actionDelete") }  // "Delete"
        public static var actionDownload: String { tr("browse.actionDownload") }  // "Download"
        public static var actionDuplicate: String { tr("browse.actionDuplicate") }  // "Duplicate"
        public static var actionExtract: String { tr("browse.actionExtract") }  // "Extract"
        public static var actionGetInfo: String { tr("browse.actionGetInfo") }  // "Get Info"
        public static var actionMove: String { tr("browse.actionMove") }  // "Move"
        public static var actionNewFile: String { tr("browse.actionNewFile") }  // "Create File"
        public static var actionNewFolder: String { tr("browse.actionNewFolder") }  // "Create Folder"
        public static var actionOpenInBrowser: String { tr("browse.actionOpenInBrowser") }  // "Open in Browser"
        public static var actionOpenInNewTab: String { tr("browse.actionOpenInNewTab") }  // "Open in New Tab"
        public static var actionOpenInNewWindow: String { tr("browse.actionOpenInNewWindow") }  // "Open in New Window"
        public static var actionPaste: String { tr("browse.actionPaste") }  // "Paste"
        public static func actionPasteCount(_ a0: CVarArg) -> String { tr("browse.actionPasteCount", a0) }
        public static var actionPasteHere: String { tr("browse.actionPasteHere") }  // "Paste here"
        public static var actionPermissions: String { tr("browse.actionPermissions") }  // "Permissions"
        public static var actionRemoveFromFavorites: String { tr("browse.actionRemoveFromFavorites") }  // "Remove from Favorites"
        public static var actionRemoveFromOffline: String { tr("browse.actionRemoveFromOffline") }  // "Remove from Offline"
        public static var actionRename: String { tr("browse.actionRename") }  // "Rename"
        public static var actionSaveToDevice: String { tr("browse.actionSaveToDevice") }  // "Save to Device"
        public static var actionShare: String { tr("browse.actionShare") }  // "Create share link"
        public static var breadcrumbHint: String { tr("browse.breadcrumbHint") }  // "Opens this folder"
        public static func bulkFavoriteFailed(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.bulkFavoriteFailed", a0, a1) }
        public static func clipboardCopiedMany(_ a0: CVarArg) -> String { tr("browse.clipboardCopiedMany", a0) }
        public static func clipboardCopiedOne(_ a0: CVarArg) -> String { tr("browse.clipboardCopiedOne", a0) }
        public static func clipboardCopyCount(_ a0: CVarArg) -> String { tr("browse.clipboardCopyCount", a0) }
        public static func clipboardCutMany(_ a0: CVarArg) -> String { tr("browse.clipboardCutMany", a0) }
        public static func clipboardCutOne(_ a0: CVarArg) -> String { tr("browse.clipboardCutOne", a0) }
        public static func clipboardMoveCount(_ a0: CVarArg) -> String { tr("browse.clipboardMoveCount", a0) }
        public static func deleteConfirmMany(_ a0: CVarArg) -> String { tr("browse.deleteConfirmMany", a0) }
        public static func deleteConfirmOne(_ a0: CVarArg) -> String { tr("browse.deleteConfirmOne", a0) }
        public static var deleteConfirmTitle: String { tr("browse.deleteConfirmTitle") }  // "Delete?"
        public static func deleteLinkedSharesMany(_ a0: CVarArg) -> String { tr("browse.deleteLinkedSharesMany", a0) }
        public static var deleteLinkedSharesOne: String { tr("browse.deleteLinkedSharesOne") }  // "This also removes 1 share link that points here."
        public static var deleteLinkedSharesUnavailable: String { tr("browse.deleteLinkedSharesUnavailable") }
        public static var deleteMessage: String { tr("browse.deleteMessage") }  // "This can't be undone."
        public static var destinationPickerConfirmMove: String { tr("browse.destinationPickerConfirmMove") }  // "Move Here"
        public static var destinationPickerLoadFailed: String { tr("browse.destinationPickerLoadFailed") }  // "Couldn't load folders."
        public static var destinationPickerMoveTitle: String { tr("browse.destinationPickerMoveTitle") }  // "Move to…"
        public static var destinationPickerNoFolders: String { tr("browse.destinationPickerNoFolders") }  // "No folders here"
        public static var downloadBulkFailed: String { tr("browse.downloadBulkFailed") }  // "Couldn't save these items to your device."
        public static func downloadSavedAllTo(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.downloadSavedAllTo", a0, a1) }
        public static func downloadSavedCountTo(_ a0: CVarArg, _ a1: CVarArg, _ a2: CVarArg) -> String { tr("browse.downloadSavedCountTo", a0, a1, a2) }
        public static func downloadSavedTo(_ a0: CVarArg) -> String { tr("browse.downloadSavedTo", a0) }
        public static var locations: String { tr("browse.locations") }  // "Locations"
        public static var myFiles: String { tr("browse.myFiles") }  // "My Files"
        public static var myFilesSubtitle: String { tr("browse.myFilesSubtitle") }  // "Only visible to you"
        public static var nameErrorReserved: String { tr("browse.nameErrorReserved") }  // "That name isn't allowed."
        public static var nameErrorSeparators: String { tr("browse.nameErrorSeparators") }  // "A name can't contain / or \."
        public static var navigationTitle: String { tr("browse.navigationTitle") }  // "Browse"
        public static var newFilePlaceholder: String { tr("browse.newFilePlaceholder") }  // "notes.txt"
        public static var newFileTitle: String { tr("browse.newFileTitle") }  // "New File"
        public static var newFileTypeHint: String { tr("browse.newFileTypeHint") }
        public static var newFolderConfirm: String { tr("browse.newFolderConfirm") }  // "Create"
        public static var newFolderPlaceholder: String { tr("browse.newFolderPlaceholder") }  // "Folder name"
        public static var newFolderTitle: String { tr("browse.newFolderTitle") }  // "New Folder"
        public static func offlineBannerDetail(_ a0: CVarArg) -> String { tr("browse.offlineBannerDetail", a0) }
        public static var offlineBannerTitle: String { tr("browse.offlineBannerTitle") }  // "Offline"
        public static var open: String { tr("browse.open") }  // "Open"
        public static var progressCompressing: String { tr("browse.progressCompressing") }  // "Compressing…"
        public static var progressCopying: String { tr("browse.progressCopying") }  // "Copying…"
        public static var progressDownloading: String { tr("browse.progressDownloading") }  // "Downloading…"
        public static func progressDownloadingIndexed(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.progressDownloadingIndexed", a0, a1) }
        public static var progressExtracting: String { tr("browse.progressExtracting") }  // "Extracting…"
        public static var progressMoving: String { tr("browse.progressMoving") }  // "Moving…"
        public static var quickLookTooLarge: String { tr("browse.quickLookTooLarge") }  // "This file is too large for Quick Look."
        public static var quickLookUnavailable: String { tr("browse.quickLookUnavailable") }  // "Quick Look isn't available for this file type."
        public static var renameNamePlaceholder: String { tr("browse.renameNamePlaceholder") }  // "Name"
        public static var renameTitle: String { tr("browse.renameTitle") }  // "Rename"
        public static var scopeEverywhere: String { tr("browse.scopeEverywhere") }  // "Everywhere"
        public static var scopeThisFolder: String { tr("browse.scopeThisFolder") }  // "This Folder"
        public static var searchEverywhere: String { tr("browse.searchEverywhere") }  // "Search everywhere"
        public static var searchFailed: String { tr("browse.searchFailed") }  // "Couldn't search. Check your connection and try again."
        public static func searchFirstOnly(_ a0: CVarArg) -> String { tr("browse.searchFirstOnly", a0) }
        public static var searchMatchColumn: String { tr("browse.searchMatchColumn") }  // "Match"
        public static func searchMatchLine(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.searchMatchLine", a0, a1) }
        public static func searchMatchLineLabel(_ a0: CVarArg) -> String { tr("browse.searchMatchLineLabel", a0) }
        public static var searchMatchedByBoth: String { tr("browse.searchMatchedByBoth") }  // "Name and Contents"
        public static var searchMatchedByContent: String { tr("browse.searchMatchedByContent") }  // "Contents"
        public static var searchMatchedByName: String { tr("browse.searchMatchedByName") }  // "Name"
        public static func searchNoMatchesInFolder(_ a0: CVarArg) -> String { tr("browse.searchNoMatchesInFolder", a0) }
        public static var searchScopeEverywhere: String { tr("browse.searchScopeEverywhere") }  // "Everywhere"
        public static var searchScopeInFolder: String { tr("browse.searchScopeInFolder") }  // "This Folder"
        public static var searchShowMore: String { tr("browse.searchShowMore") }  // "Show More"
        public static var searchStoppedEarly: String { tr("browse.searchStoppedEarly") }
        public static func searchTooShort(_ a0: CVarArg) -> String { tr("browse.searchTooShort", a0) }
        public static var sectionPersonal: String { tr("browse.sectionPersonal") }  // "Personal"
        public static var showInEnclosingFolder: String { tr("browse.showInEnclosingFolder") }  // "Show in Enclosing Folder"
        public static var showInFinder: String { tr("browse.showInFinder") }  // "Show in Finder"
        public static var transferConflictKeepBoth: String { tr("browse.transferConflictKeepBoth") }  // "Keep Both"
        public static func transferConflictMessageMany(_ a0: CVarArg) -> String { tr("browse.transferConflictMessageMany", a0) }
        public static func transferConflictMessageOne(_ a0: CVarArg) -> String { tr("browse.transferConflictMessageOne", a0) }
        public static var transferConflictReplace: String { tr("browse.transferConflictReplace") }  // "Replace"
        public static var transferConflictTitle: String { tr("browse.transferConflictTitle") }  // "Replace items?"
        public static func transferCopied(_ a0: CVarArg) -> String { tr("browse.transferCopied", a0) }
        public static func transferCopiedWithSkipped(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.transferCopiedWithSkipped", a0, a1) }
        public static func transferMoved(_ a0: CVarArg) -> String { tr("browse.transferMoved", a0) }
        public static func transferMovedWithSkipped(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.transferMovedWithSkipped", a0, a1) }
        public static var unsupportedFileType: String { tr("browse.unsupportedFileType") }  // "Unsupported file type"
    }
    public enum ChangePassword {
        public static var addIntro: String { tr("changePassword.addIntro") }
        public static var addNavigationTitle: String { tr("changePassword.addNavigationTitle") }  // "Add Password"
        public static var addSubmitButton: String { tr("changePassword.addSubmitButton") }  // "Add Password"
        public static func errorMinLength(_ a0: CVarArg) -> String { tr("changePassword.errorMinLength", a0) }
        public static var errorMismatch: String { tr("changePassword.errorMismatch") }  // "Passwords don't match."
        public static var fieldConfirmPassword: String { tr("changePassword.fieldConfirmPassword") }  // "Re-enter new password"
        public static var fieldConfirmPasswordLabel: String { tr("changePassword.fieldConfirmPasswordLabel") }  // "Confirm New Password"
        public static var fieldCurrentPassword: String { tr("changePassword.fieldCurrentPassword") }  // "Current Password"
        public static var fieldNewPasswordLabel: String { tr("changePassword.fieldNewPasswordLabel") }  // "New Password"
        public static func fieldNewPasswordPrompt(_ a0: CVarArg) -> String { tr("changePassword.fieldNewPasswordPrompt", a0) }
        public static var intro: String { tr("changePassword.intro") }
        public static var navigationTitle: String { tr("changePassword.navigationTitle") }  // "Change Password"
        public static var submitButton: String { tr("changePassword.submitButton") }  // "Update Password"
        public static var success: String { tr("changePassword.success") }  // "Your password has been updated."
    }
    public enum ClientCertificate {
        public static var certificateLabel: String { tr("clientCertificate.certificateLabel") }  // "Certificate"
        public static var chooseAnother: String { tr("clientCertificate.chooseAnother") }  // "Choose Another File"
        public static var chooseFile: String { tr("clientCertificate.chooseFile") }  // "Choose File"
        public static var errorInvalidFile: String { tr("clientCertificate.errorInvalidFile") }  // "This isn't a valid .p12 or .pfx certificate file."
        public static var errorNoIdentity: String { tr("clientCertificate.errorNoIdentity") }
        public static var errorRemove: String { tr("clientCertificate.errorRemove") }  // "Couldn't remove the certificate from this device."
        public static var errorStorage: String { tr("clientCertificate.errorStorage") }  // "Couldn't save the certificate on this device."
        public static var errorUnreadable: String { tr("clientCertificate.errorUnreadable") }  // "Couldn't read that file."
        public static var errorWrongPassword: String { tr("clientCertificate.errorWrongPassword") }  // "That password doesn't unlock this file."
        public static func expired(_ a0: CVarArg) -> String { tr("clientCertificate.expired", a0) }
        public static var expiredWarning: String { tr("clientCertificate.expiredWarning") }
        public static func expires(_ a0: CVarArg) -> String { tr("clientCertificate.expires", a0) }
        public static func expiringSoonWarning(_ a0: CVarArg) -> String { tr("clientCertificate.expiringSoonWarning", a0) }
        public static var fileLabel: String { tr("clientCertificate.fileLabel") }  // "File"
        public static var install: String { tr("clientCertificate.install") }  // "Install"
        public static var intro: String { tr("clientCertificate.intro") }
        public static func issuedBy(_ a0: CVarArg) -> String { tr("clientCertificate.issuedBy", a0) }
        public static var none: String { tr("clientCertificate.none") }  // "No certificate installed"
        public static var passwordLabel: String { tr("clientCertificate.passwordLabel") }  // "File Password"
        public static var passwordPrompt: String { tr("clientCertificate.passwordPrompt") }  // "The password the file was exported with"
        public static var remove: String { tr("clientCertificate.remove") }  // "Remove Certificate"
        public static var removeConfirm: String { tr("clientCertificate.removeConfirm") }  // "Remove"
        public static func removeMessage(_ a0: CVarArg) -> String { tr("clientCertificate.removeMessage", a0) }
        public static var removeTitle: String { tr("clientCertificate.removeTitle") }  // "Remove certificate?"
        public static var replace: String { tr("clientCertificate.replace") }  // "Replace Certificate"
        public static var serverLabel: String { tr("clientCertificate.serverLabel") }  // "Server"
        public static var title: String { tr("clientCertificate.title") }  // "Client Certificate"
    }
    public enum Common {
        public static var back: String { tr("common.back") }  // "Back"
        public static var cancel: String { tr("common.cancel") }  // "Cancel"
        public static var change: String { tr("common.change") }  // "Change"
        public static var clear: String { tr("common.clear") }  // "Clear"
        public static var close: String { tr("common.close") }  // "Close"
        public static var copied: String { tr("common.copied") }  // "Copied"
        public static var copy: String { tr("common.copy") }  // "Copy"
        public static var delete: String { tr("common.delete") }  // "Delete"
        public static var deselect: String { tr("common.deselect") }  // "Deselect"
        public static var done: String { tr("common.done") }  // "Done"
        public static var download: String { tr("common.download") }  // "Download"
        public static var edit: String { tr("common.edit") }  // "Edit"
        public static var loading: String { tr("common.loading") }  // "Loading…"
        public static var logOut: String { tr("common.logOut") }  // "Log Out"
        public static var more: String { tr("common.more") }  // "More"
        public static var never: String { tr("common.never") }  // "Never"
        public static var ok: String { tr("common.ok") }  // "OK"
        public static var openSettings: String { tr("common.openSettings") }  // "Open Settings"
        public static var password: String { tr("common.password") }  // "Password"
        public static var remove: String { tr("common.remove") }  // "Remove"
        public static var retry: String { tr("common.retry") }  // "Try Again"
        public static var save: String { tr("common.save") }  // "Save"
        public static var search: String { tr("common.search") }  // "Search"
        public static var select: String { tr("common.select") }  // "Select"
        public static func selectedCount(_ a0: CVarArg) -> String { tr("common.selectedCount", a0) }
        public static var share: String { tr("common.share") }  // "Share"
        public static var sort: String { tr("common.sort") }  // "Sort"
        public static var syncCompleted: String { tr("common.syncCompleted") }  // "Sync completed"
    }
    public enum CreateShare {
        public static var createdBanner: String { tr("createShare.createdBanner") }  // "Share link created successfully!"
        public static var directFileLink: String { tr("createShare.directFileLink") }  // "Direct file link"
        public static var directFolderLink: String { tr("createShare.directFolderLink") }  // "Direct folder ZIP link"
        public static var directLinkMode: String { tr("createShare.directLinkMode") }  // "Direct link mode"
        public static var errorPasswordRequired: String { tr("createShare.errorPasswordRequired") }  // "Enter a password or turn off password protection."
        public static var errorPastExpiration: String { tr("createShare.errorPastExpiration") }  // "Pick an expiration date in the future."
        public static var fieldExpires: String { tr("createShare.fieldExpires") }  // "Expires"
        public static var fieldPassword: String { tr("createShare.fieldPassword") }  // "Password"
        public static var loadingUsers: String { tr("createShare.loadingUsers") }  // "Loading users…"
        public static var noOtherUsers: String { tr("createShare.noOtherUsers") }  // "No other users to share with."
        public static var sectionAccessMode: String { tr("createShare.sectionAccessMode") }  // "Access Mode"
        public static var sectionLabel: String { tr("createShare.sectionLabel") }  // "Label"
        public static var sectionShareLink: String { tr("createShare.sectionShareLink") }  // "Share Link"
        public static var sectionWhoCanAccess: String { tr("createShare.sectionWhoCanAccess") }  // "Who can access"
        public static var sharingPrefix: String { tr("createShare.sharingPrefix") }  // "Sharing:"
        public static var submit: String { tr("createShare.submit") }  // "Create Share Link"
        public static var summaryAccess: String { tr("createShare.summaryAccess") }  // "Access"
        public static var summaryExpires: String { tr("createShare.summaryExpires") }  // "Expires"
        public static var summaryPassword: String { tr("createShare.summaryPassword") }  // "Password"
        public static var summaryPasswordProtected: String { tr("createShare.summaryPasswordProtected") }  // "Protected"
        public static var summarySharedWith: String { tr("createShare.summarySharedWith") }  // "Shared with"
        public static var summarySpecificPeople: String { tr("createShare.summarySpecificPeople") }  // "Specific people"
        public static var title: String { tr("createShare.title") }  // "Create Share Link"
        public static var titleCreated: String { tr("createShare.titleCreated") }  // "Share Created"
        public static var togglePasswordProtect: String { tr("createShare.togglePasswordProtect") }  // "Password protect"
        public static var toggleSetExpiration: String { tr("createShare.toggleSetExpiration") }  // "Set expiration date"
        public static var viewInShared: String { tr("createShare.viewInShared") }  // "View in Shared"
    }
    public enum DateFormat {
        public static var automatic: String { tr("dateFormat.automatic") }  // "Automatic"
    }
    public enum DirectLinkMode {
        public static var auto: String { tr("directLinkMode.auto") }  // "Auto"
        public static var download: String { tr("directLinkMode.download") }  // "Download"
        public static var inline: String { tr("directLinkMode.inline") }  // "View"
        public static var raw: String { tr("directLinkMode.raw") }  // "Raw"
    }
    public enum DownloadQueue {
        public static func barFailedMany(_ a0: CVarArg) -> String { tr("downloadQueue.barFailedMany", a0) }
        public static var barFailedOne: String { tr("downloadQueue.barFailedOne") }  // "1 download failed"
        public static func barTitleMany(_ a0: CVarArg) -> String { tr("downloadQueue.barTitleMany", a0) }
        public static func barTitleOne(_ a0: CVarArg) -> String { tr("downloadQueue.barTitleOne", a0) }
        public static func bytesOf(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("downloadQueue.bytesOf", a0, a1) }
        public static var cancelAll: String { tr("downloadQueue.cancelAll") }  // "Cancel all downloads"
        public static var emptyList: String { tr("downloadQueue.emptyList") }  // "No downloads in progress."
        public static var navigationTitle: String { tr("downloadQueue.navigationTitle") }  // "Download Queue"
        public static var notifyDone: String { tr("downloadQueue.notifyDone") }  // "Downloads finished"
        public static var photosAccessDenied: String { tr("downloadQueue.photosAccessDenied") }  // "Allow Photos access in Settings to save pictures and videos."
        public static var photosSaveFailed: String { tr("downloadQueue.photosSaveFailed") }  // "Couldn't add this to Photos."
        public static func savedMany(_ a0: CVarArg) -> String { tr("downloadQueue.savedMany", a0) }
        public static var savedOne: String { tr("downloadQueue.savedOne") }  // "Saved to Downloads"
        public static var savedToDevice: String { tr("downloadQueue.savedToDevice") }  // "Saved to your device"
        public static var savedToPhotos: String { tr("downloadQueue.savedToPhotos") }  // "Saved to Photos"
        public static var statusSaved: String { tr("downloadQueue.statusSaved") }  // "Saved"
        public static func timeLeft(_ a0: CVarArg) -> String { tr("downloadQueue.timeLeft", a0) }
    }
    public enum Downloads {
        public static var actionOpenInFiles: String { tr("downloads.actionOpenInFiles") }  // "Open in Files"
        public static var deleteBulkMessage: String { tr("downloads.deleteBulkMessage") }
        public static func deleteConfirmMany(_ a0: CVarArg) -> String { tr("downloads.deleteConfirmMany", a0) }
        public static func deleteConfirmOne(_ a0: CVarArg) -> String { tr("downloads.deleteConfirmOne", a0) }
        public static var deleteConfirmTitle: String { tr("downloads.deleteConfirmTitle") }  // "Delete?"
        public static var deleteSingleMessage: String { tr("downloads.deleteSingleMessage") }
        public static var emptyList: String { tr("downloads.emptyList") }  // "Files you download from Browse show up here."
        public static var errorGeneric: String { tr("downloads.errorGeneric") }  // "Couldn't complete that action."
        public static var errorInvalidName: String { tr("downloads.errorInvalidName") }  // "That name isn't allowed."
        public static var errorMissing: String { tr("downloads.errorMissing") }  // "That file could no longer be found."
        public static var errorNameExists: String { tr("downloads.errorNameExists") }  // "A file with that name already exists."
    }
    public enum EditShare {
        public static var passwordKeepHint: String { tr("editShare.passwordKeepHint") }  // "Leave blank to keep the current password"
        public static var save: String { tr("editShare.save") }  // "Save Changes"
        public static var savedToast: String { tr("editShare.savedToast") }  // "Share link updated"
        public static var title: String { tr("editShare.title") }  // "Edit Share Link"
    }
    public enum EmptyState {
        public static var folderEmpty: String { tr("emptyState.folderEmpty") }  // "This folder is empty."
        public static var loadFailed: String { tr("emptyState.loadFailed") }  // "Couldn't reach the server."
        public static func noSearchMatches(_ a0: CVarArg) -> String { tr("emptyState.noSearchMatches", a0) }
    }
    public enum Error {
        public static var changedOnServer: String { tr("error.changedOnServer") }  // "This file was changed on the server after you opened it."
        public static var clientCertificateRejected: String { tr("error.clientCertificateRejected") }  // "The server refused your client certificate."
        public static var clientCertificateRequired: String { tr("error.clientCertificateRequired") }  // "This server needs a client certificate. Add one in Settings."
        public static var decoding: String { tr("error.decoding") }  // "Server responded unexpectedly."
        public static var forbidden: String { tr("error.forbidden") }  // "You don't have permission to do that."
        public static var network: String { tr("error.network") }  // "Couldn't reach the server."
        public static var offline: String { tr("error.offline") }  // "You're offline. Connect to the internet and try again."
        public static var rateLimited: String { tr("error.rateLimited") }  // "Too many requests. Try again shortly."
        public static func server(_ a0: CVarArg) -> String { tr("error.server", a0) }
        public static var sessionExpired: String { tr("error.sessionExpired") }  // "Your session expired. Sign in again."
        public static var timedOut: String { tr("error.timedOut") }
    }
    public enum Favorites {
        public static var accessibilityBadge: String { tr("favorites.accessibilityBadge") }  // "Favorite"
        public static var actionEdit: String { tr("favorites.actionEdit") }  // "Edit"
        public static var actionRemoveFromFavorites: String { tr("favorites.actionRemoveFromFavorites") }  // "Remove from Favorites"
        public static var editColorDefault: String { tr("favorites.editColorDefault") }  // "Default"
        public static var editColorLabel: String { tr("favorites.editColorLabel") }  // "Color"
        public static var editIconLabel: String { tr("favorites.editIconLabel") }  // "Icon"
        public static var editIconOutline: String { tr("favorites.editIconOutline") }  // "Outline"
        public static var editIconSolid: String { tr("favorites.editIconSolid") }  // "Solid"
        public static var editNameErrorEmpty: String { tr("favorites.editNameErrorEmpty") }  // "Name can't be empty."
        public static var editNameLabel: String { tr("favorites.editNameLabel") }  // "Name"
        public static var editSave: String { tr("favorites.editSave") }  // "Save"
        public static var editTitle: String { tr("favorites.editTitle") }  // "Edit Favorite"
        public static var emptyList: String { tr("favorites.emptyList") }  // "Star folders in Browse to see them here."
        public static var navigationTitle: String { tr("favorites.navigationTitle") }  // "Favorites"
        public static func removeConfirm(_ a0: CVarArg) -> String { tr("favorites.removeConfirm", a0) }
        public static var removeFailedMany: String { tr("favorites.removeFailedMany") }  // "Couldn't remove those favorites."
        public static var removeFailedOne: String { tr("favorites.removeFailedOne") }  // "Couldn't remove that favorite."
        public static var removeMessage: String { tr("favorites.removeMessage") }  // "This only removes them from Favorites."
        public static func removePartial(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("favorites.removePartial", a0, a1) }
        public static var reorderFailed: String { tr("favorites.reorderFailed") }  // "Couldn't save the new order."
    }
    public enum FfmpegSettings {
        public static var containerPathHelp: String { tr("ffmpegSettings.containerPathHelp") }
        public static var defaultHelp: String { tr("ffmpegSettings.defaultHelp") }
        public static var ffmpegPath: String { tr("ffmpegSettings.ffmpegPath") }  // "FFmpeg executable path"
        public static var ffmpegPlaceholder: String { tr("ffmpegSettings.ffmpegPlaceholder") }  // "/usr/local/bin/ffmpeg"
        public static var ffprobePath: String { tr("ffmpegSettings.ffprobePath") }  // "FFprobe executable path"
        public static var ffprobePlaceholder: String { tr("ffmpegSettings.ffprobePlaceholder") }  // "/usr/local/bin/ffprobe"
        public static var invalid: String { tr("ffmpegSettings.invalid") }
        public static var navigationTitle: String { tr("ffmpegSettings.navigationTitle") }  // "FFmpeg"
        public static var saveButton: String { tr("ffmpegSettings.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("ffmpegSettings.subtitle") }
        public static var unavailable: String { tr("ffmpegSettings.unavailable") }  // "FFmpeg settings are only available to administrators."
    }
    public enum FileInfo {
        public static var deleteAll: String { tr("fileInfo.deleteAll") }  // "Delete All Versions…"
        public static var deleteAllTitle: String { tr("fileInfo.deleteAllTitle") }  // "Delete all versions?"
        public static var deleteMessage: String { tr("fileInfo.deleteMessage") }
        public static var deleteTitle: String { tr("fileInfo.deleteTitle") }  // "Delete this version?"
        public static func diskFreeOf(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("fileInfo.diskFreeOf", a0, a1) }
        public static var navigationTitleFolder: String { tr("fileInfo.navigationTitleFolder") }  // "Folder"
        public static var notShared: String { tr("fileInfo.notShared") }  // "No share links"
        public static var partialScan: String { tr("fileInfo.partialScan") }  // "Counted a partial scan: this folder is very large."
        public static var renamePlaceholder: String { tr("fileInfo.renamePlaceholder") }  // "Version name"
        public static var renameTitle: String { tr("fileInfo.renameTitle") }  // "Rename Version"
        public static var restoreConfirm: String { tr("fileInfo.restoreConfirm") }  // "Restore"
        public static func restoreMessage(_ a0: CVarArg) -> String { tr("fileInfo.restoreMessage", a0) }
        public static var restoreTitle: String { tr("fileInfo.restoreTitle") }  // "Restore this version?"
        public static var rowCamera: String { tr("fileInfo.rowCamera") }  // "Camera"
        public static var rowDateCreated: String { tr("fileInfo.rowDateCreated") }  // "Date Created"
        public static var rowDateModified: String { tr("fileInfo.rowDateModified") }  // "Date Modified"
        public static var rowDateTaken: String { tr("fileInfo.rowDateTaken") }  // "Date Taken"
        public static var rowDimensions: String { tr("fileInfo.rowDimensions") }  // "Dimensions"
        public static var rowDuration: String { tr("fileInfo.rowDuration") }  // "Duration"
        public static var rowFiles: String { tr("fileInfo.rowFiles") }  // "Files"
        public static var rowFolders: String { tr("fileInfo.rowFolders") }  // "Folders"
        public static var rowKind: String { tr("fileInfo.rowKind") }  // "Kind"
        public static var rowLens: String { tr("fileInfo.rowLens") }  // "Lens"
        public static var rowLocation: String { tr("fileInfo.rowLocation") }  // "Location"
        public static var rowSize: String { tr("fileInfo.rowSize") }  // "Size"
        public static var rowSoftware: String { tr("fileInfo.rowSoftware") }  // "Software"
        public static var rowTotalSize: String { tr("fileInfo.rowTotalSize") }  // "Total Size"
        public static var sectionServerDisk: String { tr("fileInfo.sectionServerDisk") }  // "Server Disk"
        public static var sectionSharing: String { tr("fileInfo.sectionSharing") }  // "Sharing"
        public static var sectionVersions: String { tr("fileInfo.sectionVersions") }  // "Versions"
        public static var versionActions: String { tr("fileInfo.versionActions") }  // "Version actions"
        public static var versionDelete: String { tr("fileInfo.versionDelete") }  // "Delete…"
        public static var versionDownload: String { tr("fileInfo.versionDownload") }  // "Download…"
        public static var versionKept: String { tr("fileInfo.versionKept") }  // "Kept"
        public static var versionPin: String { tr("fileInfo.versionPin") }  // "Keep This Version"
        public static var versionRename: String { tr("fileInfo.versionRename") }  // "Rename…"
        public static var versionRestore: String { tr("fileInfo.versionRestore") }  // "Restore…"
        public static var versionSaveCopy: String { tr("fileInfo.versionSaveCopy") }  // "Save as Copy"
        public static var versionUnpin: String { tr("fileInfo.versionUnpin") }  // "Stop Keeping This Version"
        public static var versionsNone: String { tr("fileInfo.versionsNone") }  // "No earlier versions"
    }
    public enum Filter {
        public static var all: String { tr("filter.all") }  // "All Types"
        public static var archives: String { tr("filter.archives") }  // "Archives"
        public static var audio: String { tr("filter.audio") }  // "Audio"
        public static var button: String { tr("filter.button") }  // "Filter"
        public static var documents: String { tr("filter.documents") }  // "Documents"
        public static var folders: String { tr("filter.folders") }  // "Folders"
        public static var images: String { tr("filter.images") }  // "Images"
        public static var other: String { tr("filter.other") }  // "Other"
        public static var sheetTitle: String { tr("filter.sheetTitle") }  // "Filter by Type"
        public static var videos: String { tr("filter.videos") }  // "Videos"
    }
    public enum FolderSizeSettings {
        public static var addButton: String { tr("folderSizeSettings.addButton") }  // "Add"
        public static var additional: String { tr("folderSizeSettings.additional") }  // "Additional exclusions"
        public static var discardButton: String { tr("folderSizeSettings.discardButton") }  // "Discard"
        public static var environment: String { tr("folderSizeSettings.environment") }  // "Environment-defined exclusions"
        public static func locked(_ a0: CVarArg) -> String { tr("folderSizeSettings.locked", a0) }
        public static var modeFull: String { tr("folderSizeSettings.modeFull") }  // "Everything inside them"
        public static var modeOff: String { tr("folderSizeSettings.modeOff") }  // "Off"
        public static var modeShallow: String { tr("folderSizeSettings.modeShallow") }  // "Their own files only"
        public static var navigationTitle: String { tr("folderSizeSettings.navigationTitle") }  // "Folder Sizes"
        public static var none: String { tr("folderSizeSettings.none") }  // "No paths configured"
        public static var placeholder: String { tr("folderSizeSettings.placeholder") }  // "Stacks/docker/overlay2"
        public static var running: String { tr("folderSizeSettings.running") }  // "Measure folder sizes"
        public static var runningHelp: String { tr("folderSizeSettings.runningHelp") }
        public static var saveButton: String { tr("folderSizeSettings.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("folderSizeSettings.subtitle") }  // "Exclude paths from folder size calculation and indexing."
        public static var unavailable: String { tr("folderSizeSettings.unavailable") }  // "Folder size settings are only available to administrators."
    }
    public enum Gallery {
        public static var loadFailed: String { tr("gallery.loadFailed") }  // "Couldn't load this image."
    }
    public enum Language {
        public static var navigationTitle: String { tr("language.navigationTitle") }  // "Language"
        public static var systemDefault: String { tr("language.systemDefault") }  // "System Default"
        public static var systemDefaultSubtitle: String { tr("language.systemDefaultSubtitle") }  // "Follow your device language"
    }
    public enum Licenses {
        public static var labelAuthor: String { tr("licenses.labelAuthor") }  // "Author"
        public static var labelModifiedVersion: String { tr("licenses.labelModifiedVersion") }  // "Modified Version"
        public static var labelOriginalVersion: String { tr("licenses.labelOriginalVersion") }  // "Original Version"
        public static var labelReservedFontName: String { tr("licenses.labelReservedFontName") }  // "Reserved Font Name"
        public static var navigationTitle: String { tr("licenses.navigationTitle") }  // "Open Source Licenses"
        public static var sectionFontSoftware: String { tr("licenses.sectionFontSoftware") }  // "Font Software"
        public static var sectionSoftware: String { tr("licenses.sectionSoftware") }  // "Software"
    }
    public enum Login {
        public static var addClientCertificate: String { tr("login.addClientCertificate") }  // "Add Certificate"
        public static var changeClientCertificate: String { tr("login.changeClientCertificate") }  // "Change"
        public static var codeField: String { tr("login.codeField") }  // "Code"
        public static var codeIntroAuthenticator: String { tr("login.codeIntroAuthenticator") }
        public static var codeIntroRecovery: String { tr("login.codeIntroRecovery") }  // "Enter one of your recovery codes. Each one works only once."
        public static var codeSubmit: String { tr("login.codeSubmit") }  // "Verify"
        public static var codeTitle: String { tr("login.codeTitle") }  // "Enter your code"
        public static var codeUseAuthenticator: String { tr("login.codeUseAuthenticator") }  // "Use the authenticator code instead"
        public static var codeUseRecovery: String { tr("login.codeUseRecovery") }  // "Use a recovery code instead"
        public static var diagnosticsButton: String { tr("login.diagnosticsButton") }  // "Share sign in log"
        public static var diagnosticsIntro: String { tr("login.diagnosticsIntro") }
        public static var diagnosticsTitle: String { tr("login.diagnosticsTitle") }  // "Sign in log"
        public static var errorClientCertificateRejected: String { tr("login.errorClientCertificateRejected") }  // "The server refused this client certificate."
        public static var errorClientCertificateRequired: String { tr("login.errorClientCertificateRequired") }  // "This server asks for a client certificate."
        public static var errorDecoding: String { tr("login.errorDecoding") }
        public static var errorIncomplete: String { tr("login.errorIncomplete") }  // "Sign-in didn't complete. Please try again."
        public static var errorInvalidCode: String { tr("login.errorInvalidCode") }  // "That code is not right."
        public static var errorInvalidCredentials: String { tr("login.errorInvalidCredentials") }  // "Incorrect username or password."
        public static var errorInvalidServer: String { tr("login.errorInvalidServer") }  // "Enter a valid server address."
        public static var errorKeychain: String { tr("login.errorKeychain") }  // "Could not save your session on this device."
        public static var errorNoAuthMethods: String { tr("login.errorNoAuthMethods") }  // "This server has no sign-in methods enabled."
        public static var errorNoLocalAuth: String { tr("login.errorNoLocalAuth") }  // "This server doesn't have username/password sign-in enabled."
        public static var errorRateLimited: String { tr("login.errorRateLimited") }  // "Too many attempts. Please wait a few minutes and try again."
        public static var errorSecondFactorExpired: String { tr("login.errorSecondFactorExpired") }  // "That sign in expired. Enter your password again."
        public static func errorServer(_ a0: CVarArg) -> String { tr("login.errorServer", a0) }
        public static var errorSessionExpired: String { tr("login.errorSessionExpired") }  // "Your session expired. Please sign in again."
        public static var errorSso: String { tr("login.errorSso") }  // "Single sign-on didn't complete. Please try again."
        public static var errorUnexpectedResponse: String { tr("login.errorUnexpectedResponse") }  // "Unexpected response from server."
        public static var errorUnreachable: String { tr("login.errorUnreachable") }
        public static var hidePassword: String { tr("login.hidePassword") }  // "Hide Password"
        public static var identifierField: String { tr("login.identifierField") }  // "Email or username"
        public static var manageClientCertificate: String { tr("login.manageClientCertificate") }  // "Manage Certificate"
        public static var orDivider: String { tr("login.orDivider") }  // "or"
        public static var passwordField: String { tr("login.passwordField") }  // "Password"
        public static var plaintextWarning: String { tr("login.plaintextWarning") }
        public static var portHint: String { tr("login.portHint") }
        public static var serverInfoAccessibility: String { tr("login.serverInfoAccessibility") }  // "About connecting to a server"
        public static var serverInfoBody: String { tr("login.serverInfoBody") }
        public static var serverInfoGuide: String { tr("login.serverInfoGuide") }  // "Open setup guide"
        public static var serverInfoTitle: String { tr("login.serverInfoTitle") }  // "What is a server?"
        public static var serverQuestion: String { tr("login.serverQuestion") }  // "Where's your instance of NextExplorer?"
        public static var showPassword: String { tr("login.showPassword") }  // "Show Password"
        public static var ssoButton: String { tr("login.ssoButton") }  // "Sign in with SSO"
        public static var ssoClientCertificateNote: String { tr("login.ssoClientCertificateNote") }
        public static var submit: String { tr("login.submit") }  // "Log In"
        public static var testConnection: String { tr("login.testConnection") }  // "Test connection"
        public static func usingClientCertificate(_ a0: CVarArg) -> String { tr("login.usingClientCertificate", a0) }
    }
    public enum MacSettings {
        public static var addAccount: String { tr("macSettings.addAccount") }  // "Add Account…"
        public static var cache: String { tr("macSettings.cache") }  // "Cache"
        public static var changePassword: String { tr("macSettings.changePassword") }  // "Change Password…"
        public static var choose: String { tr("macSettings.choose") }  // "Choose…"
        public static var email: String { tr("macSettings.email") }  // "Email"
        public static var icon: String { tr("macSettings.icon") }  // "Icon"
        public static func labelFormat(_ a0: CVarArg) -> String { tr("macSettings.labelFormat", a0) }
        public static var manage: String { tr("macSettings.manage") }  // "Manage…"
        public static var permission: String { tr("macSettings.permission") }  // "Permission"
        public static var role: String { tr("macSettings.role") }  // "Role"
        public static var roleAdmin: String { tr("macSettings.roleAdmin") }  // "Administrator"
        public static var roleUser: String { tr("macSettings.roleUser") }  // "User"
        public static var signOut: String { tr("macSettings.signOut") }  // "Sign Out…"
        public static var status: String { tr("macSettings.status") }  // "Status"
        public static var statusSignedIn: String { tr("macSettings.statusSignedIn") }  // "Signed In"
        public static var support: String { tr("macSettings.support") }  // "Help & Support…"
        public static var switchAccount: String { tr("macSettings.switchAccount") }  // "Switch to This Account"
        public static var username: String { tr("macSettings.username") }  // "Username"
    }
    public enum Media {
        public static var clientCertificateUnsupported: String { tr("media.clientCertificateUnsupported") }
        public static var pause: String { tr("media.pause") }  // "Pause"
        public static var play: String { tr("media.play") }  // "Play"
        public static var position: String { tr("media.position") }  // "Playback Position"
        public static func positionValue(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("media.positionValue", a0, a1) }
    }
    public enum Menu {
        public static var about: String { tr("menu.about") }  // "About NextExplorer"
        public static var activity: String { tr("menu.activity") }  // "Transfers"
        public static var clearRecent: String { tr("menu.clearRecent") }  // "Clear Menu"
        public static var copyPath: String { tr("menu.copyPath") }  // "Copy Path"
        public static var enclosingFolder: String { tr("menu.enclosingFolder") }  // "Enclosing Folder"
        public static var forward: String { tr("menu.forward") }  // "Forward"
        public static var go: String { tr("menu.go") }  // "Go"
        public static var goToFolder: String { tr("menu.goToFolder") }  // "Go to Folder…"
        public static var goToFolderTitle: String { tr("menu.goToFolderTitle") }  // "Go to the folder:"
        public static var newTab: String { tr("menu.newTab") }  // "New Tab"
        public static var newWindow: String { tr("menu.newWindow") }  // "New Window"
        public static var quitTransfersConfirm: String { tr("menu.quitTransfersConfirm") }  // "Quit"
        public static var quitTransfersMessage: String { tr("menu.quitTransfersMessage") }
        public static var quitTransfersTitle: String { tr("menu.quitTransfersTitle") }  // "Quit NextExplorer?"
        public static var rateApp: String { tr("menu.rateApp") }  // "Rate NextExplorer…"
        public static var recentFolders: String { tr("menu.recentFolders") }  // "Recent Folders"
        public static var redo: String { tr("menu.redo") }  // "Redo"
        public static var refresh: String { tr("menu.refresh") }  // "Refresh"
        public static var showAll: String { tr("menu.showAll") }  // "Show All"
        public static var support: String { tr("menu.support") }  // "NextExplorer Support"
        public static var undo: String { tr("menu.undo") }  // "Undo"
        public static var zoomIn: String { tr("menu.zoomIn") }  // "Zoom In"
        public static var zoomOut: String { tr("menu.zoomOut") }  // "Zoom Out"
        public static var zoomToFit: String { tr("menu.zoomToFit") }  // "Zoom to Fit"
    }
    public enum Offline {
        public static func available(_ a0: CVarArg) -> String { tr("offline.available", a0) }
        public static var badgeAvailable: String { tr("offline.badgeAvailable") }  // "Available offline"
        public static var downloadFailed: String { tr("offline.downloadFailed") }  // "The offline download couldn't be completed."
        public static func downloadingName(_ a0: CVarArg) -> String { tr("offline.downloadingName", a0) }
        public static var footnote: String { tr("offline.footnote") }  // "Downloaded files open even without a connection."
        public static var manageEmpty: String { tr("offline.manageEmpty") }  // "Nothing is downloaded for offline use."
        public static var manageRow: String { tr("offline.manageRow") }  // "Manage Offline Files"
        public static var manageTitle: String { tr("offline.manageTitle") }  // "Offline Files"
        public static var preferOfflineSubtitle: String { tr("offline.preferOfflineSubtitle") }
        public static var preferOfflineToggle: String { tr("offline.preferOfflineToggle") }  // "Play Downloaded Copies"
        public static var preparing: String { tr("offline.preparing") }  // "Preparing…"
        public static func progressCount(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("offline.progressCount", a0, a1) }
        public static var removeConfirm: String { tr("offline.removeConfirm") }  // "Remove"
        public static var removeConfirmMessage: String { tr("offline.removeConfirmMessage") }
        public static var removeConfirmTitle: String { tr("offline.removeConfirmTitle") }  // "Remove Offline Files?"
        public static var removeItemMessage: String { tr("offline.removeItemMessage") }
        public static func removeItemTitle(_ a0: CVarArg) -> String { tr("offline.removeItemTitle", a0) }
        public static func removeItemsTitle(_ a0: CVarArg) -> String { tr("offline.removeItemsTitle", a0) }
        public static var removeRow: String { tr("offline.removeRow") }  // "Remove Offline Files"
        public static var resyncRow: String { tr("offline.resyncRow") }  // "Update Offline Files"
        public static var sectionSavedEarlier: String { tr("offline.sectionSavedEarlier") }  // "Saved earlier"
        public static var sectionTitle: String { tr("offline.sectionTitle") }  // "Offline"
        public static var selectionDownload: String { tr("offline.selectionDownload") }  // "Download"
        public static var selectionEmpty: String { tr("offline.selectionEmpty") }  // "This folder is empty."
        public static var selectionEstimate: String { tr("offline.selectionEstimate") }  // "Estimated Download"
        public static var selectionInsufficientSpace: String { tr("offline.selectionInsufficientSpace") }  // "Not enough free space on this device"
        public static var selectionLoadFailed: String { tr("offline.selectionLoadFailed") }  // "This folder couldn't be loaded."
        public static var selectionTitle: String { tr("offline.selectionTitle") }  // "Download for Offline"
        public static var settingsRow: String { tr("offline.settingsRow") }  // "Download Files for Offline Use"
        public static var tabEmpty: String { tr("offline.tabEmpty") }
        public static var tunnelSpeedNote: String { tr("offline.tunnelSpeedNote") }
        public static var waitingForNetwork: String { tr("offline.waitingForNetwork") }  // "Will download when you're back online"
    }
    public enum OpenWith {
        public static var failed: String { tr("openWith.failed") }  // "Couldn't open this file."
        public static func openIn(_ a0: CVarArg) -> String { tr("openWith.openIn", a0) }
        public static var openWith: String { tr("openWith.openWith") }  // "Open With"
        public static var print: String { tr("openWith.print") }  // "Print…"
        public static var viewAsText: String { tr("openWith.viewAsText") }  // "View as Text"
    }
    public enum Permissions {
        public static var applyOwnership: String { tr("permissions.applyOwnership") }  // "Apply Ownership"
        public static var applyPermissions: String { tr("permissions.applyPermissions") }  // "Apply Permissions"
        public static var applyToEnclosed: String { tr("permissions.applyToEnclosed") }  // "Apply to enclosed items"
        public static var fieldGroup: String { tr("permissions.fieldGroup") }  // "Group"
        public static var fieldOwner: String { tr("permissions.fieldOwner") }  // "Owner"
        public static var numericLabel: String { tr("permissions.numericLabel") }  // "Numeric"
        public static var ownershipNote: String { tr("permissions.ownershipNote") }
        public static var rightExecute: String { tr("permissions.rightExecute") }  // "Execute"
        public static var rightRead: String { tr("permissions.rightRead") }  // "Read"
        public static var rightWrite: String { tr("permissions.rightWrite") }  // "Write"
        public static var scopeGroup: String { tr("permissions.scopeGroup") }  // "Group"
        public static var scopeOthers: String { tr("permissions.scopeOthers") }  // "Others"
        public static var scopeOwner: String { tr("permissions.scopeOwner") }  // "Owner"
        public static var sectionMode: String { tr("permissions.sectionMode") }  // "Mode"
        public static var sectionOwnership: String { tr("permissions.sectionOwnership") }  // "Ownership"
        public static var title: String { tr("permissions.title") }  // "Permissions"
    }
    public enum PreviewToolbar {
        public static var close: String { tr("previewToolbar.close") }  // "Close"
        public static var createShareLink: String { tr("previewToolbar.createShareLink") }  // "Create share link"
        public static var delete: String { tr("previewToolbar.delete") }  // "Delete"
        public static var download: String { tr("previewToolbar.download") }  // "Download"
        public static var rename: String { tr("previewToolbar.rename") }  // "Rename"
        public static var saveToDevice: String { tr("previewToolbar.saveToDevice") }  // "Save to Device"
        public static var share: String { tr("previewToolbar.share") }  // "Share"
    }
    public enum SearchIndexSettings {
        public static var addButton: String { tr("searchIndexSettings.addButton") }  // "Add"
        public static var additional: String { tr("searchIndexSettings.additional") }  // "Additional exclusions"
        public static var discardButton: String { tr("searchIndexSettings.discardButton") }  // "Discard"
        public static var environment: String { tr("searchIndexSettings.environment") }  // "Environment-defined exclusions"
        public static func locked(_ a0: CVarArg) -> String { tr("searchIndexSettings.locked", a0) }
        public static var navigationTitle: String { tr("searchIndexSettings.navigationTitle") }  // "Search Index"
        public static var none: String { tr("searchIndexSettings.none") }  // "No path configured"
        public static var placeholder: String { tr("searchIndexSettings.placeholder") }  // "Backups/2024"
        public static var running: String { tr("searchIndexSettings.running") }  // "Keep a search index"
        public static var runningHelp: String { tr("searchIndexSettings.runningHelp") }
        public static var saveButton: String { tr("searchIndexSettings.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("searchIndexSettings.subtitle") }  // "Exclude paths from content indexing."
        public static var unavailable: String { tr("searchIndexSettings.unavailable") }  // "Search index settings are only available to administrators."
    }
    public enum Select {
        public static var deselectAll: String { tr("select.deselectAll") }  // "Deselect All"
        public static var gridView: String { tr("select.gridView") }  // "Grid View"
        public static var listView: String { tr("select.listView") }  // "List View"
        public static var selectAll: String { tr("select.selectAll") }  // "Select All"
        public static var tableView: String { tr("select.tableView") }  // "Table View"
        public static var viewAs: String { tr("select.viewAs") }  // "View"
    }
    public enum ServerDetails {
        public static var cameraDeniedMessage: String { tr("serverDetails.cameraDeniedMessage") }  // "Turn on camera access in Settings to take a photo."
        public static var cameraDeniedTitle: String { tr("serverDetails.cameraDeniedTitle") }  // "Camera Access Off"
        public static var changeLogo: String { tr("serverDetails.changeLogo") }  // "Change Icon"
        public static var chooseFromGallery: String { tr("serverDetails.chooseFromGallery") }  // "Upload from Gallery"
        public static var logoErrorTooLarge: String { tr("serverDetails.logoErrorTooLarge") }  // "That image is too large. Pick one under 2 MB."
        public static var nameErrorEmpty: String { tr("serverDetails.nameErrorEmpty") }  // "Server name can't be empty."
        public static var nameLabel: String { tr("serverDetails.nameLabel") }  // "Server Name"
        public static var namePlaceholder: String { tr("serverDetails.namePlaceholder") }  // "Explorer"
        public static var navigationTitle: String { tr("serverDetails.navigationTitle") }  // "Server"
        public static var savedMessage: String { tr("serverDetails.savedMessage") }  // "Server details updated."
        public static var takePhoto: String { tr("serverDetails.takePhoto") }  // "Take Photo"
        public static var updateButton: String { tr("serverDetails.updateButton") }  // "Update Server"
        public static var urlFootnote: String { tr("serverDetails.urlFootnote") }
        public static var urlLabel: String { tr("serverDetails.urlLabel") }  // "Server URL"
    }
    public enum ServerSettings {
        public static var detailSeparator: String { tr("serverSettings.detailSeparator") }  // " · "
        public static func featureOffHowTo(_ a0: CVarArg) -> String { tr("serverSettings.featureOffHowTo", a0) }
        public static var featureOffKept: String { tr("serverSettings.featureOffKept") }
        public static var featureOffTitle: String { tr("serverSettings.featureOffTitle") }  // "This feature is not enabled"
        public static var featureOffUseSwitch: String { tr("serverSettings.featureOffUseSwitch") }  // "Turn it on with the switch above."
    }
    public enum Settings {
        public static func accountActiveLabel(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("settings.accountActiveLabel", a0, a1) }
        public static func accountLabel(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("settings.accountLabel", a0, a1) }
        public static var accountSignOut: String { tr("settings.accountSignOut") }  // "Sign Out"
        public static func accountSignOutMessage(_ a0: CVarArg) -> String { tr("settings.accountSignOutMessage", a0) }
        public static var accountSignOutTitle: String { tr("settings.accountSignOutTitle") }  // "Sign Out?"
        public static var addAccount: String { tr("settings.addAccount") }  // "Add Account"
        public static func appVersion(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("settings.appVersion", a0, a1) }
        public static var badgeActive: String { tr("settings.badgeActive") }  // "Active"
        public static var clearCacheConfirm: String { tr("settings.clearCacheConfirm") }  // "Clear"
        public static var clearCacheMessage: String { tr("settings.clearCacheMessage") }
        public static var clearCacheTitle: String { tr("settings.clearCacheTitle") }  // "Clear Cache?"
        public static var clientCertificate: String { tr("settings.clientCertificate") }  // "Client Certificate"
        public static var clientCertificateExpired: String { tr("settings.clientCertificateExpired") }  // "Expired"
        public static var clientCertificateExpiresSoon: String { tr("settings.clientCertificateExpiresSoon") }  // "Expires soon"
        public static var clientCertificateNone: String { tr("settings.clientCertificateNone") }  // "None"
        public static var creditsBuyCoffee: String { tr("settings.creditsBuyCoffee") }  // "Buy me a coffee ☕️"
        public static var creditsLikeApp: String { tr("settings.creditsLikeApp") }  // "Like the app?"
        public static var creditsMadeBy: String { tr("settings.creditsMadeBy") }  // "Made with ❤️ by Phillip Maizza"
        public static var dateFormatNavigationTitle: String { tr("settings.dateFormatNavigationTitle") }  // "Date Format"
        public static var dateFormatShowTime: String { tr("settings.dateFormatShowTime") }  // "Show Time"
        public static var navigationTitle: String { tr("settings.navigationTitle") }  // "Settings"
        public static var removeAllDownloadsConfirm: String { tr("settings.removeAllDownloadsConfirm") }  // "Remove All"
        public static var removeAllDownloadsMessage: String { tr("settings.removeAllDownloadsMessage") }
        public static var removeAllDownloadsTitle: String { tr("settings.removeAllDownloadsTitle") }  // "Remove All Downloads?"
        public static var rowAccessRules: String { tr("settings.rowAccessRules") }  // "Folder Access Rules"
        public static var rowAddPassword: String { tr("settings.rowAddPassword") }  // "Add Password"
        public static var rowAppearance: String { tr("settings.rowAppearance") }  // "Appearance"
        public static var rowChangePassword: String { tr("settings.rowChangePassword") }  // "Change Password"
        public static var rowClearCache: String { tr("settings.rowClearCache") }  // "Clear Cache"
        public static var rowDateFormat: String { tr("settings.rowDateFormat") }  // "Date Format"
        public static var rowLanguage: String { tr("settings.rowLanguage") }  // "Language"
        public static var rowOpenSourceLicenses: String { tr("settings.rowOpenSourceLicenses") }  // "Open Source Licenses"
        public static var rowPrivacyPolicy: String { tr("settings.rowPrivacyPolicy") }  // "Privacy Policy"
        public static var rowRateApp: String { tr("settings.rowRateApp") }  // "Rate NextExplorer"
        public static var rowRemoveAllDownloads: String { tr("settings.rowRemoveAllDownloads") }  // "Remove All Downloads"
        public static var rowServer: String { tr("settings.rowServer") }  // "Server"
        public static var rowSupport: String { tr("settings.rowSupport") }  // "Help & Support"
        public static var rowTermsOfUse: String { tr("settings.rowTermsOfUse") }  // "Terms of Use"
        public static var rowThumbnailSize: String { tr("settings.rowThumbnailSize") }  // "Thumbnail Size"
        public static var rowThumbnails: String { tr("settings.rowThumbnails") }  // "Thumbnails"
        public static var rowUserManagement: String { tr("settings.rowUserManagement") }  // "User Management"
        public static var sectionAccounts: String { tr("settings.sectionAccounts") }  // "Accounts"
        public static var sectionAdmin: String { tr("settings.sectionAdmin") }  // "Admin"
        public static var sectionDisplay: String { tr("settings.sectionDisplay") }  // "Display"
        public static var sectionGeneral: String { tr("settings.sectionGeneral") }  // "General"
        public static var sectionInfo: String { tr("settings.sectionInfo") }  // "Info"
        public static var sectionLegal: String { tr("settings.sectionLegal") }  // "Legal"
        public static var sectionLicenses: String { tr("settings.sectionLicenses") }  // "Licenses"
        public static var sectionServerStorage: String { tr("settings.sectionServerStorage") }  // "Server Storage"
        public static var sectionStorage: String { tr("settings.sectionStorage") }  // "Storage"
        public static var sectionSupport: String { tr("settings.sectionSupport") }  // "Support"
        public static var sectionUsers: String { tr("settings.sectionUsers") }  // "Users"
        public static func serverStorageUsed(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("settings.serverStorageUsed", a0, a1) }
        public static var signOutAlertTitle: String { tr("settings.signOutAlertTitle") }  // "Sign Out?"
        public static var signOutButton: String { tr("settings.signOutButton") }  // "Sign Out"
        public static var signOutMessage: String { tr("settings.signOutMessage") }
        public static var signingOut: String { tr("settings.signingOut") }  // "Signing Out…"
        public static var storageFootnote: String { tr("settings.storageFootnote") }
        public static var storageFootnoteMac: String { tr("settings.storageFootnoteMac") }
        public static var toggleHaptics: String { tr("settings.toggleHaptics") }  // "Haptics"
        public static var toggleKeepClipboard: String { tr("settings.toggleKeepClipboard") }  // "Keep Items After Paste"
        public static var toggleKeepClipboardSubtitle: String { tr("settings.toggleKeepClipboardSubtitle") }
        public static var toggleRenderHTML: String { tr("settings.toggleRenderHTML") }  // "Render HTML Pages"
        public static var toggleRenderMarkdown: String { tr("settings.toggleRenderMarkdown") }  // "Render Markdown Files"
        public static var toggleShowExtensions: String { tr("settings.toggleShowExtensions") }  // "Show Filename Extensions"
        public static var toggleShowHiddenFiles: String { tr("settings.toggleShowHiddenFiles") }  // "Show Hidden Files"
        public static var toggleShowTabLabels: String { tr("settings.toggleShowTabLabels") }  // "Show Tab Labels"
        public static var toggleShowThumbnails: String { tr("settings.toggleShowThumbnails") }  // "Show Thumbnails"
        public static var uploadDefaultsClear: String { tr("settings.uploadDefaultsClear") }  // "Ask Each Time"
        public static var uploadDefaultsFolder: String { tr("settings.uploadDefaultsFolder") }  // "Default Folder"
        public static var uploadDefaultsFolderNone: String { tr("settings.uploadDefaultsFolderNone") }  // "Ask Each Time"
        public static var uploadDefaultsFooter: String { tr("settings.uploadDefaultsFooter") }
        public static var uploadDefaultsRow: String { tr("settings.uploadDefaultsRow") }  // "Shared Files"
        public static var uploadDefaultsWithoutAsking: String { tr("settings.uploadDefaultsWithoutAsking") }  // "Upload Without Asking"
    }
    public enum ShareTarget {
        public static var anyone: String { tr("shareTarget.anyone") }  // "Anyone with link"
        public static var users: String { tr("shareTarget.users") }  // "Specific users"
    }
    public enum ShareUpload {
        public static var accountHint: String { tr("shareUpload.accountHint") }  // "Choose which account receives the files."
        public static var accountLabel: String { tr("shareUpload.accountLabel") }  // "Account"
        public static func accountSummary(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("shareUpload.accountSummary", a0, a1) }
        public static var causeCannotRead: String { tr("shareUpload.causeCannotRead") }  // "It couldn't be read."
        public static var causeFolder: String { tr("shareUpload.causeFolder") }  // "Folders can't be shared. Share the files inside instead."
        public static var causeNotEnoughSpace: String { tr("shareUpload.causeNotEnoughSpace") }  // "There isn't enough free space on this device."
        public static var causeUnknown: String { tr("shareUpload.causeUnknown") }  // "It couldn't be prepared."
        public static var certificateRejected: String { tr("shareUpload.certificateRejected") }
        public static var certificateRequired: String { tr("shareUpload.certificateRequired") }
        public static func checking(_ a0: CVarArg) -> String { tr("shareUpload.checking", a0) }
        public static var defaultFolderUnavailable: String { tr("shareUpload.defaultFolderUnavailable") }
        public static var failed: String { tr("shareUpload.failed") }  // "The files couldn't be prepared for upload."
        public static func failedItemLine(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("shareUpload.failedItemLine", a0, a1) }
        public static var failedItemsHeader: String { tr("shareUpload.failedItemsHeader") }  // "These files couldn't be prepared:"
        public static func failureForbidden(_ a0: CVarArg) -> String { tr("shareUpload.failureForbidden", a0) }
        public static func failureNetwork(_ a0: CVarArg) -> String { tr("shareUpload.failureNetwork", a0) }
        public static func failureOther(_ a0: CVarArg) -> String { tr("shareUpload.failureOther", a0) }
        public static func failureServerFull(_ a0: CVarArg) -> String { tr("shareUpload.failureServerFull", a0) }
        public static func failureUnauthorized(_ a0: CVarArg) -> String { tr("shareUpload.failureUnauthorized", a0) }
        public static func fallbackItemName(_ a0: CVarArg) -> String { tr("shareUpload.fallbackItemName", a0) }
        public static var folderChoose: String { tr("shareUpload.folderChoose") }  // "Choose a Folder"
        public static var folderHint: String { tr("shareUpload.folderHint") }  // "Opens the folder picker."
        public static var folderLabel: String { tr("shareUpload.folderLabel") }  // "Folder"
        public static var insufficientSpace: String { tr("shareUpload.insufficientSpace") }
        public static func itemCount(_ a0: CVarArg) -> String { tr("shareUpload.itemCount", a0) }
        public static var keepOpen: String { tr("shareUpload.keepOpen") }  // "Keep this open until preparing finishes."
        public static var livePhotoNote: String { tr("shareUpload.livePhotoNote") }  // "Live Photos upload with their motion video."
        public static var nothingToUpload: String { tr("shareUpload.nothingToUpload") }  // "There's nothing here NextExplorer can upload."
        public static var notificationAllFailedTitle: String { tr("shareUpload.notificationAllFailedTitle") }  // "Upload failed"
        public static func notificationDoneBody(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("shareUpload.notificationDoneBody", a0, a1) }
        public static var notificationDoneTitle: String { tr("shareUpload.notificationDoneTitle") }  // "Upload finished"
        public static var notificationFailedTitle: String { tr("shareUpload.notificationFailedTitle") }  // "Some files didn't upload"
        public static var notificationHiddenPreview: String { tr("shareUpload.notificationHiddenPreview") }  // "Open NextExplorer to see how your upload went."
        public static func notificationMoreNames(_ a0: CVarArg) -> String { tr("shareUpload.notificationMoreNames", a0) }
        public static var notificationRetry: String { tr("shareUpload.notificationRetry") }  // "Retry"
        public static var openApp: String { tr("shareUpload.openApp") }  // "Open NextExplorer"
        public static var openAppInstructions: String { tr("shareUpload.openAppInstructions") }  // "Open NextExplorer from your Home Screen, then share again."
        public static func preparing(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("shareUpload.preparing", a0, a1) }
        public static func readyCount(_ a0: CVarArg) -> String { tr("shareUpload.readyCount", a0) }
        public static var retryFailed: String { tr("shareUpload.retryFailed") }  // "Retry Failed Files"
        public static var retryFailedBody: String { tr("shareUpload.retryFailedBody") }  // "Open NextExplorer and share the files again."
        public static var retryFailedTitle: String { tr("shareUpload.retryFailedTitle") }  // "Couldn't retry"
        public static var retrySignInBody: String { tr("shareUpload.retrySignInBody") }  // "Sign in to NextExplorer, then tap Retry again."
        public static var sessionUnreadable: String { tr("shareUpload.sessionUnreadable") }
        public static var signedOut: String { tr("shareUpload.signedOut") }  // "Sign in to NextExplorer first, then share again."
        public static var started: String { tr("shareUpload.started") }
        public static var title: String { tr("shareUpload.title") }  // "Upload to NextExplorer"
        public static var upload: String { tr("shareUpload.upload") }  // "Upload"
        public static var uploadReady: String { tr("shareUpload.uploadReady") }  // "Upload Ready Files"
    }
    public enum Shared {
        public static var actionFileLink: String { tr("shared.actionFileLink") }  // "File link"
        public static var actionFolderLink: String { tr("shared.actionFolderLink") }  // "Folder link"
        public static var actionShareLink: String { tr("shared.actionShareLink") }  // "Share link"
        public static var anyoneWithLink: String { tr("shared.anyoneWithLink") }  // "Anyone with link"
        public static var badgeExpired: String { tr("shared.badgeExpired") }  // "expired"
        public static var copiedDirectFile: String { tr("shared.copiedDirectFile") }  // "Direct file link copied"
        public static var copiedFolderZip: String { tr("shared.copiedFolderZip") }  // "Folder ZIP link copied"
        public static var copiedShareLink: String { tr("shared.copiedShareLink") }  // "Share link copied"
        public static var deleteMessage: String { tr("shared.deleteMessage") }
        public static var deleteTitle: String { tr("shared.deleteTitle") }  // "Delete Share Link?"
        public static var emptyByMe: String { tr("shared.emptyByMe") }  // "Share a file or folder to see its link here."
        public static var emptyWithMe: String { tr("shared.emptyWithMe") }  // "Links other people share with you show up here."
        public static var linkMode: String { tr("shared.linkMode") }  // "Link mode"
        public static var metaAccess: String { tr("shared.metaAccess") }  // "Access"
        public static var metaExpiration: String { tr("shared.metaExpiration") }  // "Expiration"
        public static var metaSharedBy: String { tr("shared.metaSharedBy") }  // "Shared by"
        public static var metaSharedWith: String { tr("shared.metaSharedWith") }  // "Shared with"
        public static func moreRecipients(_ a0: CVarArg) -> String { tr("shared.moreRecipients", a0) }
        public static var navigationTitle: String { tr("shared.navigationTitle") }  // "Shared"
        public static func noSearchMatches(_ a0: CVarArg) -> String { tr("shared.noSearchMatches", a0) }
        public static var sectionExpired: String { tr("shared.sectionExpired") }  // "Expired"
        public static var segmentByMe: String { tr("shared.segmentByMe") }  // "By me"
        public static var segmentWithMe: String { tr("shared.segmentWithMe") }  // "With me"
        public static var sharedByUnknown: String { tr("shared.sharedByUnknown") }  // "Someone"
    }
    public enum Sort {
        public static var ascending: String { tr("sort.ascending") }  // "Ascending"
        public static var dateAdded: String { tr("sort.dateAdded") }  // "Date Added"
        public static var dateModified: String { tr("sort.dateModified") }  // "Date Modified"
        public static var dateShared: String { tr("sort.dateShared") }  // "Date Shared"
        public static var descending: String { tr("sort.descending") }  // "Descending"
        public static var email: String { tr("sort.email") }  // "Email"
        public static var expiration: String { tr("sort.expiration") }  // "Expiration"
        public static var kind: String { tr("sort.kind") }  // "Kind"
        public static var name: String { tr("sort.name") }  // "Name"
        public static var sheetTitle: String { tr("sort.sheetTitle") }  // "Sort By"
        public static var size: String { tr("sort.size") }  // "Size"
        public static var type: String { tr("sort.type") }  // "Type"
    }
    public enum Tab {
        public static var browse: String { tr("tab.browse") }  // "Browse"
        public static var downloads: String { tr("tab.downloads") }  // "Downloads"
        public static var favorites: String { tr("tab.favorites") }  // "Favorites"
        public static var offline: String { tr("tab.offline") }  // "Offline"
        public static var settings: String { tr("tab.settings") }  // "Settings"
        public static var shared: String { tr("tab.shared") }  // "Shared"
    }
    public enum TextPreview {
        public static var conflictMessage: String { tr("textPreview.conflictMessage") }
        public static var conflictOverwrite: String { tr("textPreview.conflictOverwrite") }  // "Overwrite"
        public static var conflictReload: String { tr("textPreview.conflictReload") }  // "Reload"
        public static func conflictTitle(_ a0: CVarArg) -> String { tr("textPreview.conflictTitle", a0) }
        public static var dontSave: String { tr("textPreview.dontSave") }  // "Don't Save"
        public static var loadFailed: String { tr("textPreview.loadFailed") }
        public static var saved: String { tr("textPreview.saved") }  // "Saved"
        public static var unsavedMessage: String { tr("textPreview.unsavedMessage") }  // "Your changes are lost if you don't save them."
        public static func unsavedTitle(_ a0: CVarArg) -> String { tr("textPreview.unsavedTitle", a0) }
    }
    public enum ThumbnailSettings {
        public static var concurrency: String { tr("thumbnailSettings.concurrency") }  // "Concurrency"
        public static var concurrencyHelp: String { tr("thumbnailSettings.concurrencyHelp") }  // "How many thumbnails the server builds at once."
        public static var enable: String { tr("thumbnailSettings.enable") }  // "Generate Thumbnails"
        public static var enableHelp: String { tr("thumbnailSettings.enableHelp") }  // "Turn off to serve full images everywhere instead."
        public static var maxDimension: String { tr("thumbnailSettings.maxDimension") }  // "Max Dimension"
        public static var maxDimensionHelp: String { tr("thumbnailSettings.maxDimensionHelp") }  // "Longest edge of a generated thumbnail, in pixels."
        public static var navigationTitle: String { tr("thumbnailSettings.navigationTitle") }  // "Thumbnails"
        public static var quality: String { tr("thumbnailSettings.quality") }  // "Quality"
        public static var qualityHelp: String { tr("thumbnailSettings.qualityHelp") }  // "Higher looks better and uses more space."
        public static var saveButton: String { tr("thumbnailSettings.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("thumbnailSettings.subtitle") }
        public static var unavailable: String { tr("thumbnailSettings.unavailable") }  // "Thumbnail settings are only available to administrators."
    }
    public enum ThumbnailSize {
        public static var large: String { tr("thumbnailSize.large") }  // "Large"
        public static var medium: String { tr("thumbnailSize.medium") }  // "Medium"
        public static var small: String { tr("thumbnailSize.small") }  // "Small"
    }
    public enum TipJar {
        public static var errorLoad: String { tr("tipJar.errorLoad") }  // "Couldn't load the tip options. Please try again."
        public static var errorPurchase: String { tr("tipJar.errorPurchase") }  // "The purchase didn't go through. Please try again."
        public static var explanation: String { tr("tipJar.explanation") }
        public static var pending: String { tr("tipJar.pending") }  // "Waiting for approval. You'll be charged once it's approved."
        public static var title: String { tr("tipJar.title") }  // "Buy me a coffee"
        public static var toastThanks: String { tr("tipJar.toastThanks") }  // "Thank you for supporting the project! 🙏"
    }
    public enum TrashSettings {
        public static var available: String { tr("trashSettings.available") }  // "Available"
        public static var checkpointMinutes: String { tr("trashSettings.checkpointMinutes") }  // "Office checkpoint (minutes)"
        public static var dailyDays: String { tr("trashSettings.dailyDays") }  // "Then one per day (days)"
        public static var discardButton: String { tr("trashSettings.discardButton") }  // "Discard"
        public static var enabled: String { tr("trashSettings.enabled") }  // "Send deleted items to the trash"
        public static var enabledHelp: String { tr("trashSettings.enabledHelp") }
        public static var environmentNote: String { tr("trashSettings.environmentNote") }
        public static func eventAdopted(_ a0: CVarArg) -> String { tr("trashSettings.eventAdopted", a0) }
        public static var eventBreaker: String { tr("trashSettings.eventBreaker") }  // "Too many items missing at once: nothing was changed"
        public static func eventEvicted(_ a0: CVarArg) -> String { tr("trashSettings.eventEvicted", a0) }
        public static func eventFailed(_ a0: CVarArg) -> String { tr("trashSettings.eventFailed", a0) }
        public static func eventForgotten(_ a0: CVarArg) -> String { tr("trashSettings.eventForgotten", a0) }
        public static func eventLost(_ a0: CVarArg) -> String { tr("trashSettings.eventLost", a0) }
        public static func eventVersionEvicted(_ a0: CVarArg) -> String { tr("trashSettings.eventVersionEvicted", a0) }
        public static var eventVersionFailed: String { tr("trashSettings.eventVersionFailed") }  // "A version could not be removed"
        public static var eventVersionLost: String { tr("trashSettings.eventVersionLost") }  // "A version was missing its content"
        public static func eventVersionTooLarge(_ a0: CVarArg) -> String { tr("trashSettings.eventVersionTooLarge", a0) }
        public static var eventVersionsBreaker: String { tr("trashSettings.eventVersionsBreaker") }  // "Too many versions missing at once: nothing was changed"
        public static var hourlyDays: String { tr("trashSettings.hourlyDays") }  // "Then one per hour (days)"
        public static var journalHeader: String { tr("trashSettings.journalHeader") }  // "Journal"
        public static var keepAllHours: String { tr("trashSettings.keepAllHours") }  // "Keep every version (hours)"
        public static func lastPass(_ a0: CVarArg) -> String { tr("trashSettings.lastPass", a0) }
        public static func lastPassPurged(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("trashSettings.lastPassPurged", a0, a1) }
        public static var maxPerFile: String { tr("trashSettings.maxPerFile") }  // "Versions per file at most"
        public static var maxPercent: String { tr("trashSettings.maxPercent") }  // "Share of each volume (%)"
        public static var maxPercentHelp: String { tr("trashSettings.maxPercentHelp") }  // "The most the trash may hold on a volume, from 1 to 90%."
        public static var maxSize: String { tr("trashSettings.maxSize") }  // "Size cap per volume (GiB)"
        public static var maxSizeHelp: String { tr("trashSettings.maxSizeHelp") }  // "Optional. The smaller of the share and the cap applies."
        public static var maxSizeNone: String { tr("trashSettings.maxSizeNone") }  // "No cap"
        public static var navigationTitle: String { tr("trashSettings.navigationTitle") }  // "Trash and Versions"
        public static var never: String { tr("trashSettings.never") }  // "not yet"
        public static var noBudget: String { tr("trashSettings.noBudget") }  // "no limit"
        public static var retention: String { tr("trashSettings.retention") }  // "Retention (days)"
        public static var retentionHelp: String { tr("trashSettings.retentionHelp") }  // "From 1 to 3650 days."
        public static var runMaintenance: String { tr("trashSettings.runMaintenance") }  // "Run Maintenance Now"
        public static var saveButton: String { tr("trashSettings.saveButton") }  // "Save Changes"
        public static var sharedSpace: String { tr("trashSettings.sharedSpace") }
        public static var subtitle: String { tr("trashSettings.subtitle") }
        public static var tiersHelp: String { tr("trashSettings.tiersHelp") }
        public static var trashHeader: String { tr("trashSettings.trashHeader") }  // "Trash"
        public static var trashInvalid: String { tr("trashSettings.trashInvalid") }
        public static var unavailable: String { tr("trashSettings.unavailable") }
        public static var unavailableMissing: String { tr("trashSettings.unavailableMissing") }  // "Not mounted or removed"
        public static var unavailableReplaced: String { tr("trashSettings.unavailableReplaced") }  // "Another disk in its place"
        public static var unavailableUnreadable: String { tr("trashSettings.unavailableUnreadable") }  // "Unreadable"
        public static func usage(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("trashSettings.usage", a0, a1) }
        public static var verify: String { tr("trashSettings.verify") }  // "Verify"
        public static func verifyIssues(_ a0: CVarArg) -> String { tr("trashSettings.verifyIssues", a0) }
        public static var verifyOk: String { tr("trashSettings.verifyOk") }  // "Every volume's trash is consistent."
        public static var versionsEnabled: String { tr("trashSettings.versionsEnabled") }  // "Keep earlier versions of files"
        public static var versionsEnabledHelp: String { tr("trashSettings.versionsEnabledHelp") }
        public static var versionsEnvironmentNote: String { tr("trashSettings.versionsEnvironmentNote") }
        public static var versionsHeader: String { tr("trashSettings.versionsHeader") }  // "File Versions"
        public static var versionsInvalid: String { tr("trashSettings.versionsInvalid") }
        public static var versionsSubtitle: String { tr("trashSettings.versionsSubtitle") }
        public static func violation(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("trashSettings.violation", a0, a1) }
        public static func zoneItems(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("trashSettings.zoneItems", a0, a1) }
        public static func zoneKindPersonal(_ a0: CVarArg) -> String { tr("trashSettings.zoneKindPersonal", a0) }
        public static func zoneKindUserVolume(_ a0: CVarArg) -> String { tr("trashSettings.zoneKindUserVolume", a0) }
        public static func zoneProblems(_ a0: CVarArg) -> String { tr("trashSettings.zoneProblems", a0) }
        public static func zoneVersions(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("trashSettings.zoneVersions", a0, a1) }
        public static var zonesEmpty: String { tr("trashSettings.zonesEmpty") }  // "Nothing has been deleted into a trash yet."
        public static var zonesHeader: String { tr("trashSettings.zonesHeader") }  // "Trash by Volume"
        public static var zonesSubtitle: String { tr("trashSettings.zonesSubtitle") }
    }
    public enum TwoFactor {
        public static var codeAccessibilityLabel: String { tr("twoFactor.codeAccessibilityLabel") }  // "Authenticator code"
        public static var confirmButton: String { tr("twoFactor.confirmButton") }  // "Verify and Turn On"
        public static var copyCodesButton: String { tr("twoFactor.copyCodesButton") }  // "Copy Codes"
        public static var copyKeyAccessibilityLabel: String { tr("twoFactor.copyKeyAccessibilityLabel") }  // "Copy setup key"
        public static var enrollIntro: String { tr("twoFactor.enrollIntro") }
        public static var keyLabel: String { tr("twoFactor.keyLabel") }  // "Setup Key"
        public static var manageButton: String { tr("twoFactor.manageButton") }  // "Manage…"
        public static var navigationTitle: String { tr("twoFactor.navigationTitle") }  // "Two-Factor Authentication"
        public static var newCodesButton: String { tr("twoFactor.newCodesButton") }  // "Get New Recovery Codes"
        public static var offIntro: String { tr("twoFactor.offIntro") }
        public static var offTitle: String { tr("twoFactor.offTitle") }  // "Two-factor authentication is off"
        public static var onTitle: String { tr("twoFactor.onTitle") }  // "Two-factor authentication is on"
        public static var passwordConfirmButton: String { tr("twoFactor.passwordConfirmButton") }  // "Confirm"
        public static var passwordField: String { tr("twoFactor.passwordField") }  // "Password"
        public static var passwordNewCodesIntro: String { tr("twoFactor.passwordNewCodesIntro") }
        public static var passwordTurnOffIntro: String { tr("twoFactor.passwordTurnOffIntro") }  // "Enter your password to turn off two-factor authentication."
        public static var qrAccessibilityLabel: String { tr("twoFactor.qrAccessibilityLabel") }  // "QR code for your authenticator app"
        public static func recoveryCodesLeft(_ a0: CVarArg) -> String { tr("twoFactor.recoveryCodesLeft", a0) }
        public static var recoveryDoneButton: String { tr("twoFactor.recoveryDoneButton") }  // "I've Saved Them"
        public static var recoveryIntro: String { tr("twoFactor.recoveryIntro") }
        public static var recoveryTitle: String { tr("twoFactor.recoveryTitle") }  // "Save your recovery codes"
        public static var shareCodesButton: String { tr("twoFactor.shareCodesButton") }  // "Share Codes"
        public static var turnOffButton: String { tr("twoFactor.turnOffButton") }  // "Turn Off"
        public static var turnOnButton: String { tr("twoFactor.turnOnButton") }  // "Turn On"
    }
    public enum UnsupportedPreview {
        public static var cannotOpen: String { tr("unsupportedPreview.cannotOpen") }  // "This app can't open this type of file."
        public static var genericType: String { tr("unsupportedPreview.genericType") }  // "File"
        public static func macDescription(_ a0: CVarArg, _ a1: CVarArg, _ a2: CVarArg) -> String { tr("unsupportedPreview.macDescription", a0, a1, a2) }
    }
    public enum UploadSettings {
        public static var autoFallback: String { tr("uploadSettings.autoFallback") }  // "Auto-fallback to chunked"
        public static var autoFallbackHelp: String { tr("uploadSettings.autoFallbackHelp") }
        public static var chunkSize: String { tr("uploadSettings.chunkSize") }  // "Chunk size"
        public static var chunkSizeHelp: String { tr("uploadSettings.chunkSizeHelp") }
        public static func chunkSizeValue(_ a0: CVarArg) -> String { tr("uploadSettings.chunkSizeValue", a0) }
        public static var chunkedEnable: String { tr("uploadSettings.chunkedEnable") }  // "Enable chunked uploads"
        public static var chunkedEnableHelp: String { tr("uploadSettings.chunkedEnableHelp") }
        public static var navigationTitle: String { tr("uploadSettings.navigationTitle") }  // "Uploads"
        public static var saveButton: String { tr("uploadSettings.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("uploadSettings.subtitle") }  // "Configure how files are sent to the server."
        public static var unavailable: String { tr("uploadSettings.unavailable") }  // "Upload settings are only available to administrators."
    }
    public enum Uploads {
        public static var actionTakePhoto: String { tr("uploads.actionTakePhoto") }  // "Take Photo or Video"
        public static var actionUploadFromFiles: String { tr("uploads.actionUploadFromFiles") }  // "Upload from Files"
        public static var actionUploadFromPhotos: String { tr("uploads.actionUploadFromPhotos") }  // "Upload from Gallery"
        public static func barFailedMany(_ a0: CVarArg) -> String { tr("uploads.barFailedMany", a0) }
        public static var barFailedOne: String { tr("uploads.barFailedOne") }  // "1 upload failed"
        public static func barTitleMany(_ a0: CVarArg) -> String { tr("uploads.barTitleMany", a0) }
        public static func barTitleOne(_ a0: CVarArg) -> String { tr("uploads.barTitleOne", a0) }
        public static var cameraDeniedMessage: String { tr("uploads.cameraDeniedMessage") }  // "Allow camera access in Settings to take a photo or video."
        public static var cameraDeniedTitle: String { tr("uploads.cameraDeniedTitle") }  // "Camera access needed"
        public static var cancelAll: String { tr("uploads.cancelAll") }  // "Cancel all uploads"
        public static var clear: String { tr("uploads.clear") }  // "Clear"
        public static var complete: String { tr("uploads.complete") }  // "Upload complete"
        public static func completeMany(_ a0: CVarArg) -> String { tr("uploads.completeMany", a0) }
        public static func completeWithFailures(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("uploads.completeWithFailures", a0, a1) }
        public static var destinationConfirm: String { tr("uploads.destinationConfirm") }  // "Upload here"
        public static var destinationTitle: String { tr("uploads.destinationTitle") }  // "Upload to…"
        public static var discardConfirm: String { tr("uploads.discardConfirm") }  // "Discard"
        public static var discardMessage: String { tr("uploads.discardMessage") }  // "The files you added won't be uploaded."
        public static var discardTitle: String { tr("uploads.discardTitle") }  // "Discard upload?"
        public static var emptyList: String { tr("uploads.emptyList") }  // "No uploads yet."
        public static var failedGeneric: String { tr("uploads.failedGeneric") }  // "Couldn't upload this file."
        public static var menuTitle: String { tr("uploads.menuTitle") }  // "Upload"
        public static var navigationTitle: String { tr("uploads.navigationTitle") }  // "Uploads"
        public static func notifyBody(_ a0: CVarArg) -> String { tr("uploads.notifyBody", a0) }
        public static var notifyDone: String { tr("uploads.notifyDone") }  // "Uploads finished"
        public static var retryAll: String { tr("uploads.retryAll") }  // "Retry all"
        public static var reviewAddMore: String { tr("uploads.reviewAddMore") }  // "Add more files"
        public static var reviewChooseFolder: String { tr("uploads.reviewChooseFolder") }  // "Choose a folder"
        public static var reviewInsecureNetworkNotice: String { tr("uploads.reviewInsecureNetworkNotice") }
        public static func reviewPreparing(_ a0: CVarArg) -> String { tr("uploads.reviewPreparing", a0) }
        public static func reviewPreviewFile(_ a0: CVarArg) -> String { tr("uploads.reviewPreviewFile", a0) }
        public static var reviewSectionFiles: String { tr("uploads.reviewSectionFiles") }  // "Files"
        public static var reviewSectionPath: String { tr("uploads.reviewSectionPath") }  // "Path"
        public static var reviewSectionSize: String { tr("uploads.reviewSectionSize") }  // "Total size"
        public static func reviewTitleMany(_ a0: CVarArg) -> String { tr("uploads.reviewTitleMany", a0) }
        public static var reviewTitleOne: String { tr("uploads.reviewTitleOne") }  // "Upload 1 file"
        public static var reviewUploadButton: String { tr("uploads.reviewUploadButton") }  // "Upload"
        public static var stagingFailed: String { tr("uploads.stagingFailed") }  // "Couldn't add those files. Try again."
        public static func stagingSkipped(_ a0: CVarArg) -> String { tr("uploads.stagingSkipped", a0) }
        public static var statusFailed: String { tr("uploads.statusFailed") }  // "Upload failed"
        public static var statusWaiting: String { tr("uploads.statusWaiting") }  // "Waiting"
    }
    public enum UserDetail {
        public static var dangerZoneRemoveUser: String { tr("userDetail.dangerZoneRemoveUser") }  // "Remove User"
        public static var dangerZoneSubtitle: String { tr("userDetail.dangerZoneSubtitle") }
        public static var dangerZoneTitle: String { tr("userDetail.dangerZoneTitle") }  // "Danger Zone"
        public static var directoryPickerFailed: String { tr("userDetail.directoryPickerFailed") }  // "Couldn't list directories."
        public static var directoryPickerGoUp: String { tr("userDetail.directoryPickerGoUp") }  // "Go up one directory"
        public static func directoryPickerOpen(_ a0: CVarArg) -> String { tr("userDetail.directoryPickerOpen", a0) }
        public static var directoryPickerUseThis: String { tr("userDetail.directoryPickerUseThis") }  // "Use This Directory"
        public static var fallbackName: String { tr("userDetail.fallbackName") }  // "User"
        public static func grantAdminMessage(_ a0: CVarArg) -> String { tr("userDetail.grantAdminMessage", a0) }
        public static var grantAdminTitle: String { tr("userDetail.grantAdminTitle") }  // "Grant Admin?"
        public static var passwordHasLocal: String { tr("userDetail.passwordHasLocal") }  // "This user signs in with an email and password."
        public static var passwordReset: String { tr("userDetail.passwordReset") }  // "Reset Password"
        public static var passwordSSOOnly: String { tr("userDetail.passwordSSOOnly") }  // "This user has no local password and signs in with SSO only."
        public static var passwordSet: String { tr("userDetail.passwordSet") }  // "Set Password"
        public static var profileDisplayNameField: String { tr("userDetail.profileDisplayNameField") }  // "Display Name"
        public static var profileDisplayNamePlaceholder: String { tr("userDetail.profileDisplayNamePlaceholder") }  // "Display name"
        public static var profileEmailField: String { tr("userDetail.profileEmailField") }  // "Email"
        public static var profileEmailPlaceholder: String { tr("userDetail.profileEmailPlaceholder") }  // "name@example.com"
        public static var profileSave: String { tr("userDetail.profileSave") }  // "Save Changes"
        public static var profileUsernameField: String { tr("userDetail.profileUsernameField") }  // "Username"
        public static var profileUsernamePlaceholder: String { tr("userDetail.profileUsernamePlaceholder") }  // "Username"
        public static func removeUserMessage(_ a0: CVarArg) -> String { tr("userDetail.removeUserMessage", a0) }
        public static var removeUserTitle: String { tr("userDetail.removeUserTitle") }  // "Remove User?"
        public static func removeVolumeMessage(_ a0: CVarArg) -> String { tr("userDetail.removeVolumeMessage", a0) }
        public static var removeVolumeTitle: String { tr("userDetail.removeVolumeTitle") }  // "Remove Volume?"
        public static var roleAdmin: String { tr("userDetail.roleAdmin") }  // "Administrator"
        public static var roleAdminLocked: String { tr("userDetail.roleAdminLocked") }  // "Administrators can't be demoted from the app."
        public static var roleAdminSubtitle: String { tr("userDetail.roleAdminSubtitle") }  // "Full control over files, shares and users."
        public static var roleGrantAdmin: String { tr("userDetail.roleGrantAdmin") }  // "Grant Admin"
        public static var sectionAssignedVolumes: String { tr("userDetail.sectionAssignedVolumes") }  // "Assigned Volumes"
        public static var sectionGeneralInfo: String { tr("userDetail.sectionGeneralInfo") }  // "General Info"
        public static var sectionLocalPassword: String { tr("userDetail.sectionLocalPassword") }  // "Local Password"
        public static var sectionRoles: String { tr("userDetail.sectionRoles") }  // "Roles & Permissions"
        public static var sectionSSO: String { tr("userDetail.sectionSSO") }  // "Single Sign-On"
        public static var ssoBadge: String { tr("userDetail.ssoBadge") }  // "SSO"
        public static var ssoLinked: String { tr("userDetail.ssoLinked") }  // "Linked"
        public static var ssoNone: String { tr("userDetail.ssoNone") }  // "No linked SSO providers."
        public static func volumeEditAccessibility(_ a0: CVarArg) -> String { tr("userDetail.volumeEditAccessibility", a0) }
        public static func volumeRemoveAccessibility(_ a0: CVarArg) -> String { tr("userDetail.volumeRemoveAccessibility", a0) }
        public static var volumeSheetAccessMode: String { tr("userDetail.volumeSheetAccessMode") }  // "Access Mode"
        public static var volumeSheetDirectory: String { tr("userDetail.volumeSheetDirectory") }  // "Directory"
        public static var volumeSheetLabelField: String { tr("userDetail.volumeSheetLabelField") }  // "Label"
        public static var volumeSheetLabelPlaceholder: String { tr("userDetail.volumeSheetLabelPlaceholder") }  // "Volume label"
        public static var volumeSheetSaveEdit: String { tr("userDetail.volumeSheetSaveEdit") }  // "Save Volume"
        public static var volumeSheetSaveNew: String { tr("userDetail.volumeSheetSaveNew") }  // "Assign Volume"
        public static var volumeSheetTitleEdit: String { tr("userDetail.volumeSheetTitleEdit") }  // "Edit Volume"
        public static var volumeSheetTitleNew: String { tr("userDetail.volumeSheetTitleNew") }  // "Assign Volume"
        public static var volumesAssign: String { tr("userDetail.volumesAssign") }  // "Assign Volume"
        public static var volumesFootnote: String { tr("userDetail.volumesFootnote") }
        public static var volumesNone: String { tr("userDetail.volumesNone") }  // "No volumes assigned."
        public static var volumesNoneSubtitle: String { tr("userDetail.volumesNoneSubtitle") }  // "This user only sees the default shared space."
    }
    public enum UserManagement {
        public static var badgeAdmin: String { tr("userManagement.badgeAdmin") }  // "Admin"
        public static var createEmailField: String { tr("userManagement.createEmailField") }  // "Email"
        public static var createEmailPlaceholder: String { tr("userManagement.createEmailPlaceholder") }  // "name@example.com"
        public static var createGrantAdminSubtitle: String { tr("userManagement.createGrantAdminSubtitle") }  // "Full control over files, shares and users."
        public static var createGrantAdminToggle: String { tr("userManagement.createGrantAdminToggle") }  // "Grant Admin Access"
        public static var createNavigationTitle: String { tr("userManagement.createNavigationTitle") }  // "Create User"
        public static var createPasswordField: String { tr("userManagement.createPasswordField") }  // "Password"
        public static func createPasswordPlaceholder(_ a0: CVarArg) -> String { tr("userManagement.createPasswordPlaceholder", a0) }
        public static var createSubmit: String { tr("userManagement.createSubmit") }  // "Create User"
        public static var createUser: String { tr("userManagement.createUser") }  // "Create User"
        public static var createUsernameField: String { tr("userManagement.createUsernameField") }  // "Username (optional)"
        public static var createUsernamePlaceholder: String { tr("userManagement.createUsernamePlaceholder") }  // "Derived from email"
        public static var emptyList: String { tr("userManagement.emptyList") }  // "No users yet."
        public static var errorEmailInUse: String { tr("userManagement.errorEmailInUse") }  // "Email already in use."
        public static var errorEmailInvalid: String { tr("userManagement.errorEmailInvalid") }  // "Enter a valid email address."
        public static var errorEmailRequired: String { tr("userManagement.errorEmailRequired") }  // "Email is required."
        public static func errorPasswordTooShort(_ a0: CVarArg) -> String { tr("userManagement.errorPasswordTooShort", a0) }
        public static var errorUsernameRequired: String { tr("userManagement.errorUsernameRequired") }  // "Username is required."
        public static var loadFailed: String { tr("userManagement.loadFailed") }  // "Couldn't reach the server."
        public static var navigationTitle: String { tr("userManagement.navigationTitle") }  // "User Management"
        public static func noSearchMatches(_ a0: CVarArg) -> String { tr("userManagement.noSearchMatches", a0) }
        public static var searchPrompt: String { tr("userManagement.searchPrompt") }  // "Search users"
        public static var setPasswordNavigationTitle: String { tr("userManagement.setPasswordNavigationTitle") }  // "Password"
        public static var setPasswordNewField: String { tr("userManagement.setPasswordNewField") }  // "New Password"
        public static func setPasswordPlaceholder(_ a0: CVarArg) -> String { tr("userManagement.setPasswordPlaceholder", a0) }
        public static func setPasswordResetIntro(_ a0: CVarArg) -> String { tr("userManagement.setPasswordResetIntro", a0) }
        public static var setPasswordResetTitle: String { tr("userManagement.setPasswordResetTitle") }  // "Reset Password"
        public static func setPasswordSetIntro(_ a0: CVarArg) -> String { tr("userManagement.setPasswordSetIntro", a0) }
        public static var setPasswordSetTitle: String { tr("userManagement.setPasswordSetTitle") }  // "Set Password"
        public static var sortEmail: String { tr("userManagement.sortEmail") }  // "Email"
        public static var sortName: String { tr("userManagement.sortName") }  // "Name"
        public static var sortType: String { tr("userManagement.sortType") }  // "Type"
        public static var tabProfile: String { tr("userManagement.tabProfile") }  // "Profile"
        public static var tabSecurity: String { tr("userManagement.tabSecurity") }  // "Security"
        public static var tabVolumes: String { tr("userManagement.tabVolumes") }  // "Volumes"
        public static var toastAdminGranted: String { tr("userManagement.toastAdminGranted") }  // "Admin granted"
        public static var toastPasswordUpdated: String { tr("userManagement.toastPasswordUpdated") }  // "Password updated"
        public static var toastProfileUpdated: String { tr("userManagement.toastProfileUpdated") }  // "Profile updated"
        public static var toastUserCreated: String { tr("userManagement.toastUserCreated") }  // "User created"
        public static var toastUserRemoved: String { tr("userManagement.toastUserRemoved") }  // "User removed"
        public static var toastVolumeRemoved: String { tr("userManagement.toastVolumeRemoved") }  // "Volume removed"
        public static var toastVolumeSaved: String { tr("userManagement.toastVolumeSaved") }  // "Volume saved"
    }
    public enum VersionedFiles {
        public static var anyState: String { tr("versionedFiles.anyState") }  // "Any state"
        public static var anyZone: String { tr("versionedFiles.anyZone") }  // "Any volume"
        public static func confirmAllTitle(_ a0: CVarArg) -> String { tr("versionedFiles.confirmAllTitle", a0) }
        public static var confirmDelete: String { tr("versionedFiles.confirmDelete") }  // "Delete"
        public static var confirmMessage: String { tr("versionedFiles.confirmMessage") }  // "Deleted versions cannot be recovered."
        public static func confirmSomeTitle(_ a0: CVarArg) -> String { tr("versionedFiles.confirmSomeTitle", a0) }
        public static var deleteAll: String { tr("versionedFiles.deleteAll") }  // "Delete All Versions"
        public static var deleteFailed: String { tr("versionedFiles.deleteFailed") }
        public static func deleteSelected(_ a0: CVarArg) -> String { tr("versionedFiles.deleteSelected", a0) }
        public static var deleteSelectedNone: String { tr("versionedFiles.deleteSelectedNone") }  // "Tick versions to delete"
        public static var detailFailed: String { tr("versionedFiles.detailFailed") }  // "This history could not be read."
        public static var navigationTitle: String { tr("versionedFiles.navigationTitle") }  // "File Versions"
        public static func newest(_ a0: CVarArg) -> String { tr("versionedFiles.newest", a0) }
        public static var next: String { tr("versionedFiles.next") }  // "Next"
        public static var none: String { tr("versionedFiles.none") }  // "No file has earlier versions."
        public static func pageRange(_ a0: CVarArg, _ a1: CVarArg, _ a2: CVarArg) -> String { tr("versionedFiles.pageRange", a0, a1, a2) }
        public static var previous: String { tr("versionedFiles.previous") }  // "Previous"
        public static var refresh: String { tr("versionedFiles.refresh") }  // "Refresh"
        public static func rowSummary(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("versionedFiles.rowSummary", a0, a1) }
        public static var searchPlaceholder: String { tr("versionedFiles.searchPlaceholder") }  // "A name or a path"
        public static var sortBytes: String { tr("versionedFiles.sortBytes") }  // "Space used"
        public static var sortHeader: String { tr("versionedFiles.sortHeader") }  // "Order by"
        public static var sortNewest: String { tr("versionedFiles.sortNewest") }  // "Most recent"
        public static var sortPath: String { tr("versionedFiles.sortPath") }  // "Path"
        public static var sortVersions: String { tr("versionedFiles.sortVersions") }  // "Number of versions"
        public static var stateHeader: String { tr("versionedFiles.stateHeader") }  // "State"
        public static var stateLive: String { tr("versionedFiles.stateLive") }  // "File still there"
        public static var stateOrphaned: String { tr("versionedFiles.stateOrphaned") }  // "File gone"
        public static var stateTrashed: String { tr("versionedFiles.stateTrashed") }  // "In the trash"
        public static var subtitle: String { tr("versionedFiles.subtitle") }
        public static func summary(_ a0: CVarArg, _ a1: CVarArg, _ a2: CVarArg) -> String { tr("versionedFiles.summary", a0, a1, a2) }
        public static var unavailable: String { tr("versionedFiles.unavailable") }  // "File versions are only available to administrators."
        public static func versionBy(_ a0: CVarArg) -> String { tr("versionedFiles.versionBy", a0) }
        public static var versionPinned: String { tr("versionedFiles.versionPinned") }  // "Pinned"
        public static var versionUnavailable: String { tr("versionedFiles.versionUnavailable") }  // "Unavailable"
        public static var zone: String { tr("versionedFiles.zone") }  // "Volume"
        public static func zoneKindPersonal(_ a0: CVarArg) -> String { tr("versionedFiles.zoneKindPersonal", a0) }
        public static func zoneKindUserVolume(_ a0: CVarArg) -> String { tr("versionedFiles.zoneKindUserVolume", a0) }
        public static var zoneUnknown: String { tr("versionedFiles.zoneUnknown") }  // "Unknown volume"
    }
}

// Looks up through `LocalizationOverride.bundle` so an in-app language switch resolves live
// (it points at the chosen language's compiled `.lproj`); with no override it is `.module`,
// i.e. the system-resolved language. The key itself is the fallback when a language is
// missing an entry, which the String Catalog only fills for `en`.
private func tr(_ key: String) -> String {
    LocalizationOverride.bundle.localizedString(forKey: key, value: key, table: "Localizable")
}

private func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: LocalizationOverride.locale, arguments: arguments)
}
