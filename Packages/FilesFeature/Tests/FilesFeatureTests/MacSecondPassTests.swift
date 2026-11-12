import TestUtils
#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Localization
    import Testing

    @MainActor
    @Suite(.isolatedDependencies)
    struct MacSecondPassTests {
        private let serverURL = BrowseTestSupport.serverURL

        // MARK: Go to Folder in an extra window

        @Test("Go to Folder in an extra window opens the trimmed path there, not in the main window")
        func goToFolderInAnExtraWindowOpensThereNotInTheMainWindow() async {
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { _ in }
            }

            await store.send(.goToFolderRequested(" /Photos/2026/ "))
            await store.receive(\.browse.navigateToDirectory) {
                $0.browse.path[id: 0] = BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/2026", title: "2026")
            }
        }

        @Test("A Go to Folder path with nothing left after trimming does nothing")
        func anEmptyGoToFolderPathDoesNothing() async {
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { _ in }
            }

            await store.send(.goToFolderRequested(" / "))
        }

        // MARK: Rows dragged in from another window

        private func dropTarget(canWrite: Bool = true) -> BrowseFeature.State {
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            state.access = canWrite ? BrowseTestSupport.fullAccess : BrowseTestSupport.readOnlyAccess
            state.items = [FileItem(name: "b.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")]
            return state
        }

        @Test("Rows from another window move into this folder, but rows already here or the folder itself do not")
        func rowsFromAnotherWindowMoveHereButNotOntoThemselves() async {
            let elsewhere = FileItem(name: "a.txt", path: "Other", dateModified: MockDate.date, size: 1, kind: "txt")
            let alreadyHere = FileItem(name: "b.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
            let parent = FileItem(name: "Docs", path: "", dateModified: MockDate.date, size: 0, kind: "directory")
            let moved = FileItem(name: "a.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
            let transferred = LockIsolated<[String]>([])
            let transfer = AsyncGate()
            let state = dropTarget()
            let store = TestStore(initialState: state) {
                BrowseFeature()
            } withDependencies: {
                $0.filesClient.transferItems = { _, items, destination, operation in
                    transferred.withValue { $0.append("\(items.map(\.id).joined(separator: ",")) \(destination) \(operation)") }
                    try await transfer.wait()
                    return TransferResult(destination: destination, items: [.init(from: "Other/a.txt", to: "Docs/a.txt")])
                }
            }

            await store.send(.itemsDroppedFromOtherWindow([elsewhere, alreadyHere, parent], destination: "Docs")) {
                $0.isPerformingFileAction = true
                $0.fileActionProgressMessage = L10n.Browse.progressMoving
                $0.pendingTransferRetry = BrowseFeature.TransferRetry(
                    items: [elsewhere], destination: "Docs", operation: .move, clearClipboard: false,
                    resolution: .keepBoth, itemsToReplace: []
                )
            }
            transfer.open()
            await store.receive(\.transferResponse.success) {
                $0.isPerformingFileAction = false
                $0.fileActionProgressMessage = nil
                $0.pendingTransferRetry = nil
                $0.transferSuccessMessage = L10n.Browse.transferMoved(1)
                $0.items = [alreadyHere, moved]
                $0.$undoStack.withLock {
                    $0 = [FileUndoEntry(.moved([FileUndoEntry.MovedItem(item: moved, originalParent: "Other")]))]
                }
                $0.awaitedArrivalIDs = ["Docs/a.txt"]
                $0.arrivalChecksLeft = 3
            }
            await store.receive(.delegate(.directoryContentsChanged))

            #expect(transferred.value == ["Other/a.txt Docs move"])
        }

        struct NothingToMove: Sendable, CustomTestStringConvertible {
            let name: String
            let dropped: [FileItem]
            let destination: String
            let canWrite: Bool

            var testDescription: String { name }
        }

        @Test(
            "A drop that leaves nothing to move, or that this folder may not receive, transfers nothing",
            arguments: [
                NothingToMove(
                    name: "a row already in the folder",
                    dropped: [FileItem(name: "b.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")],
                    destination: "Docs", canWrite: true
                ),
                NothingToMove(
                    name: "the folder onto itself",
                    dropped: [FileItem(name: "Docs", path: "", dateModified: MockDate.date, size: 0, kind: "directory")],
                    destination: "Docs", canWrite: true
                ),
                NothingToMove(
                    name: "a folder into its own subfolder",
                    dropped: [FileItem(name: "Docs", path: "", dateModified: MockDate.date, size: 0, kind: "directory")],
                    destination: "Docs/Sub", canWrite: true
                ),
                NothingToMove(
                    name: "a folder that is not writable",
                    dropped: [FileItem(name: "a.txt", path: "Other", dateModified: MockDate.date, size: 1, kind: "txt")],
                    destination: "Docs", canWrite: false
                ),
            ]
        )
        func aDropWithNothingToMoveTransfersNothing(_ drop: NothingToMove) async {
            let store = TestStore(initialState: dropTarget(canWrite: drop.canWrite)) {
                BrowseFeature()
            }

            await store.send(.itemsDroppedFromOtherWindow(drop.dropped, destination: drop.destination))
        }

        // MARK: Search results

        @Test("Show in Enclosing Folder ends the search and opens the folder that holds the result")
        func showInEnclosingFolderEndsTheSearchAndOpensTheFolder() async {
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Home")
            state.searchQuery = "report"
            let result = SearchResultItem(name: "report.pdf", path: "Documents/Work", kind: "file", isNameMatch: true)
            let store = TestStore(initialState: state) {
                BrowseFeature()
            }

            await store.send(.searchResultEnclosingFolderTapped(result)) {
                $0.searchQuery = ""
            }
            await store.receive(.delegate(.openPath(path: "Documents/Work", title: "Work")))
        }

        @Test("View in Shared from a search preview closes it and switches tab")
        func viewInSharedFromASearchPreviewClosesItAndSwitchesTab() async {
            var state = FavoritesFeature.State(serverURL: serverURL)
            state.previewHost = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            let store = TestStore(initialState: state) {
                FavoritesFeature()
            }

            await store.send(.viewSharesFromPreviewTapped) {
                $0.previewHost = nil
            }
            await store.receive(.delegate(.goToSharedTab))
        }
    }

    /// `MacOpenWithCopy.make` writes under the shared `Library/Caches/PreviewCache`, which
    /// `PreviewCacheStoreTests` wipes, so these tests join the same serialized gate. Inside the suite the two
    /// tests touch separate folders, so they need no ordering of their own.
    @Suite(.isolatedDependencies, SerializedPreviewCacheAccess())
    struct MacOpenWithCopyTests {
        @Test("Open With copies older than a day are removed, newer ones stay")
        func openWithCopiesOlderThanADayAreRemoved() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
            let fresh = root.appendingPathComponent("fresh", isDirectory: true)
            let stale = root.appendingPathComponent("stale", isDirectory: true)
            try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            for directory in [fresh, stale] {
                try FileManager.default.setAttributes([.modificationDate: MockDate.date, .creationDate: MockDate.date], ofItemAtPath: directory.path)
            }

            MacOpenWithCopy.removeStaleCopies(in: root, now: MockDate.date.addingTimeInterval(MacOpenWithCopy.staleCopyLifetime / 2))
            #expect(FileManager.default.fileExists(atPath: stale.path))
            MacOpenWithCopy.removeStaleCopies(in: root, now: MockDate.date.addingTimeInterval(MacOpenWithCopy.staleCopyLifetime + 60))
            #expect(!FileManager.default.fileExists(atPath: stale.path))
            #expect(!FileManager.default.fileExists(atPath: fresh.path))
        }

        @Test("An Open With copy takes the file's own name, is locked, and leaves the source alone")
        func openWithCopiesAreLockedAndLeaveTheSourceAlone() async throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let source = folder.appendingPathComponent("hash-named-blob")
            try Data("hello".utf8).write(to: source)

            let copy = try await MacOpenWithCopy.make(from: source, named: "../report.pdf")
            defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }

            #expect(copy.lastPathComponent == "report.pdf")
            #expect(copy.path.contains("/PreviewCache/\(MacOpenWithCopy.directoryName)/"))
            #expect(!FileManager.default.isWritableFile(atPath: copy.path))
            #expect(FileManager.default.isWritableFile(atPath: source.path))
            #expect(try String(contentsOf: copy, encoding: .utf8) == "hello")
        }
    }
#endif
