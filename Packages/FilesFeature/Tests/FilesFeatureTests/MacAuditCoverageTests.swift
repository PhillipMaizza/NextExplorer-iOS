import TestUtils
#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
        import FilesClient
    @testable import FilesFeature
    import Foundation
    import Localization
    import NetworkClient
    import Testing

    /// The smaller fixes of the Mac audit, each pinned by a test.
    @MainActor
    @Suite(.isolatedDependencies)
    struct MacAuditCoverageTests {
        private let serverURL = URL(string: "https://example.com")!

        @Test
        func anInvalidNameFromAnInPlaceRenameSaysWhyAndAsksNothing() async {
            let item = FileItem(name: "report.pdf", path: "Docs", dateModified: MockDate.date, size: 1, kind: "pdf")
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            state.renameSheetItem = item
            let store = TestStore(initialState: state) {
                BrowseFeature()
            }

            await store.send(.renameConfirmed("a/b.pdf")) {
                $0.renameSheetItem = nil
                $0.fileActionErrorMessage = L10n.Browse.nameErrorSeparators
            }
        }

        @Test
        func deletingTheFileOfASearchPreviewClosesItAndSearchesAgain() async {
            var state = FavoritesFeature.State(serverURL: serverURL)
            state.previewHost = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            let store = TestStore(initialState: state) {
                FavoritesFeature()
            }
            store.exhaustivity = .off

            await store.send(.previewHost(.presented(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: "Docs/a.txt")))))) {
                $0.previewHost = nil
            }
            await store.receive(\.searchRetryTapped)
        }

        @Test
        func renamingTheFileOfASearchPreviewRefreshesTheResults() async {
            var state = FavoritesFeature.State(serverURL: serverURL)
            let renamed = FileItem(name: "b.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
            state.previewHost = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            let store = TestStore(initialState: state) {
                FavoritesFeature()
            }
            store.exhaustivity = .off

            await store.send(.previewHost(.presented(.renameResponse(.success(BrowseFeature.RenameResult(originalID: "Docs/a.txt", renamed: renamed))))))
            await store.receive(\.searchRetryTapped)
            #expect(store.state.previewHost != nil)
        }

        @Test
        func theSaveConfirmationNamesTheFolderAndTheCount() {
            let url = URL(fileURLWithPath: "/Users/jdoe/Desktop/report.pdf")
            #expect(MainTabFeature.macSavedMessage(count: 1, lastSavedURL: url) == L10n.Browse.downloadSavedTo("Desktop"))
            #expect(MainTabFeature.macSavedMessage(count: 3, lastSavedURL: url) == L10n.Browse.downloadSavedAllTo(3, "Desktop"))
        }

        @Test
        func transferNotificationsFireOnceWhenAQueueDrains() {
            #expect(MacTransferNotifications.didStart(old: 0, new: 2))
            #expect(!MacTransferNotifications.didStart(old: 1, new: 2))
            #expect(!MacTransferNotifications.didDrain(old: 2, new: 1))
            #expect(MacTransferNotifications.didDrain(old: 1, new: 0))
            #expect(!MacTransferNotifications.didDrain(old: 0, new: 0))
        }

        @Test
        func theDockBarMovesInWholePercents() {
            #expect(MacDockUploadStatus.stepped(0.123_4) == 0.12)
            #expect(MacDockUploadStatus.stepped(0.125_1) == 0.13)
            #expect(MacDockUploadStatus.stepped(1) == 1)
        }

        @Test
        func aGalleryPageNeverDecodesPastTheMacCap() {
            #expect(ImageGalleryPage.decodeTarget(screenLongSide: 1_440, scale: 2) == 5_760)
            #expect(ImageGalleryPage.decodeTarget(screenLongSide: 3_008, scale: 2) == ImageGalleryPage.macMaxPixelDimension)
        }

        @Test
        func quickLookResponderJoinsAndLeavesTheWindowChain() {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
            let original = window.nextResponder
            let first = MacQuickLookResponder()
            let second = MacQuickLookResponder()

            first.insert(into: window)
            second.insert(into: window)
            #expect(window.nextResponder === second)
            #expect(second.nextResponder === first)

            first.remove(from: window)
            #expect(window.nextResponder === second)
            #expect(second.nextResponder === original)
            #expect(first.nextResponder == nil)

            second.remove(from: window)
            #expect(window.nextResponder === original)
        }

        @Test
        func quickLookControlIsWantedOnlyWithAFileToShow() {
            let panel = MacQuickLookPanel()
            #expect(!panel.hasFileToShow)
            #expect(panel.responder.owner === panel)
        }

        @Test
        func syntaxHighlightingStaysTheSameOnceItsQueriesAreCached() throws {
            let language = try #require(MacSyntaxLanguage.forKind("json"))
            let first = MacSyntaxHighlighter.spans(for: #"{"a": 1}"#, language: language)
            let second = MacSyntaxHighlighter.spans(for: #"{"a": 1}"#, language: language)
            #expect(!first.isEmpty)
            #expect(first.map(\.range) == second.map(\.range))
        }

        @Test
        func escInTheEditorClosesThePreviewInsteadOfCompletingAWord() {
            let coordinator = CodeEditorView.Coordinator(text: .constant(""))
            let closed = LockIsolated(0)
            coordinator.onEscape = { closed.withValue { $0 += 1 } }
            let textView = NSTextView()

            #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
            #expect(!coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            #expect(closed.value == 1)
        }

        @Test
        func quittingAsksOnlyWhileAnUploadOrDownloadRuns() {
            let user = User(id: "1", username: "jdoe", email: nil, displayName: nil, roles: [])
            var state = MainTabFeature.State(serverURL: serverURL, user: user)
            #expect(!state.hasTransfersInFlight)
            let item = FileItem(name: "a.txt", path: "", dateModified: MockDate.date, size: 1, kind: "txt")
            state.downloadQueue.jobs.append(DownloadQueueFeature.DownloadJob(id: UUID(0), item: item, status: .downloading))
            #expect(state.hasTransfersInFlight)
            state.downloadQueue.jobs[id: UUID(0)]?.status = .completed
            #expect(!state.hasTransfersInFlight)
        }

        @Test
        func leavingAnAdminPaneReleasesItSoItLoadsFreshNextTime() async {
            let admin = User(id: "1", username: "admin", email: nil, displayName: nil, roles: [UserRole.admin])
            var state = SettingsFeature.State(serverURL: serverURL, user: admin)
            state.userManagement = UserManagementFeature.State(serverURL: serverURL, currentUserID: "1")
            state.serverDetails = ServerDetailsFeature.State(serverURL: serverURL, branding: Branding())
            let store = TestStore(initialState: state) {
                SettingsFeature()
            }

            await store.send(.adminPaneLeft(.users)) {
                $0.userManagement = nil
            }
            await store.send(.adminPaneLeft(.server)) {
                $0.serverDetails = nil
            }
            await store.send(.adminPaneLeft(.thumbnails))
        }

        @Test
        func savesFromAnyScreenReachTheAppShell() async {
            let item = FileItem(name: "a.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
            let request = DownloadSaveRequest(item: item, target: .into(URL(fileURLWithPath: "/tmp")))
            let browse = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) { BrowseTabFeature() }
            await browse.send(.root(.delegate(.saveRequested([request]))))
            await browse.receive(.delegate(.saveRequested([request])))

            var favoritesState = FavoritesFeature.State(serverURL: serverURL)
            favoritesState.previewHost = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
            let favorites = TestStore(initialState: favoritesState) { FavoritesFeature() }
            await favorites.send(.previewHost(.presented(.delegate(.saveRequested([request])))))
            await favorites.receive(.delegate(.saveRequested([request])))
        }

        @Test
        func aChangeInAFavoritesFolderIsBroadcastAndReloadsBrowse() async {
            let user = User(id: "1", username: "jdoe", email: nil)
            var state = MainTabFeature.State(serverURL: serverURL, user: user)
            state.favorites.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs"))
            let id = state.favorites.path.ids[0]
            let folder = FileItem(name: "New", path: "Docs", dateModified: MockDate.date, size: 0, kind: "directory")
            let store = TestStore(initialState: state) {
                MainTabFeature()
            } withDependencies: {
                $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
                $0.filesClient.favorites = { _ in [] }
            }
            store.exhaustivity = .off

            await store.send(.favorites(.path(.element(id: id, action: .newFolderResponse(.success(folder)))))) {
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders(["Docs"]), origin: nil)
            }
            await store.receive(\.browse.refreshDirectory)
        }

        @Test
        func aMoveOrUndoReloadsEveryFolderInTheOtherWindows() async {
            #expect(BrowseFeature.folderContentsChange(after: .undoResponse(.success(true)), directoryPath: "Docs") == .everything)
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { _ in }
            } withDependencies: {
                $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
                $0.filesClient.favorites = { _ in [] }
                $0.filesClient.serverFeatures = { _ in throw FilesClientError.offline }
            }
            store.exhaustivity = .off

            await store.send(.otherWindowChanged(.everything))
            await store.receive(\.browse.syncPathStack)
        }

        @Test
        func aSaveReportsByteProgressToItsQueueRow() async {
            let item = FileItem(name: "a.txt", path: "Docs", dateModified: MockDate.date, size: 4, kind: "txt")
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
            let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
                DownloadQueueFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.date.now = Date(timeIntervalSince1970: 0)
                $0.filesClient.flushDownloadConnections = {}
                $0.filesClient.downloadItem = { _, _, onProgress in
                    onProgress(TransferProgress(receivedBytes: 4, expectedBytes: 4))
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
                    try Data("data".utf8).write(to: file)
                    return file
                }
            }
            store.exhaustivity = .off
            defer { try? FileManager.default.removeItem(at: target) }

            await store.send(.enqueueSaves([DownloadSaveRequest(item: item, target: .replacing(target))]))
            await store.receive(\.progress)
            await store.receive(\.downloadResponse)
            #expect(store.state.savedCount == 1)
            #expect(store.state.lastSavedURL == target)
        }

        @Test
        func aDiskFailureDuringASaveReadsAsALocalProblem() async {
            let item = FileItem(name: "a.txt", path: "Docs", dateModified: MockDate.date, size: 4, kind: "txt")
            let unwritable = URL(fileURLWithPath: "/System/NextExplorerAuditTest/a.txt")
            let client = FilesClient().with {
                $0.downloadItem = { _, _, _ in
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
                    try Data("data".utf8).write(to: file)
                    return file
                }
            }
            await #expect(throws: FilesClientError.self) {
                try await MacDownloadSaving.save(
                    DownloadSaveRequest(item: item, target: .replacing(unwritable)), serverURL: self.serverURL, filesClient: client
                ) { _ in }
            }
        }
    }

    private extension FilesClient {
        func with(_ change: (inout FilesClient) -> Void) -> FilesClient {
            var copy = self
            change(&copy)
            return copy
        }
    }
#endif
