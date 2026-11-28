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
        #expect(clip.canPaste(into: "", canReceive: true) == false)
        #expect(clip.canPaste(into: TestFolder.documents, canReceive: false) == false)
    }

    @Test(
        "A refused paste names its reason, the folder checks before the rights",
        arguments: [
            ("", true, FileClipboard.Refusal.noFolder),
            (TestFolder.inbox, true, .alreadyThere),
            (TestFolder.inbox, false, .alreadyThere),
            ("\(TestFolder.inbox)/\(TestFile.aText)", true, .intoItself),
            (TestFolder.documents, false, .noRights),
        ]
    )
    func refusalReason(target: String, canReceive: Bool, expected: FileClipboard.Refusal) {
        let clip = FileClipboard(items: [file(TestFile.aText, path: TestFolder.inbox)], operation: .move)
        #expect(clip.refusal(into: target, canReceive: canReceive) == expected)
    }

    @Test("copy into any writable folder is allowed, including the item's own parent")
    func copyIsPermissive() {
        let clip = FileClipboard(items: [file(TestFile.aText, path: TestFolder.inbox)], operation: .copy)
        #expect(clip.canPaste(into: TestFolder.inbox, canReceive: true) == true)
        #expect(clip.canPaste(into: TestFolder.documents, canReceive: true) == true)
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
        #expect(folder.canPaste(into: TestPath.mediaPhotos, canReceive: true) == false)
        #expect(folder.canPaste(into: TestPath.mediaPhotos2024, canReceive: true) == false)
        #expect(folder.canPaste(into: "Media/PhotosArchive", canReceive: true) == true)
        #expect(folder.canPaste(into: Constants.mediaOther, canReceive: true) == true)
    }

    @Test("move is blocked into the item's own parent and into a folder being moved")
    func moveGuards() {
        let file = FileClipboard(items: [file(TestFile.aText, path: TestFolder.inbox)], operation: .move)
        #expect(file.canPaste(into: TestFolder.inbox, canReceive: true) == false)
        #expect(file.canPaste(into: TestFolder.documents, canReceive: true) == true)

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
        #expect(folder.canPaste(into: TestPath.mediaPhotos, canReceive: true) == false)
        #expect(folder.canPaste(into: TestPath.mediaPhotos2024, canReceive: true) == false)
        #expect(folder.canPaste(into: Constants.mediaOther, canReceive: true) == true)
    }
}

private enum Constants {
    static let mediaOther = "Media/Other"
}

@Suite("FileAccess actions")
struct FileAccessActionTests {
    private func access(
        write: Bool = false,
        delete: Bool = false,
        folder: Bool = false,
        file: Bool = false,
        download: Bool = true
    ) -> FileAccess {
        FileAccess(
            canRead: true, canWrite: write, canUpload: false, canDelete: delete, canShare: false, canDownload: download,
            canCreateFolder: folder, canCreateFile: file
        )
    }

    @Test("A folder takes copied files with the right to create files, and copied folders only with both create rights")
    func receive() {
        let file = FileItem(name: "a.txt", path: "Docs", dateModified: .distantPast, size: 1, kind: "txt")
        let folder = FileItem(
            name: "Sub",
            path: "Docs",
            dateModified: .distantPast,
            size: 0,
            kind: FileItem.directoryKind
        )
        #expect(access(file: true).canReceive([file]))
        #expect(!access(file: true).canReceive([file, folder]))
        #expect(access(folder: true, file: true).canReceive([file, folder]))
        #expect(!access(folder: true).canReceive([folder]))
        #expect(!access(write: true).canReceive([file]))
    }

    @Test(
        "Move needs write and delete, like the web menu; extract needs both create rights; compress needs new files and the right to download what it packs"
    )
    func moveExtractCompress() {
        #expect(access(write: true, delete: true).canMove)
        #expect(!access(delete: true).canMove)
        #expect(access(folder: true, file: true).canExtract)
        #expect(!access(file: true).canExtract)
        #expect(access(file: true).canCompress)
        #expect(!access(write: true, folder: true).canCompress)
        #expect(!access(file: true, download: false).canCompress)
    }
}
