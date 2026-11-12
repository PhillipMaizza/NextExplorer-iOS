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
        private let serverURL = URL(string: "https://example.com")!
        private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

        private func makeStore(
            _ mutate: (inout MainTabFeature.State) -> Void = { _ in }
        ) -> TestStoreOf<MainTabFeature> {
            var state = MainTabFeature.State(serverURL: serverURL, user: user)
            mutate(&state)
            let store = TestStore(initialState: state) {
                MainTabFeature()
            } withDependencies: {
                $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
                $0.filesClient.favorites = { _ in [] }
                $0.uuid = .incrementing
                $0.date.now = Date(timeIntervalSince1970: 0)
                $0.filesClient.flushDownloadConnections = {}
                $0.filesClient.downloadItem = { _, _, _ in throw FilesClientError.offline }
            }
            store.exhaustivity = .off
            return store
        }

        @Test
        func aRenameInTheMainWindowIsBroadcastToTheOtherWindows() async {
            let renamed = FileItem(name: "b.txt", path: "", dateModified: MockDate.date, size: 1, kind: "txt")
            let store = makeStore()

            await store.send(.browse(.root(.renameResponse(.success(BrowseFeature.RenameResult(originalID: "a.txt", renamed: renamed)))))) {
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders([""]), origin: nil)
            }
        }

        @Test
        func aFailedChangeIsNotBroadcast() async {
            let store = makeStore()

            await store.send(.browse(.root(.renameResponse(.failure(.offline)))))
            #expect(store.state.folderWindowSync.revision == 0)
        }

        @Test
        func aChangeFromAnotherWindowReloadsHereAndKeepsItsOrigin() async {
            let origin = UUID(0)
            let store = makeStore {
                $0.browse.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
            }

            await store.send(.folderWindowChanged(.folders(["Photos"]), origin: origin)) {
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders(["Photos"]), origin: origin)
            }
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.favorites.refreshDirectory)
            await store.receive(\.browse.path)
        }

        @Test
        func finishedUploadsAreBroadcastSoAnyWindowOnThatFolderReloads() async {
            let store = makeStore()

            await store.send(.uploads(.delegate(.queueFinished(UploadsFeature.FinishSummary(
                uploadedCount: 1, failedCount: 0, lastDestination: "Docs", changedPaths: ["Docs"]
            ))))) {
                $0.folderWindowSync = FolderWindowSync(revision: 1, change: .folders(["Docs"]), origin: nil)
            }
        }

        @Test
        func savesGoToTheDownloadQueue() async {
            let item = FileItem(name: "a.txt", path: "Docs", dateModified: MockDate.date, size: 1, kind: "txt")
            let request = DownloadSaveRequest(item: item, target: .into(URL(fileURLWithPath: "/tmp")))
            let store = makeStore()

            await store.send(.browse(.delegate(.saveRequested([request]))))
            await store.receive(\.downloadQueue.enqueueSaves)
        }

        @Test
        func aFinishedSaveConfirmsWhereItLandedInFinder() async {
            let savedURL = URL(fileURLWithPath: "/Users/jdoe/Desktop/report.pdf")
            let store = makeStore()

            await store.send(.downloadQueue(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(
                savedCount: 1, failedCount: 0, lastSavedURL: savedURL
            ))))) {
                $0.lastSavedDownloadURL = savedURL
                $0.downloadToast = L10n.Browse.downloadSavedTo("Desktop")
            }
        }
    }
#endif
