import CoreModels
@testable import FilesFeature
import Foundation
import TestUtils

/// Values the drag and drop tests share: the receiving account, the rows a drag carries, and a real
/// staged copy of a dropped file.
enum BrowseDropFixtures {
    static let receiver = DragOrigin(serverURL: BrowseTestSupport.serverURL.absoluteString, scope: "scope-a")
    static let otherAccount = DragOrigin(serverURL: BrowseTestSupport.serverURL.absoluteString, scope: "scope-b")
    static let otherServer = DragOrigin(serverURL: "https://other.example.com", scope: "scope-a")

    /// A row of a dragged listing: a PDF of ten bytes, or a folder.
    static func entry(_ name: String, in path: String = TestFolder.docs, isFolder: Bool = false) -> FileItem {
        isFolder
            ? BrowseFixtures.folder(name, in: path)
            : BrowseFixtures.file(
                name,
                in: path,
                kind: TestKind.pdf,
                size: 10
            )
    }

    /// A real staged drop copy, created the way a drop stages one.
    static func stagedCopy(name: String = "dropped.txt") throws -> URL {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("drop-src-\(TestID.name())-\(name)")
        try Data("x".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let staged = try DroppedFileStaging.stage(source, isOriginal: true)
        let renamed = staged.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: staged, to: renamed)
        return renamed
    }

    static func removeStagedCopy(_ url: URL) {
        DroppedFileStaging.discardCopy(at: url)
    }
}
