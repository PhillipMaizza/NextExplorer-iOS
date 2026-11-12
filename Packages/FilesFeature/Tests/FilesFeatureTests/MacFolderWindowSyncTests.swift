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
    struct MacFolderWindowSyncTests {
        private let serverURL = BrowseTestSupport.serverURL
        private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

        private func makeStore(
            _ mutate: (inout MainTabFeature.State) -> Void = { _ in },
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> TestStoreOf<MainTabFeature> {
            var state = MainTabFeature.State(serverURL: serverURL, user: user)
            mutate(&state)
            return TestStore(initialState: state) {
                MainTabFeature()
            } withDependencies: {
                $0.date = .constant(MockDate.date)
                $0.uuid = .incrementing
                configure(&$0)
            }
        }

        // MARK: What counts as a change

        struct ChangeCase: Sendable, CustomTestStringConvertible {
            let name: String
            let action: BrowseFeature.Action
            let expected: FolderContentsChange?

            var testDescription: String { name }
        }

        private nonisolated static let item = FileItem(name: TestFile.aText, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
        private nonisolated static let transferred = TransferResult(destination: TestFolder.docs, items: [.init(from: "Other/a.txt", to: "Docs/a.txt")])

        @Test(
            "A finished edit reloads its own folder in the other windows, a move or undo reloads everything, a failure reloads nothing",
            arguments: [
                ChangeCase(name: "rename", action: .renameResponse(.success(.init(originalID: "Docs/b.txt", renamed: item))), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "new folder", action: .newFolderResponse(.success(item)), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "new file", action: .newFileResponse(.success(item)), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "delete", action: .deleteResponse(.success(.init(itemID: "Docs/a.txt"))), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "bulk delete", action: .bulkDeleteResponse(.success(.init(itemIDs: ["Docs/a.txt"]))), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "extract", action: .extractZipResponse(.success(item)), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "compress", action: .compressResponse(.success(item)), expected: .folders([TestFolder.docs])),
                ChangeCase(name: "text save", action: .textSaveResponse(path: "Docs/a.txt", result: .success("etag")), expected: .folders([TestFolder.docs])),
                ChangeCase(
                    name: "transfer",
                    action: .transferResponse(.success(.init(result: transferred, operation: .move, clearClipboard: false))),
                    expected: .everything
                ),
                ChangeCase(name: "undo", action: .undoResponse(.success(true)), expected: .everything),
                ChangeCase(name: "rename failure", action: .renameResponse(.failure(.offline)), expected: nil),
                ChangeCase(name: "delete failure", action: .deleteResponse(.failure(.offline)), expected: nil),
                ChangeCase(name: "transfer failure", action: .transferResponse(.failure(.offline)), expected: nil),
                ChangeCase(name: "undo failure", action: .undoResponse(.failure(.offline)), expected: nil),
                ChangeCase(name: "text save failure", action: .textSaveResponse(path: "Docs/a.txt", result: .failure(.offline)), expected: nil),
                ChangeCase(name: "a refresh", action: .refreshButtonTapped, expected: nil),
            ]
        )
        func whichActionsChangeWhatTheOtherWindowsShow(_ changeCase: ChangeCase) {
            #expect(BrowseFeature.folderContentsChange(after: changeCase.action, directoryPath: TestFolder.docs) == changeCase.expected)
        }

        // MARK: Broadcasting from the main window

        @Test("A rename in the main window is broadcast to the other windows and reloads the Favorites copy")
        func aRenameInTheMainWindowIsBroadcastToTheOtherWindows() async {
            let renamed = FileItem(name: TestFile.bText, path: "", dateModified: MockDate.date, size: 1, kind: TestKind.text)
            let store = makeStore()

            await store.send(.browse(.root(.renameResponse(.success(BrowseFeature.RenameResult(originalID: TestFile.aText, renamed: renamed)))))) {
                $0.browse.root.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamed, previousName: TestFile.aText))] }
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders([""]), origin: nil)
            }
            await store.receive(\.favorites.refreshDirectory)
        }

        @Test("A failed change in the main window is not broadcast")
        func aFailedChangeIsNotBroadcast() async {
            let store = makeStore()

            await store.send(.browse(.root(.renameResponse(.failure(.offline))))) {
                $0.browse.root.fileActionErrorMessage = FilesClientError.offline.userMessage
            }
        }

        @Test("A change in a pushed Favorites folder is broadcast and reloads the Browse screens showing that folder")
        func aChangeInAFavoritesFolderIsBroadcastAndReloadsBrowse() async {
            let folder = FileItem(name: "New", path: TestFolder.docs, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
            var pushedID = StackElementID(0)
            let listing = AsyncGate()
            let store = makeStore {
                $0.favorites.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs))
                $0.browse.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs))
                pushedID = $0.favorites.path.ids[0]
            } configure: {
                $0.holdFolderListings([TestFolder.docs: listing])
            }
            let browseID = store.state.browse.path.ids[0]

            await store.send(.favorites(.path(.element(id: pushedID, action: .newFolderResponse(.success(folder)))))) {
                $0.favorites.path[id: pushedID]?.items = [folder]
                $0.favorites.path[id: pushedID]?.$undoStack.withLock { $0 = [FileUndoEntry(.created([folder]))] }
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders([TestFolder.docs]), origin: nil)
            }
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.browse.path[id: browseID].refreshButtonTapped) {
                $0.browse.path[id: browseID]?.phase = .loading
            }
            listing.open()
            await store.receive(\.browse.path[id: browseID].itemsResponse.success) {
                $0.browse.path[id: browseID]?.phase = .loaded
                $0.browse.path[id: browseID]?.access = BrowseTestSupport.readOnlyAccess
            }
            await store.receive(\.browse.path[id: browseID].favoritesResponse) {
                $0.browse.path[id: browseID]?.hasLoadedFavorites = true
            }
        }

        @Test("A change from another window is recorded with its origin, and reloads the folder shown here")
        func aChangeFromAnotherWindowReloadsHereAndKeepsItsOrigin() async {
            let origin = UUID(0)
            let listing = AsyncGate()
            let store = makeStore {
                $0.browse.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.photos, title: TestFolder.photos))
            } configure: {
                $0.holdFolderListings([TestFolder.photos: listing])
            }
            let id = store.state.browse.path.ids[0]

            await store.send(.folderWindowChanged(.folders([TestFolder.photos]), origin: origin)) {
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders([TestFolder.photos]), origin: origin)
            }
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.favorites.refreshDirectory)
            await store.receive(\.browse.path[id: id].refreshButtonTapped) {
                $0.browse.path[id: id]?.phase = .loading
            }
            listing.open()
            await store.receive(\.browse.path[id: id].itemsResponse.success) {
                $0.browse.path[id: id]?.phase = .loaded
                $0.browse.path[id: id]?.access = BrowseTestSupport.readOnlyAccess
            }
            await store.receive(\.browse.path[id: id].favoritesResponse) {
                $0.browse.path[id: id]?.hasLoadedFavorites = true
            }
        }

        @Test("Finished uploads are broadcast, folders sorted, so any window on those folders reloads")
        func finishedUploadsAreBroadcastSoAnyWindowOnThatFolderReloads() async {
            let store = makeStore()

            await store.send(.uploads(.delegate(.queueFinished(UploadsFeature.FinishSummary(
                uploadedCount: 2, failedCount: 0, lastDestination: TestFolder.docs, changedPaths: [TestFolder.docs, TestFolder.archive]
            ))))) {
                $0.uploadToast = MainTabFeature.UploadToast(message: L10n.Uploads.completeMany(2), openDestination: "Docs")
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders([TestFolder.archive, TestFolder.docs]), origin: nil)
            }
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.favorites.refreshDirectory)
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.favorites.refreshDirectory)
        }

        @Test("An upload that changed nothing is not broadcast")
        func anUploadThatChangedNothingIsNotBroadcast() async {
            let store = makeStore()

            await store.send(.uploads(.delegate(.queueFinished(UploadsFeature.FinishSummary(
                uploadedCount: 0, failedCount: 1, lastDestination: TestFolder.docs, changedPaths: []
            )))))
        }

        // MARK: Saves

        @Test("A save requested from Browse goes to the download queue and runs against the chosen target")
        func savesGoToTheDownloadQueue() async throws {
            let item = FileItem(name: TestFile.aText, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
            let target = URL(fileURLWithPath: "/tmp")
            let started = AsyncGate()
            let flushed = LockIsolated(0)
            let store = makeStore(configure: {
                $0.filesClient.flushDownloadConnections = { flushed.withValue { $0 += 1 } }
                $0.filesClient.downloadItem = { _, _, _ in
                    started.open()
                    try await suspendUntilCancelled()
                    throw CancellationError()
                }
            })

            await store.send(.browse(.delegate(.saveRequested([DownloadSaveRequest(item: item, target: .into(target))]))))
            await store.receive(\.downloadQueue.enqueueSaves) {
                $0.downloadQueue.jobs = [DownloadQueueFeature.DownloadJob(id: UUID(0), item: item, status: .queued, saveTarget: .into(target))]
            }
            await store.receive(\.downloadQueue.startNextIfIdle) {
                $0.downloadQueue.jobs[id: UUID(0)]?.status = .downloading
                $0.downloadQueue.jobs[id: UUID(0)]?.startedAt = MockDate.date
            }
            try await started.wait()
            await store.send(.downloadQueue(.cancelAllTapped)) {
                $0.downloadQueue.jobs = []
            }
            await store.finish()
            #expect(flushed.value == 1)
        }

        struct SavedToast: Sendable {
            let count: Int
            let message: String
        }

        private nonisolated static let savedToasts = [
            SavedToast(count: 1, message: L10n.Browse.downloadSavedTo("Desktop")),
            SavedToast(count: 3, message: L10n.Browse.downloadSavedAllTo(3, "Desktop")),
        ]

        @Test(
            "A finished save names the folder it landed in, so Show in Finder can reveal it",
            arguments: savedToasts
        )
        func aFinishedSaveConfirmsWhereItLandedInFinder(_ toast: SavedToast) async {
            let savedURL = URL(fileURLWithPath: "/Users/jdoe/Desktop/report.pdf")
            let store = makeStore()

            await store.send(.downloadQueue(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(
                savedCount: toast.count, failedCount: 0, lastSavedURL: savedURL
            ))))) {
                $0.lastSavedDownloadURL = savedURL
                $0.downloadToast = toast.message
            }
        }
    }
#endif
