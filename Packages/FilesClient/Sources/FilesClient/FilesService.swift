import CoreModels
import Foundation
import NetworkClient

/// Plain JSON REST calls against NextExplorer's file-browsing endpoints
/// (`/api/browse`, `/api/search`, `/api/favorites`, `/api/volumes`). Auth is
/// implicit: the session cookie captured by `AuthClient` rides along on
/// every request via the shared `HTTPCookieStorage`.
struct FilesService: Sendable {
    let networkClient: NetworkClient

    func browse(serverURL: URL, path: String) async throws -> BrowseResult {
        let url = Self.browseURL(serverURL: serverURL, path: path)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: BrowseResult.self)
    }

    func search(serverURL: URL, path: String, query: String, limit: Int?) async throws -> [SearchResultItem] {
        var components = URLComponents(url: serverURL.appendingPathComponent(APIPath.search), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: QueryKey.query, value: query)]
        if !path.isEmpty {
            queryItems.append(URLQueryItem(name: QueryKey.path, value: path))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: QueryKey.limit, value: String(limit)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw FilesClientError.decoding("Could not build search URL.")
        }
        let request = Self.makeRequest(url: url, method: .get)
        let envelope = try await send(request, decoding: SearchEnvelope.self)
        return envelope.items
    }

    func favorites(serverURL: URL) async throws -> [Favorite] {
        let url = serverURL.appendingPathComponent(APIPath.favorites)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: [Favorite].self)
    }

    func addFavorite(serverURL: URL, path: String) async throws -> Favorite {
        let url = serverURL.appendingPathComponent(APIPath.favorites)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(FavoritePathBody(path: path))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await send(request, decoding: Favorite.self)
    }

    /// `PATCH /api/favorites/:id`, confirmed against `backend/src/services/favoritesService.js`
    /// `updateFavorite`: `{ label, icon, color }` (position left to the reorder endpoint).
    func updateFavorite(serverURL: URL, id: String, label: String?, icon: String, color: String?) async throws -> Favorite {
        let url = serverURL.appendingPathComponent(APIPath.favorites).appendingPathComponent(id)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(UpdateFavoriteBody(label: label, icon: icon, color: color))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await sendReportingMessage(request, decoding: Favorite.self)
    }

    /// `PATCH /api/favorites/reorder`: `{ order: [id, ...] }` — every id, once. Returns the
    /// full list in the new order.
    func reorderFavorites(serverURL: URL, orderedIDs: [String]) async throws -> [Favorite] {
        let url = serverURL.appendingPathComponent(APIPath.favoritesReorder)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(ReorderFavoritesBody(order: orderedIDs))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await sendReportingMessage(request, decoding: [Favorite].self)
    }

    func removeFavorite(serverURL: URL, path: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.favorites)
        var request = Self.makeRequest(url: url, method: .delete)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(FavoritePathBody(path: path))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `POST /api/files/rename`, confirmed against `backend/src/routes/files/rename.js`:
    /// `path` is the item's *parent* directory, `name` its current name — matching `FileItem`'s
    /// own `path`/`name` fields exactly, so the whole item can be forwarded unchanged.
    func renameItem(serverURL: URL, item: FileItem, newName: String) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.filesRename)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(RenameItemBody(path: item.path, name: item.name, newName: newName))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: RenameItemEnvelope.self)
        return envelope.item
    }

    /// `POST /api/files/folder`, confirmed against `backend/src/routes/files/folder.js`: `path`
    /// is the parent directory's relative path (the server 400s an empty one), `name` the new
    /// folder's name. Responds 201 `{ item }` with the created folder, its name possibly
    /// suffixed on a collision.
    func createFolder(serverURL: URL, path: String, name: String) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.filesFolder)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(CreateFolderBody(path: path, name: name))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: CreateFolderEnvelope.self)
        return envelope.item
    }

    /// `GET /api/thumbnails/*`, confirmed against `backend/src/routes/thumbnails.js`: returns
    /// `{ thumbnail: "" }` when thumbnails are disabled server-side or the file's type isn't
    /// thumbnailable, `{ thumbnail: "/static/thumbnails/<hash>.webp" }` once generated (cached
    /// after the first request), or `{ thumbnail: "/api/preview?path=..." }` as a fallback for
    /// images whose thumbnail generation failed. All three are server-relative, resolved
    /// against `serverURL`; an empty string means "no thumbnail," not an error.
    func thumbnailURL(serverURL: URL, path: String) async throws -> URL? {
        var url = serverURL.appendingPathComponent(APIPath.thumbnails)
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        let request = Self.makeRequest(url: url, method: .get)
        let envelope = try await send(request, decoding: ThumbnailEnvelope.self)
        guard !envelope.thumbnail.isEmpty else { return nil }
        return URL(string: envelope.thumbnail, relativeTo: serverURL)?.absoluteURL
    }

    /// `GET /api/preview?path=...`, confirmed against `backend/src/routes/files/preview.js`:
    /// streams the raw file with the correct `Content-Type`. Downloaded whole into memory and
    /// written to a fresh temp subdirectory (not a shared/reused path — two different files
    /// with the same name would otherwise collide) so `QLPreviewController` gets a local file
    /// URL with the right extension for UTI detection.
    /// Cached on disk (`Library/Caches`, survives across launches, purged only under storage
    /// pressure) keyed by the item's own path — not a fresh directory per call — so reopening
    /// the same unchanged file never re-hits the server. Staleness is checked via a small
    /// sidecar recording `dateModified`/`size` at download time: if either differs from the
    /// current `item`, the cache is treated as stale and re-downloaded.
    /// `POST /api/editor` / `PUT /api/editor`, confirmed against `backend/src/routes/editor.js`:
    /// the real text view/edit path for anything `GET /api/preview` won't serve (415s on
    /// everything outside images/RAW/video/audio/pdf) — plain text, markdown, code, config
    /// files. The server itself enforces a size cap (1MB default) and sniffs for binary
    /// content, surfacing either as a plain validation error this maps to `.server(statusCode:)`.
    func fetchTextContent(serverURL: URL, path: String) async throws -> String {
        let url = serverURL.appendingPathComponent(APIPath.editor)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(EditorPathBody(path: path))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: EditorContentEnvelope.self)
        return envelope.content
    }

    func saveTextContent(serverURL: URL, path: String, content: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.editor)
        var request = Self.makeRequest(url: url, method: .put)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(EditorSaveBody(path: path, content: content))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `POST /api/files/zip/extract`, confirmed against `backend/src/routes/zip.js`: unpacks
    /// the archive into a *new* sibling folder (named after the zip, deduped if taken) and
    /// returns that folder as an item — there's no listing-only/peek-inside endpoint, and only
    /// `.zip` is supported server-side (`.rar`/`.7z`/etc. 415 with "Only .zip archives...").
    func extractZip(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.zipExtract)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(ExtractZipBody(path: item.id))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: ExtractZipEnvelope.self)
        return envelope.item
    }

    /// `POST /api/files/zip/compress`, confirmed against `backend/src/routes/zip.js`: zips a
    /// single item (file or directory) into a new sibling archive in its own parent folder,
    /// auto-naming it from the source (`defaultZipNameForItems`) when `name` is omitted.
    func compressItem(serverURL: URL, item: FileItem) async throws -> FileItem {
        let url = serverURL.appendingPathComponent(APIPath.zipCompress)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            let body = CompressItemBody(items: [CompressItemBody.Item(name: item.name, path: item.path)], destination: item.path)
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await send(request, decoding: CompressItemEnvelope.self)
        return envelope.item
    }

    /// `POST /api/shares`, confirmed against `backend/src/routes/shares.js` +
    /// `sharesService.js`. `userIds` is only meaningful when `sharingType == "users"` (the
    /// server ignores it otherwise); `expiresAt` must be a future ISO date or the server 400s.
    /// The 201 body is the share row flattened together with `shareUrl` / `directFileUrl`.
    func createShareLink(serverURL: URL, request: CreateShareLinkRequest) async throws -> CreatedShare {
        let url = serverURL.appendingPathComponent(APIPath.shares)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        let body = CreateShareBody(
            sourcePath: request.sourcePath,
            label: request.label,
            accessMode: request.accessMode.rawValue,
            sharingType: request.target.rawValue,
            password: request.password,
            userIds: request.target == .users ? request.userIds : [],
            expiresAt: request.expiresAt.map(Self.formatShareExpiry)
        )
        do {
            httpRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await send(httpRequest, decoding: CreatedShare.self)
    }

    /// `GET /api/shares` (owner) and `GET /api/shares/shared-with-me` (recipient), both
    /// wrapped `{ shares: [...] }`. The recipient variant omits `sourcePath`/`sourceSpace`
    /// and adds `sourceName`.
    func shareLinks(serverURL: URL, sharedWithMe: Bool) async throws -> [Share] {
        let url = sharedWithMe
            ? serverURL.appendingPathComponent(APIPath.sharesSharedWithMe)
            : serverURL.appendingPathComponent(APIPath.shares)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ShareLinksEnvelope.self).shares
    }

    /// `GET /api/users/shareable`, confirmed against `backend/src/routes/users.js` +
    /// `services/users/management.js`: every user but the caller as
    /// `{id, email, username, displayName}` (no `roles`), wrapped `{ users: [...] }`.
    func shareableUsers(serverURL: URL) async throws -> [User] {
        let url = serverURL.appendingPathComponent(APIPath.usersShareable)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ShareableUsersEnvelope.self).users
    }

    /// `GET /api/share/<token>/info`, confirmed against `backend/src/routes/shares.js`:
    /// unauthenticated public metadata for a share link. The token is a single path segment.
    func resolveShareLink(serverURL: URL, token: String) async throws -> ShareInfo {
        let url = serverURL
            .appendingPathComponent(APIPath.share)
            .appendingPathComponent(token)
            .appendingPathComponent(APIPath.shareInfoComponent)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ShareInfo.self)
    }

    /// `PUT /api/shares/:id`, confirmed against `backend/src/routes/shares.js` +
    /// `sharesService.updateShare`: owner-only, `'key' in body` semantics, returns the
    /// updated share unwrapped.
    func updateShareLink(serverURL: URL, shareID: String, request: UpdateShareRequest) async throws -> Share {
        let url = serverURL.appendingPathComponent(APIPath.shares).appendingPathComponent(shareID)
        var httpRequest = Self.makeRequest(url: url, method: .put)
        httpRequest.setJSONContentType()
        let body = UpdateShareBody(
            label: request.label,
            accessMode: request.accessMode.rawValue,
            sharingType: request.target.rawValue,
            expiresAt: request.expiresAt.map(Self.formatShareExpiry),
            userIds: request.target == .users ? request.userIds : nil,
            password: request.password
        )
        do {
            httpRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await sendReportingMessage(httpRequest, decoding: Share.self)
    }

    /// `DELETE /api/shares/:id` → 204, owner only.
    func deleteShareLink(serverURL: URL, shareID: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.shares).appendingPathComponent(shareID)
        let request = Self.makeRequest(url: url, method: .delete)
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// A fresh formatter per call — `ISO8601DateFormatter` isn't `Sendable`, and this
    /// `struct` is, so it can't be held as a stored static.
    private static func formatShareExpiry(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// `POST /api/auth/password`, verified against `backend/src/routes/auth.js` and
    /// `services/users/localAuth.js` `changeLocalPassword`: `{ currentPassword, newPassword }`
    /// returns 204. The route is rate limited (429) and rejects a wrong current password (401
    /// "Current password is incorrect.") or a password below the minimum length (400).
    func changeOwnPassword(serverURL: URL, currentPassword: String, newPassword: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.changeOwnPassword)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        request.httpBody = try Self.encode(ChangeOwnPasswordBody(
            currentPassword: currentPassword, newPassword: newPassword
        ))
        let (data, response) = try await performSend(request)
        // Unlike every other call, a 401 here is "current password is incorrect", not a dead
        // session, so it must reach the user as its message, not as `.sessionExpired`.
        switch response.statusCode {
        case 200..<300:
            return
        case 429:
            throw FilesClientError.rateLimited
        default:
            if let message = Self.errorMessage(from: data) {
                throw FilesClientError.serverMessage(statusCode: response.statusCode, message: message)
            }
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    // MARK: Admin user management

    /// `GET /api/features`. Every flag section is a `{ enabled: Bool }` object; `ServerFeatures`
    /// only pulls the ones this app acts on.
    func serverFeatures(serverURL: URL) async throws -> ServerFeatures {
        let url = serverURL.appendingPathComponent(APIPath.features)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: ServerFeatures.self)
    }

    /// `GET /api/users` (admin), wrapped `{ users: [...] }`, each with `roles` and `authMethods`.
    func listUsers(serverURL: URL) async throws -> [User] {
        let url = serverURL.appendingPathComponent(APIPath.users)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: UsersEnvelope.self).users
    }

    /// `POST /api/users` (admin) → 201 `{ user }`.
    func createUser(serverURL: URL, request: CreateUserRequest) async throws -> User {
        let url = serverURL.appendingPathComponent(APIPath.users)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(CreateUserBody(
            email: request.email,
            username: request.username,
            password: request.password,
            displayName: request.displayName,
            roles: request.isAdmin ? [UserRole.admin] : []
        ))
        return try await sendReportingMessage(httpRequest, decoding: UserEnvelope.self).user
    }

    /// `PATCH /api/users/:id` (admin) returns `{ user }`. Only the non nil fields of `request`
    /// are sent, matching the server's "update just what's present" behaviour.
    func updateUser(serverURL: URL, userID: String, request: UpdateUserRequest) async throws -> User {
        let url = serverURL.appendingPathComponent(APIPath.users).appendingPathComponent(userID)
        var httpRequest = Self.makeRequest(url: url, method: .patch)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(UpdateUserBody(
            email: request.email,
            username: request.username,
            displayName: request.displayName,
            roles: request.roles
        ))
        return try await sendReportingMessage(httpRequest, decoding: UserEnvelope.self).user
    }

    /// `POST /api/users/:id/password` (admin) → 204.
    func setUserPassword(serverURL: URL, userID: String, newPassword: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.users).appendingPathComponent(userID).appendingPathComponent(APIPath.Component.password)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(NewPasswordBody(newPassword: newPassword))
        let (data, response) = try await performSend(httpRequest)
        try Self.validateReportingMessage(data, response)
    }

    /// `DELETE /api/users/:id` (admin) returns 204. The server rejects deleting yourself or the
    /// last admin, with a message this surfaces verbatim.
    func deleteUser(serverURL: URL, userID: String) async throws {
        let url = serverURL.appendingPathComponent(APIPath.users).appendingPathComponent(userID)
        let request = Self.makeRequest(url: url, method: .delete)
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    // MARK: Admin per user volumes

    /// `GET /api/users/:id/volumes` (admin, `USER_VOLUMES` feature).
    func userVolumes(serverURL: URL, userID: String) async throws -> [UserVolume] {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID)
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: UserVolumesEnvelope.self).volumes
    }

    /// `POST /api/users/:id/volumes` → 201 `{ volume }`.
    func addUserVolume(serverURL: URL, userID: String, request: AddUserVolumeRequest) async throws -> UserVolume {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID)
        var httpRequest = Self.makeRequest(url: url, method: .post)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(AddUserVolumeBody(
            label: request.label,
            path: request.path,
            accessMode: request.accessMode.rawValue
        ))
        return try await sendReportingMessage(httpRequest, decoding: UserVolumeEnvelope.self).volume
    }

    /// `PATCH /api/users/:id/volumes/:volumeID`. The server accepts label and access mode; the
    /// path itself is immutable once assigned.
    func updateUserVolume(
        serverURL: URL, userID: String, volumeID: String, label: String?, accessMode: ShareAccessMode
    ) async throws -> UserVolume {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID).appendingPathComponent(volumeID)
        var httpRequest = Self.makeRequest(url: url, method: .patch)
        httpRequest.setJSONContentType()
        httpRequest.httpBody = try Self.encode(UpdateUserVolumeBody(label: label, accessMode: accessMode.rawValue))
        return try await sendReportingMessage(httpRequest, decoding: UserVolumeEnvelope.self).volume
    }

    /// `DELETE /api/users/:id/volumes/:volumeID` → 204.
    func removeUserVolume(serverURL: URL, userID: String, volumeID: String) async throws {
        let url = Self.userVolumesURL(serverURL: serverURL, userID: userID).appendingPathComponent(volumeID)
        let request = Self.makeRequest(url: url, method: .delete)
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `GET /api/admin/browse-directories?path=`. Omit `path` to start at the server's
    /// configured volume root.
    func browseAdminDirectories(serverURL: URL, path: String?) async throws -> AdminDirectoryListing {
        var components = URLComponents(
            url: serverURL.appendingPathComponent(APIPath.adminBrowseDirectories),
            resolvingAgainstBaseURL: false
        )
        if let path, !path.isEmpty {
            components?.queryItems = [URLQueryItem(name: QueryKey.path, value: path)]
        }
        guard let url = components?.url else { throw FilesClientError.network("Bad URL") }
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: AdminDirectoryListing.self)
    }

    private static func userVolumesURL(serverURL: URL, userID: String) -> URL {
        serverURL
            .appendingPathComponent(APIPath.users)
            .appendingPathComponent(userID)
            .appendingPathComponent(APIPath.Component.volumes)
    }

    private static func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    func previewFile(serverURL: URL, item: FileItem) async throws -> URL {
        let directory = Self.previewCacheDirectory(for: item, namespace: "preview")
        // RAW formats always come back as a JPEG stream (`rawPreviewService`), regardless of
        // the original extension — save with a matching extension or QuickLook's UTI
        // detection (extension-based) tries to render JPEG bytes as e.g. `.nef` and fails.
        let fileName = item.isRawImage ? "\(item.name).jpg" : item.name
        let fileURL = directory.appendingPathComponent(fileName)
        let metaURL = directory.appendingPathComponent(".meta")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let cachedMeta = try? String(contentsOf: metaURL, encoding: .utf8),
           cachedMeta == Self.cacheMetaValue(for: item) {
            return fileURL
        }

        guard let url = FilesClient.previewURL(serverURL: serverURL, item: item) else {
            throw FilesClientError.decoding("Could not build preview URL.")
        }
        let request = Self.makeRequest(url: url, method: .get)
        let (data, response) = try await performSend(request)
        try Self.validate(response)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try Self.cacheMetaValue(for: item).write(to: metaURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// `POST /api/download`, confirmed against `backend/src/routes/files/download.js` mounted
    /// at plain `/api` (not `/api/files`) in `backend/src/routes/index.js` — easy to get wrong
    /// by pattern-matching the file's own path (`routes/files/download.js`) instead of its
    /// actual mount point.
    /// unlike `GET /api/preview`, this isn't restricted to `PREVIEWABLE_EXTENSIONS` — a single
    /// non-directory target streams back as the raw file (`res.download`), whatever its kind.
    /// That's what makes client-side archive browsing (`ZIPFoundation`/`Unrar.swift`) possible
    /// at all: the server has no listing-only endpoint, so the whole archive has to come down
    /// first. Reuses `previewFile`'s cache layout (same staleness key) but under its own
    /// `namespace`, so the two endpoints never share a cache slot for the same item.
    func downloadRawFile(serverURL: URL, item: FileItem) async throws -> URL {
        let directory = Self.previewCacheDirectory(for: item, namespace: "download")
        let fileURL = directory.appendingPathComponent(item.name)
        let metaURL = directory.appendingPathComponent(".meta")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let cachedMeta = try? String(contentsOf: metaURL, encoding: .utf8),
           cachedMeta == Self.cacheMetaValue(for: item) {
            return fileURL
        }

        let url = serverURL.appendingPathComponent(APIPath.download)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(DownloadRawFileBody(path: item.id))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (data, response) = try await performSend(request)
        try Self.validate(response)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            try Self.cacheMetaValue(for: item).write(to: metaURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// `POST /api/upload`, confirmed against `backend/src/routes/upload.js` +
    /// `services/uploadService.js`. One `multipart/form-data` request per file: the text
    /// fields (`uploadTo`, `relativePath`) MUST precede the `filedata` part — multer's custom
    /// storage reads `req.body` inside `_handleFile`, so a file part that arrives first sees an
    /// empty body. The whole request is first written to a temporary multipart envelope on
    /// disk (one extra copy of the payload), then streamed from that file, so the upload never
    /// sits in memory even for large files. Response is a one-element array of the stored file
    /// (auto-renamed on collision).
    func uploadFile(
        serverURL: URL,
        fileURL: URL,
        fileName: String,
        destination: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> FileItem {
        let boundary = "Boundary-\(UUID().uuidString)"
        let envelopeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: envelopeURL) }

        do {
            try Self.writeMultipartEnvelope(
                to: envelopeURL, boundary: boundary, fileURL: fileURL,
                fileName: fileName, destination: destination
            )
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }

        var request = Self.makeRequest(url: serverURL.appendingPathComponent(APIPath.upload), method: .post)
        request.setValue(MIMEType.multipartFormData(boundary: boundary), forHTTPHeaderField: HTTPHeaderField.contentType)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await networkClient.upload(request, envelopeURL, onProgress)
        } catch {
            throw FilesClientError.network(String(describing: error))
        }
        try Self.validateReportingMessage(data, response)

        let uploaded: [FileItem]
        do {
            uploaded = try Self.makeDecoder().decode([FileItem].self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        guard let file = uploaded.first else {
            throw FilesClientError.decoding("Upload response was empty.")
        }
        return file
    }

    private static func writeMultipartEnvelope(
        to url: URL, boundary: String, fileURL: URL, fileName: String, destination: String
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        func writeField(_ name: String, _ value: String) throws {
            let part = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
            try handle.write(contentsOf: Data(part.utf8))
        }

        try writeField(MultipartField.uploadDestination, destination)
        try writeField(MultipartField.relativePath, fileName)

        // The server takes the stored name from the `relativePath` field, not this header, but
        // a raw `"` or CR/LF here would still break the multipart framing.
        let headerFileName = fileName
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(MultipartField.fileData)\"; filename=\"\(headerFileName)\"\r\nContent-Type: \(MIMEType.octetStream)\r\n\r\n"
        try handle.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while case let chunk = input.readData(ofLength: 1_048_576), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    /// One subdirectory per item path (slashes swapped out so it's a single valid path
    /// component) — distinct files that happen to share a name never collide, since they
    /// have distinct full paths. `namespace` keeps `previewFile` (`GET /api/preview`) and
    /// `downloadRawFile` (`POST /api/download`) from ever sharing a cache entry for the same
    /// item — two different endpoints, nothing guarantees they'll always serve identical bytes
    /// for every kind that happens to use both (RAW images already diverge one direction).
    private static func previewCacheDirectory(for item: FileItem, namespace: String) -> URL {
        let cachesDirectory = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let key = item.id.replacingOccurrences(of: "/", with: "_")
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    private static func cacheMetaValue(for item: FileItem) -> String {
        "\(item.dateModified.timeIntervalSince1970)|\(item.size)"
    }

    /// `GET /api/metadata/*`, confirmed against `backend/src/routes/metadata.js`: a single
    /// wildcard path segment covering the item's full logical path (parent + name), same
    /// percent-encoding-per-segment approach as `browseURL`.
    func fetchMetadata(serverURL: URL, path: String) async throws -> FileMetadata {
        var url = serverURL.appendingPathComponent(APIPath.metadata)
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: FileMetadata.self)
    }

    /// `GET /api/usage/*`, confirmed against `backend/src/routes/usage.js`: one wildcard path
    /// segment (empty = the root, needs the trailing slash), same per-segment encoding as
    /// `browseURL` / `fetchMetadata`.
    func fetchUsage(serverURL: URL, path: String) async throws -> StorageUsage {
        var url = serverURL.appendingPathComponent(APIPath.usage)
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        if segments.isEmpty {
            url = url.appendingPathComponent("")
        } else {
            for segment in segments {
                url = url.appendingPathComponent(String(segment))
            }
        }
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: StorageUsage.self)
    }

    /// `GET /api/permissions/*`, confirmed against `backend/src/routes/permissions.js`: one
    /// wildcard path segment, same per-segment encoding as `fetchMetadata` / `fetchUsage`. A
    /// denied path 403s with the server's denial reason, worth surfacing verbatim.
    func fetchPermissions(serverURL: URL, path: String) async throws -> FilePermissions {
        var url = serverURL.appendingPathComponent(APIPath.permissions)
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        let request = Self.makeRequest(url: url, method: .get)
        return try await sendReportingMessage(request, decoding: FilePermissions.self)
    }

    /// `POST /api/permissions/chmod`: `{ path, mode, recursive }`. The server enforces
    /// `mode` matching `/^[0-7]{3}$/`; `recursive` only does anything on a directory.
    func changePermissions(serverURL: URL, path: String, mode: String, recursive: Bool) async throws {
        let url = serverURL.appendingPathComponent(APIPath.permissionsChmod)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(ChmodBody(path: path, mode: mode, recursive: recursive))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `POST /api/permissions/chown`: `{ path, owner?, group? }` — a nil field is omitted, and
    /// the server rejects a body carrying neither.
    func changeOwnership(serverURL: URL, path: String, owner: String?, group: String?) async throws {
        let url = serverURL.appendingPathComponent(APIPath.permissionsChown)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(ChownBody(path: path, owner: owner, group: group))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
    }

    /// `POST /api/files/delete-impact`, confirmed against `backend/src/routes/files/delete.js`
    /// and `fileTransferService.getDeleteImpact`: same `{path, name, kind}` item shape as the
    /// delete itself, answering with the count of share links that deleting those items would
    /// break. Used to warn before the fact; the delete still enforces regardless.
    func deleteImpact(serverURL: URL, items: [FileItem]) async throws -> DeleteImpact {
        let url = serverURL.appendingPathComponent(APIPath.filesDeleteImpact)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(path: $0.path, name: $0.name, kind: $0.kind) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await send(request, decoding: DeleteImpact.self)
    }

    /// `DELETE /api/files`, confirmed against `backend/src/routes/files/delete.js` and
    /// `fileTransferService.resolveDeleteTargets`: each item is `{path, name}` — again exactly
    /// `FileItem`'s own fields, `kind` included as the server's fallback for already-missing items.
    func deleteItems(serverURL: URL, items: [FileItem]) async throws {
        let url = serverURL.appendingPathComponent(APIPath.files)
        var request = Self.makeRequest(url: url, method: .delete)
        request.setJSONContentType()
        do {
            let body = DeleteItemsBody(items: items.map { DeleteItemsBody.Item(path: $0.path, name: $0.name, kind: $0.kind) })
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `POST /api/files/copy` and `POST /api/files/move`, confirmed against
    /// `backend/src/routes/files/transfer.js` and `services/fileTransferService.js`:
    /// `{ items: [{ path, name }], destination }` — `path`/`name` are `FileItem`'s own fields,
    /// same as rename/delete. Name collisions in the destination are resolved server side
    /// (`findAvailableName`). A validation failure (empty destination, source missing, a
    /// folder moved into itself) comes back with a message worth surfacing verbatim.
    func transferItems(
        serverURL: URL, items: [FileItem], destination: String, operation: TransferOperation
    ) async throws -> TransferResult {
        let endpoint = operation == .copy ? "api/files/copy" : "api/files/move"
        let url = serverURL.appendingPathComponent(endpoint)
        var request = Self.makeRequest(url: url, method: .post)
        request.setJSONContentType()
        do {
            let body = TransferItemsBody(
                items: items.map { TransferItemsBody.Item(path: $0.path, name: $0.name) },
                destination: destination
            )
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        return try await sendReportingMessage(request, decoding: TransferResult.self)
    }

    func volumes(serverURL: URL) async throws -> [Volume] {
        let url = serverURL.appendingPathComponent(APIPath.volumes)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: [Volume].self)
    }

    func fetchPreferences(serverURL: URL) async throws -> UserPreferences {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        let request = Self.makeRequest(url: url, method: .get)
        let envelope = try await send(request, decoding: SettingsEnvelope.self)
        return envelope.user ?? UserPreferences()
    }

    func updatePreference(serverURL: URL, key: UserPreferenceKey, value: Bool) async throws {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            request.httpBody = try JSONEncoder().encode(PatchPreferencesBody(user: [key.rawValue: value]))
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let (_, response) = try await performSend(request)
        try Self.validate(response)
    }

    /// `GET /api/settings` — extracts the admin-only `thumbnails` + `access.rules`. A
    /// non-admin session just gets no such keys, decoded as nil / empty.
    func fetchSystemSettings(serverURL: URL) async throws -> SystemSettings {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: SystemSettings.self)
    }

    /// `PATCH /api/settings` with a full `{ thumbnails: {...} }` object; the server clamps
    /// each field and echoes `getSettingsForUser`, out of which `thumbnails` is read.
    func updateThumbnailSettings(serverURL: URL, settings: ThumbnailSettings) async throws -> ThumbnailSettings {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            let body = PatchThumbnailsBody(thumbnails: .init(
                enabled: settings.isEnabled,
                size: settings.size,
                quality: settings.quality,
                concurrency: settings.concurrency
            ))
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let echoed = try await sendReportingMessage(request, decoding: SystemSettings.self)
        guard let thumbnails = echoed.thumbnails else {
            throw FilesClientError.decoding("Settings response carried no thumbnails.")
        }
        return thumbnails
    }

    /// `PATCH /api/settings` with `{ access: { rules: [...] } }`; the whole array replaces the
    /// stored rules. The echo's `access.rules` is the server-normalised result.
    func updateAccessRules(serverURL: URL, rules: [AccessRule]) async throws -> [AccessRule] {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            let body = PatchAccessBody(access: .init(rules: rules))
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let echoed = try await sendReportingMessage(request, decoding: SystemSettings.self)
        return echoed.accessRules
    }

    /// `GET /api/branding` (`backend/src/routes/settings.js`) — unauthenticated, returns the
    /// branding object directly (not enveloped).
    func fetchBranding(serverURL: URL) async throws -> Branding {
        let url = serverURL.appendingPathComponent(APIPath.branding)
        let request = Self.makeRequest(url: url, method: .get)
        return try await send(request, decoding: Branding.self)
    }

    /// `PATCH /api/settings` with `{ branding: { appName, appLogoUrl } }`. The server merges
    /// and echoes back `getSettingsForUser`, out of which the `branding` object is read.
    func updateBranding(serverURL: URL, appName: String, appLogoUrl: String) async throws -> Branding {
        let url = serverURL.appendingPathComponent(APIPath.settings)
        var request = Self.makeRequest(url: url, method: .patch)
        request.setJSONContentType()
        do {
            let body = PatchBrandingBody(branding: .init(appName: appName, appLogoUrl: appLogoUrl))
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        let envelope = try await sendReportingMessage(request, decoding: SettingsEnvelope.self)
        guard let branding = envelope.branding else {
            throw FilesClientError.decoding("Settings response carried no branding.")
        }
        return branding
    }

    /// `POST /api/settings/upload-logo` — a single `logo` multipart part. The whole payload is
    /// small (≤2 MB, enforced client and server side), so the envelope is built in memory
    /// rather than streamed from disk like `uploadFile`.
    func uploadServerLogo(serverURL: URL, jpegData: Data) async throws -> String {
        let url = serverURL.appendingPathComponent(APIPath.uploadLogo)
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = Self.makeRequest(url: url, method: .post)
        request.setValue(MIMEType.multipartFormData(boundary: boundary), forHTTPHeaderField: HTTPHeaderField.contentType)

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(MultipartField.logo)\"; filename=\"logo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: \(MIMEType.jpeg)\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let envelope = try await sendReportingMessage(request, decoding: LogoUploadEnvelope.self)
        return envelope.logoUrl
    }

    private struct SearchEnvelope: Decodable {
        let items: [SearchResultItem]
    }

    private struct ThumbnailEnvelope: Decodable {
        let thumbnail: String
    }

    private struct EditorPathBody: Encodable {
        let path: String
    }

    private struct EditorContentEnvelope: Decodable {
        let content: String
    }

    private struct EditorSaveBody: Encodable {
        let path: String
        let content: String
    }

    /// `GET /api/settings` / the `PATCH` echo. Only `user` and `branding` are decoded;
    /// the admin-only `thumbnails`/`access` objects aren't modeled by this client.
    private struct SettingsEnvelope: Decodable {
        let user: UserPreferences?
        let branding: Branding?
    }

    private struct PatchPreferencesBody: Encodable {
        let user: [String: Bool]
    }

    private struct PatchBrandingBody: Encodable {
        struct Branding: Encodable {
            let appName: String
            let appLogoUrl: String
        }
        let branding: Branding
    }

    private struct PatchThumbnailsBody: Encodable {
        struct Thumbnails: Encodable {
            let enabled: Bool
            let size: Int
            let quality: Int
            let concurrency: Int
        }
        let thumbnails: Thumbnails
    }

    private struct PatchAccessBody: Encodable {
        struct Access: Encodable {
            let rules: [AccessRule]
        }
        let access: Access
    }

    private struct LogoUploadEnvelope: Decodable {
        let logoUrl: String
    }

    private struct FavoritePathBody: Encodable {
        let path: String
    }

    /// All three keys are always written — `null` included — so the server (which skips
    /// `undefined` keys) actually clears a removed label or colour rather than keeping the old one.
    private struct UpdateFavoriteBody: Encodable {
        let label: String?
        let icon: String
        let color: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(icon, forKey: .icon)
            try container.encode(color, forKey: .color)
        }

        enum CodingKeys: String, CodingKey { case label, icon, color }
    }

    private struct ReorderFavoritesBody: Encodable {
        let order: [String]
    }

    private struct RenameItemBody: Encodable {
        let path: String
        let name: String
        let newName: String
    }

    private struct RenameItemEnvelope: Decodable {
        let item: FileItem
    }

    private struct CreateFolderBody: Encodable {
        let path: String
        let name: String
    }

    private struct CreateFolderEnvelope: Decodable {
        let item: FileItem
    }

    private struct ExtractZipBody: Encodable {
        let path: String
    }

    private struct ExtractZipEnvelope: Decodable {
        let item: FileItem
    }

    private struct CompressItemBody: Encodable {
        struct Item: Encodable {
            let name: String
            let path: String
        }
        let items: [Item]
        let destination: String
    }

    private struct CompressItemEnvelope: Decodable {
        let item: FileItem
    }

    private struct DownloadRawFileBody: Encodable {
        let path: String
    }

    private struct CreateShareBody: Encodable {
        let sourcePath: String
        let label: String?
        let accessMode: String
        let sharingType: String
        let password: String?
        let userIds: [String]
        let expiresAt: String?
    }

    /// Body for `PUT /api/shares/:id`. `label` / `expiresAt` are always written (`null`
    /// included — that's how the server clears them); `userIds` only when it's a users-share;
    /// `password` only when the caller is actually changing or removing it.
    private struct UpdateShareBody: Encodable {
        let label: String?
        let accessMode: String
        let sharingType: String
        let expiresAt: String?
        let userIds: [String]?
        let password: UpdateShareRequest.PasswordChange

        enum CodingKeys: String, CodingKey {
            case label, accessMode, sharingType, expiresAt, userIds, password
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(accessMode, forKey: .accessMode)
            try container.encode(sharingType, forKey: .sharingType)
            try container.encode(expiresAt, forKey: .expiresAt)
            try container.encodeIfPresent(userIds, forKey: .userIds)
            switch password {
            case .keep:
                break
            case .remove:
                try container.encodeNil(forKey: .password)
            case let .set(value):
                try container.encode(value, forKey: .password)
            }
        }
    }

    private struct ShareLinksEnvelope: Decodable {
        let shares: [Share]
    }

    private struct ShareableUsersEnvelope: Decodable {
        let users: [User]
    }

    private struct TransferItemsBody: Encodable {
        struct Item: Encodable {
            let path: String
            let name: String
        }

        let items: [Item]
        let destination: String
    }

    private struct ChmodBody: Encodable {
        let path: String
        let mode: String
        let recursive: Bool
    }

    /// A nil `owner`/`group` is left out by the synthesized encoder (`encodeIfPresent`), which
    /// is exactly what the server wants — it treats a missing key as "leave this unchanged".
    private struct ChownBody: Encodable {
        let path: String
        let owner: String?
        let group: String?
    }

    private struct DeleteItemsBody: Encodable {
        struct Item: Encodable {
            let path: String
            let name: String
            let kind: String
        }

        let items: [Item]
    }

    /// `GET /api/browse/*`. An empty path browses the root and must still end in a
    /// trailing slash (`/api/browse/`); non-empty paths are split and each segment
    /// percent-encoded individually so names containing `/`-unsafe characters survive.
    private static func browseURL(serverURL: URL, path: String) -> URL {
        var url = serverURL.appendingPathComponent(APIPath.browse)
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        if segments.isEmpty {
            return url.appendingPathComponent("")
        }
        for segment in segments {
            url = url.appendingPathComponent(String(segment))
        }
        return url
    }

    private func send<Response: Decodable>(_ request: URLRequest, decoding type: Response.Type) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validate(response)
        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    private func performSend(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await networkClient.send(request)
        } catch {
            throw FilesClientError.network(String(describing: error))
        }
    }

    private static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw FilesClientError.sessionExpired
        case 429:
            throw FilesClientError.rateLimited
        default:
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    private static func makeRequest(url: URL, method: HTTPMethod) -> URLRequest {
        var request = URLRequest(url: url, method: method)
        request.setValue(MIMEType.json, forHTTPHeaderField: HTTPHeaderField.accept)
        return request
    }

    /// Like `send`, but a non 2xx response whose body carries a message becomes
    /// `.serverMessage` rather than a bare `.server(statusCode:)`. The admin user management
    /// endpoints return meaningful validation text ("Email already in use.", etc.).
    private func sendReportingMessage<Response: Decodable>(
        _ request: URLRequest, decoding type: Response.Type
    ) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    private static func validateReportingMessage(_ data: Data, _ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw FilesClientError.sessionExpired
        case 429:
            throw FilesClientError.rateLimited
        default:
            if let message = errorMessage(from: data) {
                throw FilesClientError.serverMessage(statusCode: response.statusCode, message: message)
            }
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    /// NextExplorer's error handler wraps operational errors as `{ error: { message } }`; the
    /// auth middleware uses a bare `{ error: "..." }` string; a few legacy routes use
    /// `{ message }`. Accept all three.
    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object[ErrorBodyKey.error] as? [String: Any], let message = error[ErrorBodyKey.message] as? String {
            return message
        }
        if let error = object[ErrorBodyKey.error] as? String {
            return error
        }
        if let message = object[ErrorBodyKey.message] as? String {
            return message
        }
        return nil
    }

    // MARK: Admin request/response wire types

    private struct UsersEnvelope: Decodable { let users: [User] }
    private struct UserEnvelope: Decodable { let user: User }
    private struct UserVolumesEnvelope: Decodable { let volumes: [UserVolume] }
    private struct UserVolumeEnvelope: Decodable { let volume: UserVolume }

    private struct CreateUserBody: Encodable {
        let email: String
        let username: String?
        let password: String
        let displayName: String?
        let roles: [String]
    }

    private struct UpdateUserBody: Encodable {
        let email: String?
        let username: String?
        let displayName: String?
        let roles: [String]?
    }

    private struct NewPasswordBody: Encodable {
        let newPassword: String
    }

    private struct ChangeOwnPasswordBody: Encodable {
        let currentPassword: String
        let newPassword: String
    }

    private struct AddUserVolumeBody: Encodable {
        let label: String
        let path: String
        let accessMode: String
    }

    private struct UpdateUserVolumeBody: Encodable {
        let label: String?
        let accessMode: String
    }

    /// `dateModified`/`createdAt`/`updatedAt` cross the wire as `Date.toISOString()`
    /// output (millisecond fractional seconds); the default `.iso8601` strategy's
    /// formatter rejects the fractional part, so fractional seconds must be opted in.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { keyedDecoder in
            let container = try keyedDecoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(dateString)")
            }
            return date
        }
        return decoder
    }
}
