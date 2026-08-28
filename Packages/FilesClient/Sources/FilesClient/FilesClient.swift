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
    public var volumes: @Sendable (_ serverURL: URL) async throws -> [Volume]
    public var fetchPreferences: @Sendable (_ serverURL: URL) async throws -> UserPreferences
    public var updatePreference: @Sendable (
        _ serverURL: URL, _ key: UserPreferenceKey, _ value: Bool
    ) async throws -> Void
    public var renameItem: @Sendable (
        _ serverURL: URL, _ item: FileItem, _ newName: String
    ) async throws -> FileItem
    public var deleteItems: @Sendable (_ serverURL: URL, _ items: [FileItem]) async throws -> Void
    /// `POST /api/files/copy` or `/api/files/move` depending on `operation`. `destination` is
    /// the target directory's relative path; the server rejects an empty one ("Cannot copy or
    /// move items to the root path").
    public var transferItems: @Sendable (
        _ serverURL: URL, _ items: [FileItem], _ destination: String, _ operation: TransferOperation
    ) async throws -> TransferResult
    public var fetchMetadata: @Sendable (_ serverURL: URL, _ path: String) async throws -> FileMetadata
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
    public var deleteShareLink: @Sendable (_ serverURL: URL, _ shareID: String) async throws -> Void
    /// `GET /api/users/shareable`: every user except the caller, for a user specific share.
    public var shareableUsers: @Sendable (_ serverURL: URL) async throws -> [User]

    /// `POST /api/auth/password`: the signed in user changes their own local password. Needs
    /// the current password; rate limited server side.
    public var changeOwnPassword: @Sendable (
        _ serverURL: URL, _ currentPassword: String, _ newPassword: String
    ) async throws -> Void

    // MARK: Admin user management (all require the caller to have the `admin` role)

    /// `GET /api/features`: the server's feature flags (currently just user volumes).
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
        var components = URLComponents(url: serverURL.appendingPathComponent("api/preview"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: item.id)]
        return components?.url
    }

    /// `GET /api/raw?path=...` — the file served verbatim (`text/plain`, `nosniff`). Handed to
    /// Safari for "Open in Browser": the server has no rendered-HTML endpoint, and cookie auth
    /// means Safari may hit a login page first (or 401 if the server requires auth).
    public static func rawFileURL(serverURL: URL, item: FileItem) -> URL? {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/raw"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: item.id)]
        return components?.url
    }
}
