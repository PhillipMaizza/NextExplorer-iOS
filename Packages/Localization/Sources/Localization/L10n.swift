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
        public static var permissionReadOnly: String { tr("accessRules.permissionReadOnly") }  // "Read only"
        public static var permissionReadWrite: String { tr("accessRules.permissionReadWrite") }  // "Read & write"
        public static var recursive: String { tr("accessRules.recursive") }  // "Apply to subfolders"
        public static var remove: String { tr("accessRules.remove") }  // "Remove"
        public static var saveButton: String { tr("accessRules.saveButton") }  // "Save Changes"
        public static var subtitle: String { tr("accessRules.subtitle") }  // "Override read and write access for specific paths."
        public static var unavailable: String { tr("accessRules.unavailable") }  // "Access rules are only available to administrators."
    }
    public enum Archive {
        public static var emptyFolder: String { tr("archive.emptyFolder") }  // "This folder is empty."
        public static var openArchiveFailed: String { tr("archive.openArchiveFailed") }  // "Couldn't open this archive."
        public static var openFailed: String { tr("archive.openFailed") }  // "Couldn't open this file."
        public static var unsupportedFileType: String { tr("archive.unsupportedFileType") }  // "Unsupported file type"
    }
    public enum Browse {
        public static var actionAddToFavorites: String { tr("browse.actionAddToFavorites") }  // "Add to Favorites"
        public static var actionClearClipboard: String { tr("browse.actionClearClipboard") }  // "Clear clipboard"
        public static var actionCompress: String { tr("browse.actionCompress") }  // "Compress"
        public static var actionCopy: String { tr("browse.actionCopy") }  // "Copy"
        public static var actionDelete: String { tr("browse.actionDelete") }  // "Delete"
        public static var actionDownload: String { tr("browse.actionDownload") }  // "Download"
        public static var actionExtract: String { tr("browse.actionExtract") }  // "Extract"
        public static var actionGetInfo: String { tr("browse.actionGetInfo") }  // "Get Info"
        public static var actionMove: String { tr("browse.actionMove") }  // "Move"
        public static var actionNewFolder: String { tr("browse.actionNewFolder") }  // "Create Folder"
        public static var actionOpenInBrowser: String { tr("browse.actionOpenInBrowser") }  // "Open in Browser"
        public static var actionPaste: String { tr("browse.actionPaste") }  // "Paste"
        public static func actionPasteCount(_ a0: CVarArg) -> String { tr("browse.actionPasteCount", a0) }
        public static var actionPasteHere: String { tr("browse.actionPasteHere") }  // "Paste here"
        public static var actionPermissions: String { tr("browse.actionPermissions") }  // "Permissions"
        public static var actionRemoveFromFavorites: String { tr("browse.actionRemoveFromFavorites") }  // "Remove from Favorites"
        public static var actionRename: String { tr("browse.actionRename") }  // "Rename"
        public static var actionShare: String { tr("browse.actionShare") }  // "Create share link"
        public static func clipboardCopiedMany(_ a0: CVarArg) -> String { tr("browse.clipboardCopiedMany", a0) }
        public static func clipboardCopiedOne(_ a0: CVarArg) -> String { tr("browse.clipboardCopiedOne", a0) }
        public static func clipboardCopyCount(_ a0: CVarArg) -> String { tr("browse.clipboardCopyCount", a0) }
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
        public static var navigationTitle: String { tr("browse.navigationTitle") }  // "Browse"
        public static var newFolderConfirm: String { tr("browse.newFolderConfirm") }  // "Create"
        public static var newFolderPlaceholder: String { tr("browse.newFolderPlaceholder") }  // "Folder name"
        public static var newFolderTitle: String { tr("browse.newFolderTitle") }  // "New folder"
        public static var open: String { tr("browse.open") }  // "Open"
        public static var progressCompressing: String { tr("browse.progressCompressing") }  // "Compressing…"
        public static var progressCopying: String { tr("browse.progressCopying") }  // "Copying…"
        public static var progressDownloading: String { tr("browse.progressDownloading") }  // "Downloading…"
        public static func progressDownloadingIndexed(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("browse.progressDownloadingIndexed", a0, a1) }
        public static var progressExtracting: String { tr("browse.progressExtracting") }  // "Extracting…"
        public static var progressMoving: String { tr("browse.progressMoving") }  // "Moving…"
        public static var renameNamePlaceholder: String { tr("browse.renameNamePlaceholder") }  // "Name"
        public static var renameTitle: String { tr("browse.renameTitle") }  // "Rename"
        public static var scopeEverywhere: String { tr("browse.scopeEverywhere") }  // "Everywhere"
        public static var scopeThisFolder: String { tr("browse.scopeThisFolder") }  // "This Folder"
        public static var searchEverywhere: String { tr("browse.searchEverywhere") }  // "Search everywhere"
        public static var searchFailed: String { tr("browse.searchFailed") }  // "Couldn't search. Check your connection and try again."
        public static func searchNoMatchesInFolder(_ a0: CVarArg) -> String { tr("browse.searchNoMatchesInFolder", a0) }
        public static var searchScopeEverywhere: String { tr("browse.searchScopeEverywhere") }  // "Everywhere"
        public static var searchScopeInFolder: String { tr("browse.searchScopeInFolder") }  // "This Folder"
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
        public static func errorMinLength(_ a0: CVarArg) -> String { tr("changePassword.errorMinLength", a0) }
        public static var errorMismatch: String { tr("changePassword.errorMismatch") }  // "Passwords don't match."
        public static var fieldConfirmPassword: String { tr("changePassword.fieldConfirmPassword") }  // "Re-enter new password"
        public static var fieldConfirmPasswordLabel: String { tr("changePassword.fieldConfirmPasswordLabel") }  // "Confirm new password"
        public static var fieldCurrentPassword: String { tr("changePassword.fieldCurrentPassword") }  // "Current password"
        public static var fieldNewPasswordLabel: String { tr("changePassword.fieldNewPasswordLabel") }  // "New password"
        public static func fieldNewPasswordPrompt(_ a0: CVarArg) -> String { tr("changePassword.fieldNewPasswordPrompt", a0) }
        public static var intro: String { tr("changePassword.intro") }
        public static var navigationTitle: String { tr("changePassword.navigationTitle") }  // "Change Password"
        public static var submitButton: String { tr("changePassword.submitButton") }  // "Update Password"
        public static var success: String { tr("changePassword.success") }  // "Your password has been updated."
    }
    public enum Common {
        public static var back: String { tr("common.back") }  // "Back"
        public static var cancel: String { tr("common.cancel") }  // "Cancel"
        public static var clear: String { tr("common.clear") }  // "Clear"
        public static var close: String { tr("common.close") }  // "Close"
        public static var delete: String { tr("common.delete") }  // "Delete"
        public static var done: String { tr("common.done") }  // "Done"
        public static var download: String { tr("common.download") }  // "Download"
        public static var edit: String { tr("common.edit") }  // "Edit"
        public static var logOut: String { tr("common.logOut") }  // "Log Out"
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
    }
    public enum CreateShare {
        public static var createdBanner: String { tr("createShare.createdBanner") }  // "Share link created successfully!"
        public static var directFileLink: String { tr("createShare.directFileLink") }  // "Direct file link"
        public static var directFolderLink: String { tr("createShare.directFolderLink") }  // "Direct folder ZIP link"
        public static var directLinkMode: String { tr("createShare.directLinkMode") }  // "Direct link mode"
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
    public enum DownloadLocation {
        public static var cache: String { tr("downloadLocation.cache") }  // "Cache"
        public static var documents: String { tr("downloadLocation.documents") }  // "Documents"
    }
    public enum Downloads {
        public static var actionOpenInFiles: String { tr("downloads.actionOpenInFiles") }  // "Open in Files"
        public static var deleteBulkMessage: String { tr("downloads.deleteBulkMessage") }
        public static func deleteConfirmMany(_ a0: CVarArg) -> String { tr("downloads.deleteConfirmMany", a0) }
        public static func deleteConfirmOne(_ a0: CVarArg) -> String { tr("downloads.deleteConfirmOne", a0) }
        public static var deleteConfirmTitle: String { tr("downloads.deleteConfirmTitle") }  // "Delete?"
        public static var deleteSingleMessage: String { tr("downloads.deleteSingleMessage") }
        public static var emptyList: String { tr("downloads.emptyList") }  // "Files you download from Browse show up here."
        public static var navigationTitle: String { tr("downloads.navigationTitle") }  // "Downloads"
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
        public static var decoding: String { tr("error.decoding") }  // "Server responded unexpectedly."
        public static var forbidden: String { tr("error.forbidden") }  // "You don't have permission to do that."
        public static var network: String { tr("error.network") }  // "Couldn't reach the server."
        public static var rateLimited: String { tr("error.rateLimited") }  // "Too many requests. Try again shortly."
        public static func server(_ a0: CVarArg) -> String { tr("error.server", a0) }
        public static var sessionExpired: String { tr("error.sessionExpired") }  // "Your session expired. Sign in again."
    }
    public enum Favorites {
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
    public enum FileInfo {
        public static func diskFreeOf(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("fileInfo.diskFreeOf", a0, a1) }
        public static var navigationTitleFolder: String { tr("fileInfo.navigationTitleFolder") }  // "Folder"
        public static var partialScan: String { tr("fileInfo.partialScan") }  // "Counted a partial scan — this folder is very large."
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
        public static var rowTotalSize: String { tr("fileInfo.rowTotalSize") }  // "Total Size"
        public static var sectionServerDisk: String { tr("fileInfo.sectionServerDisk") }  // "Server Disk"
    }
    public enum Gallery {
        public static var loadFailed: String { tr("gallery.loadFailed") }  // "Couldn't load this image."
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
        public static var emailField: String { tr("login.emailField") }  // "Email"
        public static var errorDecoding: String { tr("login.errorDecoding") }
        public static var errorIncomplete: String { tr("login.errorIncomplete") }  // "Sign-in didn't complete. Please try again."
        public static var errorInvalidCredentials: String { tr("login.errorInvalidCredentials") }  // "Incorrect username or password."
        public static var errorInvalidEmail: String { tr("login.errorInvalidEmail") }  // "Enter a valid email address."
        public static var errorInvalidServer: String { tr("login.errorInvalidServer") }  // "Enter a valid server address."
        public static var errorKeychain: String { tr("login.errorKeychain") }  // "Could not save your session on this device."
        public static var errorNoLocalAuth: String { tr("login.errorNoLocalAuth") }  // "This server doesn't have username/password sign-in enabled."
        public static var errorRateLimited: String { tr("login.errorRateLimited") }  // "Too many attempts. Please wait a few minutes and try again."
        public static var errorSessionExpired: String { tr("login.errorSessionExpired") }  // "Your session expired. Please sign in again."
        public static var errorUnexpectedResponse: String { tr("login.errorUnexpectedResponse") }  // "Unexpected response from server."
        public static var errorUnreachable: String { tr("login.errorUnreachable") }
        public static var passwordField: String { tr("login.passwordField") }  // "Password"
        public static var plaintextWarning: String { tr("login.plaintextWarning") }
        public static var portHint: String { tr("login.portHint") }
        public static var serverQuestion: String { tr("login.serverQuestion") }  // "Where's your instance of NextExplorer?"
        public static var submit: String { tr("login.submit") }  // "Log In"
        public static var testConnection: String { tr("login.testConnection") }  // "Test connection"
    }
    public enum OpenShareLink {
        public static var errorExpired: String { tr("openShareLink.errorExpired") }  // "This share link has expired."
        public static var errorInvalidLink: String { tr("openShareLink.errorInvalidLink") }  // "That doesn't look like a share link."
        public static var errorNotFound: String { tr("openShareLink.errorNotFound") }  // "No share found for that link. It may have been removed."
        public static func expiresPrefix(_ a0: CVarArg) -> String { tr("openShareLink.expiresPrefix", a0) }
        public static var fieldLabel: String { tr("openShareLink.fieldLabel") }  // "Share link"
        public static var fieldPrompt: String { tr("openShareLink.fieldPrompt") }  // "Paste a link or code"
        public static var lookUp: String { tr("openShareLink.lookUp") }  // "Look Up"
        public static var open: String { tr("openShareLink.open") }  // "Open"
        public static var passwordProtected: String { tr("openShareLink.passwordProtected") }  // "Password protected"
        public static var restrictedNote: String { tr("openShareLink.restrictedNote") }
        public static var sharedFile: String { tr("openShareLink.sharedFile") }  // "Shared file"
        public static var sharedFolder: String { tr("openShareLink.sharedFolder") }  // "Shared folder"
        public static var title: String { tr("openShareLink.title") }  // "Open a Shared Link"
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
        public static var share: String { tr("previewToolbar.share") }  // "Share"
    }
    public enum Select {
        public static var deselectAll: String { tr("select.deselectAll") }  // "Deselect All"
        public static var gridView: String { tr("select.gridView") }  // "Grid View"
        public static var listView: String { tr("select.listView") }  // "List View"
        public static var selectAll: String { tr("select.selectAll") }  // "Select All"
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
    public enum Settings {
        public static func appVersion(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("settings.appVersion", a0, a1) }
        public static var clearCacheConfirm: String { tr("settings.clearCacheConfirm") }  // "Clear"
        public static var clearCacheMessage: String { tr("settings.clearCacheMessage") }
        public static var clearCacheTitle: String { tr("settings.clearCacheTitle") }  // "Clear Cache?"
        public static var dateFormatNavigationTitle: String { tr("settings.dateFormatNavigationTitle") }  // "Date Format"
        public static var dateFormatShowTime: String { tr("settings.dateFormatShowTime") }  // "Show Time"
        public static var navigationTitle: String { tr("settings.navigationTitle") }  // "Settings"
        public static var removeAllDownloadsConfirm: String { tr("settings.removeAllDownloadsConfirm") }  // "Remove All"
        public static var removeAllDownloadsMessage: String { tr("settings.removeAllDownloadsMessage") }
        public static var removeAllDownloadsTitle: String { tr("settings.removeAllDownloadsTitle") }  // "Remove All Downloads?"
        public static var rowAccessRules: String { tr("settings.rowAccessRules") }  // "Folder Access Rules"
        public static var rowChangePassword: String { tr("settings.rowChangePassword") }  // "Change Password"
        public static var rowClearCache: String { tr("settings.rowClearCache") }  // "Clear Cache"
        public static var rowDateFormat: String { tr("settings.rowDateFormat") }  // "Date Format"
        public static var rowOpenSourceLicenses: String { tr("settings.rowOpenSourceLicenses") }  // "Open Source Licenses"
        public static var rowRemoveAllDownloads: String { tr("settings.rowRemoveAllDownloads") }  // "Remove All Downloads"
        public static var rowServer: String { tr("settings.rowServer") }  // "Server"
        public static var rowThumbnailSize: String { tr("settings.rowThumbnailSize") }  // "Thumbnail Size"
        public static var rowThumbnails: String { tr("settings.rowThumbnails") }  // "Thumbnails"
        public static var rowUserManagement: String { tr("settings.rowUserManagement") }  // "User Management"
        public static var sectionAdmin: String { tr("settings.sectionAdmin") }  // "Admin"
        public static var sectionDisplay: String { tr("settings.sectionDisplay") }  // "Display"
        public static var sectionGeneral: String { tr("settings.sectionGeneral") }  // "General"
        public static var sectionLicenses: String { tr("settings.sectionLicenses") }  // "Licenses"
        public static var sectionServerStorage: String { tr("settings.sectionServerStorage") }  // "Server Storage"
        public static var sectionStorage: String { tr("settings.sectionStorage") }  // "Storage"
        public static var sectionUsers: String { tr("settings.sectionUsers") }  // "Users"
        public static func serverStorageUsed(_ a0: CVarArg, _ a1: CVarArg) -> String { tr("settings.serverStorageUsed", a0, a1) }
        public static var signOutAlertTitle: String { tr("settings.signOutAlertTitle") }  // "Sign Out?"
        public static var signOutButton: String { tr("settings.signOutButton") }  // "Sign Out"
        public static var signOutMessage: String { tr("settings.signOutMessage") }  // "You'll need to sign in again to access your files."
        public static var signingOut: String { tr("settings.signingOut") }  // "Signing Out…"
        public static var storageFootnote: String { tr("settings.storageFootnote") }
        public static var toggleDarkMode: String { tr("settings.toggleDarkMode") }  // "Dark Mode"
        public static var toggleHaptics: String { tr("settings.toggleHaptics") }  // "Haptics"
        public static var toggleKeepClipboard: String { tr("settings.toggleKeepClipboard") }  // "Keep Items After Paste"
        public static var toggleKeepClipboardSubtitle: String { tr("settings.toggleKeepClipboardSubtitle") }
        public static var toggleRemoveArchives: String { tr("settings.toggleRemoveArchives") }  // "Remove Archives After Download"
        public static var toggleRenderHTML: String { tr("settings.toggleRenderHTML") }  // "Render HTML Pages"
        public static var toggleRenderMarkdown: String { tr("settings.toggleRenderMarkdown") }  // "Render Markdown Files"
        public static var toggleShowExtensions: String { tr("settings.toggleShowExtensions") }  // "Show Filename Extensions"
        public static var toggleShowHiddenFiles: String { tr("settings.toggleShowHiddenFiles") }  // "Show Hidden Files"
        public static var toggleShowThumbnails: String { tr("settings.toggleShowThumbnails") }  // "Show Thumbnails"
    }
    public enum ShareTarget {
        public static var anyone: String { tr("shareTarget.anyone") }  // "Anyone with link"
        public static var users: String { tr("shareTarget.users") }  // "Specific users"
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
        public static var settings: String { tr("tab.settings") }  // "Settings"
        public static var shared: String { tr("tab.shared") }  // "Shared"
    }
    public enum TextPreview {
        public static var loadFailed: String { tr("textPreview.loadFailed") }
        public static var saved: String { tr("textPreview.saved") }  // "Saved"
    }
    public enum ThumbnailSettings {
        public static var concurrency: String { tr("thumbnailSettings.concurrency") }  // "Concurrency"
        public static var concurrencyHelp: String { tr("thumbnailSettings.concurrencyHelp") }  // "How many thumbnails the server builds at once."
        public static var enable: String { tr("thumbnailSettings.enable") }  // "Generate thumbnails"
        public static var enableHelp: String { tr("thumbnailSettings.enableHelp") }  // "Turn off to serve full images everywhere instead."
        public static var maxDimension: String { tr("thumbnailSettings.maxDimension") }  // "Max dimension"
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
        public static var directoryPickerUseThis: String { tr("userDetail.directoryPickerUseThis") }  // "Use this directory"
        public static var fallbackName: String { tr("userDetail.fallbackName") }  // "User"
        public static var passwordHasLocal: String { tr("userDetail.passwordHasLocal") }  // "This user signs in with an email and password."
        public static var passwordReset: String { tr("userDetail.passwordReset") }  // "Reset Password"
        public static var passwordSSOOnly: String { tr("userDetail.passwordSSOOnly") }  // "This user has no local password — SSO only."
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
        public static var createGrantAdminToggle: String { tr("userManagement.createGrantAdminToggle") }  // "Grant admin access"
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
        public static var setPasswordNewField: String { tr("userManagement.setPasswordNewField") }  // "New password"
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
}

private func tr(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "Localizable", bundle: .module)
}

private func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: .current, arguments: arguments)
}
