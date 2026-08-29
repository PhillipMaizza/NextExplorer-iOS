import Foundation

/// Whether a share grants write access. Mirrors the server's `access_mode`
/// (`['readonly', 'readwrite']`) — confirmed against `backend/src/services/sharesService.js`.
public enum ShareAccessMode: String, Codable, Sendable, CaseIterable, Hashable {
    case readonly
    case readwrite
}

/// Who a share is for. Mirrors the server's `sharing_type` (`['anyone', 'users']`).
public enum ShareTarget: String, Codable, Sendable, CaseIterable, Hashable {
    case anyone
    case users
}

/// Presentation mode for a share's direct link (`?mode=`). A file streams; a folder comes
/// back as a ZIP. `inline` is shown as "View" in the UI, matching the web client's
/// `DIRECT_SHARE_FILE_MODES`.
public enum DirectLinkMode: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case auto
    case inline
    case raw
    case download

    public var id: String { rawValue }
}

/// One row from `GET /api/shares` (shared by me) or `GET /api/shares/shared-with-me`
/// (shared with me). Confirmed against `sharesService.js`'s `toClientShare`: the
/// shared-with-me variant drops `sourcePath`/`sourceSpace` and adds `sourceName` (leaf only).
public struct Share: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let shareToken: String
    public let ownerId: String
    /// Present only in the shared-by-me list.
    public let sourcePath: String?
    /// Present only in the shared-with-me list (leaf folder/file name).
    public let sourceName: String?
    public let isDirectory: Bool
    public let accessMode: ShareAccessMode
    public let sharingType: ShareTarget
    public let hasPassword: Bool
    public let expiresAt: Date?
    public let label: String?
    public let downloadCount: Int
    public let lastAccessedAt: Date?
    /// The users a `.users` share is granted to — the owner-side lists (`GET /api/shares`,
    /// `GET /api/shares/:id`) add this; nil for `.anyone` shares and the recipient list.
    public let permittedUserIds: [String]?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        shareToken: String,
        ownerId: String,
        sourcePath: String? = nil,
        sourceName: String? = nil,
        isDirectory: Bool,
        accessMode: ShareAccessMode,
        sharingType: ShareTarget,
        hasPassword: Bool,
        expiresAt: Date? = nil,
        label: String? = nil,
        downloadCount: Int = 0,
        lastAccessedAt: Date? = nil,
        permittedUserIds: [String]? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.shareToken = shareToken
        self.ownerId = ownerId
        self.sourcePath = sourcePath
        self.sourceName = sourceName
        self.isDirectory = isDirectory
        self.accessMode = accessMode
        self.sharingType = sharingType
        self.hasPassword = hasPassword
        self.expiresAt = expiresAt
        self.label = label
        self.downloadCount = downloadCount
        self.lastAccessedAt = lastAccessedAt
        self.permittedUserIds = permittedUserIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, shareToken, ownerId, sourcePath, sourceName, isDirectory, accessMode
        case sharingType, hasPassword, expiresAt, label, downloadCount, lastAccessedAt
        case permittedUserIds, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        shareToken = try container.decode(String.self, forKey: .shareToken)
        ownerId = try Self.decodeStringOrInt(container, forKey: .ownerId)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        accessMode = try container.decode(ShareAccessMode.self, forKey: .accessMode)
        sharingType = try container.decode(ShareTarget.self, forKey: .sharingType)
        hasPassword = try container.decode(Bool.self, forKey: .hasPassword)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        downloadCount = try container.decodeIfPresent(Int.self, forKey: .downloadCount) ?? 0
        lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt)
        permittedUserIds = try container.decodeIfPresent([String].self, forKey: .permittedUserIds)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// `owner_id` follows the same unconfirmed int-vs-string shape as `User.id`.
    private static func decodeStringOrInt(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> String {
        if let stringValue = try? container.decode(String.self, forKey: key) { return stringValue }
        return String(try container.decode(Int.self, forKey: key))
    }

    /// Explicit label, else the recipient-only leaf name, else the last component of the
    /// owner-side path, else the token.
    public var displayName: String {
        if let label, !label.isEmpty { return label }
        if let sourceName, !sourceName.isEmpty { return sourceName }
        if let leaf = sourcePath?.split(separator: "/").last { return String(leaf) }
        return shareToken
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

/// The `POST /api/shares` 201 body: the new `Share` flattened together with the two
/// resolved URLs the server builds from `PUBLIC_URL` (or the request host).
public struct CreatedShare: Equatable, Sendable, Decodable {
    public let share: Share
    public let shareUrl: URL
    public let directFileUrl: URL

    public init(share: Share, shareUrl: URL, directFileUrl: URL) {
        self.share = share
        self.shareUrl = shareUrl
        self.directFileUrl = directFileUrl
    }

    private enum CodingKeys: String, CodingKey {
        case shareUrl, directFileUrl
    }

    public init(from decoder: Decoder) throws {
        share = try Share(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shareUrl = try container.decode(URL.self, forKey: .shareUrl)
        directFileUrl = try container.decode(URL.self, forKey: .directFileUrl)
    }

    /// `directFileUrl` is the `auto` variant; other modes append `?mode=`.
    public func directLink(mode: DirectLinkMode) -> URL {
        guard mode != .auto else { return directFileUrl }
        var components = URLComponents(url: directFileUrl, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        return components?.url ?? directFileUrl
    }
}

/// Body for `POST /api/shares`. `userIds` is only sent when `target == .users`; the server
/// ignores it otherwise. `expiresAt` must be in the future or the server 400s.
public struct CreateShareLinkRequest: Equatable, Sendable {
    public var sourcePath: String
    public var label: String?
    public var accessMode: ShareAccessMode
    public var target: ShareTarget
    public var password: String?
    public var userIds: [String]
    public var expiresAt: Date?

    public init(
        sourcePath: String,
        label: String? = nil,
        accessMode: ShareAccessMode = .readonly,
        target: ShareTarget = .anyone,
        password: String? = nil,
        userIds: [String] = [],
        expiresAt: Date? = nil
    ) {
        self.sourcePath = sourcePath
        self.label = label
        self.accessMode = accessMode
        self.target = target
        self.password = password
        self.userIds = userIds
        self.expiresAt = expiresAt
    }
}

/// Body for `PUT /api/shares/:id` (`backend/src/routes/shares.js` → `sharesService.updateShare`).
/// The server applies each key that's present (`'key' in body`) and leaves the rest, so the
/// only field that needs care is the password: sending a string sets a new one, `null` removes
/// it, and *omitting the key* keeps whatever's already there — the current value can't be read
/// back (only a hash exists server side).
public struct UpdateShareRequest: Equatable, Sendable {
    public var label: String?
    public var accessMode: ShareAccessMode
    public var target: ShareTarget
    public var expiresAt: Date?
    /// Only sent when `target == .users`; the server ignores it otherwise.
    public var userIds: [String]
    public var password: PasswordChange

    public enum PasswordChange: Equatable, Sendable {
        /// Don't touch the current password — the `password` key is left out entirely.
        case keep
        /// Clear the password — sends `password: null`.
        case remove
        /// Replace it — sends `password: "<value>"`.
        case set(String)
    }

    public init(
        label: String? = nil,
        accessMode: ShareAccessMode = .readonly,
        target: ShareTarget = .anyone,
        expiresAt: Date? = nil,
        userIds: [String] = [],
        password: PasswordChange = .keep
    ) {
        self.label = label
        self.accessMode = accessMode
        self.target = target
        self.expiresAt = expiresAt
        self.userIds = userIds
        self.password = password
    }
}
