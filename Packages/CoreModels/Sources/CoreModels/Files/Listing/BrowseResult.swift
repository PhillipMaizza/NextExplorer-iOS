/// Mirrors the response body of `GET /api/browse/*` (`backend/src/routes/browse.js`).
/// The route also returns `current`, unused by the client so far.
public struct BrowseResult: Codable, Equatable, Sendable {
    public let items: [FileItem]
    public let access: FileAccess
    public let path: String
    public let shareInfo: ShareInfo?

    public init(items: [FileItem], access: FileAccess, path: String, shareInfo: ShareInfo? = nil) {
        self.items = items
        self.access = access
        self.path = path
        self.shareInfo = shareInfo
    }

    public struct ShareInfo: Codable, Equatable, Sendable {
        public let label: String?
        public let sourceFolderName: String

        public init(label: String?, sourceFolderName: String) {
            self.label = label
            self.sourceFolderName = sourceFolderName
        }

        public var name: String? {
            [sourceFolderName, label ?? ""].first { !$0.isEmpty }
        }
    }
}
