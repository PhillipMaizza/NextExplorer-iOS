/// The caller's permissions on a browsed directory, mirrors the `access` object
/// returned alongside `items` by `GET /api/browse/*` (`backend/src/routes/browse.js`).
public struct FileAccess: Codable, Equatable, Sendable {
    public let canRead: Bool
    public let canWrite: Bool
    public let canUpload: Bool
    public let canDelete: Bool
    public let canShare: Bool
    public let canDownload: Bool

    public init(
        canRead: Bool,
        canWrite: Bool,
        canUpload: Bool,
        canDelete: Bool,
        canShare: Bool,
        canDownload: Bool
    ) {
        self.canRead = canRead
        self.canWrite = canWrite
        self.canUpload = canUpload
        self.canDelete = canDelete
        self.canShare = canShare
        self.canDownload = canDownload
    }
}
