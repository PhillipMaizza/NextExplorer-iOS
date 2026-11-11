import Foundation

/// Server-side thumbnail generation config from `GET /api/settings` (admin only). Controls
/// how `GET /api/thumbnails/*` builds images for every client. Verified against
/// `backend/src/services/settingsService.js` `sanitizeThumbnails`.
public struct ThumbnailSettings: Equatable, Sendable, Decodable {
    public var isEnabled: Bool
    /// Longest edge of a generated thumbnail, in pixels.
    public var size: Int
    /// JPEG quality, 1 to 100.
    public var quality: Int
    /// How many thumbnails the server builds concurrently.
    public var concurrency: Int

    public static let sizeRange = 64 ... 1024
    public static let qualityRange = 1 ... 100
    public static let concurrencyRange = 1 ... 50

    public init(isEnabled: Bool = true, size: Int = 200, quality: Int = 70, concurrency: Int = 10) {
        self.isEnabled = isEnabled
        self.size = size
        self.quality = quality
        self.concurrency = concurrency
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, size, quality, concurrency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ThumbnailSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.isEnabled
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? defaults.size
        quality = try container.decodeIfPresent(Int.self, forKey: .quality) ?? defaults.quality
        concurrency = try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? defaults.concurrency
    }
}

/// One path-scoped access override from `GET /api/settings`'s `access.rules` (admin only).
/// The server applies these on top of filesystem permissions. Verified against
/// `sanitizeAccessRules` in `backend/src/services/settingsService.js`.
public struct AccessRule: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var path: String
    public var isRecursive: Bool
    public var permission: Permission

    public enum Permission: String, CaseIterable, Sendable, Codable {
        case readWrite = "rw"
        case readOnly = "ro"
        case hidden
    }

    public init(id: String, path: String, isRecursive: Bool, permission: Permission) {
        self.id = id
        self.path = path
        self.isRecursive = isRecursive
        self.permission = permission
    }

    private enum CodingKeys: String, CodingKey {
        case id, path
        case recursive
        case permissions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        isRecursive = try container.decodeIfPresent(Bool.self, forKey: .recursive) ?? false
        permission = try container.decodeIfPresent(Permission.self, forKey: .permissions) ?? .readWrite
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(isRecursive, forKey: .recursive)
        try container.encode(permission, forKey: .permissions)
    }
}

/// The admin-only slice of `GET /api/settings`. Both fields are absent for non-admins, so a
/// nil `thumbnails` / empty `accessRules` means "not available to this user".
public struct SystemSettings: Equatable, Sendable, Decodable {
    public var thumbnails: ThumbnailSettings?
    public var accessRules: [AccessRule]
    public var uploads: UploadSettings?
    public var ffmpeg: FFmpegSettings?
    public var searchIndex: SearchIndexSettings?
    public var folderSize: FolderSizeSettings?
    public var activity: ActivitySettings?
    public var trash: TrashSettings?
    public var versions: VersionsSettings?

    public init(
        thumbnails: ThumbnailSettings? = nil,
        accessRules: [AccessRule] = [],
        uploads: UploadSettings? = nil,
        ffmpeg: FFmpegSettings? = nil,
        searchIndex: SearchIndexSettings? = nil,
        folderSize: FolderSizeSettings? = nil,
        activity: ActivitySettings? = nil,
        trash: TrashSettings? = nil,
        versions: VersionsSettings? = nil
    ) {
        self.thumbnails = thumbnails
        self.accessRules = accessRules
        self.uploads = uploads
        self.ffmpeg = ffmpeg
        self.searchIndex = searchIndex
        self.folderSize = folderSize
        self.activity = activity
        self.trash = trash
        self.versions = versions
    }

    private enum CodingKeys: String, CodingKey {
        case thumbnails, access, uploads, ffmpeg, searchIndex, folderSize, activity, trash, versions
    }

    private struct AccessContainer: Decodable {
        let rules: [AccessRule]?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thumbnails = try container.decodeIfPresent(ThumbnailSettings.self, forKey: .thumbnails)
        let access = try container.decodeIfPresent(AccessContainer.self, forKey: .access)
        accessRules = access?.rules ?? []
        uploads = try container.decodeIfPresent(UploadSettings.self, forKey: .uploads)
        ffmpeg = try container.decodeIfPresent(FFmpegSettings.self, forKey: .ffmpeg)
        searchIndex = try container.decodeIfPresent(SearchIndexSettings.self, forKey: .searchIndex)
        folderSize = try container.decodeIfPresent(FolderSizeSettings.self, forKey: .folderSize)
        activity = try container.decodeIfPresent(ActivitySettings.self, forKey: .activity)
        trash = try container.decodeIfPresent(TrashSettings.self, forKey: .trash)
        versions = try container.decodeIfPresent(VersionsSettings.self, forKey: .versions)
    }
}
