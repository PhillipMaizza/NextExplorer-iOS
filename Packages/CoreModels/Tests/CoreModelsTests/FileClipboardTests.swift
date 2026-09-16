@testable import CoreModels
import Foundation
import Testing

@Suite("FileClipboard.canPaste")
struct FileClipboardTests {
    private func file(_ name: String, path: String) -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "txt")
    }

    @Test("root and read-only folders are never valid targets")
    func rejectsRootAndReadOnly() {
        let clip = FileClipboard(items: [file("a.txt", path: "Inbox")], operation: .copy)
        #expect(clip.canPaste(into: "", canWrite: true) == false)
        #expect(clip.canPaste(into: "Documents", canWrite: false) == false)
    }

    @Test("copy into any writable folder is allowed, including the item's own parent")
    func copyIsPermissive() {
        let clip = FileClipboard(items: [file("a.txt", path: "Inbox")], operation: .copy)
        #expect(clip.canPaste(into: "Inbox", canWrite: true) == true)
        #expect(clip.canPaste(into: "Documents", canWrite: true) == true)
    }

    @Test("copy of a folder into itself or a subdirectory of itself is blocked (server EINVAL)")
    func copyIntoSelfIsBlocked() {
        let folder = FileClipboard(
            items: [FileItem(name: "Photos", path: "Media", dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")],
            operation: .copy
        )
        #expect(folder.canPaste(into: "Media/Photos", canWrite: true) == false)
        #expect(folder.canPaste(into: "Media/Photos/2024", canWrite: true) == false)
        #expect(folder.canPaste(into: "Media/PhotosArchive", canWrite: true) == true)
        #expect(folder.canPaste(into: "Media/Other", canWrite: true) == true)
    }

    @Test("move is blocked into the item's own parent and into a folder being moved")
    func moveGuards() {
        let file = FileClipboard(items: [file("a.txt", path: "Inbox")], operation: .move)
        #expect(file.canPaste(into: "Inbox", canWrite: true) == false)
        #expect(file.canPaste(into: "Documents", canWrite: true) == true)

        let folder = FileClipboard(
            items: [FileItem(name: "Photos", path: "Media", dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")],
            operation: .move
        )
        #expect(folder.canPaste(into: "Media/Photos", canWrite: true) == false)
        #expect(folder.canPaste(into: "Media/Photos/2024", canWrite: true) == false)
        #expect(folder.canPaste(into: "Media/Other", canWrite: true) == true)
    }
}
