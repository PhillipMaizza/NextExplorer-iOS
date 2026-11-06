/// The caller's permissions on a browsed directory, mirrors the `access` object
/// returned alongside `items` by `GET /api/browse/*` (`backend/src/routes/browse.js`).
public struct FileAccess: Codable, Equatable, Sendable {
    public let canRead: Bool
    public let canWrite: Bool
    public let canUpload: Bool
    public let canDelete: Bool
    public let canShare: Bool
    public let canDownload: Bool
    /// `canCreateFolder` / `canCreateFile`: answered apart from `canUpload`, since a share can
    /// allow uploads and refuse new files or folders (or the other way round), and a read only
    /// mount allows none. A server or a saved listing without them falls back to `canUpload`.
    public let canCreateFolder: Bool
    public let canCreateFile: Bool

    public init(
        canRead: Bool,
        canWrite: Bool,
        canUpload: Bool,
        canDelete: Bool,
        canShare: Bool,
        canDownload: Bool,
        canCreateFolder: Bool? = nil,
        canCreateFile: Bool? = nil
    ) {
        self.canRead = canRead
        self.canWrite = canWrite
        self.canUpload = canUpload
        self.canDelete = canDelete
        self.canShare = canShare
        self.canDownload = canDownload
        self.canCreateFolder = canCreateFolder ?? canUpload
        self.canCreateFile = canCreateFile ?? canUpload
    }

    private enum CodingKeys: String, CodingKey {
        case canRead, canWrite, canUpload, canDelete, canShare, canDownload, canCreateFolder, canCreateFile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            canRead: container.decode(Bool.self, forKey: .canRead),
            canWrite: container.decode(Bool.self, forKey: .canWrite),
            canUpload: container.decode(Bool.self, forKey: .canUpload),
            canDelete: container.decode(Bool.self, forKey: .canDelete),
            canShare: container.decode(Bool.self, forKey: .canShare),
            canDownload: container.decode(Bool.self, forKey: .canDownload),
            canCreateFolder: container.decodeIfPresent(Bool.self, forKey: .canCreateFolder),
            canCreateFile: container.decodeIfPresent(Bool.self, forKey: .canCreateFile)
        )
    }
}
