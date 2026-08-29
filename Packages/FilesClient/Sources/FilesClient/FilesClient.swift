import CoreModels
import DependenciesMacros
import Foundation

@DependencyClient
public struct FilesClient: Sendable {
    public var browse: @Sendable (_ serverURL: URL, _ path: String) async throws -> BrowseResult
    public var search: @Sendable (
        _ serverURL: URL, _ path: String, _ query: String, _ limit: Int?
    ) async throws -> [SearchResultItem]
    public var favorites: @Sendable (_ serverURL: URL) async throws -> [Favorite]
    public var addFavorite: @Sendable (_ serverURL: URL, _ path: String) async throws -> Favorite
    public var removeFavorite: @Sendable (_ serverURL: URL, _ path: String) async throws -> Void
    /// `PATCH /api/favorites/:id` (`backend/src/routes/favorites.js`): updates a favorite's
    /// label, icon and colour. An empty `label`/`color` clears it server side; a blank `icon`
    /// falls back to the server default. Returns the single updated favorite.
    public var updateFavorite: @Sendable (
        _ serverURL: URL, _ id: String, _ label: String?, _ icon: String, _ color: String?
    ) async throws -> Favorite
    /// `PATCH /api/favorites/reorder`: `orderedIDs` must list every favorite exactly once or
    /// the server 400s. Returns the full list in the new order (`position` = index).
    public var reorderFavorites: @Sendable (
        _ serverURL: URL, _ orderedIDs: [String]
    ) async throws -> [Favorite]
    public var volumes: @Sendable (_ serverURL: URL) async throws -> [Volume]
    public var fetchPreferences: @Sendable (_ serverURL: URL) async throws -> UserPreferences
    public var updatePreference: @Sendable (
        _ serverURL: URL, _ key: UserPreferenceKey, _ value: Bool
    ) async throws -> Void
    /// `GET /api/branding` — the server's app name + logo, unauthenticated.
    public var fetchBranding: @Sendable (_ serverURL: URL) async throws -> Branding
    /// `PATCH /api/settings` with `{ branding: {...} }` (admin only; the server 403s a
    /// non-admin). Returns the branding as the server stored it.
    public var updateBranding: @Sendable (
        _ serverURL: URL, _ appName: String, _ appLogoUrl: String
    ) async throws -> Branding
    /// `POST /api/settings/upload-logo` (admin) — one JPEG in a `logo` multipart field,
    /// ≤2 MB. Returns the server-relative URL of the stored logo, to be persisted via
    /// `updateBranding`.
    public var uploadServerLogo: @Sendable (_ serverURL: URL, _ jpegData: Data) async throws -> String
    public var renameItem: @Sendable (
        _ serverURL: URL, _ item: FileItem, _ newName: String
    ) async throws -> FileItem
    /// `POST /api/files/folder` (`backend/src/routes/files/folder.js`): creates a subfolder in
    /// `path`, the parent directory's relative path — the server rejects an empty one ("Cannot
    /// create folders in the root path"). A blank `name` becomes "Untitled Folder" server side
    /// and a name collision is auto suffixed rather than erroring. Returns the created folder.
    public var createFolder: @Sendable (
        _ serverURL: URL, _ path: String, _ name: String
    ) async throws -> FileItem
    /// `POST /api/files/delete-impact`: how many share links deleting `items` would break.
    /// A warning source for the delete confirmation; the delete itself is never gated on it.
    public var deleteImpact: @Sendable (_ serverURL: URL, _ items: [FileItem]) async throws -> DeleteImpact
    public var deleteItems: @Sendable (_ serverURL: URL, _ items: [FileItem]) async throws -> Void
    /// `POST /api/files/copy` or `/api/files/move` depending on `operation`. `destination` is
    /// the target directory's relative path; the server rejects an empty one ("Cannot copy or
    /// move items to the root path").
    public var transferItems: @Sendable (
        _ serverURL: URL, _ items: [FileItem], _ destination: String, _ operation: TransferOperation
    ) async throws -> TransferResult
    public var fetchMetadata: @Sendable (_ serverURL: URL, _ path: String) async throws -> FileMetadata
    /// `GET /api/usage/<path>` (`backend/src/routes/usage.js`): the folder's recursive size
    /// plus the free/total of the filesystem it's on. A denied path comes back all zeros.
    public var fetchUsage: @Sendable (_ serverURL: URL, _ path: String) async throws -> StorageUsage
    /// `GET /api/permissions/<path>` (`backend/src/routes/permissions.js`): the file's raw
    /// `stat` mode plus resolved owner/group. Needs read access to the path.
    public var fetchPermissions: @Sendable (_ serverURL: URL, _ path: String) async throws -> FilePermissions
    /// `POST /api/permissions/chmod`: `mode` is a 3-digit octal string ("755"); `recursive`
    /// applies `chmod -R` when the path is a directory. Guests and non-writers get a 403.
    public var changePermissions: @Sendable (
        _ serverURL: URL, _ path: String, _ mode: String, _ recursive: Bool
    ) async throws -> Void
    /// `POST /api/permissions/chown`: at least one of `owner`/`group`. Usually needs root on
    /// the server, so a 403 "requires root/admin" is the common outcome for a non-root server.
    public var changeOwnership: @Sendable (
        _ serverURL: URL, _ path: String, _ owner: String?, _ group: String?
    ) async throws -> Void
    public var thumbnailURL: @Sendable (_ serverURL: URL, _ path: String) async throws -> URL?
    public var previewFile: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> URL
    public var fetchTextContent: @Sendable (_ serverURL: URL, _ path: String) async throws -> String
    public var saveTextContent: @Sendable (_ serverURL: URL, _ path: String, _ content: String) async throws -> Void
    public var extractZip: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> FileItem
    public var downloadRawFile: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> URL
    /// `POST /api/upload` (`backend/src/routes/upload.js`): one `multipart/form-data` request
    /// per file — `uploadTo` = destination directory, `relativePath` = `fileName`, `filedata` =
    /// the file at `fileURL`. `destination` must not be empty (the server rejects the root).
    /// The request is first assembled into a temporary multipart envelope on disk (one extra
    /// copy of the payload), then streamed from that file, so nothing buffers the whole file
    /// in memory. Reports fractional progress (0...1); returns the server's echo of the stored
    /// file, which may carry an auto-renamed `name` on a collision.
    public var uploadFile: @Sendable (
        _ serverURL: URL,
        _ fileURL: URL,
        _ fileName: String,
        _ destination: String,
        _ onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> FileItem
    public var compressItem: @Sendable (_ serverURL: URL, _ item: FileItem) async throws -> FileItem
    public var createShareLink: @Sendable (
        _ serverURL: URL, _ request: CreateShareLinkRequest
    ) async throws -> CreatedShare
    public var mySharedLinks: @Sendable (_ serverURL: URL) async throws -> [Share]
    public var sharedWithMeLinks: @Sendable (_ serverURL: URL) async throws -> [Share]
    /// `PUT /api/shares/:id` (owner only): applies the fields in `request` and returns the
    /// updated share.
    public var updateShareLink: @Sendable (
        _ serverURL: URL, _ shareID: String, _ request: UpdateShareRequest
    ) async throws -> Share
    public var deleteShareLink: @Sendable (_ serverURL: URL, _ shareID: String) async throws -> Void
    /// `GET /api/users/shareable`: every user except the caller, for a user specific share.
    public var shareableUsers: @Sendable (_ serverURL: URL) async throws -> [User]
    /// `GET /api/share/<token>/info` — public metadata for a share link a recipient was sent.
    /// Unauthenticated; a bad token 404s.
    public var resolveShareLink: @Sendable (_ serverURL: URL, _ token: String) async throws -> ShareInfo

    /// `POST /api/onlyoffice/config`: a launch payload for an ONLYOFFICE editing session on
    /// the file at `path`. Server 400s with a message when `PUBLIC_URL` / `ONLYOFFICE_URL`
    /// are unset.
    public var fetchOnlyOfficeConfig: @Sendable (
        _ serverURL: URL, _ path: String, _ mode: OfficeEditorMode
    ) async throws -> OnlyOfficeLaunch
    /// `POST /api/collabora/config`: a ready-to-load Collabora Online iframe URL for the file
    /// at `path`. Server 400s with a message when the Collabora env vars are unset.
    public var fetchCollaboraConfig: @Sendable (
        _ serverURL: URL, _ path: String, _ mode: OfficeEditorMode
    ) async throws -> CollaboraLaunch

    /// `POST /api/auth/password`: the signed in user changes their own local password. Needs
    /// the current password; rate limited server side.
    public var changeOwnPassword: @Sendable (
        _ serverURL: URL, _ currentPassword: String, _ newPassword: String
    ) async throws -> Void

    // MARK: Admin user management (all require the caller to have the `admin` role)

    /// `GET /api/features`: the server's feature flags (user volumes, volume usage, office editors).
    public var serverFeatures: @Sendable (_ serverURL: URL) async throws -> ServerFeatures
    /// `GET /api/users`: every user with roles and auth methods.
    public var listUsers: @Sendable (_ serverURL: URL) async throws -> [User]
    /// `POST /api/users`: create a user with a local password.
    public var createUser: @Sendable (_ serverURL: URL, _ request: CreateUserRequest) async throws -> User
    /// `PATCH /api/users/:id`: update profile fields and roles.
    public var updateUser: @Sendable (
        _ serverURL: URL, _ userID: String, _ request: UpdateUserRequest
    ) async throws -> User
    /// `POST /api/users/:id/password`: set a user's local password (no current password needed).
    public var setUserPassword: @Sendable (
        _ serverURL: URL, _ userID: String, _ newPassword: String
    ) async throws -> Void
    /// `DELETE /api/users/:id`: remove a user. The server rejects deleting yourself or the last admin.
    public var deleteUser: @Sendable (_ serverURL: URL, _ userID: String) async throws -> Void

    // MARK: Admin per user volumes (also require the `USER_VOLUMES` feature)

    /// `GET /api/users/:id/volumes`.
    public var userVolumes: @Sendable (_ serverURL: URL, _ userID: String) async throws -> [UserVolume]
    /// `POST /api/users/:id/volumes`.
    public var addUserVolume: @Sendable (
        _ serverURL: URL, _ userID: String, _ request: AddUserVolumeRequest
    ) async throws -> UserVolume
    /// `PATCH /api/users/:id/volumes/:volumeID`: label and access mode.
    public var updateUserVolume: @Sendable (
        _ serverURL: URL, _ userID: String, _ volumeID: String, _ label: String?, _ accessMode: ShareAccessMode
    ) async throws -> UserVolume
    /// `DELETE /api/users/:id/volumes/:volumeID`.
    public var removeUserVolume: @Sendable (
        _ serverURL: URL, _ userID: String, _ volumeID: String
    ) async throws -> Void
    /// `GET /api/admin/browse-directories?path=`: directory picker for assigning a volume.
    public var browseAdminDirectories: @Sendable (
        _ serverURL: URL, _ path: String?
    ) async throws -> AdminDirectoryListing
}

extension FilesClient {
    /// The same `GET /api/preview?path=...` URL `previewFile` downloads, exposed as a plain
    /// synchronous URL for streamable media (video/audio): `AVPlayer` can play it directly,
    /// using the server's existing HTTP Range support for seeking, without buffering the
    /// whole file into memory first the way a full download would.
    public static func previewURL(serverURL: URL, item: FileItem) -> URL? {
        var components = URLComponents(url: serverURL.appendingPathComponent(APIPath.preview), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: QueryKey.path, value: item.id)]
        return components?.url
    }

    /// `GET /api/raw?path=...` — the file served verbatim (`text/plain`, `nosniff`). Handed to
    /// Safari for "Open in Browser": the server has no rendered-HTML endpoint, and cookie auth
    /// means Safari may hit a login page first (or 401 if the server requires auth).
    public static func rawFileURL(serverURL: URL, item: FileItem) -> URL? {
        var components = URLComponents(url: serverURL.appendingPathComponent(APIPath.raw), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: QueryKey.path, value: item.id)]
        return components?.url
    }
}
