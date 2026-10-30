#if os(macOS)
    import Foundation

    /// What a Mac Browse window opens on: a folder (empty path = the root) and, for ⌘T / "Open in
    /// New Tab", the window it should join as a tab.
    public struct FolderWindowRoute: Codable, Hashable, Sendable {
        public static let windowID = "folder"

        public let path: String
        public let title: String
        public let tabHostWindowNumber: Int?

        public init(path: String, title: String, tabHostWindowNumber: Int? = nil) {
            self.path = path
            self.title = title
            self.tabHostWindowNumber = tabHostWindowNumber
        }
    }
#endif
