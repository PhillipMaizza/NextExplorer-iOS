import Foundation

/// Every server route this client talks to, relative to the server base URL. Kept in one
/// place so a path typo is a compile error, not a 404 at runtime, and so the backend
/// contract is auditable from a single file.
enum APIPath {
    static let browse = "api/browse"
    static let search = "api/search"
    static let favorites = "api/favorites"
    static let favoritesReorder = "api/favorites/reorder"
    static let volumes = "api/volumes"
    static let settings = "api/settings"
    static let branding = "api/branding"
    static let uploadLogo = "api/settings/upload-logo"
    static let features = "api/features"
    static let metadata = "api/metadata"
    static let usage = "api/usage"
    static let permissions = "api/permissions"
    static let permissionsChmod = "api/permissions/chmod"
    static let permissionsChown = "api/permissions/chown"
    static let thumbnails = "api/thumbnails"
    static let preview = "api/preview"
    static let raw = "api/raw"
    static let download = "api/download"
    static let upload = "api/upload"
    static let editor = "api/editor"
    static let changeOwnPassword = "api/auth/password"

    static let shares = "api/shares"
    static let sharesSharedWithMe = "api/shares/shared-with-me"
    /// Guest-facing share routes (`backend/src/routes/shares.js`, also mounted at `/api/share`).
    static let share = "api/share"
    /// Trailing component of `api/share/<token>/info`.
    static let shareInfoComponent = "info"

    static let users = "api/users"
    static let usersShareable = "api/users/shareable"
    static let adminBrowseDirectories = "api/admin/browse-directories"

    static let filesRename = "api/files/rename"
    static let filesFolder = "api/files/folder"
    static let filesDeleteImpact = "api/files/delete-impact"
    static let files = "api/files"
    static let filesCopy = "api/files/copy"
    static let filesMove = "api/files/move"
    static let zipExtract = "api/files/zip/extract"
    static let zipCompress = "api/files/zip/compress"

    /// Trailing components appended to a parent route (`api/users/:id/<component>`).
    enum Component {
        static let password = "password"
        static let volumes = "volumes"
    }
}

/// URL query-item names.
enum QueryKey {
    static let query = "q"
    static let path = "path"
    static let limit = "limit"
}

/// `multipart/form-data` field names.
enum MultipartField {
    static let uploadDestination = "uploadTo"
    static let relativePath = "relativePath"
    static let fileData = "filedata"
    static let logo = "logo"
}

/// Keys read out of a raw JSON error body (`{ "error": { "message": "..." } }` or
/// `{ "message": "..." }`).
enum ErrorBodyKey {
    static let error = "error"
    static let message = "message"
}
