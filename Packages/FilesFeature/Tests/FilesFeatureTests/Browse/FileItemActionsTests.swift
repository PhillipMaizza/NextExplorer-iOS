import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@MainActor
struct FileItemActionsTests {
    private static let folderPath = "share/tok"
    private static let file = BrowseFixtures.file("notes.txt", in: folderPath)
    private static let subfolder = BrowseFixtures.folder("Sub", in: folderPath)
    private static let archive = BrowseFixtures.file("bundle.zip", in: folderPath)

    private func access(
        write: Bool = false, upload: Bool = false, delete: Bool = false, share: Bool = false,
        download: Bool = false, folder: Bool = false, file: Bool = false
    ) -> FileAccess {
        FileAccess(
            canRead: true, canWrite: write, canUpload: upload, canDelete: delete, canShare: share,
            canDownload: download, canCreateFolder: folder, canCreateFile: file
        )
    }

    private func screen(_ access: FileAccess, isKeptOffline: Bool = false) -> BrowseFeature.State {
        var state = BrowseFixtures.state(
            Self.folderPath, items: [Self.file, Self.subfolder, Self.archive], access: access
        )
        state.isKeptOffline = isKeptOffline
        return state
    }

    @Test(
        "A view only share offers reading and copying, as the web menu and the server allow, and nothing that downloads, writes or shares"
    )
    func viewOnlyShare() {
        let actions = screen(access()).actions(for: Self.file)
        #expect(actions == FileItemActions(canCopy: true))
    }

    @Test("A read only share with downloads on adds download, offline and Open With")
    func readOnlyShareWithDownloads() {
        let actions = screen(access(download: true)).actions(for: Self.file)
        #expect(actions == FileItemActions(canDownload: true, canKeepOffline: true, canExport: true, canCopy: true))
    }

    @Test(
        "A writable share that refuses new folders duplicates and compresses files, never folders, and never extracts"
    )
    func writableShareWithoutNewFolders() {
        let state = screen(access(write: true, upload: true, delete: true, download: true, file: true))
        let onFile = state.actions(for: Self.file)
        #expect(onFile.canRename && onFile.canMove && onFile.canDelete && onFile.canDuplicate && onFile.canCompress)
        #expect(!onFile.canShare)
        #expect(!state.actions(for: Self.subfolder).canDuplicate)
        #expect(!state.actions(for: Self.archive).canExtract)
    }

    @Test("A folder of my own offers every action the server grants, extract included")
    func ownFolder() {
        var state = screen(access(
            write: true, upload: true, delete: true, share: true, download: true, folder: true, file: true
        ))
        state.directoryPath = "personal/Docs"
        state.items = [
            BrowseFixtures.file("bundle.zip", in: state.directoryPath),
            BrowseFixtures.folder("Sub", in: state.directoryPath),
        ]
        state.$isAdmin.withLock { $0 = true }
        let onArchive = state.actions(for: state.items[0])
        #expect(onArchive.canExtract && onArchive.canShare && onArchive.canEditPermissions)
        #expect(state.actions(for: state.items[1]).canDuplicate)
    }

    @Test("The volumes at the root are only read: the server refuses to copy, move, rename or delete them")
    func rootVolumes() {
        var state = screen(access(
            write: true, upload: true, delete: true, share: true, download: true, folder: true, file: true
        ))
        state.directoryPath = ""
        state.items = [BrowseFixtures.folder("Files", in: ""), BrowseFixtures.folder("Media", in: "")]
        let actions = state.actions(for: state.items[0])
        #expect(actions == FileItemActions(canDownload: true, canKeepOffline: true, canExport: true, canEditText: true))
    }

    @Test("A writable share never offers Permissions, even to an admin")
    func shareIsNeverRepermissioned() {
        var state = screen(access(
            write: true, upload: true, delete: true, share: true, download: true, folder: true, file: true
        ))
        state.$isAdmin.withLock { $0 = true }
        #expect(!state.actions(for: Self.archive).canEditPermissions)
    }

    @Test("A screen of kept files offers no server actions")
    func keptOffline() {
        let actions = screen(access(share: true, download: true), isKeptOffline: true).actions(for: Self.file)
        #expect(!actions.canKeepOffline && !actions.canShare && !actions.canCopy && !actions.canEditPermissions)
    }

    @Test("An item from another folder, as a search hit, gets nothing from this folder's access")
    func itemFromAnotherFolder() {
        let elsewhere = BrowseFixtures.file("far.txt", in: "personal/Docs")
        let state = screen(access(
            write: true, upload: true, delete: true, share: true, download: true, folder: true, file: true
        ))
        #expect(state.actions(for: elsewhere) == FileItemActions())
    }

    @Test("Several picks keep what works on many, compress included, and drop what works on one: rename, extract")
    func severalPicks() {
        let state = screen(access(
            write: true, upload: true, delete: true, share: true, download: true, folder: true, file: true
        ))
        let actions = state.actions(for: [Self.file, Self.archive])
        #expect(actions.canMove && actions.canDelete && actions.canCopy && actions.canDuplicate && actions
            .canCompress && actions.canDownload)
        #expect(!actions.canRename && !actions.canExtract && !actions.canEditPermissions)
        #expect(state.actions(for: []) == FileItemActions())
    }

    #if os(macOS)
        @Test("The inspector's More is empty on a view only file, and lists organising rows in my own folder")
        func inspectorMoreRows() {
            #expect(screen(access()).inspectorMoreRows(for: Self.subfolder).isEmpty == false)
            let viewOnlyFile = screen(access()).inspectorMoreRows(for: Self.file)
            #expect(viewOnlyFile.actions.canCopy && !viewOnlyFile.isEmpty)
            var noCopy = screen(access())
            noCopy.directoryPath = ""
            noCopy.items = [BrowseFixtures.folder("Only", in: "")]
            #expect(noCopy.inspectorMoreRows(for: noCopy.items[0]).isEmpty)
            let own = screen(access(write: true, delete: true, download: true, file: true))
                .inspectorMoreRows(for: Self.file)
            #expect(own.showsOpenWith && own.showsDownload && own.showsKeepOffline && own.actions.canDelete)
        }
    #endif
}
