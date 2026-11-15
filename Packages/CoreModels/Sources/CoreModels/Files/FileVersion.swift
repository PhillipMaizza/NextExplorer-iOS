import Foundation

/// Response from `GET /api/versions?path=`, confirmed against `backend/src/routes/versions.js`
/// and `services/versions/index.js` (`listVersions`): the file's saved versions, newest first,
/// and what the caller may do with them.
public struct FileVersionHistory: Decodable, Equatable, Sendable {
    /// Whether the server keeps versions at all (`versions.enabled` in its settings).
    public let isEnabled: Bool
    public let versions: [FileVersion]
    public let totalBytes: Int64
    public let rights: Rights

    private enum CodingKeys: String, CodingKey {
        case versions, totalBytes, rights
        case isEnabled = "enabled"
    }

    public struct Rights: Decodable, Equatable, Sendable {
        public let canSee: Bool
        public let canDownload: Bool
        public let canRestore: Bool
        public let canRemove: Bool

        private enum CodingKeys: String, CodingKey {
            case canSee = "see"
            case canDownload = "download"
            case canRestore = "restore"
            case canRemove = "remove"
        }

        public init(canSee: Bool, canDownload: Bool, canRestore: Bool, canRemove: Bool) {
            self.canSee = canSee
            self.canDownload = canDownload
            self.canRestore = canRestore
            self.canRemove = canRemove
        }
    }

    public init(isEnabled: Bool, versions: [FileVersion], totalBytes: Int64, rights: Rights) {
        self.isEnabled = isEnabled
        self.versions = versions
        self.totalBytes = totalBytes
        self.rights = rights
    }
}

/// One saved version of a file (`presentVersion` on the server).
public struct FileVersion: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let size: Int64
    /// When the file had this content.
    public let modifiedAt: Date
    /// When the server kept it.
    public let capturedAt: Date
    public let author: Author?
    public let label: String?
    public let isPinned: Bool
    /// `false` once the storage holding it is gone; `nil` when the server didn't say.
    public let isAvailable: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, size, modifiedAt, capturedAt, author, label
        case isPinned = "pinned"
        case isAvailable = "available"
    }

    public struct Author: Decodable, Equatable, Sendable {
        public let label: String?

        public init(label: String?) {
            self.label = label
        }
    }

    public init(
        id: String,
        size: Int64,
        modifiedAt: Date,
        capturedAt: Date,
        author: Author? = nil,
        label: String? = nil,
        isPinned: Bool = false,
        isAvailable: Bool? = true
    ) {
        self.id = id
        self.size = size
        self.modifiedAt = modifiedAt
        self.capturedAt = capturedAt
        self.author = author
        self.label = label
        self.isPinned = isPinned
        self.isAvailable = isAvailable
    }
}
