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
        private let serverURL = BrowseTestSupport.serverURL

        @Test("An invalid name from an in place rename says why and asks nothing")
        func anInvalidNameFromAnInPlaceRenameSaysWhyAndAsksNothing() async {
            let item = FileItem(name: TestFile.report, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.pdf)
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs)
            state.renameSheetItem = item
            let store = TestStore(initialState: state) {
                BrowseFeature()
            }

            await store.send(.renameConfirmed("a/b.pdf")) {
                $0.renameSheetItem = nil
                $0.fileActionErrorMessage = L10n.Browse.nameErrorSeparators
            }
        }

        private func searchPreview() -> FavoritesFeature.State {
            var state = FavoritesFeature.State(serverURL: serverURL)
            state.previewHost = BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs)
            return state
        }

        @Test("Deleting the file of a search preview closes it and searches again")
        func deletingTheFileOfASearchPreviewClosesItAndSearchesAgain() async {
            let store = TestStore(initialState: searchPreview()) {
                FavoritesFeature()
            }

            await store.send(.previewHost(.presented(.deleteResponse(.success(BrowseFeature.DeleteResult(itemID: "Docs/a.txt")))))) {
                $0.previewHost = nil
            }
            await store.receive(\.searchRetryTapped)
        }

        @Test("Renaming the file of a search preview keeps the preview and refreshes the results behind it")
        func renamingTheFileOfASearchPreviewRefreshesTheResults() async {
            let renamed = FileItem(name: TestFile.bText, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
            let store = TestStore(initialState: searchPreview()) {
                FavoritesFeature()
            }

            await store.send(.previewHost(.presented(.renameResponse(.success(BrowseFeature.RenameResult(originalID: "Docs/a.txt", renamed: renamed)))))) {
                $0.previewHost?.$undoStack.withLock { $0 = [FileUndoEntry(.renamed(renamed, previousName: TestFile.aText))] }
            }
            await store.receive(\.searchRetryTapped)
        }

        struct SavedMessage: Sendable {
            let count: Int
            let expected: String
        }

        private nonisolated static let savedMessages = [
            SavedMessage(count: 1, expected: L10n.Browse.downloadSavedTo("Desktop")),
            SavedMessage(count: 3, expected: L10n.Browse.downloadSavedAllTo(3, "Desktop")),
        ]

        @Test("The save confirmation names the folder and the count", arguments: savedMessages)
        func theSaveConfirmationNamesTheFolderAndTheCount(_ saved: SavedMessage) {
            let url = URL(fileURLWithPath: "/Users/jdoe/Desktop/report.pdf")

            #expect(MainTabFeature.macSavedMessage(count: saved.count, lastSavedURL: url) == saved.expected)
        }

        struct TransferEdge: Sendable {
            let old: Int
            let new: Int
            let didStart: Bool
            let didDrain: Bool
        }

        @Test(
            "Transfer notifications fire once when a queue starts and once when it drains",
            arguments: [
                TransferEdge(old: 0, new: 2, didStart: true, didDrain: false),
                TransferEdge(old: 1, new: 2, didStart: false, didDrain: false),
                TransferEdge(old: 2, new: 1, didStart: false, didDrain: false),
                TransferEdge(old: 1, new: 0, didStart: false, didDrain: true),
                TransferEdge(old: 0, new: 0, didStart: false, didDrain: false),
            ]
        )
        func transferNotificationsFireOnceWhenAQueueDrains(_ edge: TransferEdge) {
            #expect(MacTransferNotifications.didStart(old: edge.old, new: edge.new) == edge.didStart)
            #expect(MacTransferNotifications.didDrain(old: edge.old, new: edge.new) == edge.didDrain)
        }

        struct DockStep: Sendable {
            let fraction: Double
            let stepped: Double
        }

        @Test(
            "The Dock bar moves in whole percents",
            arguments: [
                DockStep(fraction: 0.123_4, stepped: 0.12),
                DockStep(fraction: 0.125_1, stepped: 0.13),
                DockStep(fraction: 1, stepped: 1),
            ]
        )
        func theDockBarMovesInWholePercents(_ step: DockStep) {
            #expect(MacDockUploadStatus.stepped(step.fraction) == step.stepped)
        }

        @Test("A gallery page never decodes past the Mac cap")
        func aGalleryPageNeverDecodesPastTheMacCap() {
            #expect(ImageGalleryPage.decodeTarget(screenLongSide: 1_440, scale: 2) == 5_760)
            #expect(ImageGalleryPage.decodeTarget(screenLongSide: 3_008, scale: 2) == ImageGalleryPage.macMaxPixelDimension)
        }

        @Test("The Quick Look responder joins and leaves the window chain")
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

        @Test("Quick Look control is wanted only with a file to show")
        func quickLookControlIsWantedOnlyWithAFileToShow() {
            let panel = MacQuickLookPanel()
            #expect(!panel.hasFileToShow)
            #expect(panel.responder.owner === panel)
        }

        @Test("Syntax highlighting stays the same once its queries are cached")
        func syntaxHighlightingStaysTheSameOnceItsQueriesAreCached() throws {
            let language = try #require(MacSyntaxLanguage.forKind("json"))
            let sample = try FilesFeatureFixture.highlighterSample.string()
            let first = MacSyntaxHighlighter.spans(for: sample, language: language)
            let second = MacSyntaxHighlighter.spans(for: sample, language: language)
            #expect(!first.isEmpty)
            #expect(first.map(\.range) == second.map(\.range))
        }

        @Test("Esc in the editor closes the preview instead of completing a word")
        func escInTheEditorClosesThePreviewInsteadOfCompletingAWord() {
            let coordinator = CodeEditorView.Coordinator(text: .constant(""))
            let closed = LockIsolated(0)
            coordinator.onEscape = { closed.withValue { $0 += 1 } }
            let textView = NSTextView()

            #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
            #expect(!coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            #expect(closed.value == 1)
        }

        @Test("Quitting asks only while an upload or download runs")
        func quittingAsksOnlyWhileAnUploadOrDownloadRuns() {
            let user = User(id: "1", username: "jdoe", email: nil, displayName: nil, roles: [])
            var state = MainTabFeature.State(serverURL: serverURL, user: user)
            #expect(!state.hasTransfersInFlight)
            let item = FileItem(name: TestFile.aText, path: "", dateModified: MockDate.date, size: 1, kind: TestKind.text)
            state.downloadQueue.jobs.append(DownloadQueueFeature.DownloadJob(id: UUID(0), item: item, status: .downloading))
            #expect(state.hasTransfersInFlight)
            state.downloadQueue.jobs[id: UUID(0)]?.status = .completed
            #expect(!state.hasTransfersInFlight)
        }

        @Test("Leaving an admin pane releases it so it loads fresh next time")
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

        @Test("A save requested from a search preview reaches the app shell")
        func savesFromASearchPreviewReachTheAppShell() async {
            let item = FileItem(name: TestFile.aText, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
            let request = DownloadSaveRequest(item: item, target: .into(URL(fileURLWithPath: "/tmp")))
            let store = TestStore(initialState: searchPreview()) { FavoritesFeature() }

            await store.send(.previewHost(.presented(.delegate(.saveRequested([request])))))
            await store.receive(.delegate(.saveRequested([request])))
        }
    }
#endif
