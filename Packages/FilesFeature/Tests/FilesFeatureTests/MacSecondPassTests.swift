import TestUtils
#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DependenciesTestSupport
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    @Suite(.dependencies)
    struct MacSecondPassTests {
        private let serverURL = URL(string: "https://example.com")!
        private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)

        @Test
        func goToFolderInAnExtraWindowOpensThereNotInTheMainWindow() async {
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { _ in }
            }
            store.exhaustivity = .off

            await store.send(.goToFolderRequested(" /Photos/2026/ "))
            await store.receive(\.browse.navigateToDirectory)
            #expect(store.state.browse.path.last?.directoryPath == "Photos/2026")
        }

        @Test
        func anEmptyGoToFolderPathDoesNothing() async {
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { _ in }
            }

            await store.send(.goToFolderRequested(" / "))
        }

        @Test
        func rowsFromAnotherWindowMoveHereButNotOntoThemselves() async {
            let elsewhere = FileItem(name: "a.txt", path: "Other", dateModified: MockDate.date, size: 1, kind: "txt")
            let alreadyHere = FileItem(name: "b.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
            let parent = FileItem(name: "Docs", path: "", dateModified: MockDate.date, size: 0, kind: "directory")
            let moved = LockIsolated<[String]>([])
            let access = access
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            state.access = access
            state.items = [alreadyHere]
            let store = TestStore(initialState: state) {
                BrowseFeature()
            } withDependencies: {
                $0.filesClient.browse = { _, path in BrowseResult(items: [], access: access, path: path) }
                $0.filesClient.transferItems = { _, items, destination, _ in
                    moved.withValue { $0 = items.map(\.id) }
                    return TransferResult(destination: destination, items: items.map { TransferResult.Entry(from: $0.id, to: destination + "/" + $0.name) })
                }
            }
            store.exhaustivity = .off

            await store.send(.itemsDroppedFromOtherWindow([elsewhere, alreadyHere, parent], destination: "Docs"))
            await store.skipReceivedActions()
            #expect(moved.value == [elsewhere.id])
        }

        @Test
        func showInEnclosingFolderEndsTheSearchAndOpensTheFolder() async {
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Home")
            state.searchQuery = "report"
            let result = SearchResultItem(name: "report.pdf", path: "Documents/Work", kind: "file", isNameMatch: true)
            let store = TestStore(initialState: state) {
                BrowseFeature()
            }
            store.exhaustivity = .off

            await store.send(.searchResultEnclosingFolderTapped(result)) {
                $0.searchQuery = ""
            }
            await store.receive(.delegate(.openPath(path: "Documents/Work", title: "Work")))
        }

        @Test
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

        @Test
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

        @Test
        func openWithCopiesAreLockedAndLeaveTheSourceAlone() async throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
