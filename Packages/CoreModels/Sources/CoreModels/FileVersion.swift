import Foundation

/// Response from `GET /api/versions?path=`, confirmed against `backend/src/routes/versions.js`
/// and `services/versions/index.js` (`listVersions`): the file's saved versions, newest first,
/// and what the caller may do with them.
public struct FileVersionHistory: Decodable, Equatable, Sendable {
    /// Whether the server keeps versions at all (`versions.enabled` in its settings).
    public let enabled: Bool
    public let versions: [FileVersion]
    public let totalBytes: Int64
    public let rights: Rights

    public struct Rights: Decodable, Equatable, Sendable {
        public let see: Bool
        public let download: Bool
        public let restore: Bool
        public let remove: Bool

        public init(see: Bool, download: Bool, restore: Bool, remove: Bool) {
            self.see = see
            self.download = download
            self.restore = restore
            self.remove = remove
        }
    }

    public init(enabled: Bool, versions: [FileVersion], totalBytes: Int64, rights: Rights) {
        self.enabled = enabled
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
    public let pinned: Bool
    /// `false` once the storage holding it is gone; `nil` when the server didn't say.
    public let available: Bool?

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
        pinned: Bool = false,
        available: Bool? = true
    ) {
        self.id = id
        self.size = size
        self.modifiedAt = modifiedAt
        self.capturedAt = capturedAt
        self.author = author
        self.label = label
        self.pinned = pinned
        self.available = available
    }
}
