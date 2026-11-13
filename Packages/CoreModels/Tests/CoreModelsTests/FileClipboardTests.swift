@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileClipboard.canPaste")
struct FileClipboardTests {
    private func file(_ name: String, path: String) -> FileItem {
        FileItem(
            name: name,
            path: path,
            dateModified: MockDate.date.addingTimeInterval(1),
            size: 0,
            kind: TestKind.text
        )
    }

    @Test("root and read-only folders are never valid targets")
    func rejectsRootAndReadOnly() {
        let clip = FileClipboard(items: [file(TestFile.aText, path: TestFolder.inbox)], operation: .copy)
        #expect(clip.canPaste(into: "", canWrite: true) == false)
        #expect(clip.canPaste(into: TestFolder.documents, canWrite: false) == false)
    }

    @Test("copy into any writable folder is allowed, including the item's own parent")
    func copyIsPermissive() {
        let clip = FileClipboard(items: [file(TestFile.aText, path: TestFolder.inbox)], operation: .copy)
        #expect(clip.canPaste(into: TestFolder.inbox, canWrite: true) == true)
        #expect(clip.canPaste(into: TestFolder.documents, canWrite: true) == true)
    }

    @Test("copy of a folder into itself or a subdirectory of itself is blocked (server EINVAL)")
    func copyIntoSelfIsBlocked() {
        let folder = FileClipboard(
            items: [FileItem(
                name: TestFolder.photos,
                path: TestFolder.media,
                dateModified: MockDate.date.addingTimeInterval(1),
                size: 0,
                kind: FileItem.directoryKind
            )],
            operation: .copy
        )
        #expect(folder.canPaste(into: TestPath.mediaPhotos, canWrite: true) == false)
        #expect(folder.canPaste(into: TestPath.mediaPhotos2024, canWrite: true) == false)
        #expect(folder.canPaste(into: "Media/PhotosArchive", canWrite: true) == true)
        #expect(folder.canPaste(into: Constants.mediaOther, canWrite: true) == true)
    }

    @Test("move is blocked into the item's own parent and into a folder being moved")
    func moveGuards() {
        let file = FileClipboard(items: [file(TestFile.aText, path: TestFolder.inbox)], operation: .move)
        #expect(file.canPaste(into: TestFolder.inbox, canWrite: true) == false)
        #expect(file.canPaste(into: TestFolder.documents, canWrite: true) == true)

        let folder = FileClipboard(
            items: [FileItem(
                name: TestFolder.photos,
                path: TestFolder.media,
                dateModified: MockDate.date.addingTimeInterval(1),
                size: 0,
                kind: FileItem.directoryKind
            )],
            operation: .move
        )
        #expect(folder.canPaste(into: TestPath.mediaPhotos, canWrite: true) == false)
        #expect(folder.canPaste(into: TestPath.mediaPhotos2024, canWrite: true) == false)
        #expect(folder.canPaste(into: Constants.mediaOther, canWrite: true) == true)
    }
}

private enum Constants {
    static let mediaOther = "Media/Other"
}
