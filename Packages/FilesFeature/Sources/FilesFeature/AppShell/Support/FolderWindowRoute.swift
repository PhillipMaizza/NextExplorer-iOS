#if os(macOS)
    import Foundation

    /// What a Mac Browse window opens on: a folder (empty path = the root).
    public struct FolderWindowRoute: Codable, Hashable, Sendable {
        public static let windowID = "folder"

        public let path: String
        public let title: String

        public init(path: String, title: String) {
            self.path = path
            self.title = title
        }
    }
#endif
